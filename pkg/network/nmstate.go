package network

import (
	"context"
	"fmt"
	"net"

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcileNMState creates/updates NodeNetworkConfigurationPolicy for the given Wukong.
//
// 功能：
// - 对于 bridge 类型的网络，自动创建 Linux Bridge
// - 与 Multus 配合：先配置节点网络，Multus 再使用这些网络
func ReconcileNMState(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) error {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling NMState networks", "vmprofile", client.ObjectKeyFromObject(vmp), "networkCount", len(vmp.Spec.Networks))

	// 检查 NMState CRD 是否存在
	crdExists, err := checkNMStateCRDExists(ctx, c)
	if err != nil {
		logger.Error(err, "failed to check NMState CRD")
		return err
	}
	if !crdExists {
		logger.V(1).Info("NMState CRD not found, skipping NMState reconciliation")
		return nil
	}

	// 遍历网络配置，为需要 NMState 的网络创建 NodeNetworkConfigurationPolicy
	for _, netCfg := range vmp.Spec.Networks {
		// 跳过 default 网络（使用 Pod 网络，不需要 NMState）
		if netCfg.Name == "default" {
			continue
		}

		// 只处理 bridge 和 ovs 类型（macvlan/ipvlan 不支持）
		if netCfg.Type != "bridge" && netCfg.Type != "ovs" {
			logger.V(1).Info("Skipping network type for NMState", "network", netCfg.Name, "type", netCfg.Type)
			continue
		}

		// 对于 bridge 类型，需要创建桥接
		if netCfg.Type == "bridge" || netCfg.Type == "ovs" {
			if err := reconcileBridgePolicy(ctx, c, vmp, &netCfg); err != nil {
				logger.Error(err, "failed to reconcile bridge policy", "network", netCfg.Name)
				return err
			}
		}
	}

	return nil
}

// checkNMStateCRDExists 检查 NMState NodeNetworkConfigurationPolicy CRD 是否存在
func checkNMStateCRDExists(ctx context.Context, c client.Client) (bool, error) {
	crd := &unstructured.Unstructured{}
	crd.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "apiextensions.k8s.io",
		Version: "v1",
		Kind:    "CustomResourceDefinition",
	})
	key := client.ObjectKey{Name: "nodenetworkconfigurationpolicies.nmstate.io"}
	err := c.Get(ctx, key, crd)
	if err != nil {
		if errors.IsNotFound(err) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// reconcileBridgePolicy 创建/更新桥接网络策略
func reconcileBridgePolicy(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, netCfg *vmv1alpha1.NetworkConfig) error {
	logger := log.FromContext(ctx)

	// 生成策略名称
	policyName := fmt.Sprintf("%s-%s-bridge", vmp.Name, netCfg.Name)

	// 确定桥接名称
	bridgeName := netCfg.BridgeName
	if bridgeName == "" {
		bridgeName = fmt.Sprintf("br-%s", netCfg.Name)
	}

	// 确定物理网卡（必须明确指定）
	physicalInterface := netCfg.PhysicalInterface
	if physicalInterface == "" {
		return fmt.Errorf("physicalInterface is required for bridge/ovs network type, network: %s", netCfg.Name)
	}

	// 检查是否配置了 VLANID（暂时不支持）
	if netCfg.VLANID != nil {
		logger.Error(nil, "VLAN is not supported yet", "network", netCfg.Name, "vlanId", *netCfg.VLANID, "physicalInterface", physicalInterface)
		return fmt.Errorf("VLAN configuration is not supported yet, network: %s, vlanId: %d", netCfg.Name, *netCfg.VLANID)
	}

	// 自动获取物理网卡的 IP 配置信息（IP 地址和配置方式：DHCP 或静态）
	ipInfo, err := getIPConfigFromNodeNetworkState(ctx, c, physicalInterface)
	if err != nil {
		logger.Error(err, "failed to get IP config from NodeNetworkState", "interface", physicalInterface, "network", netCfg.Name)
		return fmt.Errorf("failed to get IP config from NodeNetworkState for interface %s: %w", physicalInterface, err)
	}

	// 验证实际 IP 地址格式（如果不是 DHCP 模式，必须有 IP 地址）
	useDHCP := ipInfo.useDHCP
	if !useDHCP {
		if ipInfo.ipAddress == "" {
			logger.Error(nil, "static IP mode but no IP address found in NodeNetworkState", "network", netCfg.Name, "interface", physicalInterface)
			return fmt.Errorf("static IP mode but no IP address found in NodeNetworkState for interface %s", physicalInterface)
		}
		_, _, err := parseIPAddress(ipInfo.ipAddress)
		if err != nil {
			logger.Error(err, "invalid IP address format from NodeNetworkState", "ipAddress", ipInfo.ipAddress, "network", netCfg.Name, "interface", physicalInterface)
			return fmt.Errorf("invalid IP address format from NodeNetworkState: %s, error: %w", ipInfo.ipAddress, err)
		}
	}
	logger.Info("Auto-detected IP config from NodeNetworkState", "ipAddress", ipInfo.ipAddress, "useDHCP", ipInfo.useDHCP, "interface", physicalInterface)

	// 构建 NodeNetworkConfigurationPolicy
	// 注意：NodeNetworkConfigurationPolicy 是集群级别资源，没有命名空间
	nncp := &unstructured.Unstructured{}
	nncp.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "nmstate.io",
		Version: "v1",
		Kind:    "NodeNetworkConfigurationPolicy",
	})
	nncp.SetName(policyName)
	// NodeNetworkConfigurationPolicy 是集群级别资源，不设置命名空间

	// 构建 desiredState
	desiredState := map[string]interface{}{
		"interfaces": []interface{}{},
	}

	interfaces := []interface{}{}

	// 重要：NMState 采用声明式配置，必须明确指定每个接口的状态
	// 当物理网卡被添加到桥接时，如果不明确配置，NMState 会移除物理网卡的 IP
	// 因此需要：
	// 1. 在桥接上配置节点 IP（从 NodeNetworkState 自动检测）
	// 2. 明确指定物理网卡禁用 IP（IP 在桥接上）

	// 构建桥接接口配置
	bridgeInterface := map[string]interface{}{
		"name":  bridgeName,
		"type":  "linux-bridge",
		"state": "up",
		"bridge": map[string]interface{}{
			"options": map[string]interface{}{
				"stp": map[string]interface{}{
					"enabled": false,
				},
			},
			"port": []interface{}{
				map[string]interface{}{
					"name": physicalInterface,
				},
			},
		},
	}

	// 在桥接上配置节点 IP（从 NodeNetworkState 自动检测）
	// 根据物理网卡的配置方式（DHCP 或静态）来配置桥接
	if useDHCP {
		// 物理网卡使用 DHCP，桥接也使用 DHCP
		bridgeInterface["ipv4"] = map[string]interface{}{
			"enabled": true,
			"dhcp":    true,
		}
		logger.Info("Configuring bridge with DHCP (matching physical interface)", "bridge", bridgeName, "physicalInterface", physicalInterface)
	} else {
		// 物理网卡使用静态 IP，桥接也使用静态 IP
		ip, prefixLen, err := parseIPAddress(ipInfo.ipAddress)
		if err != nil {
			logger.Error(err, "failed to parse IP address from NodeNetworkState", "ipAddress", ipInfo.ipAddress, "network", netCfg.Name)
			return fmt.Errorf("invalid IP address format from NodeNetworkState: %s, error: %w", ipInfo.ipAddress, err)
		}

		bridgeInterface["ipv4"] = map[string]interface{}{
			"enabled": true,
			"dhcp":    false,
			"address": []interface{}{
				map[string]interface{}{
					"ip":            ip,
					"prefix-length": int64(prefixLen), // 转换为 int64，unstructured 需要可深度复制的类型
				},
			},
		}
		logger.Info("Configuring bridge with static IP (matching physical interface)", "bridge", bridgeName, "ip", ip, "prefixLen", prefixLen, "physicalInterface", physicalInterface)
	}

	interfaces = append(interfaces, bridgeInterface)

	// 明确指定物理网卡的状态：禁用 IP（IP 在桥接上）
	physicalInterfaceConfig := map[string]interface{}{
		"name":  physicalInterface,
		"type":  "ethernet",
		"state": "up",
		"ipv4": map[string]interface{}{
			"enabled": false, // 禁用物理网卡的 IP，IP 在桥接上
		},
	}
	interfaces = append(interfaces, physicalInterfaceConfig)

	desiredState["interfaces"] = interfaces

	// 设置 spec
	if err := unstructured.SetNestedField(nncp.Object, desiredState, "spec", "desiredState"); err != nil {
		return fmt.Errorf("failed to set desiredState: %w", err)
	}

	// 尝试获取现有的策略
	existingNNCP := &unstructured.Unstructured{}
	existingNNCP.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "nmstate.io",
		Version: "v1",
		Kind:    "NodeNetworkConfigurationPolicy",
	})
	// NodeNetworkConfigurationPolicy 是集群级别资源，没有命名空间
	key := client.ObjectKey{Name: policyName}

	err := c.Get(ctx, key, existingNNCP)
	if err != nil {
		if errors.IsNotFound(err) {
			// 创建新策略
			logger.Info("Creating NodeNetworkConfigurationPolicy", "name", policyName, "bridge", bridgeName)
			if err := c.Create(ctx, nncp); err != nil {
				return fmt.Errorf("failed to create NodeNetworkConfigurationPolicy: %w", err)
			}
		} else {
			return fmt.Errorf("failed to get NodeNetworkConfigurationPolicy: %w", err)
		}
	} else {
		// 更新现有策略
		logger.V(1).Info("Updating NodeNetworkConfigurationPolicy", "name", policyName)
		existingNNCP.Object["spec"] = nncp.Object["spec"]
		if err := c.Update(ctx, existingNNCP); err != nil {
			return fmt.Errorf("failed to update NodeNetworkConfigurationPolicy: %w", err)
		}
	}

	return nil
}

// parseIPAddress 解析 IP 地址和前缀长度
// 输入格式: "192.168.0.121/24"
// 返回: IP 地址字符串, 前缀长度, 错误
func parseIPAddress(ipAddr string) (string, int, error) {
	ip, ipNet, err := net.ParseCIDR(ipAddr)
	if err != nil {
		return "", 0, fmt.Errorf("invalid CIDR format: %w", err)
	}

	prefixLen, _ := ipNet.Mask.Size()
	return ip.String(), prefixLen, nil
}

// ipConfigInfo 存储从 NodeNetworkState 获取的 IP 配置信息
type ipConfigInfo struct {
	ipAddress string // IP 地址，格式: "192.168.0.105/24"
	useDHCP   bool   // 是否使用 DHCP
}

// getIPConfigFromNodeNetworkState 从 NodeNetworkState 获取物理接口的 IP 配置信息（IP 地址和配置方式）
// 返回: IP 配置信息（包括 IP 地址和是否使用 DHCP）
func getIPConfigFromNodeNetworkState(ctx context.Context, c client.Client, interfaceName string) (*ipConfigInfo, error) {
	// 获取所有 NodeNetworkState 资源
	nodeNetworkStateList := &unstructured.UnstructuredList{}
	nodeNetworkStateList.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "nmstate.io",
		Version: "v1beta1",
		Kind:    "NodeNetworkStateList",
	})
	
	err := c.List(ctx, nodeNetworkStateList)
	if err != nil {
		return nil, fmt.Errorf("failed to list NodeNetworkState: %w", err)
	}
	
	// 遍历所有节点，查找接口的 IP 配置
	for _, item := range nodeNetworkStateList.Items {
		interfaces, found, err := unstructured.NestedSlice(item.Object, "status", "currentState", "interfaces")
		if err != nil || !found {
			continue
		}
		
		for _, iface := range interfaces {
			ifaceMap, ok := iface.(map[string]interface{})
			if !ok {
				continue
			}
			
			name, _ := ifaceMap["name"].(string)
			if name != interfaceName {
				continue
			}
			
			// 找到目标接口，获取 IP 配置
			ipv4, found, err := unstructured.NestedMap(ifaceMap, "ipv4")
			if err != nil || !found {
				continue
			}
			
			// 检查是否启用 DHCP
			dhcp, found, _ := unstructured.NestedBool(ipv4, "dhcp")
			useDHCP := found && dhcp
			
			// 获取 IP 地址（如果有）
			addresses, found, err := unstructured.NestedSlice(ipv4, "address")
			var ipAddress string
			if err == nil && found && len(addresses) > 0 {
				// 获取第一个 IPv4 地址
				addr, ok := addresses[0].(map[string]interface{})
				if ok {
					ip, _ := addr["ip"].(string)
					prefixLen, _ := addr["prefix-length"].(int64)
					if ip != "" && prefixLen > 0 {
						ipAddress = fmt.Sprintf("%s/%d", ip, prefixLen)
					}
				}
			}
			
			// 如果使用 DHCP，即使没有当前 IP 地址也返回（DHCP 会动态获取）
			if useDHCP {
				return &ipConfigInfo{
					ipAddress: ipAddress, // 可能是空的（如果 DHCP 还没有分配 IP）
					useDHCP:   true,
				}, nil
			}
			
			// 如果是静态 IP，必须有 IP 地址
			if ipAddress != "" {
				return &ipConfigInfo{
					ipAddress: ipAddress,
					useDHCP:   false,
				}, nil
			}
		}
	}
	
	return nil, fmt.Errorf("interface %s not found or has no IP configuration in NodeNetworkState", interfaceName)
}

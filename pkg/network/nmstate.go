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

	// 检查 NMState CRD 是否存在（必须先检查，如果有需要 NMState 的网络但 CRD 不存在，应该报错）
	crdExists, err := checkNMStateCRDExists(ctx, c)
	if err != nil {
		logger.Error(err, "failed to check NMState CRD")
		return err
	}

	// 遍历网络配置，为需要 NMState 的网络创建 NodeNetworkConfigurationPolicy
	for _, netCfg := range vmp.Spec.Networks {
		// 跳过 default 网络（使用 Pod 网络，不需要 NMState）
		if netCfg.Name == "default" {
			continue
		}

		// 只处理 bridge 和 ovs 类型（其他类型由 Multus 处理，不需要 NMState）
		if netCfg.Type != "bridge" && netCfg.Type != "ovs" {
			continue
		}

		// 如果配置了 bridge/ovs 类型但 CRD 不存在，报错
		if !crdExists {
			logger.Error(nil, "NMState CRD not found but bridge/ovs network is configured", "wukong", vmp.Name, "network", netCfg.Name, "type", netCfg.Type)
			return fmt.Errorf("NMState CRD (nodenetworkconfigurationpolicies.nmstate.io) not found, but bridge/ovs network %s (type: %s) is configured in Wukong %s. Please install NMState Operator", netCfg.Name, netCfg.Type, vmp.Name)
		}

		// 处理 bridge 和 ovs 类型
		if err := reconcileBridgePolicy(ctx, c, vmp, &netCfg); err != nil {
			logger.Error(err, "failed to reconcile bridge policy", "network", netCfg.Name)
			return err
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

	// 检查 IP 配置：目前只支持 DHCP
	if netCfg.IPConfig != nil && netCfg.IPConfig.Mode != "" && netCfg.IPConfig.Mode != "dhcp" {
		return fmt.Errorf("only DHCP mode is supported for bridge network currently, network: %s, mode: %s", netCfg.Name, netCfg.IPConfig.Mode)
	}

	// 检查策略是否存在
	key := client.ObjectKey{Name: policyName}
	existingNNCP := &unstructured.Unstructured{}
	existingNNCP.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "nmstate.io",
		Version: "v1",
		Kind:    "NodeNetworkConfigurationPolicy",
	})
	err := c.Get(ctx, key, existingNNCP)
	policyExists := err == nil && !errors.IsNotFound(err)

	// 目前只支持 DHCP，直接使用 DHCP 配置
	logger.Info("Using DHCP for bridge IP configuration", "bridge", bridgeName)

	// 构建策略的 desiredState（只使用 DHCP）
	desiredState, err := buildBridgeDesiredState(bridgeName, physicalInterface)
	if err != nil {
		return fmt.Errorf("failed to build desiredState: %w", err)
	}

	// 创建或更新策略（复用之前检查的 existingNNCP，如果策略已存在）
	var nncp *unstructured.Unstructured
	if policyExists {
		// 策略已存在，使用 existingNNCP
		nncp = existingNNCP
		if err := unstructured.SetNestedField(nncp.Object, desiredState, "spec", "desiredState"); err != nil {
			return fmt.Errorf("failed to set desiredState: %w", err)
		}
		logger.V(1).Info("Updating NodeNetworkConfigurationPolicy", "name", policyName)
		if err := c.Update(ctx, nncp); err != nil {
			return fmt.Errorf("failed to update NodeNetworkConfigurationPolicy: %w", err)
		}
	} else {
		// 策略不存在，创建新的对象
		nncp = &unstructured.Unstructured{}
		nncp.SetGroupVersionKind(schema.GroupVersionKind{
			Group:   "nmstate.io",
			Version: "v1",
			Kind:    "NodeNetworkConfigurationPolicy",
		})
		nncp.SetName(policyName)
		if err := unstructured.SetNestedField(nncp.Object, desiredState, "spec", "desiredState"); err != nil {
			return fmt.Errorf("failed to set desiredState: %w", err)
		}
		logger.Info("Creating NodeNetworkConfigurationPolicy", "name", policyName, "bridge", bridgeName)
		if err := c.Create(ctx, nncp); err != nil {
			return fmt.Errorf("failed to create NodeNetworkConfigurationPolicy: %w", err)
		}
	}

	return nil
}

// buildBridgeDesiredState 构建桥接策略的 desiredState（目前只支持 DHCP）
func buildBridgeDesiredState(bridgeName, physicalInterface string) (map[string]interface{}, error) {
	interfaces := []interface{}{}

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
		// 在桥接上配置 IP（使用 DHCP）
		"ipv4": map[string]interface{}{
			"enabled": true,
			"dhcp":    true,
		},
	}
	interfaces = append(interfaces, bridgeInterface)

	// 明确指定物理网卡禁用 IP（IP 在桥接上）
	physicalInterfaceConfig := map[string]interface{}{
		"name":  physicalInterface,
		"type":  "ethernet",
		"state": "up",
		"ipv4": map[string]interface{}{
			"enabled": false,
		},
	}
	interfaces = append(interfaces, physicalInterfaceConfig)

	return map[string]interface{}{
		"interfaces": interfaces,
	}, nil
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

// getIPConfigFromNodeNetworkState 从 NodeNetworkState 获取桥接接口的 IP 配置信息（IP 地址和配置方式）
// 注意：物理接口没有 IP（ipv4.enabled: false），IP 在桥接上，所以只查找桥接接口的 IP 配置
// 参数 bridgeName 是桥接名称（如 "br-external"）
// 返回: IP 配置信息（包括 IP 地址和是否使用 DHCP）
func getIPConfigFromNodeNetworkState(ctx context.Context, c client.Client, bridgeName string) (*ipConfigInfo, error) {
	// 首先尝试列出所有节点，然后对每个节点使用 Get
	// 这样可以避免使用 List 获取所有 NodeNetworkState（List 操作在 API Server 响应慢时会超时）
	nodeList := &unstructured.UnstructuredList{}
	nodeList.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "",
		Version: "v1",
		Kind:    "NodeList",
	})

	err := c.List(ctx, nodeList)
	if err != nil {
		return nil, fmt.Errorf("failed to list nodes: %w", err)
	}

	// 遍历所有节点，使用 Get 获取每个节点的 NodeNetworkState
	for _, node := range nodeList.Items {
		nodeName, found, err := unstructured.NestedString(node.Object, "metadata", "name")
		if err != nil || !found || nodeName == "" {
			continue
		}

		// 使用 Get 获取特定节点的 NodeNetworkState（比 List 所有 NodeNetworkState 更快）
		nodeNetworkState := &unstructured.Unstructured{}
		nodeNetworkState.SetGroupVersionKind(schema.GroupVersionKind{
			Group:   "nmstate.io",
			Version: "v1beta1",
			Kind:    "NodeNetworkState",
		})
		key := client.ObjectKey{Name: nodeName}

		err = c.Get(ctx, key, nodeNetworkState)
		if err != nil {
			// 如果某个节点的 NodeNetworkState 不存在，继续查找下一个节点
			continue
		}

		item := nodeNetworkState
		interfaces, found, err := unstructured.NestedSlice(item.Object, "status", "currentState", "interfaces")
		if err != nil || !found {
			continue
		}

		// 查找桥接接口（类型为 linux-bridge 或 ovs-bridge）
		for _, iface := range interfaces {
			ifaceMap, ok := iface.(map[string]interface{})
			if !ok {
				continue
			}

			name, _ := ifaceMap["name"].(string)
			if name != bridgeName {
				continue
			}

			// 检查是否是桥接接口
			ifaceType, _ := ifaceMap["type"].(string)
			if ifaceType != "linux-bridge" && ifaceType != "ovs-bridge" {
				continue
			}

			// 找到了桥接接口，获取 IP 配置
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

	return nil, fmt.Errorf("bridge %s not found or has no IP configuration in NodeNetworkState", bridgeName)
}

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
// - 对于有 VLAN 的网络，自动创建 VLAN 接口
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

	// 如果有 VLAN，先创建 VLAN 接口
	if netCfg.VLANID != nil {
		vlanInterfaceName := fmt.Sprintf("%s.%d", physicalInterface, *netCfg.VLANID)
		vlanInterface := map[string]interface{}{
			"name":  vlanInterfaceName,
			"type":  "vlan",
			"state": "up",
			"vlan": map[string]interface{}{
				"base-iface": physicalInterface,
				"id":         int64(*netCfg.VLANID), // 转换为 int64，unstructured 需要可深度复制的类型
			},
		}
		interfaces = append(interfaces, vlanInterface)

		// 桥接使用 VLAN 接口作为端口
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
						"name": vlanInterfaceName,
					},
				},
			},
		}
		interfaces = append(interfaces, bridgeInterface)
	} else {
		// 没有 VLAN，直接使用物理网卡
		// 重要：NMState 采用声明式配置，必须明确指定每个接口的状态
		// 当物理网卡被添加到桥接时，如果不明确配置，NMState 会移除物理网卡的 IP
		// 因此需要：
		// 1. 在桥接上配置节点 IP（从 NodeIP 字段获取）
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

		// 如果指定了 NodeIP，在桥接上配置 IP
		if netCfg.NodeIP != nil && *netCfg.NodeIP != "" {
			ip, prefixLen, err := parseIPAddress(*netCfg.NodeIP)
			if err != nil {
				logger.Error(err, "failed to parse nodeIP", "nodeIP", *netCfg.NodeIP, "network", netCfg.Name)
				return fmt.Errorf("invalid nodeIP format: %s, expected format: 192.168.0.121/24, error: %w", *netCfg.NodeIP, err)
			}

			bridgeInterface["ipv4"] = map[string]interface{}{
				"enabled": true,
				"address": []interface{}{
					map[string]interface{}{
						"ip":            ip,
						"prefix-length": int64(prefixLen), // 转换为 int64，unstructured 需要可深度复制的类型
					},
				},
			}
			logger.Info("Configuring node IP on bridge", "bridge", bridgeName, "ip", ip, "prefixLen", prefixLen)
		} else {
			// 如果没有指定 NodeIP，记录警告
			logger.V(1).Info("NodeIP not specified, bridge will be created without IP. Node network connectivity may be lost", "network", netCfg.Name, "physicalInterface", physicalInterface)
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
	}

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

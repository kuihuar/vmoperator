package network

import (
	"context"
	"fmt"

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

	// 确定物理网卡（如果没有指定，使用默认值）
	// 注意：这里假设使用 ens160，实际应该从配置或环境变量获取
	physicalInterface := "ens160"
	if netCfg.BridgeName != "" && netCfg.Type != "bridge" {
		// 如果 BridgeName 被用作物理网卡名称（macvlan 场景）
		physicalInterface = netCfg.BridgeName
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
				"id":          *netCfg.VLANID,
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
		interfaces = append(interfaces, bridgeInterface)
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

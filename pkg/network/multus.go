package network

import (
	"context"
	"encoding/json"
	"fmt"
	"net"

	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcileNetworks creates/updates NetworkAttachmentDefinitions for the given Wukong
// and returns the resulting NetworkStatus list.
//
// 目标（原型阶段）：
// - 为每个 NetworkConfig 准备一个 NetworkAttachmentDefinition（如果未显式指定 NADName）
// - 目前使用 Unstructured 避免额外依赖，后续可以替换为强类型客户端
func ReconcileNetworks(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.NetworkStatus, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling Multus networks", "vmprofile", client.ObjectKeyFromObject(vmp), "networkCount", len(vmp.Spec.Networks))

	statuses := make([]vmv1alpha1.NetworkStatus, 0, len(vmp.Spec.Networks))

	for _, netCfg := range vmp.Spec.Networks {
		// 跳过 default 网络，它使用 Pod 网络，不需要 Multus NAD
		if netCfg.Name == "default" {
			statuses = append(statuses, vmv1alpha1.NetworkStatus{
				Name: netCfg.Name,
				// 不设置 NADName，表示使用默认 Pod 网络
			})
			continue
		}

		// 只支持 bridge 和 ovs 类型（根据 KubeVirt 官方文档，macvlan/ipvlan 不支持）
		if netCfg.Type != "bridge" && netCfg.Type != "ovs" {
			logger.Info("Skipping unsupported network type", "network", netCfg.Name, "type", netCfg.Type, "reason", "only bridge and ovs are supported for KubeVirt")
			statuses = append(statuses, vmv1alpha1.NetworkStatus{
				Name: netCfg.Name,
				// 不设置 NADName，表示不支持
			})
			continue
		}

		// 如果用户已经指定了 NADName，则只记录状态，不自动创建
		nadName := netCfg.NADName
		if nadName == "" {
			nadName = fmt.Sprintf("%s-%s-nad", vmp.Name, netCfg.Name)
		}

		nad := &unstructured.Unstructured{}
		// 手动设置 GVK，因为 NetworkAttachmentDefinition 是 CRD
		nad.SetGroupVersionKind(schema.GroupVersionKind{
			Group:   "k8s.cni.cncf.io",
			Version: "v1",
			Kind:    "NetworkAttachmentDefinition",
		})

		key := client.ObjectKey{Namespace: vmp.Namespace, Name: nadName}

		err := c.Get(ctx, key, nad)
		if err != nil {
			if errors.IsNotFound(err) && netCfg.NADName == "" {
				// 检查 Multus CRD 是否存在
				crdExists, crdErr := checkMultusCRDExists(ctx, c)
				if crdErr != nil {
					logger.Error(crdErr, "failed to check Multus CRD", "network", netCfg.Name)
					return nil, crdErr
				}
				if !crdExists {
					// Multus 未安装，使用默认 Pod 网络
					logger.Info("Multus CNI not installed, using default Pod network", "network", netCfg.Name)
					statuses = append(statuses, vmv1alpha1.NetworkStatus{
						Name: netCfg.Name,
						// 不设置 NADName，表示使用默认网络
					})
					continue
				}

				// 未找到且未显式指定 NADName，则自动创建一个简单的 NAD
				logger.Info("Creating NetworkAttachmentDefinition", "name", nadName, "namespace", vmp.Namespace)
				nad.SetName(nadName)
				nad.SetNamespace(vmp.Namespace)

				configStr, cfgErr := buildCNIConfig(&netCfg)
				if cfgErr != nil {
					logger.Error(cfgErr, "failed to build CNI config", "network", netCfg.Name)
					return nil, cfgErr
				}

				if err := unstructured.SetNestedField(nad.Object, map[string]interface{}{
					"config": configStr,
				}, "spec"); err != nil {
					logger.Error(err, "failed to set NAD spec.config", "name", nadName)
					return nil, err
				}

				if err := c.Create(ctx, nad); err != nil {
					logger.Error(err, "failed to create NetworkAttachmentDefinition", "name", nadName)
					return nil, err
				}
			} else if !errors.IsNotFound(err) {
				// 如果不是 NotFound 错误，说明是其他错误
				logger.Error(err, "failed to get NetworkAttachmentDefinition", "name", nadName)
				return nil, err
			}
		} else {
			logger.V(1).Info("Found existing NetworkAttachmentDefinition", "name", nadName)
		}

		statuses = append(statuses, vmv1alpha1.NetworkStatus{
			Name: netCfg.Name,
			// NADName 记录实际使用的 NAD 名称
			NADName: nadName,
			// Interface/IP/MAC 需要在 VM 运行后由 KubeVirt / guest-agent 填充，这里先留空
		})
	}

	return statuses, nil
}

// checkMultusCRDExists 检查 Multus NetworkAttachmentDefinition CRD 是否存在
func checkMultusCRDExists(ctx context.Context, c client.Client) (bool, error) {
	crd := &apiextensionsv1.CustomResourceDefinition{}
	key := client.ObjectKey{Name: "network-attachment-definitions.k8s.cni.cncf.io"}
	err := c.Get(ctx, key, crd)
	if err != nil {
		if errors.IsNotFound(err) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// buildCNIConfig 构造一个简单的 CNI 配置 JSON 字符串。
// 这里仅作为原型示例，实际生产环境需要根据具体网络规划进行调整。
func buildCNIConfig(netCfg *vmv1alpha1.NetworkConfig) (string, error) {
	type baseConfig struct {
		CNIVersion string                 `json:"cniVersion"`
		Type       string                 `json:"type"`
		Bridge     string                 `json:"bridge,omitempty"`
		Master     string                 `json:"master,omitempty"`
		Mode       string                 `json:"mode,omitempty"`
		VLAN       *int                   `json:"vlan,omitempty"`
		IPAM       map[string]interface{} `json:"ipam,omitempty"`
	}

	// 只支持 bridge 类型（根据 KubeVirt 官方文档，macvlan/ipvlan 不能用于 bridge interfaces）
	// 参考：https://kubevirt.io/user-guide/network/interfaces_and_networks/#invalid-cnis-for-secondary-networks
	if netCfg.Type != "bridge" && netCfg.Type != "ovs" {
		return "", fmt.Errorf("unsupported network type: %s. Only bridge and ovs are supported for KubeVirt", netCfg.Type)
	}

	// 强制使用 bridge CNI
	cfg := baseConfig{
		CNIVersion: "0.3.1",
		Type:       "bridge", // 强制使用 bridge CNI
	}

	// 配置桥接名称
	if netCfg.BridgeName != "" {
		cfg.Bridge = netCfg.BridgeName
	} else {
		// 默认桥接名称，与 NMState 创建的桥接名称保持一致
		cfg.Bridge = fmt.Sprintf("br-%s", netCfg.Name)
	}
	// 注意：VLAN 由 NMState 处理，这里不需要设置 VLAN
	// 如果设置了 VLAN，NMState 会创建 VLAN 接口，桥接会使用 VLAN 接口

	// 根据 IPConfig 选择 ipam 类型
	if netCfg.IPConfig != nil {
		if netCfg.IPConfig.Mode == "dhcp" {
			cfg.IPAM = map[string]interface{}{
				"type": "dhcp",
			}
		} else if netCfg.IPConfig.Mode == "static" && netCfg.IPConfig.Address != nil {
			// bridge CNI 使用 host-local IPAM 配置静态 IP
			// 解析 IP 地址和子网掩码
			address := *netCfg.IPConfig.Address
			// address 格式: "192.168.100.10/24"
			// 提取 IP 和子网
			ip, ipNet, err := net.ParseCIDR(address)
			if err != nil {
				return "", fmt.Errorf("invalid IP address format: %s", address)
			}

			// 获取子网范围
			subnet := ipNet.String()

			// 使用 host-local IPAM，设置 rangeStart 和 rangeEnd 为同一个 IP
			// 这样可以确保分配固定的 IP 地址
			ipam := map[string]interface{}{
				"type":       "host-local",
				"subnet":     subnet,
				"rangeStart": ip.String(),
				"rangeEnd":   ip.String(),
			}

			// 如果指定了网关，注入到 IPAM 路由中
			if netCfg.IPConfig.Gateway != nil {
				ipam["routes"] = []map[string]interface{}{
					{
						"dst": "0.0.0.0/0",
						"gw":  *netCfg.IPConfig.Gateway,
					},
				}
			}
			cfg.IPAM = ipam
		}
	}

	data, err := json.Marshal(cfg)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

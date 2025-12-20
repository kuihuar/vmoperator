package network

import (
	"context"
	"encoding/json"
	"fmt"

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
	key := client.ObjectKey{Name: "networkattachmentdefinitions.k8s.cni.cncf.io"}
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
		VLAN       *int                   `json:"vlan,omitempty"`
		IPAM       map[string]interface{} `json:"ipam,omitempty"`
	}

	cfg := baseConfig{
		CNIVersion: "0.3.1",
		Type:       netCfg.Type,
	}

	// 对 bridge/ovs 类型，使用 bridge 字段和可选 VLAN
	if netCfg.Type == "bridge" || netCfg.Type == "ovs" {
		if netCfg.BridgeName != "" {
			cfg.Bridge = netCfg.BridgeName
		} else {
			cfg.Bridge = fmt.Sprintf("br-%s", netCfg.Name)
		}
		if netCfg.VLANID != nil {
			cfg.VLAN = netCfg.VLANID
		}
	}

	// 简单根据 IPConfig 选择 ipam 类型
	if netCfg.IPConfig != nil {
		if netCfg.IPConfig.Mode == "dhcp" {
			cfg.IPAM = map[string]interface{}{
				"type": "dhcp",
			}
		} else if netCfg.IPConfig.Mode == "static" && netCfg.IPConfig.Address != nil {
			cfg.IPAM = map[string]interface{}{
				"type": "static",
				"addresses": []map[string]string{
					{
						"address": *netCfg.IPConfig.Address,
					},
				},
			}
			if netCfg.IPConfig.Gateway != nil {
				cfg.IPAM["routes"] = []map[string]string{
					{
						"dst": "0.0.0.0/0",
						"gw":  *netCfg.IPConfig.Gateway,
					},
				}
			}
		}
	}

	data, err := json.Marshal(cfg)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

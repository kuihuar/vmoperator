package network

import (
	"context"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcileNMState is a placeholder for NMState integration.
//
// 原型阶段仅预留接口：
// - 未来可以在这里根据 NetworkConfig 生成 NodeNetworkConfigurationPolicy（NNCP）
// - 目前默认不创建任何 NNCP，仅为后续扩展预留入口
func ReconcileNMState(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) error {
	logger := log.FromContext(ctx)
	logger.V(1).Info("ReconcileNMState (no-op prototype)", "vmprofile", client.ObjectKeyFromObject(vmp))

	// 示例：当未来需要按网络生成 NNCP 时，可按如下方式构造 Unstructured：
	_ = &unstructured.Unstructured{
		Object: map[string]interface{}{
			"apiVersion": "nmstate.io/v1",
			"kind":       "NodeNetworkConfigurationPolicy",
			// "metadata": map[string]interface{}{
			// 	"name": "example-nncp",
			// },
			// "spec": map[string]interface{}{
			// 	"desiredState": map[string]interface{}{...},
			// },
		},
	}

	return nil
}

package controller

import (
	"context"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// WukongSnapshotReconciler reconciles a WukongSnapshot object
type WukongSnapshotReconciler struct {
	client.Client
}

// Reconcile handles the snapshot creation process
func (r *WukongSnapshotReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// 1. 获取 WukongSnapshot
	var snapshot vmv1alpha1.WukongSnapshot
	if err := r.Get(ctx, req.NamespacedName, &snapshot); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// 2. 如果已经成功，不再处理
	if snapshot.Status.Phase == "Succeeded" {
		return ctrl.Result{}, nil
	}

	// 3. 获取对应的 Wukong 实例
	var wukong vmv1alpha1.Wukong
	wukongKey := client.ObjectKey{Namespace: snapshot.Namespace, Name: snapshot.Spec.WukongName}
	if err := r.Get(ctx, wukongKey, &wukong); err != nil {
		snapshot.Status.Phase = "Failed"
		snapshot.Status.Error = fmt.Sprintf("Wukong %s not found", snapshot.Spec.WukongName)
		r.Status().Update(ctx, &snapshot)
		return ctrl.Result{}, err
	}

	// 4. 创建 KubeVirt VirtualMachineSnapshot (使用 Unstructured)
	kvSnapshotName := fmt.Sprintf("%s-snapshot-%d", snapshot.Spec.WukongName, time.Now().Unix())
	kvSnapshot := &unstructured.Unstructured{}
	kvSnapshot.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "snapshot.kubevirt.io",
		Version: "v1alpha1",
		Kind:    "VirtualMachineSnapshot",
	})
	kvSnapshot.SetName(kvSnapshotName)
	kvSnapshot.SetNamespace(snapshot.Namespace)

	spec := map[string]interface{}{
		"source": map[string]interface{}{
			"apiGroup": "kubevirt.io",
			"kind":     "VirtualMachine",
			"name":     wukong.Status.VMName,
		},
	}
	unstructured.SetNestedField(kvSnapshot.Object, spec, "spec")

	if snapshot.Status.SnapshotName == "" {
		if err := r.Create(ctx, kvSnapshot); err != nil {
			if !apierrors.IsAlreadyExists(err) {
				return ctrl.Result{}, err
			}
		}
		snapshot.Status.SnapshotName = kvSnapshotName
		snapshot.Status.Phase = "Creating"
		r.Status().Update(ctx, &snapshot)
		return ctrl.Result{RequeueAfter: time.Second * 5}, nil
	}

	// 5. 检查快照状态
	err := r.Get(ctx, client.ObjectKey{Namespace: snapshot.Namespace, Name: snapshot.Status.SnapshotName}, kvSnapshot)
	if err != nil {
		return ctrl.Result{}, err
	}

	ready, found, _ := unstructured.NestedBool(kvSnapshot.Object, "status", "readyToUse")
	if found && ready {
		snapshot.Status.Phase = "Succeeded"
		now := metav1.Now()
		snapshot.Status.CreationTime = &now
		r.Status().Update(ctx, &snapshot)
		logger.Info("Snapshot succeeded", "name", snapshot.Name)
		return ctrl.Result{}, nil
	}

	return ctrl.Result{RequeueAfter: time.Second * 10}, nil
}

func (r *WukongSnapshotReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&vmv1alpha1.WukongSnapshot{}).
		Complete(r)
}

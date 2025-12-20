package storage

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcilePVC creates or gets an existing PersistentVolumeClaim for the given disk configuration.
// It returns the PVC name and bound status.
func ReconcilePVC(ctx context.Context, c client.Client, disk vmv1alpha1.DiskConfig, namespace, vmName string) (string, bool, error) {
	logger := log.FromContext(ctx)
	pvcName := fmt.Sprintf("%s-%s", vmName, disk.Name)

	logger.Info("Reconciling PVC", "name", pvcName, "namespace", namespace, "size", disk.Size, "storageClass", disk.StorageClassName)

	// 解析存储大小
	storageQuantity, err := resource.ParseQuantity(disk.Size)
	if err != nil {
		logger.Error(err, "failed to parse storage size", "size", disk.Size)
		return "", false, fmt.Errorf("invalid storage size %s: %w", disk.Size, err)
	}

	// 创建 PVC 对象
	pvc := &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      pvcName,
			Namespace: namespace,
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
			Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: storageQuantity,
				},
			},
			StorageClassName: &disk.StorageClassName,
		},
	}

	// 检查 context 是否已取消
	if ctx.Err() != nil {
		logger.V(1).Info("Context canceled before checking PVC, will retry", "name", pvcName, "error", ctx.Err())
		return pvcName, false, ctx.Err()
	}

	// 尝试获取现有的 PVC
	existingPVC := &corev1.PersistentVolumeClaim{}
	key := client.ObjectKey{Namespace: namespace, Name: pvcName}
	err = c.Get(ctx, key, existingPVC)
	if err != nil {
		if errors.IsNotFound(err) {
			// PVC 不存在，创建新的
			logger.Info("Creating PersistentVolumeClaim", "name", pvcName)
			if err := c.Create(ctx, pvc); err != nil {
				logger.Error(err, "failed to create PersistentVolumeClaim", "name", pvcName)
				return "", false, err
			}
			// 不等待，让 controller requeue 来检查状态
			logger.Info("PVC created, will check status in next reconcile", "name", pvcName)
			return pvcName, false, nil
		}
		// 如果是 context canceled，返回以便 controller 处理
		if ctx.Err() != nil {
			logger.V(1).Info("Context canceled during Get PVC, will retry", "name", pvcName)
			return pvcName, false, ctx.Err()
		}
		// 其他错误
		logger.Error(err, "failed to get PersistentVolumeClaim", "name", pvcName)
		return "", false, err
	}

	// PVC 已存在，检查绑定状态
	logger.V(1).Info("Found existing PersistentVolumeClaim", "name", pvcName, "phase", existingPVC.Status.Phase)

	// 检查 StorageClass 的 volumeBindingMode
	// 如果是 WaitForFirstConsumer，即使 PVC 未绑定也可以继续（PVC 会在 Pod 创建时绑定）
	bound := existingPVC.Status.Phase == corev1.ClaimBound
	if !bound && existingPVC.Spec.StorageClassName != nil {
		storageClassName := *existingPVC.Spec.StorageClassName
		// 检查 StorageClass 的 volumeBindingMode
		sc := &storagev1.StorageClass{}
		scKey := client.ObjectKey{Name: storageClassName}
		if err := c.Get(ctx, scKey, sc); err == nil {
			if sc.VolumeBindingMode != nil && *sc.VolumeBindingMode == storagev1.VolumeBindingWaitForFirstConsumer {
				// WaitForFirstConsumer 模式：PVC 会在第一个 Pod 创建时绑定
				// 如果 PVC 处于 Pending 状态且没有错误，可以继续
				if existingPVC.Status.Phase == corev1.ClaimPending {
					logger.V(1).Info("PVC is in WaitForFirstConsumer mode, will bind when VM Pod is created", "name", pvcName)
					// 返回 bound=true，允许继续创建 VM
					return pvcName, true, nil
				}
			}
		}
	}

	return pvcName, bound, nil
}

// CheckPVCBound checks if a PersistentVolumeClaim is bound (non-blocking).
// Returns true if PVC is bound, false if still pending, error if in Lost state.
func CheckPVCBound(ctx context.Context, c client.Client, namespace, name string) (bool, error) {
	logger := log.FromContext(ctx)

	// 检查 context 是否已取消
	if ctx.Err() != nil {
		logger.V(1).Info("Context canceled, will retry in next reconcile", "name", name, "error", ctx.Err())
		return false, ctx.Err()
	}

	pvc := &corev1.PersistentVolumeClaim{}
	key := client.ObjectKey{Namespace: namespace, Name: name}
	if err := c.Get(ctx, key, pvc); err != nil {
		if errors.IsNotFound(err) {
			// PVC 可能还在创建中
			logger.V(1).Info("PVC not found, may still be creating", "name", name)
			return false, nil
		}
		// 如果是 context canceled，返回特殊错误以便 controller 处理
		if ctx.Err() != nil {
			logger.V(1).Info("Context canceled during Get, will retry", "name", name)
			return false, ctx.Err()
		}
		return false, err
	}

	phase := pvc.Status.Phase
	logger.V(1).Info("PVC status", "name", name, "phase", phase)

	if phase == corev1.ClaimBound {
		logger.Info("PVC is bound", "name", name)
		return true, nil
	}

	if phase == corev1.ClaimLost {
		return false, fmt.Errorf("PVC %s/%s is in Lost state", namespace, name)
	}

	// 其他状态（Pending 等），还在进行中
	logger.V(1).Info("PVC is still pending", "name", name, "phase", phase)
	return false, nil
}

// WaitForPVCBound waits for a PersistentVolumeClaim to be bound (deprecated, use CheckPVCBound instead).
// This function is kept for backward compatibility but should not be used in Reconcile loops.
func WaitForPVCBound(ctx context.Context, c client.Client, namespace, name string, timeout time.Duration) (bool, error) {
	return CheckPVCBound(ctx, c, namespace, name)
}

// DeletePVC deletes a PersistentVolumeClaim.
func DeletePVC(ctx context.Context, c client.Client, namespace, name string) error {
	logger := log.FromContext(ctx)
	logger.Info("Deleting PersistentVolumeClaim", "name", name, "namespace", namespace)

	pvc := &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
		},
	}

	if err := c.Delete(ctx, pvc); err != nil {
		if errors.IsNotFound(err) {
			logger.V(1).Info("PVC already deleted", "name", name)
			return nil
		}
		logger.Error(err, "failed to delete PersistentVolumeClaim", "name", name)
		return err
	}

	return nil
}

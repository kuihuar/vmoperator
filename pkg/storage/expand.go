package storage

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ExpandPVC expands a PVC if the new size is larger than the current size.
// Returns true if expansion was attempted, and any error.
func ExpandPVC(ctx context.Context, c client.Client, pvcName, namespace, newSize string) (bool, error) {
	logger := log.FromContext(ctx)

	// 解析新的存储大小
	newQuantity, err := resource.ParseQuantity(newSize)
	if err != nil {
		return false, fmt.Errorf("invalid storage size %s: %w", newSize, err)
	}

	// 获取现有的 PVC
	pvc := &corev1.PersistentVolumeClaim{}
	key := client.ObjectKey{Namespace: namespace, Name: pvcName}
	if err := c.Get(ctx, key, pvc); err != nil {
		if errors.IsNotFound(err) {
			return false, fmt.Errorf("PVC %s not found", pvcName)
		}
		return false, err
	}

	// 检查当前大小
	currentQuantity := pvc.Spec.Resources.Requests[corev1.ResourceStorage]
	if newQuantity.Cmp(currentQuantity) <= 0 {
		// 新大小小于或等于当前大小，不需要扩展
		logger.V(1).Info("New size is not larger than current size, skipping expansion",
			"pvc", pvcName, "current", currentQuantity.String(), "new", newQuantity.String())
		return false, nil
	}

	// 检查 StorageClass 是否支持扩展
	storageClassName := ""
	if pvc.Spec.StorageClassName != nil {
		storageClassName = *pvc.Spec.StorageClassName
	} else {
		// 使用默认的 StorageClass
		scList := &storagev1.StorageClassList{}
		if err := c.List(ctx, scList); err == nil {
			for _, sc := range scList.Items {
				if sc.Annotations["storageclass.kubernetes.io/is-default-class"] == "true" {
					storageClassName = sc.Name
					break
				}
			}
		}
	}

	if storageClassName != "" {
		sc := &storagev1.StorageClass{}
		scKey := client.ObjectKey{Name: storageClassName}
		if err := c.Get(ctx, scKey, sc); err == nil {
			if sc.AllowVolumeExpansion != nil && !*sc.AllowVolumeExpansion {
				return false, fmt.Errorf("StorageClass %s does not allow volume expansion", storageClassName)
			}
		}
	}

	// 检查 PVC 是否已绑定
	if pvc.Status.Phase != corev1.ClaimBound {
		return false, fmt.Errorf("PVC %s is not bound (current phase: %s), cannot expand", pvcName, pvc.Status.Phase)
	}

	// 更新 PVC 大小
	logger.Info("Expanding PVC", "pvc", pvcName, "current", currentQuantity.String(), "new", newQuantity.String())
	pvc.Spec.Resources.Requests[corev1.ResourceStorage] = newQuantity

	if err := c.Update(ctx, pvc); err != nil {
		return false, fmt.Errorf("failed to update PVC %s: %w", pvcName, err)
	}

	logger.Info("PVC expansion requested", "pvc", pvcName, "newSize", newQuantity.String())
	return true, nil
}

// CheckPVCExpansionStatus checks if a PVC expansion is in progress or completed.
// Returns true if expansion is complete, false if in progress, and any error.
func CheckPVCExpansionStatus(ctx context.Context, c client.Client, pvcName, namespace string) (bool, error) {
	logger := log.FromContext(ctx)

	pvc := &corev1.PersistentVolumeClaim{}
	key := client.ObjectKey{Namespace: namespace, Name: pvcName}
	if err := c.Get(ctx, key, pvc); err != nil {
		return false, err
	}

	// 检查 PVC 的 conditions
	for _, condition := range pvc.Status.Conditions {
		if condition.Type == corev1.PersistentVolumeClaimResizing {
			logger.V(1).Info("PVC expansion in progress", "pvc", pvcName)
			return false, nil
		}
	}

	// 检查是否有 FileSystemResizePending condition（表示需要文件系统扩展）
	for _, condition := range pvc.Status.Conditions {
		if condition.Type == corev1.PersistentVolumeClaimFileSystemResizePending {
			logger.V(1).Info("PVC expansion complete, file system resize pending", "pvc", pvcName)
			// 扩展已完成，但需要在 VM 内部扩展文件系统
			return true, nil
		}
	}

	// 如果没有 Resizing 或 FileSystemResizePending condition，扩展已完成
	logger.V(1).Info("PVC expansion appears complete", "pvc", pvcName)
	return true, nil
}

// ReconcileDiskExpansion reconciles disk size changes for a Wukong.
// It checks if any disk size has changed and attempts to expand the corresponding PVC.
func ReconcileDiskExpansion(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, volumesStatus []vmv1alpha1.VolumeStatus) error {
	logger := log.FromContext(ctx)

	// 遍历所有磁盘配置
	for _, disk := range vmp.Spec.Disks {
		// 查找对应的 VolumeStatus
		var currentVolumeStatus *vmv1alpha1.VolumeStatus
		for i := range volumesStatus {
			if volumesStatus[i].Name == disk.Name {
				currentVolumeStatus = &volumesStatus[i]
				break
			}
		}

		if currentVolumeStatus == nil {
			// 磁盘还没有创建，跳过
			continue
		}

		// 比较大小
		currentSize := currentVolumeStatus.Size
		newSize := disk.Size

		if currentSize != newSize {
			logger.Info("Disk size changed, attempting expansion",
				"disk", disk.Name, "current", currentSize, "new", newSize)

			// 尝试扩展 PVC
			expanded, err := ExpandPVC(ctx, c, currentVolumeStatus.PVCName, vmp.Namespace, newSize)
			if err != nil {
				logger.Error(err, "failed to expand PVC", "disk", disk.Name, "pvc", currentVolumeStatus.PVCName)
				return err
			}

			if expanded {
				logger.Info("PVC expansion initiated", "disk", disk.Name, "pvc", currentVolumeStatus.PVCName)
				// 更新 VolumeStatus 中的大小（会在 controller 中同步）
				currentVolumeStatus.Size = newSize
			}
		}
	}

	return nil
}

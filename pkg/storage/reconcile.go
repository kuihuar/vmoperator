package storage

import (
	"context"

	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcileDisks reconciles all disks for a Wukong.
// It creates either DataVolume (if disk.image is specified) or PVC (if not).
// Returns a list of VolumeStatus for each disk.
func ReconcileDisks(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.VolumeStatus, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling disks", "vmprofile", client.ObjectKeyFromObject(vmp), "diskCount", len(vmp.Spec.Disks))

	volumesStatus := make([]vmv1alpha1.VolumeStatus, 0, len(vmp.Spec.Disks))

	for _, disk := range vmp.Spec.Disks {
		var pvcName string
		var bound bool
		var err error

		// 如果指定了 image，使用 DataVolume；否则使用 PVC
		if disk.Image != "" {
			logger.Info("Creating DataVolume for disk with image", "disk", disk.Name, "image", disk.Image)
			pvcName, bound, err = ReconcileDataVolume(ctx, c, disk, vmp.Namespace, vmp.Name)
		} else {
			logger.Info("Creating PVC for disk", "disk", disk.Name)
			pvcName, bound, err = ReconcilePVC(ctx, c, disk, vmp.Namespace, vmp.Name)
		}

		if err != nil {
			// 如果是 context canceled，返回错误以便 controller requeue
			if ctx.Err() != nil {
				logger.V(1).Info("Context canceled during disk reconciliation, will retry", "disk", disk.Name, "error", err)
				return nil, err
			}
			logger.Error(err, "failed to reconcile disk", "disk", disk.Name)
			return nil, err
		}

		volumesStatus = append(volumesStatus, vmv1alpha1.VolumeStatus{
			Name:    disk.Name,
			PVCName: pvcName,
			Bound:   bound,
			Size:    disk.Size,
		})
	}

	return volumesStatus, nil
}

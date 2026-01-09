/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kubevirtv1 "kubevirt.io/api/core/v1"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
	"github.com/kuihuar/novasphere/pkg/kubevirt"
	"github.com/kuihuar/novasphere/pkg/network"
	"github.com/kuihuar/novasphere/pkg/storage"
)

const (
	// finalizerName 是 Wukong 的 finalizer 名称
	finalizerName = "wukong.novasphere.dev/finalizer"
)

// WukongReconciler reconciles a Wukong object
type WukongReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=vm.novasphere.dev,resources=wukongs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=vm.novasphere.dev,resources=wukongs/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=vm.novasphere.dev,resources=wukongs/finalizers,verbs=update
// +kubebuilder:rbac:groups=kubevirt.io,resources=virtualmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kubevirt.io,resources=virtualmachineinstances,verbs=get;list;watch
// +kubebuilder:rbac:groups=k8s.cni.cncf.io,resources=networkattachmentdefinitions,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=nmstate.io,resources=nodenetworkconfigurationpolicies,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cdi.kubevirt.io,resources=datavolumes,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=persistentvolumeclaims,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=secrets,verbs=get;list;watch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
func (r *WukongReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling Wukong", "name", req.Name, "namespace", req.Namespace)

	// 1. 获取 Wukong
	var vmp vmv1alpha1.Wukong
	if err := r.Get(ctx, req.NamespacedName, &vmp); err != nil {
		if apierrors.IsNotFound(err) {
			// 资源已删除，忽略
			return ctrl.Result{}, nil
		}
		logger.Error(err, "unable to fetch Wukong")
		return ctrl.Result{}, err
	}

	// 2. 检查是否正在删除
	if !vmp.DeletionTimestamp.IsZero() {
		// 资源正在删除，执行清理逻辑
		return r.reconcileDelete(ctx, &vmp)
	}

	// 3. 添加 finalizer（如果还没有）
	if !containsString(vmp.Finalizers, finalizerName) {
		vmp.Finalizers = append(vmp.Finalizers, finalizerName)
		if err := r.Update(ctx, &vmp); err != nil {
			logger.Error(err, "unable to add finalizer")
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	// 4. 验证 spec
	if err := r.validateSpec(&vmp); err != nil {
		logger.Error(err, "invalid Wukong spec")
		vmp.Status.Phase = vmv1alpha1.PhaseError
		r.Status().Update(ctx, &vmp)
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}

	// 5. 初始化状态（如果是新资源）
	if vmp.Status.Phase == "" {
		vmp.Status.Phase = vmv1alpha1.PhasePending
		if err := r.Status().Update(ctx, &vmp); err != nil {
			logger.Error(err, "unable to update Wukong status")
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	// 6. 更新状态为 Creating（如果需要）
	if vmp.Status.Phase != vmv1alpha1.PhaseCreating && vmp.Status.Phase != vmv1alpha1.PhaseRunning {
		vmp.Status.Phase = vmv1alpha1.PhaseCreating
		if err := r.Status().Update(ctx, &vmp); err != nil {
			logger.Error(err, "unable to update Wukong status")
			return ctrl.Result{}, err
		}
	}

	// 7. 处理网络配置
	networksStatus, err := r.reconcileNetworks(ctx, &vmp)
	if err != nil {
		logger.Error(err, "failed to reconcile networks")
		vmp.Status.Phase = vmv1alpha1.PhaseError
		r.Status().Update(ctx, &vmp)
		return ctrl.Result{RequeueAfter: time.Second * 30}, err
	}

	// 8. 处理存储配置
	volumesStatus, err := r.reconcileDisks(ctx, &vmp)
	if err != nil {
		// 如果是 context canceled，requeue 而不是报错
		if ctx.Err() != nil {
			logger.V(1).Info("Context canceled during disk reconciliation, will requeue", "error", err)
			return ctrl.Result{RequeueAfter: time.Second * 10}, nil
		}
		logger.Error(err, "failed to reconcile disks")
		vmp.Status.Phase = vmv1alpha1.PhaseError
		r.Status().Update(ctx, &vmp)
		return ctrl.Result{RequeueAfter: time.Second * 30}, err
	}

	// 8.1. 处理磁盘扩展（如果磁盘大小发生变化）
	if err := storage.ReconcileDiskExpansion(ctx, r.Client, &vmp, volumesStatus); err != nil {
		logger.V(1).Info("Disk expansion in progress or failed", "error", err)
		// 磁盘扩展失败不影响整体流程，记录日志即可
		// 扩展可能需要一些时间，会在下次 reconcile 时重试
	}

	// 检查所有卷是否已绑定，如果未绑定则 requeue
	allVolumesBound := true
	for _, vol := range volumesStatus {
		if !vol.Bound {
			allVolumesBound = false
			logger.V(1).Info("Volume not bound yet, will requeue", "volume", vol.Name, "pvc", vol.PVCName)
			break
		}
	}
	if !allVolumesBound {
		logger.Info("Not all volumes are bound yet, requeuing", "volumes", len(volumesStatus))
		vmp.Status.Volumes = volumesStatus
		r.updateConditions(&vmp, networksStatus, volumesStatus, "")
		r.Status().Update(ctx, &vmp)
		return ctrl.Result{RequeueAfter: time.Second * 10}, nil
	}

	// 9. 创建/更新 VirtualMachine (KubeVirt)
	vmName, err := r.reconcileVirtualMachine(ctx, &vmp, networksStatus, volumesStatus)
	if err != nil {
		logger.Error(err, "failed to reconcile VirtualMachine")
		vmp.Status.Phase = vmv1alpha1.PhaseError
		r.Status().Update(ctx, &vmp)
		return ctrl.Result{RequeueAfter: time.Second * 30}, err
	}

	// 10. 同步 VM 状态（包括从 VMI 获取网络信息）
	vmPhase, nodeName, err := kubevirt.GetVMStatus(ctx, r.Client, vmp.Namespace, vmName)
	if err != nil {
		logger.V(1).Info("failed to get VM status", "vmName", vmName, "error", err)
		// 不返回错误，继续更新其他状态
	}

	// 11. 从 VMI 同步网络状态（如果 VM 正在运行）
	if vmPhase == "Running" && vmName != "" {
		if err := r.syncNetworkStatusFromVMI(ctx, &vmp, vmName, networksStatus); err != nil {
			logger.V(1).Info("failed to sync network status from VMI", "error", err)
		}
	}

	// 12. 更新 Wukong 状态
	vmp.Status.VMName = vmName
	vmp.Status.Networks = networksStatus
	vmp.Status.Volumes = volumesStatus
	if nodeName != "" {
		vmp.Status.NodeName = nodeName
	}

	// 根据 VM phase 更新 Wukong phase
	switch vmPhase {
	case "Running":
		vmp.Status.Phase = vmv1alpha1.PhaseRunning
	case "Scheduling", "Scheduled", "Pending":
		vmp.Status.Phase = vmv1alpha1.PhaseCreating
		// 如果正在创建，稍后重试
		return ctrl.Result{RequeueAfter: time.Second * 10}, nil
	case "Failed", "Unknown":
		vmp.Status.Phase = vmv1alpha1.PhaseError
	case "":
		// VMI 不存在，VM 可能已停止
		if vmp.Spec.StartStrategy != nil && !vmp.Spec.StartStrategy.AutoStart {
			vmp.Status.Phase = vmv1alpha1.PhaseStopped
		} else {
			vmp.Status.Phase = vmv1alpha1.PhaseCreating
			return ctrl.Result{RequeueAfter: time.Second * 10}, nil
		}
	default:
		vmp.Status.Phase = vmv1alpha1.PhaseCreating
		return ctrl.Result{RequeueAfter: time.Second * 10}, nil
	}

	// 13. 更新条件
	r.updateConditions(&vmp, networksStatus, volumesStatus, vmPhase)

	if err := r.Status().Update(ctx, &vmp); err != nil {
		logger.Error(err, "unable to update VirtualMachineProfile status")
		return ctrl.Result{}, err
	}

	logger.Info("Successfully reconciled Wukong", "name", req.Name, "phase", vmp.Status.Phase)
	return ctrl.Result{}, nil
}

// reconcileNetworks 处理网络配置
func (r *WukongReconciler) reconcileNetworks(ctx context.Context, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.NetworkStatus, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling networks (Multus + NMState)", "count", len(vmp.Spec.Networks))

	// 1. 使用 Multus 管理 NetworkAttachmentDefinition
	netStatuses, err := network.ReconcileNetworks(ctx, r.Client, vmp)
	if err != nil {
		return nil, err
	}

	// 2. 使用 NMState 预留接口（当前为 no-op，占位）
	if err := network.ReconcileNMState(ctx, r.Client, vmp); err != nil {
		return nil, err
	}

	return netStatuses, nil
}

// reconcileDisks 处理存储配置
func (r *WukongReconciler) reconcileDisks(ctx context.Context, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.VolumeStatus, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling disks (PVC/DataVolume)", "count", len(vmp.Spec.Disks))

	// 使用存储管理模块处理所有磁盘
	volumesStatus, err := storage.ReconcileDisks(ctx, r.Client, vmp)
	if err != nil {
		// 如果是 context canceled，不记录 ERROR，直接返回让上层处理
		if ctx.Err() != nil {
			logger.V(1).Info("Context canceled during disk reconciliation, will retry", "error", err)
			return nil, err
		}
		logger.Error(err, "failed to reconcile disks")
		return nil, err
	}

	return volumesStatus, nil
}

// reconcileVirtualMachine 创建/更新 KubeVirt VirtualMachine
func (r *WukongReconciler) reconcileVirtualMachine(ctx context.Context, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus) (string, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling VirtualMachine (KubeVirt)")

	// 使用 KubeVirt 模块创建/更新 VM
	vmName, err := kubevirt.ReconcileVirtualMachine(ctx, r.Client, vmp, networks, volumes)
	if err != nil {
		logger.Error(err, "failed to reconcile VirtualMachine")
		return "", err
	}

	return vmName, nil
}

// reconcileDelete 处理资源删除时的清理逻辑
func (r *WukongReconciler) reconcileDelete(ctx context.Context, vmp *vmv1alpha1.Wukong) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling deletion of Wukong", "name", vmp.Name)

	// 1. 删除 VirtualMachine（显式删除，确保资源被清理）
	if vmp.Status.VMName != "" {
		vmName := vmp.Status.VMName
		logger.Info("Deleting VirtualMachine", "name", vmName)
		vm := &kubevirtv1.VirtualMachine{}
		key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmName}
		if err := r.Get(ctx, key, vm); err == nil {
			// VirtualMachine 存在，删除它
			if err := r.Delete(ctx, vm); err != nil {
				if !apierrors.IsNotFound(err) {
					logger.Error(err, "failed to delete VirtualMachine", "name", vmName)
					return ctrl.Result{RequeueAfter: time.Second * 5}, err
				}
			} else {
				logger.Info("VirtualMachine deletion initiated", "name", vmName)
				// 等待 VirtualMachine 删除完成
				return ctrl.Result{RequeueAfter: time.Second * 2}, nil
			}
		} else if !apierrors.IsNotFound(err) {
			logger.Error(err, "failed to get VirtualMachine", "name", vmName)
			return ctrl.Result{RequeueAfter: time.Second * 5}, err
		}
	}

	// 2. 删除 DataVolume（先删除 DataVolume，它会自动删除 PVC）
	for _, vol := range vmp.Status.Volumes {
		if vol.PVCName != "" {
			// 检查是否是 DataVolume 创建的 PVC（DataVolume 名称通常与 PVC 名称相同）
			dvName := vol.PVCName
			logger.Info("Deleting DataVolume", "name", dvName)
			if err := storage.DeleteDataVolume(ctx, r.Client, vmp.Namespace, dvName); err != nil {
				if !apierrors.IsNotFound(err) {
					logger.Error(err, "failed to delete DataVolume", "name", dvName)
					return ctrl.Result{RequeueAfter: time.Second * 5}, err
				}
			} else {
				logger.Info("DataVolume deletion initiated", "name", dvName)
				// 等待 DataVolume 删除完成
				return ctrl.Result{RequeueAfter: time.Second * 2}, nil
			}

			// 如果 PVC 不是由 DataVolume 创建的，直接删除 PVC
			pvc := &corev1.PersistentVolumeClaim{}
			key := client.ObjectKey{Namespace: vmp.Namespace, Name: vol.PVCName}
			if err := r.Get(ctx, key, pvc); err == nil {
				// 检查是否有 ownerReference（如果有，说明会被自动删除）
				if len(pvc.OwnerReferences) == 0 {
					logger.Info("Deleting PVC", "name", vol.PVCName)
					if err := r.Delete(ctx, pvc); err != nil {
						if !apierrors.IsNotFound(err) {
							logger.Error(err, "failed to delete PVC", "name", vol.PVCName)
							return ctrl.Result{RequeueAfter: time.Second * 5}, err
						}
					} else {
						logger.Info("PVC deletion initiated", "name", vol.PVCName)
						return ctrl.Result{RequeueAfter: time.Second * 2}, nil
					}
				}
			} else if !apierrors.IsNotFound(err) {
				logger.Error(err, "failed to get PVC", "name", vol.PVCName)
				return ctrl.Result{RequeueAfter: time.Second * 5}, err
			}
		}
	}

	// 3. 删除 NetworkAttachmentDefinition（如果是由我们创建的）
	// 注意：如果 NAD 是用户手动创建的，不应该删除
	for _, net := range vmp.Status.Networks {
		if net.NADName != "" {
			logger.V(1).Info("NAD will be cleaned up", "name", net.NADName)
			// NAD 会通过 OwnerReference 或手动清理
			// 如果需要显式删除，可以在这里添加删除逻辑
		}
	}

	// 4. 检查是否所有资源都已删除
	// 如果 VirtualMachine 或 PVC 还在，继续等待
	if vmp.Status.VMName != "" {
		vm := &kubevirtv1.VirtualMachine{}
		key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmp.Status.VMName}
		if err := r.Get(ctx, key, vm); err == nil {
			logger.V(1).Info("VirtualMachine still exists, waiting for deletion", "name", vmp.Status.VMName)
			return ctrl.Result{RequeueAfter: time.Second * 2}, nil
		}
	}

	for _, vol := range vmp.Status.Volumes {
		if vol.PVCName != "" {
			pvc := &corev1.PersistentVolumeClaim{}
			key := client.ObjectKey{Namespace: vmp.Namespace, Name: vol.PVCName}
			if err := r.Get(ctx, key, pvc); err == nil {
				logger.V(1).Info("PVC still exists, waiting for deletion", "name", vol.PVCName)
				return ctrl.Result{RequeueAfter: time.Second * 2}, nil		// 3. 检查是否还有残留资源
		// 如果 VM 还在，或者还有 DataVolume/PVC 没删完，不要移除 finalizer
		// 上面的逻辑已经通过 RequeueAfter 确保了重试，这里做最后的安全检查
		
		// 4. 移除 finalizer
		vmp.Finalizers = removeString(vmp.Finalizers, finalizerName)
		if err := r.Update(ctx, vmp); err != nil {
			logger.Error(err, "unable to remove finalizer")
			return ctrl.Result{}, err
		}
	
		logger.Info("Successfully deleted Wukong and cleaned up resources", "name", vmp.Name)
		return ctrl.Result{}, nil
	}ateSpec 验证 Wukong spec 的有效性
func (r *WukongReconciler) validateSpec(vmp *vmv1alpha1.Wukong) error {
	// 验证 CPU
	if vmp.Spec.CPU < 1 || vmp.Spec.CPU > 64 {
		return fmt.Errorf("invalid CPU: must be between 1 and 64, got %d", vmp.Spec.CPU)
	}

	// 验证内存格式（基本检查）
	if vmp.Spec.Memory == "" {
		return fmt.Errorf("memory is required")
	}

	// 验证至少有一个磁盘
	if len(vmp.Spec.Disks) == 0 {
		return fmt.Errorf("at least one disk is required")
	}

	// 验证磁盘配置
	for i, disk := range vmp.Spec.Disks {
		if disk.Name == "" {
			return fmt.Errorf("disk[%d].name is required", i)
		}
		if disk.Size == "" {
			return fmt.Errorf("disk[%d].size is required", i)
		}
		if disk.StorageClassName == "" {
			return fmt.Errorf("disk[%d].storageClassName is required", i)
		}
	}

	return nil
}

// syncNetworkStatusFromVMI 从 VMI 同步网络状态（IP 地址等）
func (r *WukongReconciler) syncNetworkStatusFromVMI(ctx context.Context, vmp *vmv1alpha1.Wukong, vmName string, networks []vmv1alpha1.NetworkStatus) error {
	logger := log.FromContext(ctx)

	vmi := &kubevirtv1.VirtualMachineInstance{}
	key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmName}
	if err := r.Get(ctx, key, vmi); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}

	// 创建网络名称到索引的映射
	netMap := make(map[string]int)
	for i, net := range networks {
		netMap[net.Name] = i
	}

	// 从 VMI 状态同步接口信息
	updated := false
	for _, iface := range vmi.Status.Interfaces {
		if idx, ok := netMap[iface.Name]; ok {
			if networks[idx].MACAddress != iface.MAC {
				networks[idx].MACAddress = iface.MAC
				updated = true
			}
			if networks[idx].IPAddress != iface.IP {
				networks[idx].IPAddress = iface.IP
				updated = true
			}
			if networks[idx].Interface != iface.InterfaceName {
				networks[idx].Interface = iface.InterfaceName
				updated = true
			}
		}
	}

	if updated {
		logger.Info("Updated network status from VMI", "vmName", vmName)
	}

	return nil
}

// updateConditions 更新状态条件
func (r *WukongReconciler) updateConditions(vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus, vmPhase string) {
	now := metav1.Now()

	// Ready 条件 - 根据 VM phase 判断
	readyStatus := metav1.ConditionFalse
	readyReason := "VMNotReady"
	readyMessage := "Virtual machine is not ready"
	if vmPhase == "Running" {
		readyStatus = metav1.ConditionTrue
		readyReason = "VMRunning"
		readyMessage = "Virtual machine is running"
	} else if vmPhase == "Failed" || vmPhase == "Unknown" {
		readyReason = "VMFailed"
		readyMessage = fmt.Sprintf("Virtual machine is in %s state", vmPhase)
	} else if vmPhase != "" {
		readyReason = "VMCreating"
		readyMessage = fmt.Sprintf("Virtual machine is in %s state", vmPhase)
	}

	readyCondition := metav1.Condition{
		Type:               "Ready",
		Status:             readyStatus,
		Reason:             readyReason,
		Message:            readyMessage,
		LastTransitionTime: now,
	}

	// NetworksConfigured 条件
	networksConfigured := len(networks) > 0
	networksCondition := metav1.Condition{
		Type:               "NetworksConfigured",
		Status:             metav1.ConditionStatus(boolToConditionStatus(networksConfigured)),
		Reason:             "NetworksReady",
		Message:            fmt.Sprintf("%d networks configured", len(networks)),
		LastTransitionTime: now,
	}

	// VolumesBound 条件
	allVolumesBound := true
	for _, vol := range volumes {
		if !vol.Bound {
			allVolumesBound = false
			break
		}
	}
	volumesCondition := metav1.Condition{
		Type:               "VolumesBound",
		Status:             metav1.ConditionStatus(boolToConditionStatus(allVolumesBound)),
		Reason:             "VolumesReady",
		Message:            fmt.Sprintf("%d volumes bound", len(volumes)),
		LastTransitionTime: now,
	}

	// 简化实现：直接覆盖当前 Conditions 列表，避免复杂的切片操作导致的 deep copy panic
	vmp.Status.Conditions = []metav1.Condition{
		readyCondition,
		networksCondition,
		volumesCondition,
	}
}

// boolToConditionStatus 将 bool 转换为 ConditionStatus
func boolToConditionStatus(b bool) string {
	if b {
		return string(metav1.ConditionTrue)
	}
	return string(metav1.ConditionFalse)
}

// SetupWithManager sets up the controller with the Manager.
func (r *WukongReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&vmv1alpha1.Wukong{}).
		Named("wukong").
		Complete(r)
}

// containsString 检查字符串切片是否包含指定字符串
func containsString(slice []string, s string) bool {
	for _, item := range slice {
		if item == s {
			return true
		}
	}
	return false
}

// removeString 从字符串切片中移除指定字符串
func removeString(slice []string, s string) []string {
	var result []string
	for _, item := range slice {
		if item == s {
			continue
		}
		result = append(result, item)
	}
	return result
}

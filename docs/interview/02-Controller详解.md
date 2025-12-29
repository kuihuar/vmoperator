# Controller 详解

## 1. Controller 概述

`WukongReconciler` 是项目的核心 Controller，负责协调 Wukong CRD 的期望状态和实际状态。

### 1.1 核心职责

- **状态同步**: 持续监控 Wukong 资源，确保实际状态与期望状态一致
- **资源创建**: 根据 Spec 创建网络、存储、虚拟机等资源
- **生命周期管理**: 处理资源的创建、更新、删除
- **错误恢复**: 检测并修复不一致状态

### 1.2 关键代码位置

```go
// internal/controller/wukong_controller.go
type WukongReconciler struct {
    client.Client
    Scheme *runtime.Scheme
}
```

## 2. Reconcile 循环

### 2.1 Reconcile 函数流程

```go
func (r *WukongReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. 获取 Wukong 资源
    // 2. 检查删除状态
    // 3. 添加 Finalizer
    // 4. 验证 Spec
    // 5. 初始化状态
    // 6. 处理网络配置
    // 7. 处理存储配置
    // 8. 创建/更新 VirtualMachine
    // 9. 同步状态
    // 10. 更新 Conditions
}
```

### 2.2 关键步骤详解

#### 步骤 1: 获取资源

```go
var vmp vmv1alpha1.Wukong
if err := r.Get(ctx, req.NamespacedName, &vmp); err != nil {
    if apierrors.IsNotFound(err) {
        return ctrl.Result{}, nil  // 资源已删除，忽略
    }
    return ctrl.Result{}, err
}
```

#### 步骤 2: 处理删除

```go
if !vmp.DeletionTimestamp.IsZero() {
    return r.reconcileDelete(ctx, &vmp)
}
```

#### 步骤 3: Finalizer 管理

```go
if !containsString(vmp.Finalizers, finalizerName) {
    vmp.Finalizers = append(vmp.Finalizers, finalizerName)
    if err := r.Update(ctx, &vmp); err != nil {
        return ctrl.Result{}, err
    }
    return ctrl.Result{Requeue: true}, nil
}
```

**Finalizer 的作用**:
- 确保资源删除前完成清理工作
- 防止资源被意外删除

## 3. 网络配置处理

### 3.1 reconcileNetworks

```go
func (r *WukongReconciler) reconcileNetworks(ctx context.Context, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.NetworkStatus, error) {
    // 1. 使用 Multus 管理 NetworkAttachmentDefinition
    netStatuses, err := network.ReconcileNetworks(ctx, r.Client, vmp)
    
    // 2. 使用 NMState 预留接口（占位）
    if err := network.ReconcileNMState(ctx, r.Client, vmp); err != nil {
        return nil, err
    }
    
    return netStatuses, nil
}
```

**处理逻辑**:
- 为每个 `NetworkConfig` 创建或查找 `NetworkAttachmentDefinition`
- 如果用户指定了 `NADName`，直接使用；否则自动创建
- 返回网络状态列表

## 4. 存储配置处理

### 4.1 reconcileDisks

```go
func (r *WukongReconciler) reconcileDisks(ctx context.Context, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.VolumeStatus, error) {
    // 使用存储管理模块处理所有磁盘
    volumesStatus, err := storage.ReconcileDisks(ctx, r.Client, vmp)
    return volumesStatus, nil
}
```

**处理逻辑**:
- 遍历所有 `DiskConfig`
- 如果指定了 `Image`，创建 `DataVolume`；否则创建 `PVC`
- 等待卷绑定完成
- 返回卷状态列表

### 4.2 磁盘扩展

```go
// 处理磁盘扩展（如果磁盘大小发生变化）
if err := storage.ReconcileDiskExpansion(ctx, r.Client, &vmp, volumesStatus); err != nil {
    logger.V(1).Info("Disk expansion in progress or failed", "error", err)
}
```

### 4.3 等待卷绑定

```go
// 检查所有卷是否已绑定
allVolumesBound := true
for _, vol := range volumesStatus {
    if !vol.Bound {
        allVolumesBound = false
        break
    }
}
if !allVolumesBound {
    return ctrl.Result{RequeueAfter: time.Second * 10}, nil
}
```

## 5. VirtualMachine 创建

### 5.1 reconcileVirtualMachine

```go
func (r *WukongReconciler) reconcileVirtualMachine(ctx context.Context, vmp *vmv1alpha1.Wukong, 
    networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus) (string, error) {
    
    // 使用 KubeVirt 模块创建/更新 VM
    vmName, err := kubevirt.ReconcileVirtualMachine(ctx, r.Client, vmp, networks, volumes)
    return vmName, nil
}
```

**时机**: 只有在所有网络和存储都配置完成后，才创建 VirtualMachine。

## 6. 状态同步

### 6.1 从 VMI 获取状态

```go
// 同步 VM 状态（包括从 VMI 获取网络信息）
vmPhase, nodeName, err := kubevirt.GetVMStatus(ctx, r.Client, vmp.Namespace, vmName)
```

### 6.2 更新 Wukong Status

```go
// 根据 VM phase 更新 Wukong phase
switch vmPhase {
case "Running":
    vmp.Status.Phase = vmv1alpha1.PhaseRunning
case "Scheduling", "Scheduled", "Pending":
    vmp.Status.Phase = vmv1alpha1.PhaseCreating
    return ctrl.Result{RequeueAfter: time.Second * 10}, nil
case "Failed", "Unknown":
    vmp.Status.Phase = vmv1alpha1.PhaseError
}
```

## 7. Conditions 管理

### 7.1 updateConditions

```go
func (r *WukongReconciler) updateConditions(vmp *vmv1alpha1.Wukong, 
    networks []vmv1alpha1.NetworkStatus, 
    volumes []vmv1alpha1.VolumeStatus, 
    vmPhase string) {
    
    // Ready 条件
    readyCondition := metav1.Condition{
        Type:    "Ready",
        Status:  readyStatus,
        Reason:  readyReason,
        Message: readyMessage,
    }
    
    // NetworksConfigured 条件
    // VolumesBound 条件
}
```

**Conditions 类型**:
- `Ready`: VM 是否就绪
- `NetworksConfigured`: 网络是否配置完成
- `VolumesBound`: 存储卷是否绑定

## 8. 删除处理

### 8.1 reconcileDelete

```go
func (r *WukongReconciler) reconcileDelete(ctx context.Context, vmp *vmv1alpha1.Wukong) (ctrl.Result, error) {
    // 1. 删除 VirtualMachine (通过 OwnerReference 自动删除)
    // 2. 删除 PVC/DataVolume (通过 OwnerReference 自动删除)
    // 3. 删除 NetworkAttachmentDefinition
    // 4. 移除 Finalizer
}
```

**清理顺序**:
1. VirtualMachine 和 VMI
2. PVC 和 DataVolume
3. NetworkAttachmentDefinition
4. 移除 Finalizer（允许资源删除）

## 9. 错误处理

### 9.1 Context Canceled 处理

```go
if ctx.Err() != nil {
    logger.V(1).Info("Context canceled, will requeue", "error", err)
    return ctrl.Result{RequeueAfter: time.Second * 10}, nil
}
```

### 9.2 错误状态设置

```go
if err != nil {
    logger.Error(err, "failed to reconcile")
    vmp.Status.Phase = vmv1alpha1.PhaseError
    r.Status().Update(ctx, &vmp)
    return ctrl.Result{RequeueAfter: time.Second * 30}, err
}
```

## 10. Requeue 策略

### 10.1 立即 Requeue

```go
return ctrl.Result{Requeue: true}, nil
```

**场景**: 
- 添加 Finalizer 后
- 初始化状态后

### 10.2 延迟 Requeue

```go
return ctrl.Result{RequeueAfter: time.Second * 10}, nil
```

**场景**:
- 等待卷绑定
- VM 正在创建中
- 错误恢复

### 10.3 不 Requeue

```go
return ctrl.Result{}, nil
```

**场景**:
- 资源已删除
- 状态已同步完成

## 11. RBAC 权限

```go
// +kubebuilder:rbac:groups=vm.novasphere.dev,resources=wukongs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kubevirt.io,resources=virtualmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=k8s.cni.cncf.io,resources=networkattachmentdefinitions,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cdi.kubevirt.io,resources=datavolumes,verbs=get;list;watch;create;update;patch;delete
```

## 12. 面试要点

### 12.1 为什么需要 Finalizer？

**答案**: 
- 确保资源删除前完成清理工作
- 防止级联删除时资源残留
- 保证数据一致性

### 12.2 Reconcile 循环的设计原则？

**答案**:
- **幂等性**: 多次执行结果相同
- **可重试**: 错误时自动重试
- **状态驱动**: 根据当前状态决定下一步操作
- **优雅降级**: 部分失败不影响整体流程

### 12.3 如何处理资源创建的顺序？

**答案**:
1. 先创建网络配置（NetworkAttachmentDefinition）
2. 再创建存储配置（PVC/DataVolume），等待绑定
3. 最后创建 VirtualMachine（依赖网络和存储）

### 12.4 状态同步的时机？

**答案**:
- 每次 Reconcile 都会同步状态
- 从底层资源（VMI、PVC）获取实际状态
- 更新 Wukong Status 和 Conditions
- 根据状态决定是否需要 Requeue


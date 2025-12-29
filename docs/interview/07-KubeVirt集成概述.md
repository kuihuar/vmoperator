# KubeVirt 集成概述

## 1. KubeVirt 简介

KubeVirt 是在 Kubernetes 上运行虚拟机的 Operator，允许在容器环境中运行传统的虚拟机工作负载。

### 1.1 核心概念

- **VirtualMachine (VM)**: 虚拟机的定义，类似于 Deployment
- **VirtualMachineInstance (VMI)**: 运行中的虚拟机实例，类似于 Pod
- **关系**: VM 管理 VMI 的生命周期

### 1.2 在项目中的作用

VM Operator 将 Wukong CRD 转换为 KubeVirt VirtualMachine，实现虚拟机的创建和管理。

## 2. 集成架构

```
Wukong Spec
    ↓
Controller 处理网络和存储
    ↓
kubevirt.ReconcileVirtualMachine()
    ↓
构建 VirtualMachine 对象
    ↓
创建/更新 VirtualMachine
    ↓
KubeVirt 创建 VirtualMachineInstance
    ↓
虚拟机运行
```

## 3. 关键函数

### 3.1 ReconcileVirtualMachine

```go
func ReconcileVirtualMachine(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, 
    networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus) (string, error)
```

**功能**: 创建或更新 KubeVirt VirtualMachine

### 3.2 GetVMStatus

```go
func GetVMStatus(ctx context.Context, c client.Client, namespace, vmName string) (string, string, error)
```

**功能**: 获取 VirtualMachine 的状态信息（phase 和 nodeName）

## 4. VirtualMachine 构建流程

### 4.1 构建步骤

```
1. buildVirtualMachine()
   ├── 设置基本元数据
   ├── 设置 OwnerReference
   └── 构建 Spec
       ↓
2. buildVMSpec()
   ├── 配置 CPU 和内存
   ├── 配置网络接口
   ├── 配置存储卷
   ├── 配置 Cloud-Init
   └── 配置调度策略
       ↓
3. 创建或更新 VirtualMachine
```

### 4.2 VM 命名规则

```go
vmName := fmt.Sprintf("%s-vm", vmp.Name)
```

**示例**:
- Wukong: `web-server-01`
- VM: `web-server-01-vm`

## 5. OwnerReference 设置

### 5.1 作用

```go
vm.OwnerReferences = []metav1.OwnerReference{
    {
        APIVersion: vmp.APIVersion,
        Kind:       vmp.Kind,
        Name:       vmp.Name,
        UID:        vmp.UID,
        Controller: &controller,
    },
}
```

**好处**:
- 级联删除：删除 Wukong 时自动删除 VM
- 资源关联：明确资源的所有权关系

## 6. 状态同步

### 6.1 从 VMI 获取状态

```go
vmPhase, nodeName, err := kubevirt.GetVMStatus(ctx, r.Client, vmp.Namespace, vmName)
```

### 6.2 Phase 映射

| VMI Phase | Wukong Phase |
|-----------|--------------|
| `Running` | `Running` |
| `Scheduling` / `Scheduled` / `Pending` | `Creating` |
| `Failed` / `Unknown` | `Error` |
| 不存在 | `Stopped` 或 `Creating` |

## 7. 关键代码位置

- **VM 协调**: `pkg/kubevirt/vm.go` - `ReconcileVirtualMachine()`
- **VM 构建**: `pkg/kubevirt/vm.go` - `buildVirtualMachine()`, `buildVMSpec()`
- **状态获取**: `pkg/kubevirt/vm.go` - `GetVMStatus()`
- **网络配置**: `pkg/kubevirt/vm.go` - `buildNetworks()`, `buildInterfaces()`
- **存储配置**: `pkg/kubevirt/vm.go` - `buildVolumes()`, `buildDisks()`
- **Cloud-Init**: `pkg/kubevirt/vm.go` - `buildCloudInitData()`

## 8. 面试要点

### 8.1 VirtualMachine 和 VirtualMachineInstance 的区别？

**答案**:
- **VirtualMachine**: 虚拟机的定义，管理 VMI 的生命周期
- **VirtualMachineInstance**: 运行中的虚拟机实例
- 关系类似于 Deployment 和 Pod

### 8.2 为什么需要 OwnerReference？

**答案**:
- 实现级联删除：删除 Wukong 时自动删除 VM
- 明确资源所有权关系
- 符合 Kubernetes 资源管理最佳实践

### 8.3 状态同步的时机？

**答案**:
- 每次 Reconcile 都会同步状态
- 从 VMI 获取实际的运行状态
- 更新 Wukong Status 和 Phase


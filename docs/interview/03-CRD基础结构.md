# CRD 基础结构

## 1. Wukong CRD 概述

`Wukong` 是项目的核心 CRD，用于定义虚拟机的完整配置。

### 1.1 API 版本

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
```

### 1.2 基本结构

```go
type Wukong struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitzero"`
    Spec              WukongSpec   `json:"spec"`
    Status            WukongStatus `json:"status,omitzero"`
}
```

**关键特性**:
- `+kubebuilder:subresource:status`: 支持状态子资源
- `Spec`: 用户定义的期望状态
- `Status`: Controller 维护的实际状态

## 2. 核心字段概览

### 2.1 Spec 字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cpu` | int | ✅ | CPU 核心数 (1-64) |
| `memory` | string | ✅ | 内存大小 (如 "8Gi") |
| `networks` | []NetworkConfig | ❌ | 网络接口配置 |
| `disks` | []DiskConfig | ❌ | 存储磁盘配置 |
| `osImage` | string | ❌ | 操作系统镜像 |
| `sshKeySecret` | string | ❌ | SSH 密钥 Secret 名称 |
| `cloudInitUser` | CloudInitUserSpec | ❌ | Cloud-Init 用户配置 |
| `highAvailability` | HighAvailabilitySpec | ❌ | 高可用配置 |
| `startStrategy` | StartStrategySpec | ❌ | 启动策略 |

### 2.2 Status 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `phase` | string | 当前阶段 (Pending/Creating/Running/Stopped/Error) |
| `vmName` | string | 对应的 KubeVirt VirtualMachine 名称 |
| `nodeName` | string | VM 运行的节点名称 |
| `conditions` | []Condition | 状态条件列表 |
| `networks` | []NetworkStatus | 网络状态列表 |
| `volumes` | []VolumeStatus | 存储卷状态列表 |

## 3. Phase 状态机

```
Pending → Creating → Running
              ↓
          Stopped/Error
```

### 3.1 Phase 定义

```go
const (
    PhasePending  = "Pending"   // 初始状态，等待处理
    PhaseCreating = "Creating"  // 正在创建资源
    PhaseRunning  = "Running"   // VM 正在运行
    PhaseStopped  = "Stopped"   // VM 已停止
    PhaseError    = "Error"     // 发生错误
)
```

### 3.2 Phase 转换逻辑

```go
// 根据 VM phase 更新 Wukong phase
switch vmPhase {
case "Running":
    vmp.Status.Phase = vmv1alpha1.PhaseRunning
case "Scheduling", "Scheduled", "Pending":
    vmp.Status.Phase = vmv1alpha1.PhaseCreating
case "Failed", "Unknown":
    vmp.Status.Phase = vmv1alpha1.PhaseError
}
```

## 4. Conditions 机制

### 4.1 Condition 类型

```go
// Ready: VM 是否就绪
readyCondition := metav1.Condition{
    Type:    "Ready",
    Status:  metav1.ConditionTrue/False,
    Reason:  "VMRunning" / "VMNotReady",
    Message: "Virtual machine is running",
}

// NetworksConfigured: 网络是否配置完成
networksCondition := metav1.Condition{
    Type:    "NetworksConfigured",
    Status:  metav1.ConditionTrue/False,
    Reason:  "NetworksReady",
    Message: "N networks configured",
}

// VolumesBound: 存储卷是否绑定
volumesCondition := metav1.Condition{
    Type:    "VolumesBound",
    Status:  metav1.ConditionTrue/False,
    Reason:  "VolumesReady",
    Message: "N volumes bound",
}
```

### 4.2 Condition 状态判断

```go
// Ready: 根据 VM phase 判断
if vmPhase == "Running" {
    readyStatus = metav1.ConditionTrue
}

// NetworksConfigured: 检查网络数量
networksConfigured := len(networks) > 0

// VolumesBound: 检查所有卷是否绑定
allVolumesBound := true
for _, vol := range volumes {
    if !vol.Bound {
        allVolumesBound = false
        break
    }
}
```

## 5. 验证规则

### 5.1 CPU 验证

```go
// +kubebuilder:validation:Minimum=1
// +kubebuilder:validation:Maximum=64
CPU int `json:"cpu"`
```

### 5.2 Memory 验证

```go
// +kubebuilder:validation:Pattern=`^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|K|M|G|T|P|E)?$`
Memory string `json:"memory"`
```

### 5.3 网络名称验证

```go
// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
Name string `json:"name"`
```

## 6. 完整示例

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: web-server-01
  namespace: default
spec:
  cpu: 4
  memory: 8Gi
  networks:
    - name: mgmt
      type: bridge
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
  disks:
    - name: system
      size: 80Gi
      storageClassName: longhorn
      boot: true
status:
  phase: Running
  vmName: web-server-01-vm
  nodeName: host1
  conditions:
    - type: Ready
      status: "True"
      reason: VMRunning
    - type: NetworksConfigured
      status: "True"
      reason: NetworksReady
    - type: VolumesBound
      status: "True"
      reason: VolumesReady
```

## 7. 面试要点

### 7.1 为什么需要 Spec 和 Status 分离？

**答案**:
- **声明式管理**: Spec 是用户期望状态，Status 是实际状态
- **状态追踪**: Controller 通过对比 Spec 和 Status 决定操作
- **子资源**: Status 作为子资源，更新不影响 Spec 的版本号

### 7.2 Phase 和 Conditions 的区别？

**答案**:
- **Phase**: 资源的主要状态，单一值（Pending/Creating/Running）
- **Conditions**: 详细的状态条件，多个条件同时存在（Ready/NetworksConfigured/VolumesBound）
- **用途**: Phase 用于快速判断，Conditions 用于详细诊断

### 7.3 如何设计 CRD 的验证规则？

**答案**:
- 使用 `+kubebuilder:validation` 标记
- 设置最小值、最大值、正则表达式
- 在 Controller 中再次验证（双重验证）
- 提供清晰的错误信息


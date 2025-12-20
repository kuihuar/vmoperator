# 架构设计文档

## 系统架构概览

VM Operator 采用分层架构设计，从用户接口到底层基础设施，每一层都有明确的职责。

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户接口层                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         VirtualMachineProfile CRD (YAML/API)             │  │
│  │  {cpu, memory, networks, disks, highAvailability}        │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     控制层 (Control Layer)                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           VM Operator Controller (kubebuilder)            │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ 网络管理器    │  │ 存储管理器    │  │ VM 生命周期   │  │  │
│  │  │ NetworkMgr   │  │ StorageMgr   │  │ VMLifecycle  │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Multus     │  │  NMState     │  │   KubeVirt   │
│              │  │  Operator    │  │              │
│ NetworkAttach│  │ NodeNetwork  │  │ VirtualMachine│
│ mentDefinition│ │ ConfigPolicy │  │ VirtualMachine│
│              │  │              │  │   Instance   │
└──────────────┘  └──────────────┘  └──────────────┘
        │                    │                    │
        │                    │                    │
        │                    │                    ▼
        │                    │          ┌──────────────┐
        │                    │          │     CDI      │
        │                    │          │              │
        │                    │          │ DataVolume   │
        │                    │          │ DataSource   │
        │                    │          │ Import/Clone │
        │                    │          └──────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   基础设施层 (Infrastructure)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │   k3s 集群   │  │  华美存储     │  │  节点网络     │        │
│  │              │  │              │  │              │        │
│  │ API Server   │  │ CSI Driver   │  │ Linux Bridge │        │
│  │ etcd         │  │ StorageClass │  │ VLAN         │        │
│  │ Controller   │  │ PVC/PV       │  │ SR-IOV       │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

## 核心组件详解

### 1. VM Operator Controller

**职责**:
- 监听 `VirtualMachineProfile` 资源变化
- 协调网络、存储和虚拟机的创建
- 同步状态信息

**关键模块**:

#### 1.1 网络管理器 (NetworkManager)

```go
type NetworkManager struct {
    client    client.Client
    multus    MultusClient
    nmstate   NMStateClient
}

func (nm *NetworkManager) ReconcileNetworks(ctx context.Context, vmp *VirtualMachineProfile) error {
    // 1. 为每个网络创建/检查 NetworkAttachmentDefinition
    // 2. 根据需要创建 NodeNetworkConfigurationPolicy
    // 3. 等待网络配置完成
    // 4. 返回网络状态
}
```

**处理流程**:
1. 解析 `spec.networks[]`
2. 对于每个网络：
   - 如果 `nadName` 为空，创建新的 `NetworkAttachmentDefinition`
   - 如果网络类型需要节点配置（如 bridge），创建 `NodeNetworkConfigurationPolicy`
3. 等待网络资源就绪
4. 更新状态

#### 1.2 存储管理器 (StorageManager)

```go
type StorageManager struct {
    client client.Client
    cdi    CDIClient  // CDI 客户端
}

func (sm *StorageManager) ReconcileDisks(ctx context.Context, vmp *VirtualMachineProfile) error {
    // 1. 为每个磁盘创建 PersistentVolumeClaim 或 DataVolume
    // 2. 如果指定了 image，使用 CDI DataVolume 从镜像创建磁盘
    // 3. 等待 PVC/DataVolume 绑定
    // 4. 返回磁盘状态
}
```

**处理流程**:
1. 解析 `spec.disks[]`
2. 对于每个磁盘：
   - **如果指定了 `image`**：
     - 创建 `DataVolume`（CDI 资源）
     - DataVolume 会自动从容器镜像导入数据到 PVC
   - **如果未指定 `image`**：
     - 直接创建空的 `PersistentVolumeClaim`（使用指定的 `storageClassName`）
3. 等待 PVC/DataVolume 绑定完成
4. 更新状态

**CDI DataVolume 示例**:
```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: web-vm-01-system
spec:
  source:
    registry:
      url: "docker://registry.example.com/centos-stream:8"
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: huamei-sc-ssd
    resources:
      requests:
        storage: 80Gi
```

#### 1.3 VM 生命周期管理器 (VMLifecycleManager)

```go
type VMLifecycleManager struct {
    client    client.Client
    kubevirt  KubeVirtClient
}

func (vm *VMLifecycleManager) ReconcileVM(ctx context.Context, vmp *VirtualMachineProfile, networks []NetworkStatus, volumes []VolumeStatus) error {
    // 1. 构建 VirtualMachine 对象
    // 2. 创建/更新 VirtualMachine
    // 3. 监控 VirtualMachineInstance 状态
    // 4. 同步状态到 VirtualMachineProfile
}
```

**处理流程**:
1. 构建 `VirtualMachine` 对象：
   - 设置 CPU、内存
   - 配置网络注解（Multus）
   - 挂载磁盘（PVC）
   - 配置 Cloud-Init（SSH 密钥、网络配置）
2. 创建或更新 `VirtualMachine`
3. 监控 `VirtualMachineInstance` 状态
4. 同步 IP 地址、运行状态等到 `VirtualMachineProfile.Status`

### 2. Multus CNI 集成

**作用**: 为 Pod/VM 提供多网络接口支持

**关键资源**: `NetworkAttachmentDefinition`

**示例配置**:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: mgmt-net
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-mgmt",
      "vlan": 100,
      "ipam": {
        "type": "static",
        "addresses": [{"address": "192.168.100.10/24"}]
      }
    }
```

**在 VM 中使用**:

```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [
        {"name": "mgmt-net", "interface": "net1"},
        {"name": "business-net", "interface": "net2"}
      ]
```

### 3. NMState Operator 集成

**作用**: 管理节点级网络配置（桥接、VLAN、Bond 等）

**关键资源**: `NodeNetworkConfigurationPolicy`

**示例配置**:

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: br-mgmt-policy
spec:
  desiredState:
    interfaces:
      - name: br-mgmt
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: eth1
              vlan:
                id: 100
```

**处理时机**:
- 当网络类型为 `bridge` 且需要创建新桥接时
- 当需要配置 SR-IOV 设备时
- 当需要配置 VLAN 时

### 4. CDI (Containerized Data Importer) 集成

**作用**: KubeVirt 的数据导入/导出工具，用于从容器镜像创建虚拟机磁盘

**关键资源**:
- `DataVolume`: 数据卷定义，用于从镜像导入数据到 PVC
- `DataSource`: 数据源定义，可重用的数据源
- `DataImportCron`: 定期同步数据源

**使用场景**:
1. **从容器镜像创建磁盘**: 当 `spec.disks[].image` 指定时，使用 DataVolume 从镜像导入
2. **磁盘克隆**: 从现有 PVC 克隆新磁盘
3. **磁盘导入**: 从 URL、S3 等外部源导入数据

**DataVolume 工作流程**:
```
用户指定 disk.image
    │
    ▼
创建 DataVolume
    │
    ▼
CDI Controller 处理
    │
    ├─→ 从镜像仓库拉取镜像
    ├─→ 转换为磁盘格式 (qcow2/raw)
    └─→ 写入 PVC
    │
    ▼
PVC 绑定完成，可供 VM 使用
```

**示例配置**:
```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: web-vm-01-system
spec:
  source:
    registry:
      url: "docker://registry.example.com/centos-stream:8"
      pullMethod: node  # 或 pod
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: huamei-sc-ssd
    resources:
      requests:
        storage: 80Gi
```

**在 VM Operator 中的集成**:
- 存储管理器检查 `disk.image` 字段
- 如果存在，创建 DataVolume 而不是直接创建 PVC
- 等待 DataVolume 状态变为 `Succeeded`
- 使用 DataVolume 创建的 PVC 挂载到 VM

### 5. KubeVirt 集成

**作用**: 在 Kubernetes 上运行和管理虚拟机

**关键资源**:
- `VirtualMachine`: 虚拟机定义
- `VirtualMachineInstance`: 运行中的虚拟机实例

**VM 配置要点**:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: web-vm-01-vm
spec:
  running: true
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: '[...]'  # Multus 网络
    spec:
      domain:
        cpu:
          cores: 4
        memory:
          guest: 8Gi
        devices:
          disks:
            - name: system
              disk:
                bus: virtio
      volumes:
        - name: system
          persistentVolumeClaim:
            claimName: web-vm-01-system
      networks:
        - name: default
          pod: {}
        - name: mgmt-net
          multus:
            networkName: mgmt-net
```

### 6. 华美存储集成

**作用**: 提供持久化存储

**关键资源**:
- `StorageClass`: 存储类定义
- `PersistentVolumeClaim`: 存储声明
- `PersistentVolume`: 持久卷（由 CSI 自动创建）

**使用方式**:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: web-vm-01-system
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: huamei-sc-ssd
  resources:
    requests:
      storage: 80Gi
```

## 数据流

### 创建虚拟机流程

```
用户创建 VirtualMachineProfile
    │
    ▼
Controller Reconcile 触发
    │
    ├─→ 网络管理器
    │   ├─→ 创建 NetworkAttachmentDefinition (Multus)
    │   ├─→ 创建 NodeNetworkConfigurationPolicy (NMState)
    │   └─→ 等待网络就绪
    │
    ├─→ 存储管理器
    │   ├─→ 检查 disk.image
    │   ├─→ 如果指定 image:
    │   │   ├─→ 创建 DataVolume (CDI)
    │   │   └─→ 等待 DataVolume 完成导入
    │   ├─→ 如果未指定 image:
    │   │   └─→ 创建 PersistentVolumeClaim
    │   └─→ 等待 PVC 绑定
    │
    └─→ VM 生命周期管理器
        ├─→ 构建 VirtualMachine 对象
        ├─→ 创建 VirtualMachine (KubeVirt)
        ├─→ 监控 VirtualMachineInstance
        └─→ 更新 VirtualMachineProfile.Status
```

### 状态同步流程

```
VirtualMachineInstance 状态变化
    │
    ▼
Controller 监控到变化
    │
    ├─→ 读取 VMI 状态
    │   ├─→ phase (Running/Stopped/Error)
    │   ├─→ interfaces (IP 地址、MAC 地址)
    │   └─→ nodeName
    │
    └─→ 更新 VirtualMachineProfile.Status
        ├─→ phase
        ├─→ networks[].ipAddress
        └─→ nodeName
```

## 扩展点

### 1. 自定义网络插件

可以通过实现 `NetworkPlugin` 接口支持新的网络类型：

```go
type NetworkPlugin interface {
    CreateNAD(ctx context.Context, network NetworkConfig) (*NetworkAttachmentDefinition, error)
    CreateNNCP(ctx context.Context, network NetworkConfig) (*NodeNetworkConfigurationPolicy, error)
    Validate(network NetworkConfig) error
}
```

### 2. 自定义存储后端

可以通过实现 `StorageBackend` 接口支持新的存储类型：

```go
type StorageBackend interface {
    CreateVolume(ctx context.Context, disk DiskConfig) (*PersistentVolumeClaim, error)
    DeleteVolume(ctx context.Context, pvcName string) error
    Validate(disk DiskConfig) error
}
```

### 3. 自定义 VM 模板

可以通过实现 `VMTemplate` 接口支持不同的操作系统模板：

```go
type VMTemplate interface {
    BuildVM(vmp *VirtualMachineProfile, networks []NetworkStatus, volumes []VolumeStatus) (*VirtualMachine, error)
    GetCloudInitConfig(vmp *VirtualMachineProfile) (string, error)
}
```

## 安全考虑

### 1. RBAC 配置

Controller 需要以下权限：
- `VirtualMachineProfile` 资源的 CRUD
- `NetworkAttachmentDefinition` 的创建
- `NodeNetworkConfigurationPolicy` 的创建
- `PersistentVolumeClaim` 的创建
- `DataVolume` 的创建和查询（CDI）
- `VirtualMachine` 和 `VirtualMachineInstance` 的 CRUD

### 2. 网络隔离

- 使用 NetworkPolicy 限制 VM 之间的网络通信
- 使用 VLAN 隔离不同业务网络
- 使用防火墙规则限制外部访问

### 3. 存储安全

- 使用 StorageClass 的加密选项
- 限制 PVC 的访问模式
- 定期备份重要数据

## 性能优化

### 1. 并发处理

- 使用工作队列处理多个 VirtualMachineProfile
- 网络和存储创建可以并行进行
- 批量创建资源减少 API 调用

### 2. 缓存策略

- 缓存 StorageClass 和 NetworkAttachmentDefinition
- 使用 Informer 减少 API Server 压力
- 定期刷新缓存

### 3. 资源限制

- 限制同时创建的 VM 数量
- 使用资源配额（ResourceQuota）
- 监控节点资源使用情况

## 监控和可观测性

### 1. 指标

- VirtualMachineProfile 创建/更新/删除数量
- VM 启动成功率
- 网络配置成功率
- 存储绑定成功率
- 平均创建时间

### 2. 日志

- Controller 操作日志
- 网络配置日志
- 存储操作日志
- VM 生命周期日志

### 3. 追踪

- 使用 OpenTelemetry 追踪请求流程
- 记录每个阶段的耗时
- 识别性能瓶颈

---

**文档版本**: v1.0.0  
**最后更新**: 2024-01-01


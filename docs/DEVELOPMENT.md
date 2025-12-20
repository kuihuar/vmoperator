# 定制虚拟机开发项目 - 开发文档

## 目录

- [项目概述](#项目概述)
- [技术架构](#技术架构)
- [技术栈说明](#技术栈说明)
- [环境准备](#环境准备)
- [项目结构](#项目结构)
- [API 设计](#api-设计)
- [开发步骤](#开发步骤)
- [集成方案](#集成方案)
- [部署指南](#部署指南)
- [测试方案](#测试方案)
- [故障排查](#故障排查)

---

## 项目概述

### 项目目标

本项目旨在基于 Kubernetes 生态构建一个**定制虚拟机管理平台**，通过统一的 CRD（Custom Resource Definition）接口，简化虚拟机的创建、配置和管理流程。

### 核心功能

1. **统一虚拟机管理接口**：通过自定义 CRD 提供简洁的虚拟机配置方式
2. **多网络支持**：支持虚拟机配置多个网络接口（管理网、业务网等）
3. **灵活存储管理**：集成华美存储，支持多种存储类型和配置
4. **网络自动化配置**：自动配置节点网络（VLAN、桥接、SR-IOV等）
5. **高可用支持**：支持虚拟机高可用、反亲和性等策略

### 用户价值

- **简化操作**：用户只需编写一个 YAML 文件即可创建完整的虚拟机环境
- **自动化配置**：自动处理网络、存储等底层配置细节
- **统一管理**：在 Kubernetes 平台上统一管理虚拟机和容器工作负载

---

## 技术架构

### 整体架构图

```
┌─────────────────────────────────────────────────────────┐
│                   用户层 (User Layer)                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │     VirtualMachineProfile CRD (自定义资源)        │  │
│  │  {cpu, memory, networks, disks, ha...}          │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              VM Operator (kubebuilder)                  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  VirtualMachineProfile Controller                │  │
│  │  - 网络管理 (Multus + NMState)                    │  │
│  │  - 存储管理 (华美存储)                             │  │
│  │  - 虚拟机生命周期 (KubeVirt)                       │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   KubeVirt   │  │    Multus    │  │  NMState     │
│              │  │              │  │  Operator    │
│ VirtualMachine│ │ NetworkAttach│ │ NodeNetwork  │
│ VirtualMachine│ │ mentDefinition│ │ ConfigPolicy │
│   Instance   │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
        │                 │                 │
        │                 │                 │
        │                 │                 ▼
        │                 │          ┌──────────────┐
        │                 │          │     CDI      │
        │                 │          │              │
        │                 │          │ DataVolume   │
        │                 │          │ DataSource   │
        │                 │          │ Import/Clone │
        │                 │          └──────────────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              基础设施层 (Infrastructure)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   k3s 集群   │  │  华美存储     │  │  节点网络     │ │
│  │              │  │              │  │              │ │
│  │  - API Server│  │  - CSI Driver│  │  - Bridge    │ │
│  │  - etcd      │  │  - Storage   │  │  - VLAN      │ │
│  │  - Controller│  │    Class     │  │  - SR-IOV    │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 数据流

1. **用户创建 VirtualMachineProfile** → Operator Controller 监听到资源创建
2. **网络配置阶段**：
   - 检查/创建 `NetworkAttachmentDefinition` (Multus)
   - 检查/创建 `NodeNetworkConfigurationPolicy` (NMState)
3. **存储配置阶段**：
   - 如果指定了 `disk.image`：创建 `DataVolume` (CDI)，从容器镜像导入数据到 PVC
   - 如果未指定 `image`：直接创建 `PersistentVolumeClaim` (使用华美存储 StorageClass)
   - 等待 PVC/DataVolume 绑定完成
4. **虚拟机创建阶段**：
   - 创建 `VirtualMachine` (KubeVirt)
   - 配置网络注解、磁盘挂载、CPU/内存等
5. **状态同步**：
   - 监控 `VirtualMachineInstance` 状态
   - 更新 `VirtualMachineProfile.Status`

---

## 技术栈说明

### 核心组件

| 组件 | 版本要求 | 作用 | 官方文档 |
|------|---------|------|---------|
| **k3s** | >= 1.24 | 轻量级 Kubernetes 发行版，作为集群基础 | https://k3s.io |
| **kubebuilder** | >= 3.0 | Operator 开发框架 | https://book.kubebuilder.io |
| **KubeVirt** | >= 0.58 | 在 K8s 上运行虚拟机的 Operator | https://kubevirt.io |
| **CDI** | >= 1.57 | 容器化数据导入工具，用于从镜像创建磁盘 | https://github.com/kubevirt/containerized-data-importer |
| **Multus CNI** | >= 3.9 | 多网络接口支持 | https://github.com/k8snetworkplumbingwg/multus-cni |
| **NMState Operator** | >= 0.73 | 节点网络配置管理 | https://nmstate.github.io |
| **华美存储** | 根据厂商 | 分布式存储 CSI 驱动 | 厂商文档 |

### 依赖关系

```
k3s (基础集群)
  ├── CDI (数据导入工具)
  │   └── 支持从镜像创建磁盘
  ├── KubeVirt (虚拟化层)
  │   └── 依赖 CDI
  ├── Multus CNI (多网络支持)
  ├── NMState Operator (网络配置)
  ├── 华美存储 CSI (存储驱动)
  └── VM Operator (本项目 - 统一管理)
```

---

## 环境准备

### 1. 硬件要求

- **CPU**: 支持虚拟化扩展（Intel VT-x / AMD-V）
- **内存**: 至少 8GB（推荐 16GB+）
- **存储**: 至少 50GB 可用空间
- **网络**: 至少 2 个网络接口（用于多网络测试）

### 2. 软件要求

```bash
# 操作系统：Linux (推荐 Ubuntu 20.04+) 或 macOS (用于开发)
# 容器运行时：containerd (k3s 自带) 或 Docker

# 必需工具
- kubectl >= 1.24
- kubebuilder >= 3.0
- go >= 1.19
- docker (可选，用于构建镜像)
- make
```

### 3. 安装 k3s

```bash
# 快速安装
curl -sfL https://get.k3s.io | sh -

# 或使用自定义配置
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

# 验证安装
sudo k3s kubectl get nodes
```

### 4. 安装 kubebuilder

```bash
# macOS
brew install kubebuilder

# Linux
# 下载并安装
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && sudo mv kubebuilder /usr/local/bin/

# 验证
kubebuilder version
```

### 5. 安装基础组件（按顺序）

> **注意**: 详细组件清单请参考 [完整组件清单](COMPONENTS.md)

#### 5.1 安装 CDI (Containerized Data Importer)

CDI 是 KubeVirt 的数据导入工具，必须先安装：

```bash
# 设置版本
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 安装 CDI Operator
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

# 安装 CDI CR
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 等待就绪
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s

# 验证
kubectl get pods -n cdi
```

#### 5.2 安装 KubeVirt

```bash
# 设置版本
export VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)

# 安装 CRD
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml

# 等待就绪
kubectl wait -n kubevirt kv kubevirt --for condition=Available --timeout=300s
```

#### 5.3 安装 Multus CNI

```bash
# 克隆仓库
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git
cd multus-cni

# 安装
cat ./deployments/multus-daemonset-thick.yml | kubectl apply -f -

# 验证
kubectl get pods -n kube-system | grep multus
```

#### 5.4 安装 NMState Operator

```bash
# 创建命名空间
kubectl create namespace nmstate

# 安装 Operator
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.73.0/nmstate-operator.yaml

# 等待就绪
kubectl wait -n nmstate --for=condition=ready pod -l app=kubernetes-nmstate-operator --timeout=300s
```

#### 5.5 安装华美存储

> **注意**: 根据华美存储厂商提供的文档进行安装，一般包括：
> - CSI Driver 部署
> - StorageClass 创建
> - 权限配置

```bash
# 示例（请根据实际文档调整）
# kubectl apply -f huamei-csi-driver.yaml
# kubectl apply -f huamei-storageclass.yaml
```

### 6. 验证环境

```bash
# 检查 k3s
kubectl get nodes

# 检查 CDI
kubectl get pods -n cdi

# 检查 KubeVirt
kubectl get pods -n kubevirt

# 检查 Multus
kubectl get pods -n kube-system | grep multus

# 检查 NMState
kubectl get pods -n nmstate

# 检查存储
kubectl get storageclass

# 检查虚拟化支持
lsmod | grep kvm
```

> **提示**: 更多组件信息请参考 [完整组件清单](COMPONENTS.md)

---

## 项目结构

### 目录结构

```
vmoperator/
├── api/                          # API 定义
│   └── v1alpha1/
│       ├── groupversion_info.go
│       ├── virtualmachineprofile_types.go  # CRD 类型定义
│       └── zz_generated.deepcopy.go
├── config/                       # 部署配置
│   ├── crd/                      # CRD 清单
│   ├── rbac/                     # RBAC 配置
│   ├── manager/                  # Manager 部署
│   └── samples/                  # 示例资源
├── controllers/                  # 控制器
│   ├── virtualmachineprofile_controller.go  # 主控制器
│   └── suite_test.go
├── pkg/                          # 内部包
│   ├── kubevirt/                 # KubeVirt 封装
│   │   ├── client.go
│   │   └── vm.go
│   ├── network/                  # 网络管理
│   │   ├── multus.go
│   │   └── nmstate.go
│   ├── storage/                  # 存储管理
│   │   └── pvc.go
│   └── utils/                    # 工具函数
│       └── helpers.go
├── hack/                         # 脚本和工具
│   └── tools.go
├── docs/                         # 文档
│   ├── DEVELOPMENT.md            # 本文档
│   └── API.md                    # API 详细说明
├── Dockerfile                    # 镜像构建
├── Makefile                      # 构建脚本
├── go.mod                        # Go 依赖
├── go.sum
└── README.md
```

---

## API 设计

### VirtualMachineProfile CRD

#### 完整 Spec 定义

```yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: web-vm-01
  namespace: default
spec:
  # 基础配置
  cpu: 4
  memory: 8Gi
  osImage: "registry.local/centos-stream:8"
  sshKeySecret: "web-vm-ssh"  # Secret 名称，包含公钥
  
  # 网络配置
  networks:
    - name: mgmt                    # 网络名称
      type: bridge                  # 网络类型: bridge, macvlan, sriov, ovs
      nadName: mgmt-net             # 可选：使用已存在的 NAD
      vlanId: 100                   # 可选：VLAN ID
      bridgeName: br-mgmt           # 可选：桥接名称（用于 bridge 类型）
      ipConfig:
        mode: static                 # static 或 dhcp
        address: 192.168.100.10/24
        gateway: 192.168.100.1
        dnsServers:
          - 8.8.8.8
          - 8.8.4.4
    - name: business
      type: sriov
      vlanId: 200
      ipConfig:
        mode: dhcp
  
  # 磁盘配置
  disks:
    - name: system
      size: 80Gi
      storageClassName: huamei-sc-ssd
      boot: true
      image: "registry.local/centos-stream:8"  # 可选：从镜像创建
    - name: data
      size: 500Gi
      storageClassName: huamei-sc-hdd
  
  # 高可用配置
  highAvailability:
    restartPolicy: Always           # Always, OnFailure, Never
    antiAffinity: true              # 是否启用反亲和性
    nodeSelector:                   # 节点选择器
      kubernetes.io/arch: amd64
  
  # 启动配置
  startStrategy:
    runStrategy: Always             # Always, RerunOnFailure, Manual
    autoStart: true                 # 是否自动启动
```

#### Status 定义

```yaml
status:
  phase: Running                    # Pending, Creating, Running, Stopped, Error
  vmName: web-vm-01-vm              # 对应的 KubeVirt VM 名称
  nodeName: node-01                 # 运行节点
  conditions:
    - type: Ready
      status: "True"
      lastTransitionTime: "2024-01-01T00:00:00Z"
    - type: NetworksConfigured
      status: "True"
    - type: VolumesBound
      status: "True"
  networks:
    - name: mgmt
      interface: eth0
      ipAddress: 192.168.100.10/24
      macAddress: "aa:bb:cc:dd:ee:ff"
    - name: business
      interface: eth1
      ipAddress: 192.168.200.50/24
      macAddress: "aa:bb:cc:dd:ee:01"
  volumes:
    - name: system
      pvcName: web-vm-01-system
      bound: true
    - name: data
      pvcName: web-vm-01-data
      bound: true
```

### Go 类型定义（预览）

```go
// api/v1alpha1/virtualmachineprofile_types.go

type VirtualMachineProfileSpec struct {
    CPU          int             `json:"cpu"`
    Memory       string          `json:"memory"`
    OSImage      string          `json:"osImage,omitempty"`
    SSHKeySecret string          `json:"sshKeySecret,omitempty"`
    
    Networks     []NetworkConfig `json:"networks,omitempty"`
    Disks        []DiskConfig    `json:"disks,omitempty"`
    
    HighAvailability *HighAvailabilitySpec `json:"highAvailability,omitempty"`
    StartStrategy    *StartStrategySpec    `json:"startStrategy,omitempty"`
}

type NetworkConfig struct {
    Name      string        `json:"name"`
    Type      string        `json:"type"`  // bridge, macvlan, sriov, ovs
    NADName   string        `json:"nadName,omitempty"`
    VLANID    *int          `json:"vlanId,omitempty"`
    BridgeName string       `json:"bridgeName,omitempty"`
    IPConfig  *IPConfigSpec `json:"ipConfig,omitempty"`
}

type IPConfigSpec struct {
    Mode       string   `json:"mode"`  // static, dhcp
    Address    *string  `json:"address,omitempty"`
    Gateway    *string  `json:"gateway,omitempty"`
    DNSServers []string `json:"dnsServers,omitempty"`
}

type DiskConfig struct {
    Name             string `json:"name"`
    Size             string `json:"size"`
    StorageClassName string `json:"storageClassName"`
    Boot             bool   `json:"boot,omitempty"`
    Image            string `json:"image,omitempty"`
}

type HighAvailabilitySpec struct {
    RestartPolicy string            `json:"restartPolicy,omitempty"`
    AntiAffinity  bool              `json:"antiAffinity,omitempty"`
    NodeSelector  map[string]string `json:"nodeSelector,omitempty"`
}

type StartStrategySpec struct {
    RunStrategy string `json:"runStrategy,omitempty"`
    AutoStart   bool   `json:"autoStart,omitempty"`
}

type VirtualMachineProfileStatus struct {
    Phase    string                   `json:"phase,omitempty"`
    VMName   string                   `json:"vmName,omitempty"`
    NodeName string                   `json:"nodeName,omitempty"`
    Conditions []metav1.Condition     `json:"conditions,omitempty"`
    Networks []NetworkStatus          `json:"networks,omitempty"`
    Volumes  []VolumeStatus           `json:"volumes,omitempty"`
}
```

---

## 开发步骤

### 阶段 1: 项目初始化

#### 1.1 初始化 kubebuilder 项目

```bash
# 进入项目目录
cd /Users/jianfenliu/Workspace/vmoperator

# 初始化项目
# --domain: API 组的域名，用于生成 CRD 的 API 组名（如 vm.example.com）
# --repo: Go 模块路径，对应 go.mod 中的 module 声明
kubebuilder init --domain=example.com --repo=github.com/jianfenliu/vmoperator

# 创建 API
kubebuilder create api --group=vm --version=v1alpha1 --kind=VirtualMachineProfile
# 选择: Y (创建 Resource) 和 Y (创建 Controller)
```

> **参数说明**:
> - `--domain=example.com`: 定义 API 组域名，最终 API 版本为 `vm.example.com/v1alpha1`
>   - 如果有公司域名，可以使用公司域名（如 `mycompany.com`）
>   - 开发测试可以使用 `example.com` 或 `local.dev`
> - `--repo=github.com/jianfenliu/vmoperator`: 定义 Go 模块路径
>   - 应该与实际的代码仓库路径一致
>   - 如果使用 GitHub，格式为 `github.com/username/vmoperator`
>   - 如果使用 GitLab，格式为 `gitlab.com/group/vmoperator`
>
> **详细说明**: 请参考 [kubebuilder init 参数说明](KUBEBUILDER_INIT.md)

#### 1.2 配置依赖

编辑 `go.mod`，添加必要的依赖：

```bash
go get k8s.io/api/core/v1
go get k8s.io/apimachinery/pkg/apis/meta/v1
go get sigs.k8s.io/controller-runtime/pkg/client
go get kubevirt.io/api/core/v1
go get kubevirt.io/containerized-data-importer-api/pkg/apis/core/v1beta1
go get github.com/k8snetworkplumbingwg/network-attachment-definition-client/pkg/apis/k8s.cni.cncf.io/v1
go get github.com/nmstate/kubernetes-nmstate/api/v1
```

### 阶段 2: 定义 CRD 类型

#### 2.1 编辑类型定义

编辑 `api/v1alpha1/virtualmachineprofile_types.go`，实现完整的 Spec 和 Status 结构。

#### 2.2 生成代码

```bash
make generate
make manifests
```

### 阶段 3: 实现控制器逻辑

#### 3.1 网络管理模块

创建 `pkg/network/multus.go` 和 `pkg/network/nmstate.go`，实现：
- 创建/更新 `NetworkAttachmentDefinition`
- 创建/更新 `NodeNetworkConfigurationPolicy`
- 网络状态检查

#### 3.2 存储管理模块

创建 `pkg/storage/pvc.go` 和 `pkg/storage/datavolume.go`，实现：
- 检查 `disk.image` 字段
- 如果指定了 `image`：创建 `DataVolume` (CDI)
- 如果未指定 `image`：创建 `PersistentVolumeClaim`
- 等待 PVC/DataVolume 绑定
- 清理 PVC/DataVolume

#### 3.3 KubeVirt 集成模块

创建 `pkg/kubevirt/vm.go`，实现：
- 构建 `VirtualMachine` 对象
- 配置网络注解
- 配置磁盘挂载
- 状态同步

#### 3.4 主控制器

编辑 `controllers/virtualmachineprofile_controller.go`，实现 `Reconcile` 逻辑：

```go
func (r *VirtualMachineProfileReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. 获取 VirtualMachineProfile
    // 2. 处理网络配置
    // 3. 处理存储配置
    // 4. 创建/更新 VirtualMachine
    // 5. 同步状态
    // 6. 返回结果
}
```

### 阶段 4: 测试

#### 4.1 单元测试

```bash
make test
```

#### 4.2 集成测试

```bash
# 部署到集群
make deploy

# 创建测试资源
kubectl apply -f config/samples/

# 检查状态
kubectl get vmprofile
kubectl describe vmprofile <name>
```

### 阶段 5: 构建和部署

#### 5.1 构建镜像

```bash
make docker-build IMG=your-registry/vmoperator:latest
make docker-push IMG=your-registry/vmoperator:latest
```

#### 5.2 部署 Operator

```bash
make deploy IMG=your-registry/vmoperator:latest
```

---

## 集成方案

### 1. Multus 集成

#### 1.1 自动创建 NetworkAttachmentDefinition

当 `spec.networks[].nadName` 为空时，Operator 自动创建 NAD：

```go
// pkg/network/multus.go
func CreateNAD(ctx context.Context, client client.Client, network NetworkConfig, namespace string) error {
    nad := &netattdefv1.NetworkAttachmentDefinition{
        ObjectMeta: metav1.ObjectMeta{
            Name:      network.Name + "-nad",
            Namespace: namespace,
        },
        Spec: netattdefv1.NetworkAttachmentDefinitionSpec{
            Config: buildCNIConfig(network),
        },
    }
    return client.Create(ctx, nad)
}
```

#### 1.2 CNI 配置生成

根据网络类型生成对应的 CNI 配置 JSON：

- **bridge**: 使用 bridge CNI
- **macvlan**: 使用 macvlan CNI
- **sriov**: 使用 sriov CNI
- **ovs**: 使用 OVS CNI

### 2. NMState 集成

#### 2.1 节点网络策略创建

当需要配置节点级网络（如创建桥接）时，创建 `NodeNetworkConfigurationPolicy`：

```go
// pkg/network/nmstate.go
func CreateNNCP(ctx context.Context, client client.Client, network NetworkConfig) error {
    nncp := &nmstatev1.NodeNetworkConfigurationPolicy{
        ObjectMeta: metav1.ObjectMeta{
            Name: network.Name + "-nncp",
        },
        Spec: nmstatev1.NodeNetworkConfigurationPolicySpec{
            DesiredState: buildDesiredState(network),
        },
    }
    return client.Create(ctx, nncp)
}
```

#### 2.2 网络状态检查

检查 `NodeNetworkState` 以确认网络配置是否生效。

### 3. CDI 集成

#### 3.1 DataVolume 创建

当 `spec.disks[].image` 指定时，使用 CDI DataVolume 从容器镜像创建磁盘：

```go
// pkg/storage/datavolume.go
import cdiapiv1 "kubevirt.io/containerized-data-importer-api/pkg/apis/core/v1beta1"

func CreateDataVolume(ctx context.Context, client client.Client, disk DiskConfig, namespace, name string) (*cdiapiv1.DataVolume, error) {
    dv := &cdiapiv1.DataVolume{
        ObjectMeta: metav1.ObjectMeta{
            Name:      name,
            Namespace: namespace,
        },
        Spec: cdiapiv1.DataVolumeSpec{
            Source: &cdiapiv1.DataVolumeSource{
                Registry: &cdiapiv1.DataVolumeSourceRegistry{
                    URL:        disk.Image,
                    PullMethod: cdiapiv1.RegistryPullNode, // 或 RegistryPullPod
                },
            },
            PVC: &corev1.PersistentVolumeClaimSpec{
                AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
                Resources: corev1.ResourceRequirements{
                    Requests: corev1.ResourceList{
                        corev1.ResourceStorage: resource.MustParse(disk.Size),
                    },
                },
                StorageClassName: &disk.StorageClassName,
            },
        },
    }
    return dv, client.Create(ctx, dv)
}
```

#### 3.2 等待 DataVolume 完成

```go
func WaitForDataVolumeReady(ctx context.Context, client client.Client, namespace, name string, timeout time.Duration) error {
    // 轮询检查 DataVolume 状态
    // 直到 phase == Succeeded
    // DataVolume 会自动创建对应的 PVC
}
```

### 4. 华美存储集成

#### 4.1 PVC 创建

当未指定 `disk.image` 时，直接创建 PVC：

```go
// pkg/storage/pvc.go
func CreatePVC(ctx context.Context, client client.Client, disk DiskConfig, namespace, name string) (*corev1.PersistentVolumeClaim, error) {
    pvc := &corev1.PersistentVolumeClaim{
        ObjectMeta: metav1.ObjectMeta{
            Name:      name,
            Namespace: namespace,
        },
        Spec: corev1.PersistentVolumeClaimSpec{
            AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
            Resources: corev1.ResourceRequirements{
                Requests: corev1.ResourceList{
                    corev1.ResourceStorage: resource.MustParse(disk.Size),
                },
            },
            StorageClassName: &disk.StorageClassName,
        },
    }
    return pvc, client.Create(ctx, pvc)
}
```

#### 4.2 等待 PVC 绑定

```go
func WaitForPVCBound(ctx context.Context, client client.Client, namespace, name string, timeout time.Duration) error {
    // 轮询检查 PVC 状态
    // 直到 phase == Bound
}
```

### 5. KubeVirt 集成

#### 4.1 VirtualMachine 构建

```go
// pkg/kubevirt/vm.go
func BuildVM(vmp *vmv1alpha1.VirtualMachineProfile, networks []NetworkStatus, volumes []VolumeStatus) *kubevirtv1.VirtualMachine {
    vm := &kubevirtv1.VirtualMachine{
        ObjectMeta: metav1.ObjectMeta{
            Name:      vmp.Name + "-vm",
            Namespace: vmp.Namespace,
        },
        Spec: kubevirtv1.VirtualMachineSpec{
            Running: &vmp.Spec.StartStrategy.AutoStart,
            Template: &kubevirtv1.VirtualMachineInstanceTemplateSpec{
                ObjectMeta: metav1.ObjectMeta{
                    Annotations: buildNetworkAnnotations(networks),
                },
                Spec: kubevirtv1.VirtualMachineInstanceSpec{
                    Domain: kubevirtv1.DomainSpec{
                        CPU:    &kubevirtv1.CPU{Cores: uint32(vmp.Spec.CPU)},
                        Memory: &kubevirtv1.Memory{Guest: &resource.Quantity{}},
                        Devices: kubevirtv1.Devices{
                            Disks: buildDisks(volumes),
                        },
                    },
                    Networks: buildNetworks(networks),
                    Volumes:  buildVolumes(volumes),
                },
            },
        },
    }
    return vm
}
```

#### 4.2 网络注解格式

```go
func buildNetworkAnnotations(networks []NetworkStatus) map[string]string {
    annotations := make(map[string]string)
    netList := []map[string]string{}
    for i, net := range networks {
        netList = append(netList, map[string]string{
            "name":      net.NADName,
            "interface": fmt.Sprintf("net%d", i+1),
        })
    }
    netJSON, _ := json.Marshal(netList)
    annotations["k8s.v1.cni.cncf.io/networks"] = string(netJSON)
    return annotations
}
```

---

## 部署指南

### 1. 开发环境部署

```bash
# 1. 生成 CRD 和 RBAC
make manifests

# 2. 安装 CRD
make install

# 3. 运行 Controller（本地）
make run
```

### 2. 生产环境部署

```bash
# 1. 构建镜像
make docker-build IMG=registry.example.com/vmoperator:v1.0.0

# 2. 推送镜像
make docker-push IMG=registry.example.com/vmoperator:v1.0.0

# 3. 部署到集群
make deploy IMG=registry.example.com/vmoperator:v1.0.0

# 4. 验证
kubectl get pods -n vmoperator-system
kubectl get crd | grep virtualmachineprofile
```

### 3. 卸载

```bash
make undeploy
```

---

## 测试方案

### 1. 单元测试

```bash
# 运行所有测试
make test

# 运行特定测试
go test ./pkg/network/... -v
go test ./pkg/storage/... -v
go test ./pkg/kubevirt/... -v
```

### 2. 集成测试

#### 2.1 创建测试资源

```yaml
# config/samples/vm_v1alpha1_virtualmachineprofile.yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: test-vm
spec:
  cpu: 2
  memory: 4Gi
  networks:
    - name: mgmt
      type: bridge
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
  disks:
    - name: system
      size: 20Gi
      storageClassName: huamei-sc-ssd
      boot: true
```

#### 2.2 验证流程

```bash
# 1. 创建资源
kubectl apply -f config/samples/

# 2. 检查状态
kubectl get vmprofile test-vm -o yaml

# 3. 检查 NAD
kubectl get networkattachmentdefinition

# 4. 检查 PVC
kubectl get pvc

# 5. 检查 VM
kubectl get virtualmachine
kubectl get virtualmachineinstance

# 6. 检查 VM 状态
kubectl describe vmprofile test-vm
```

### 3. 端到端测试场景

1. **基础虚拟机创建**：CPU、内存、单磁盘、单网络
2. **多网络配置**：管理网 + 业务网
3. **多磁盘配置**：系统盘 + 数据盘
4. **高可用测试**：反亲和性、自动重启
5. **网络配置测试**：VLAN、桥接、SR-IOV
6. **存储测试**：不同 StorageClass、大容量磁盘
7. **故障恢复**：删除 VM 后重建、网络故障恢复

---

## 故障排查

### 常见问题

#### 1. VM 无法启动

```bash
# 检查 VM 状态
kubectl get vmi
kubectl describe vmi <name>

# 检查事件
kubectl get events --sort-by='.lastTimestamp'

# 检查日志
kubectl logs -n vmoperator-system <controller-pod>
```

#### 2. 网络配置失败

```bash
# 检查 NAD
kubectl get nad
kubectl describe nad <name>

# 检查 NNCP
kubectl get nncp
kubectl describe nncp <name>

# 检查节点网络状态
kubectl get nns
```

#### 3. 存储绑定失败

```bash
# 检查 PVC
kubectl get pvc
kubectl describe pvc <name>

# 检查 StorageClass
kubectl get storageclass
kubectl describe storageclass <name>

# 检查 PV
kubectl get pv
```

#### 4. Controller 无法运行

```bash
# 检查 RBAC
kubectl get clusterrole,clusterrolebinding | grep vmoperator

# 检查 Controller 日志
kubectl logs -n vmoperator-system deployment/vmoperator-controller-manager
```

### 调试技巧

1. **启用详细日志**：在 Controller 中设置日志级别为 `debug`
2. **使用 kubectl debug**：进入 Pod 内部调试
3. **检查资源依赖**：确保所有依赖组件（KubeVirt、Multus 等）正常运行
4. **查看资源事件**：`kubectl get events -A --sort-by='.lastTimestamp'`

---

## 下一步计划

1. ✅ **完成开发文档**（本文档）
2. ⏳ **初始化 kubebuilder 项目**
3. ⏳ **定义 CRD 类型**
4. ⏳ **实现网络管理模块**
5. ⏳ **实现存储管理模块**
6. ⏳ **实现 KubeVirt 集成**
7. ⏳ **实现主控制器逻辑**
8. ⏳ **编写单元测试**
9. ⏳ **编写集成测试**
10. ⏳ **构建和部署**

---

## 参考资源

- [KubeVirt 官方文档](https://kubevirt.io/user-guide/)
- [CDI 官方文档](https://github.com/kubevirt/containerized-data-importer)
- [Multus CNI 文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NMState Operator 文档](https://nmstate.github.io/)
- [kubebuilder 教程](https://book.kubebuilder.io/)
- [k3s 文档](https://docs.k3s.io/)

---

**文档版本**: v1.0.0  
**最后更新**: 2024-01-01  
**维护者**: VM Operator Team


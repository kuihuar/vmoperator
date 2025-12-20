# VirtualMachineProfile API 详细说明

## 概述

`VirtualMachineProfile` 是本项目的核心 CRD，用于定义虚拟机的完整配置，包括计算资源、网络、存储和高可用策略。

## API 版本

- **当前版本**: `vm.example.com/v1alpha1`
- **稳定版本**: 待定

## 资源定义

### 完整 YAML 示例

```yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: web-server-01
  namespace: production
  labels:
    app: web-server
    tier: frontend
spec:
  # ========== 基础配置 ==========
  cpu: 4
  memory: 8Gi
  osImage: "registry.example.com/centos-stream:8"
  sshKeySecret: "web-server-ssh-keys"
  
  # ========== 网络配置 ==========
  networks:
    # 管理网络
    - name: management
      type: bridge
      nadName: ""  # 为空则自动创建
      vlanId: 100
      bridgeName: br-mgmt
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
        dnsServers:
          - 8.8.8.8
          - 8.8.4.4
    
    # 业务网络
    - name: business
      type: sriov
      nadName: "business-sriov-nad"  # 使用已存在的 NAD
      vlanId: 200
      ipConfig:
        mode: dhcp
    
    # 存储网络
    - name: storage
      type: macvlan
      ipConfig:
        mode: static
        address: 10.0.0.10/24
  
  # ========== 磁盘配置 ==========
  disks:
    # 系统盘（启动盘）
    - name: system
      size: 80Gi
      storageClassName: huamei-sc-ssd
      boot: true
      image: "registry.example.com/centos-stream:8"  # 可选：从镜像创建
    
    # 数据盘
    - name: data
      size: 500Gi
      storageClassName: huamei-sc-hdd
    
    # 日志盘
    - name: logs
      size: 100Gi
      storageClassName: huamei-sc-ssd
  
  # ========== 高可用配置 ==========
  highAvailability:
    restartPolicy: Always  # Always, OnFailure, Never
    antiAffinity: true
    nodeSelector:
      kubernetes.io/arch: amd64
      node-role.kubernetes.io/worker: ""
    tolerations:
      - key: "virtualization"
        operator: "Equal"
        value: "enabled"
        effect: "NoSchedule"
  
  # ========== 启动策略 ==========
  startStrategy:
    runStrategy: Always  # Always, RerunOnFailure, Manual
    autoStart: true
```

## 字段说明

### Spec 字段

#### 基础配置

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `cpu` | `int` | 是 | CPU 核心数 | `4` |
| `memory` | `string` | 是 | 内存大小（支持 K/M/G/T/P/E 单位） | `"8Gi"` |
| `osImage` | `string` | 否 | 操作系统镜像（用于 Cloud-Init） | `"centos:8"` |
| `sshKeySecret` | `string` | 否 | 包含 SSH 公钥的 Secret 名称 | `"my-ssh-keys"` |

#### 网络配置 (`networks[]`)

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `name` | `string` | 是 | 网络名称（唯一标识） | `"management"` |
| `type` | `string` | 是 | 网络类型：`bridge`, `macvlan`, `sriov`, `ovs` | `"bridge"` |
| `nadName` | `string` | 否 | 已存在的 NetworkAttachmentDefinition 名称 | `"mgmt-nad"` |
| `vlanId` | `int` | 否 | VLAN ID（1-4094） | `100` |
| `bridgeName` | `string` | 否 | 桥接名称（仅用于 bridge 类型） | `"br-mgmt"` |
| `ipConfig` | `IPConfigSpec` | 否 | IP 配置 | 见下方 |

**IPConfigSpec**:

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `mode` | `string` | 是 | IP 获取模式：`static` 或 `dhcp` | `"static"` |
| `address` | `string` | 条件必填 | IP 地址和子网掩码（static 模式必填） | `"192.168.1.10/24"` |
| `gateway` | `string` | 否 | 网关地址（static 模式） | `"192.168.1.1"` |
| `dnsServers` | `[]string` | 否 | DNS 服务器列表 | `["8.8.8.8", "8.8.4.4"]` |

#### 磁盘配置 (`disks[]`)

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `name` | `string` | 是 | 磁盘名称（唯一标识） | `"system"` |
| `size` | `string` | 是 | 磁盘大小（支持 K/M/G/T/P/E 单位） | `"80Gi"` |
| `storageClassName` | `string` | 是 | StorageClass 名称 | `"huamei-sc-ssd"` |
| `boot` | `bool` | 否 | 是否为启动盘（默认 false） | `true` |
| `image` | `string` | 否 | 从镜像创建磁盘（使用 DataVolume） | `"centos:8"` |

#### 高可用配置 (`highAvailability`)

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `restartPolicy` | `string` | 否 | 重启策略：`Always`, `OnFailure`, `Never` | `"Always"` |
| `antiAffinity` | `bool` | 否 | 是否启用反亲和性（默认 false） | `true` |
| `nodeSelector` | `map[string]string` | 否 | 节点选择器 | `{"arch": "amd64"}` |
| `tolerations` | `[]Toleration` | 否 | 容忍度配置 | 见 K8s Toleration |

#### 启动策略 (`startStrategy`)

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `runStrategy` | `string` | 否 | 运行策略：`Always`, `RerunOnFailure`, `Manual` | `"Always"` |
| `autoStart` | `bool` | 否 | 是否自动启动（默认 true） | `true` |

### Status 字段

```yaml
status:
  phase: Running  # Pending, Creating, Running, Stopped, Error
  vmName: web-server-01-vm
  nodeName: worker-node-01
  conditions:
    - type: Ready
      status: "True"
      lastTransitionTime: "2024-01-01T00:00:00Z"
      reason: "VMRunning"
      message: "Virtual machine is running"
    - type: NetworksConfigured
      status: "True"
    - type: VolumesBound
      status: "True"
  networks:
    - name: management
      interface: eth0
      ipAddress: 192.168.100.10/24
      macAddress: "aa:bb:cc:dd:ee:ff"
      nadName: management-nad
    - name: business
      interface: eth1
      ipAddress: 192.168.200.50/24
      macAddress: "aa:bb:cc:dd:ee:01"
      nadName: business-sriov-nad
  volumes:
    - name: system
      pvcName: web-server-01-system
      bound: true
      size: 80Gi
    - name: data
      pvcName: web-server-01-data
      bound: true
      size: 500Gi
```

#### Status 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `phase` | `string` | 当前阶段：Pending, Creating, Running, Stopped, Error |
| `vmName` | `string` | 对应的 KubeVirt VirtualMachine 名称 |
| `nodeName` | `string` | 虚拟机运行的节点名称 |
| `conditions` | `[]Condition` | 状态条件列表 |
| `networks` | `[]NetworkStatus` | 网络状态列表 |
| `volumes` | `[]VolumeStatus` | 磁盘状态列表 |

## 网络类型详解

### 1. Bridge 网络

用于创建 Linux 桥接网络，适合需要 VLAN 隔离的场景。

```yaml
networks:
  - name: mgmt
    type: bridge
    bridgeName: br-mgmt
    vlanId: 100
    ipConfig:
      mode: static
      address: 192.168.100.10/24
```

**要求**:
- 节点上需要预先配置桥接设备（可通过 NMState 自动配置）
- 需要指定 `bridgeName`

### 2. Macvlan 网络

将物理网络接口直接映射到虚拟机，适合高性能网络场景。

```yaml
networks:
  - name: business
    type: macvlan
    ipConfig:
      mode: dhcp
```

**要求**:
- 节点需要有可用的物理网络接口
- 不支持 VLAN（如需 VLAN，使用 bridge 类型）

### 3. SR-IOV 网络

使用 SR-IOV 技术，提供接近物理网络的性能。

```yaml
networks:
  - name: storage
    type: sriov
    vlanId: 200
    ipConfig:
      mode: static
      address: 10.0.0.10/24
```

**要求**:
- 节点网卡需要支持 SR-IOV
- 需要预先配置 SR-IOV 设备（可通过 NMState 配置）

### 4. OVS 网络

使用 Open vSwitch，适合需要复杂网络策略的场景。

```yaml
networks:
  - name: tenant
    type: ovs
    bridgeName: br-tenant
    ipConfig:
      mode: dhcp
```

**要求**:
- 节点需要安装 OVS
- 需要指定 `bridgeName`

## 使用示例

### 示例 1: 基础虚拟机

```yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: simple-vm
spec:
  cpu: 2
  memory: 4Gi
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
  disks:
    - name: system
      size: 20Gi
      storageClassName: huamei-sc-ssd
      boot: true
```

### 示例 2: 多网络虚拟机

```yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: multi-net-vm
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
        gateway: 192.168.100.1
    - name: business
      type: sriov
      vlanId: 200
      ipConfig:
        mode: dhcp
  disks:
    - name: system
      size: 80Gi
      storageClassName: huamei-sc-ssd
      boot: true
```

### 示例 3: 高可用虚拟机

```yaml
apiVersion: vm.example.com/v1alpha1
kind: VirtualMachineProfile
metadata:
  name: ha-vm
spec:
  cpu: 8
  memory: 16Gi
  networks:
    - name: mgmt
      type: bridge
      ipConfig:
        mode: static
        address: 192.168.1.10/24
  disks:
    - name: system
      size: 100Gi
      storageClassName: huamei-sc-ssd
      boot: true
  highAvailability:
    restartPolicy: Always
    antiAffinity: true
    nodeSelector:
      node-role.kubernetes.io/worker: ""
```

## 验证和约束

### 字段验证规则

1. **CPU**: 必须 > 0，建议 <= 64
2. **Memory**: 必须符合 Kubernetes 资源格式，最小 512Mi
3. **网络名称**: 必须唯一，符合 DNS-1123 子域名规范
4. **磁盘名称**: 必须唯一，符合 DNS-1123 子域名规范
5. **VLAN ID**: 如果指定，必须在 1-4094 范围内
6. **IP 地址**: static 模式必须提供有效的 CIDR 格式地址
7. **磁盘大小**: 必须符合 Kubernetes 资源格式，最小 1Gi

### 资源限制

- **最大网络数**: 建议不超过 8 个（取决于节点和 CNI 支持）
- **最大磁盘数**: 建议不超过 16 个
- **CPU 限制**: 受节点资源限制
- **内存限制**: 受节点资源限制

## 状态转换

```
Pending → Creating → Running
   ↓         ↓          ↓
   └─────────┴──────────┴→ Stopped
                      ↓
                    Error
```

- **Pending**: 资源已创建，等待处理
- **Creating**: 正在创建网络、存储和虚拟机
- **Running**: 虚拟机正在运行
- **Stopped**: 虚拟机已停止
- **Error**: 发生错误，需要人工干预

## 最佳实践

1. **网络命名**: 使用有意义的名称，如 `management`, `business`, `storage`
2. **磁盘规划**: 系统盘和数据盘分离，使用不同的 StorageClass
3. **高可用**: 生产环境启用 `antiAffinity` 和 `restartPolicy: Always`
4. **资源预留**: 合理设置 CPU 和内存，避免过度分配
5. **网络隔离**: 使用 VLAN 隔离不同业务网络
6. **存储选择**: 根据性能需求选择合适的 StorageClass

## 故障排查

### 查看资源状态

```bash
# 查看 VirtualMachineProfile
kubectl get vmprofile <name> -o yaml

# 查看状态
kubectl describe vmprofile <name>

# 查看相关资源
kubectl get vm,vmi,pvc,nad -l vmprofile=<name>
```

### 常见错误

1. **网络配置失败**: 检查 NAD 和 NNCP 状态
2. **存储绑定失败**: 检查 StorageClass 和 PVC 状态
3. **VM 启动失败**: 检查 VMI 事件和日志
4. **IP 配置失败**: 检查网络配置和 DHCP 服务

---

**文档版本**: v1.0.0  
**最后更新**: 2024-01-01


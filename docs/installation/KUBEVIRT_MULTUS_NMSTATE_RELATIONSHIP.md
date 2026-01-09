# KubeVirt、Multus 和 NMState 的关系详解

## 概述

本文档详细解释 KubeVirt 通过 Multus 创建的网卡访问外网和 NMState 桥接之间的关系，以及整个网络数据流的完整过程。

## 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         Kubernetes 节点                           │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   物理网卡 (ens192)                       │  │
│  │              IP: 192.168.0.121/24                        │  │
│  │              Gateway: 192.168.0.1                        │  │
│  └───────────────────────┬──────────────────────────────────┘  │
│                          │                                      │
│                          │ (作为桥接端口)                        │
│                          ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         NMState 创建的桥接 (br-external)                  │  │
│  │   由 NodeNetworkConfigurationPolicy 自动创建             │  │
│  └───────────────────────┬──────────────────────────────────┘  │
│                          │                                      │
│                          │ (Multus bridge CNI 连接)              │
│                          ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              virt-launcher Pod 网络命名空间                │  │
│  │                                                           │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │      Multus 创建的 veth pair (tap0)                │  │  │
│  │  │      由 bridge CNI 创建，连接到 br-external        │  │  │
│  │  └───────────────────────┬────────────────────────────┘  │  │
│  │                          │                                  │  │
│  │                          │ (KubeVirt 网络绑定)              │  │
│  │                          ▼                                  │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │          VM 网络接口 (eth1)                         │  │  │
│  │  │          IP: 192.168.0.200/24 (Cloud-Init 配置)    │  │  │
│  │  │          Gateway: 192.168.0.1                      │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                          │
                          │ (访问外网)
                          ▼
                    ┌──────────┐
                    │  外网     │
                    │ 8.8.8.8  │
                    └──────────┘
```

## 组件职责

### 1. NMState - 节点网络配置

**职责**：在节点上创建和管理 Linux Bridge

**工作流程**：
1. 读取 `NodeNetworkConfigurationPolicy` CRD
2. 在节点上创建 Linux Bridge（如 `br-external`）
3. 将物理网卡（如 `ens192`）添加到桥接作为端口
4. 确保桥接状态为 `up`

**生成的配置示例**：
```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ubuntu-vm-external-network-external-bridge
spec:
  desiredState:
    interfaces:
      - name: br-external
        type: linux-bridge
        state: up
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens192  # 物理网卡作为桥接端口
```

**关键点**：
- NMState **只管理桥接**，不管理物理网卡的 IP 配置
- 物理网卡的 IP 由 Netplan/NetworkManager 管理
- 桥接创建后，物理网卡成为桥接的一个端口

### 2. Multus - 多网络 CNI

**职责**：为 Pod/VM 创建额外的网络接口

**工作流程**：
1. 读取 `NetworkAttachmentDefinition` (NAD) CRD
2. 根据 NAD 中的 CNI 配置创建网络接口
3. 将接口添加到 Pod 的网络命名空间

**生成的 NAD 示例**：
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ubuntu-vm-external-network-external
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-external",  # 连接到 NMState 创建的桥接
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.0.0/24",
        "rangeStart": "192.168.0.200",
        "rangeEnd": "192.168.0.200"
      }
    }
```

**关键点**：
- Multus 使用 `bridge` CNI 连接到 NMState 创建的桥接
- 桥接名称必须与 NMState 创建的桥接名称一致
- Multus 在 Pod 网络命名空间中创建 `veth pair`，一端连接到桥接

### 3. KubeVirt - 虚拟机管理

**职责**：创建和管理虚拟机，配置 VM 网络接口

**工作流程**：
1. 读取 `VirtualMachine` CRD
2. 创建 `virt-launcher` Pod
3. 在 Pod 中启动 QEMU/KVM 虚拟机
4. 将 Multus 创建的网络接口绑定到 VM

**VirtualMachine 配置示例**：
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}  # Pod 网络
            - name: external
              bridge: {}      # Multus 网络，使用 Bridge binding
      networks:
        - name: default
          pod: {}            # Pod 网络
        - name: external
          multus:
            networkName: ubuntu-vm-external-network-external  # 引用 NAD
```

**关键点**：
- KubeVirt 使用 `bridge` binding 方式连接 Multus 网络
- Network 的 `name` 必须与 Interface 的 `name` 匹配
- `networkName` 引用 Multus NAD 的名称

## 完整数据流

### 场景：VM 访问外网 (8.8.8.8)

```
1. VM 内应用程序发起请求
   └─> VM 网络接口 (eth1, 192.168.0.200)
       └─> 路由表检查：目标 8.8.8.8，通过网关 192.168.0.1
           └─> 数据包发送到网关

2. KubeVirt 网络绑定层
   └─> 数据包从 VM 接口 (eth1) 传递到 virt-launcher Pod
       └─> 通过 TAP 设备 (tap0) 传递

3. Multus bridge CNI
   └─> 数据包从 Pod 网络命名空间的 veth pair 传递
       └─> bridge CNI 将数据包发送到 br-external 桥接

4. NMState 创建的桥接
   └─> br-external 桥接接收数据包
       └─> 桥接将数据包转发到物理网卡 (ens192)

5. 物理网卡和路由
   └─> ens192 发送数据包到物理网络
       └─> 通过网关 192.168.0.1 路由到外网
           └─> 最终到达 8.8.8.8
```

### 反向数据流（外网响应）

```
1. 外网响应到达物理网卡 (ens192)
   └─> 数据包进入 br-external 桥接

2. 桥接转发
   └─> br-external 将数据包转发到连接的 veth pair

3. Multus bridge CNI
   └─> 数据包从桥接传递到 Pod 网络命名空间
       └─> 通过 veth pair 传递到 TAP 设备

4. KubeVirt 网络绑定
   └─> 数据包从 TAP 设备传递到 VM 接口 (eth1)

5. VM 接收
   └─> VM 网络接口接收数据包
       └─> 应用程序处理响应
```

## 组件协作关系

### 1. 创建顺序

```
1. NMState 创建桥接
   └─> NodeNetworkConfigurationPolicy 被应用
       └─> 节点上创建 br-external 桥接
           └─> ens192 被添加到桥接作为端口

2. Multus 创建 NAD
   └─> NetworkAttachmentDefinition 被创建
       └─> 定义如何连接到 br-external

3. KubeVirt 创建 VM
   └─> VirtualMachine 被创建
       └─> virt-launcher Pod 被创建
           └─> Multus 根据 NAD 创建网络接口
               └─> KubeVirt 将接口绑定到 VM
```

### 2. 配置依赖关系

```
Wukong Spec
    │
    ├─> NetworkConfig
    │   ├─> type: bridge
    │   ├─> physicalInterface: ens192
    │   ├─> bridgeName: br-external
    │   └─> ipConfig: { mode: static, address: "192.168.0.200/24" }
    │
    ├─> NMState (ReconcileNMState)
    │   └─> 创建 NodeNetworkConfigurationPolicy
    │       └─> 在节点上创建 br-external 桥接
    │           └─> 将 ens192 添加到桥接
    │
    ├─> Multus (ReconcileNetworks)
    │   └─> 创建 NetworkAttachmentDefinition
    │       └─> CNI 配置：bridge: br-external
    │           └─> IPAM 配置：192.168.0.200/24
    │
    └─> KubeVirt (ReconcileVirtualMachine)
        └─> 创建 VirtualMachine
            └─> 配置 networks 和 interfaces
                └─> 引用 NetworkAttachmentDefinition
                    └─> VM 启动时，Multus 创建网络接口
                        └─> Cloud-Init 配置 VM 内 IP
```

## 关键配置点

### 1. 桥接名称必须一致

**NMState 配置**：
```yaml
interfaces:
  - name: br-external  # 桥接名称
```

**Multus NAD 配置**：
```json
{
  "type": "bridge",
  "bridge": "br-external"  # 必须与 NMState 创建的桥接名称一致
}
```

### 2. 物理网卡作为桥接端口

**NMState 配置**：
```yaml
bridge:
  port:
    - name: ens192  # 物理网卡作为桥接端口
```

**关键点**：
- 物理网卡不在 desiredState 的 interfaces 列表中
- 只作为桥接的端口，不直接管理
- IP 配置由 Netplan/NetworkManager 管理

### 3. VM IP 配置

**Cloud-Init 配置**（在 VM 内）：
```yaml
network:
  version: 2
  ethernets:
    eth1:
      addresses:
        - 192.168.0.200/24
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
```

**关键点**：
- VM 的 IP 配置由 Cloud-Init 在 VM 启动时配置
- IP 地址必须在桥接的子网范围内
- 网关必须是物理网卡的网关

## 常见问题

### Q1: 为什么需要 NMState？

**A**: 
- Multus 只负责在 Pod 网络命名空间中创建网络接口
- Multus 不能创建节点级别的桥接
- NMState 负责在节点上创建和管理桥接，Multus 连接到这些桥接

### Q2: 为什么需要 Multus？

**A**:
- Kubernetes 默认每个 Pod 只有一个网络接口（Pod 网络）
- 虚拟机需要多个网络接口（管理网、业务网、外网等）
- Multus 允许 Pod/VM 连接多个网络

### Q3: 数据包如何从 VM 到达外网？

**A**:
1. VM → TAP 设备 → Pod 网络命名空间
2. Pod 网络命名空间 → veth pair → br-external 桥接
3. br-external 桥接 → ens192 物理网卡
4. ens192 → 物理网络 → 网关 → 外网

### Q4: 如果 NMState 没有创建桥接会怎样？

**A**:
- Multus bridge CNI 会尝试连接到不存在的桥接
- 网络接口创建失败
- VM 无法访问外网

### Q5: 物理网卡的 IP 会被改变吗？

**A**:
- 不会，因为物理网卡不在 NMState 的 desiredState 中
- 物理网卡只作为桥接端口，IP 配置由 Netplan/NetworkManager 管理
- 这是当前实现的关键设计

## 总结

**NMState、Multus 和 KubeVirt 的协作关系**：

1. **NMState**：在节点上创建 Linux Bridge，将物理网卡添加到桥接
2. **Multus**：在 Pod 网络命名空间中创建网络接口，连接到 NMState 创建的桥接
3. **KubeVirt**：创建虚拟机，将 Multus 创建的网络接口绑定到 VM

**数据流**：
- VM → TAP → Pod 网络命名空间 → veth pair → 桥接 → 物理网卡 → 外网

**关键点**：
- 桥接名称必须一致
- 物理网卡只作为桥接端口，不直接管理
- VM IP 由 Cloud-Init 配置，必须在桥接子网范围内


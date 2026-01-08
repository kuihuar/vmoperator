# NMState 作用说明

## 1. NMState 是什么？

**NMState** 是一个 Kubernetes Operator，用于**管理节点级别的网络配置**。

## 2. NMState 的作用

### 2.1 主要功能

NMState 用于配置 Kubernetes **节点**的网络，包括：

- **创建网络桥接（Bridge）**
- **配置 VLAN**
- **配置 Bonding（链路聚合）**
- **配置 SR-IOV**
- **管理网络接口状态**

### 2.2 与 Multus 的区别

| 组件 | 作用范围 | 功能 |
|------|---------|------|
| **Multus** | Pod/VM 级别 | 为 Pod/VM 创建额外的网络接口 |
| **NMState** | 节点级别 | 配置节点底层的网络（桥接、VLAN 等） |

### 2.3 工作流程

```
用户定义 NetworkConfig
    ↓
NMState 配置节点网络（桥接、VLAN）  ← 节点级别
    ↓
Multus 创建 NAD（引用已配置的网络）  ← Pod/VM 级别
    ↓
KubeVirt VM 使用网络接口
```

## 3. 当前项目中的实现

### 3.1 当前状态

在 `pkg/network/nmstate.go` 中，NMState 已经**完整实现**：

```go
func ReconcileNMState(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) error {
    // 检查 NMState CRD 是否存在
    // 为 bridge 和 ovs 类型的网络创建 NodeNetworkConfigurationPolicy
    // 自动配置 VLAN 接口和 Linux Bridge
    // ...
}
```

**功能：**
- ✅ 自动创建 `NodeNetworkConfigurationPolicy`
- ✅ 支持创建 Linux Bridge
- ✅ 支持创建 VLAN 接口
- ✅ 与 Multus 配合使用

### 3.2 实现细节

1. **自动检测**：检查 NMState CRD 是否存在，如果不存在则跳过
2. **网络类型过滤**：只处理 `bridge` 和 `ovs` 类型，跳过 `default` 和 `macvlan/ipvlan`
3. **策略命名**：自动生成策略名称 `{wukong-name}-{network-name}-bridge`
4. **VLAN 支持**：如果指定了 `vlanId`，先创建 VLAN 接口，再创建桥接

## 4. NMState 的使用场景

### 4.1 何时需要 NMState？

**需要 NMState 的场景：**

1. **需要创建网络桥接**
   ```yaml
   # 例如：需要在节点上创建 br-mgmt 桥接
   apiVersion: nmstate.io/v1
   kind: NodeNetworkConfigurationPolicy
   metadata:
     name: bridge-policy
   spec:
     desiredState:
       interfaces:
         - name: br-mgmt
           type: linux-bridge
           state: up
           bridge:
             port:
               - name: eth0
   ```

2. **需要配置 VLAN**
   ```yaml
   # 例如：需要在节点上配置 VLAN 100
   apiVersion: nmstate.io/v1
   kind: NodeNetworkConfigurationPolicy
   metadata:
     name: vlan-policy
   spec:
     desiredState:
       interfaces:
         - name: eth0.100
           type: vlan
           state: up
           vlan:
             base-iface: eth0
             id: 100
   ```

3. **需要配置 Bonding**
   ```yaml
   # 例如：需要将两个网卡绑定为一个 bond
   apiVersion: nmstate.io/v1
   kind: NodeNetworkConfigurationPolicy
   metadata:
     name: bond-policy
   spec:
     desiredState:
       interfaces:
         - name: bond0
           type: bond
           state: up
           bond:
             mode: active-backup
             port:
               - eth0
               - eth1
   ```

### 4.2 当前项目如何使用 NMState

**当前使用 `bridge` 网络：**

```yaml
networks:
  - name: external
    type: bridge
    bridgeName: br-external
    vlanId: 100  # 可选
    ipConfig:
      mode: static
      address: 192.168.1.200/24
```

- `bridge` 类型需要预先在节点上创建 Linux Bridge
- **需要** NMState 自动配置桥接和 VLAN
- VM Operator 会自动调用 NMState 创建 `NodeNetworkConfigurationPolicy`

## 5. 实现细节

### 5.1 自动创建策略

当创建 Wukong CR 时，VM Operator 会自动：

1. **检测网络类型**：如果是 `bridge` 或 `ovs`，调用 `ReconcileNMState`
2. **创建策略**：自动创建 `NodeNetworkConfigurationPolicy`
3. **配置网络**：NMState Handler 在节点上创建桥接和 VLAN 接口
4. **Multus 使用**：Multus 创建 NAD，引用已创建的桥接

### 5.2 策略命名规则

策略名称格式：`{wukong-name}-{network-name}-bridge`

例如：`ubuntu-vm-management-bridge`

### 5.3 物理网卡配置

当前实现默认使用 `ens160` 作为物理网卡。可以通过修改 `pkg/network/nmstate.go` 中的 `physicalInterface` 变量来更改。

## 6. 总结

| 问题 | 答案 |
|------|------|
| **NMState 是什么？** | 用于管理 Kubernetes 节点网络配置的 Operator |
| **当前项目是否使用？** | ✅ 是，已完整实现 |
| **如何工作？** | 自动为 `bridge` 和 `ovs` 类型网络创建 `NodeNetworkConfigurationPolicy` |
| **支持哪些功能？** | Linux Bridge、VLAN 接口、自动配置节点网络 |
| **与 Multus 的关系？** | NMState 配置节点网络，Multus 使用这些网络创建 Pod/VM 接口 |

## 7. 参考文档

- [NMState 官方文档](https://nmstate.github.io/)
- [NodeNetworkConfigurationPolicy 示例](https://nmstate.github.io/examples/)
- [项目中的 NMState 集成文档](../interview/05.2-NMState集成详解.md)


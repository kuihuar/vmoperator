# NMState 桥接时 IP 地址保留问题分析

## 问题描述

当使用 NMState 创建 Linux Bridge 并将物理网卡（如 `ens192`）作为桥接端口时，如果不在 `desiredState` 中明确配置 IP 地址，NMState 会**移除物理网卡的 IP 配置**，导致节点失去网络连接。

### 问题现象

1. **原始状态**：
   ```bash
   $ ip addr show ens192
   42: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP
       inet 192.168.0.121/24 brd 192.168.0.255 scope global noprefixroute ens192
   ```

2. **创建桥接后**：
   ```bash
   $ ip addr show ens192
   42: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master br-external state UP
       link/ether 00:0c:29:1a:ca:b9 brd ff:ff:ff:ff:ff:ff
       # ❌ IP 地址被移除了！
   
   $ ip addr show br-external
   60: br-external: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP
       link/ether aa:36:98:3e:49:cb brd ff:ff:ff:ff:ff:ff
       # ❌ 桥接上也没有 IP 地址！
   ```

3. **结果**：节点失去网络连接，无法访问外网。

## 根本原因

### NMState 的声明式配置模型

NMState 采用**声明式配置模型**，要求用户在 `desiredState` 中**明确指定每个接口的状态和配置**。

当将物理网卡添加到桥接时：

1. **如果不在 `desiredState` 中明确配置物理网卡**：
   - NMState 会认为物理网卡应该被"清理"
   - 移除物理网卡上的所有 IP 配置
   - 只保留物理网卡作为桥接端口的功能

2. **如果不在 `desiredState` 中明确配置桥接的 IP**：
   - 桥接接口创建成功，但没有 IP 地址
   - 原物理网卡的 IP 不会自动迁移到桥接

### 代码逻辑位置

问题代码位于：`pkg/network/nmstate.go` 的 `reconcileBridgePolicy` 函数

```go:152:176:pkg/network/nmstate.go
} else {
    // 没有 VLAN，直接使用物理网卡
    // 重要：不在 desiredState 中明确指定物理网卡，只将其作为桥接端口
    // 这样可以避免 NMState 管理物理网卡的 IP 配置，保留现有的 Netplan/NetworkManager 配置
    // NMState 只需要知道物理网卡作为桥接端口即可，不需要直接管理它
    bridgeInterface := map[string]interface{}{
        "name":  bridgeName,
        "type":  "linux-bridge",
        "state": "up",
        "bridge": map[string]interface{}{
            "options": map[string]interface{}{
                "stp": map[string]interface{}{
                    "enabled": false,
                },
            },
            "port": []interface{}{
                map[string]interface{}{
                    "name": physicalInterface,
                },
            },
        },
    }
    interfaces = append(interfaces, bridgeInterface)
    // 注意：不在 desiredState 中包含物理网卡的配置，让 Netplan/NetworkManager 继续管理
    // NMState 只负责创建桥接并将物理网卡作为端口，不会改变物理网卡的 IP 配置
}
```

**问题**：代码注释说"不会改变物理网卡的 IP 配置"，但实际上 NMState 会移除物理网卡的 IP。

### 当前生成的 NMState 策略

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ubuntu-vm-dual-network-test-external-bridge
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
            - name: ens192
        # ❌ 缺少 IP 配置！
```

**问题**：
- 桥接接口 `br-external` 没有 IP 配置
- 物理网卡 `ens192` 不在 `desiredState` 中，NMState 会移除其 IP

## 解决方案

### 方案 1：在桥接上配置原物理网卡的 IP（推荐）

**原理**：在 `desiredState` 中明确配置桥接接口的 IP 地址，并明确指定物理网卡的状态（禁用 IP）。

**修复后的 NMState 策略**：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ubuntu-vm-dual-network-test-external-bridge
spec:
  desiredState:
    interfaces:
      - name: br-external
        type: linux-bridge
        state: up
        ipv4:
          address:
            - ip: 192.168.0.121      # 原 ens192 的 IP
              prefix-length: 24
          enabled: true
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens192
      - name: ens192
        type: ethernet
        state: up
        ipv4:
          enabled: false  # 禁用物理网卡的 IP，IP 在桥接上
```

**优点**：
- ✅ 明确控制网络配置
- ✅ 符合 NMState 的声明式模型
- ✅ 确保节点网络不中断

**缺点**：
- ⚠️ 需要知道原物理网卡的 IP 地址
- ⚠️ 如果物理网卡 IP 是 DHCP 获取的，需要改为静态配置

### 方案 2：使用 NodeIPConfig 字段（如果支持）

某些版本的 NMState 可能支持 `nodeIPConfig` 字段来自动迁移 IP，但需要验证是否支持。

### 方案 3：先获取节点 IP，再配置桥接

在创建桥接前，先查询节点上物理网卡的 IP 配置，然后将其配置到桥接上。

**实现方式**：
1. 通过 Kubernetes Node 对象的 annotations 或 labels 获取 IP
2. 或者通过 NodeNetworkState 资源获取当前网络状态
3. 然后配置到桥接上

## 修复代码实现

### ✅ 已修复

**修复位置**：`pkg/network/nmstate.go` 的 `reconcileBridgePolicy` 函数

**修复内容**：

1. **添加了 `NodeIP` 字段**（`api/v1alpha1/wukong_types.go`）：
   - 用于指定节点物理网卡的 IP 地址
   - 格式：`"192.168.0.121/24"`
   - 可选字段，但强烈建议配置以避免节点网络中断

2. **修改了桥接配置逻辑**：
   - 如果指定了 `NodeIP`，在桥接接口上配置该 IP
   - 明确指定物理网卡禁用 IP（`ipv4.enabled: false`）
   - 符合 NMState 的声明式配置模型

3. **添加了 `parseIPAddress` 辅助函数**：
   - 解析 CIDR 格式的 IP 地址
   - 返回 IP 地址和前缀长度

### 修复后的代码逻辑

```go
// 1. 如果指定了 NodeIP，在桥接上配置 IP
if netCfg.NodeIP != nil && *netCfg.NodeIP != "" {
    ip, prefixLen, err := parseIPAddress(*netCfg.NodeIP)
    if err != nil {
        return fmt.Errorf("invalid nodeIP format: %s", *netCfg.NodeIP)
    }
    
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "address": []interface{}{
            map[string]interface{}{
                "ip":           ip,
                "prefix-length": prefixLen,
            },
        },
    }
}

// 2. 明确指定物理网卡禁用 IP（IP 在桥接上）
physicalInterfaceConfig := map[string]interface{}{
    "name":  physicalInterface,
    "type":  "ethernet",
    "state": "up",
    "ipv4": map[string]interface{}{
        "enabled": false, // 禁用物理网卡的 IP，IP 在桥接上
    },
}
interfaces = append(interfaces, physicalInterfaceConfig)
```

### 生成的 NMState 策略示例

修复后，生成的策略如下：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ubuntu-vm-dual-network-test-external-bridge
spec:
  desiredState:
    interfaces:
      - name: br-external
        type: linux-bridge
        state: up
        ipv4:
          enabled: true
          address:
            - ip: 192.168.0.121
              prefix-length: 24
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: ens192
      - name: ens192
        type: ethernet
        state: up
        ipv4:
          enabled: false  # ✅ 明确禁用物理网卡的 IP
```

## 临时恢复方案

如果节点已经失去网络连接，需要先恢复：

### 方法 1：删除 NMState 策略

```bash
# 删除导致问题的策略
kubectl delete nodenetworkconfigurationpolicy ubuntu-vm-dual-network-test-external-bridge

# 等待网络恢复
# 然后手动配置桥接和 IP
```

### 方法 2：手动恢复 IP

```bash
# 在节点上执行
sudo ip addr add 192.168.0.121/24 dev br-external
sudo ip route add default via 192.168.0.1 dev br-external
```

### 方法 3：删除桥接，恢复原始配置

```bash
# 删除桥接
sudo ip link set br-external down
sudo brctl delbr br-external

# 恢复 ens192 的 IP（如果 Netplan 配置还在）
sudo netplan apply
```

## 配置方法

### ✅ 已实现：在 NetworkConfig 中添加 nodeIP 字段

**配置示例**：

```yaml
networks:
  - name: external
    type: bridge
    bridgeName: "br-external"
    physicalInterface: "ens192"
    nodeIP: "192.168.0.121/24"  # ✅ 节点 IP 配置（原 ens192 的 IP）
    ipConfig:
      mode: static
      address: "192.168.0.200/24"  # VM 的 IP
      gateway: "192.168.0.1"
```

**重要说明**：
- `nodeIP` 是**可选字段**，但**强烈建议配置**
- 如果不配置，会记录警告，节点网络可能中断
- `nodeIP` 应该是原物理网卡的 IP 地址
- 格式：`"192.168.0.121/24"`（CIDR 格式）

### 如何获取 nodeIP

1. **查看当前物理网卡 IP**：
   ```bash
   ip addr show ens192
   # 输出：inet 192.168.0.121/24
   ```

2. **配置到 Wukong 资源**：
   ```yaml
   nodeIP: "192.168.0.121/24"
   ```

### 未来改进方向

- **选项 1**：自动从 `NodeNetworkState` 资源获取物理网卡的 IP
- **选项 2**：支持 DHCP 模式（需要先查询当前 IP，然后配置为静态）

## 参考文档

- [NMState 官方文档](https://nmstate.io/)
- [Kubernetes NMState Operator](https://github.com/nmstate/kubernetes-nmstate)
- [Linux Bridge 配置](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-a-network-bridge_configuring-and-managing-networking)

## 总结

**核心问题**：NMState 的声明式模型要求明确配置，不在 `desiredState` 中的配置会被移除。

**解决方案**：✅ **已修复** - 在桥接接口上明确配置原物理网卡的 IP 地址，并明确指定物理网卡禁用 IP。

**修复状态**：✅ **已完成**
- ✅ 添加了 `NodeIP` 字段到 `NetworkConfig`
- ✅ 修改了 `reconcileBridgePolicy` 函数
- ✅ 桥接接口现在会配置节点 IP
- ✅ 物理网卡明确禁用 IP
- ✅ 更新了示例配置文件

**使用方法**：在 `NetworkConfig` 中添加 `nodeIP: "192.168.0.121/24"` 字段即可。


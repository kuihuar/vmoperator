# 为什么 NMState 会改变网卡的 IP？

## 问题描述

当使用 NMState 管理网络时，可能会发现物理网卡（如 `ens160`、`ens192`）的 IP 地址被改为 DHCP，或者静态 IP 配置丢失。

## 根本原因

### 1. NMState 的声明式配置模型

NMState 使用**声明式配置模型**（Desired State），这意味着：

- **期望状态（Desired State）**：你明确告诉 NMState 网络应该是什么样子
- **当前状态（Current State）**：系统当前的网络配置
- **Reconcile（协调）**：NMState 会尝试将当前状态调整为期望状态

### 2. 为什么会被改变？

当你在 `NodeNetworkConfigurationPolicy` 的 `desiredState` 中指定一个接口时：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
spec:
  desiredState:
    interfaces:
      - name: ens160
        type: ethernet
        state: up
        # ❌ 问题：没有明确指定 IP 配置
```

**NMState 的行为**：
1. NMState 看到 `ens160` 在 `desiredState` 中
2. 但是 `desiredState` 中没有明确指定 IP 配置
3. NMState 认为需要将接口重置为"干净状态"
4. **默认行为**：将 IP 配置改为 DHCP（这是大多数 Linux 发行版的默认值）

### 3. 声明式配置的副作用

这是声明式配置的**副作用**：

- ✅ **优点**：确保网络配置与期望状态一致，避免配置漂移
- ❌ **缺点**：如果 `desiredState` 不完整，可能会重置未指定的配置

## 解决方案

### 方案 1：明确指定 IP 配置（推荐）

在 `desiredState` 中明确指定接口的 IP 配置：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
spec:
  desiredState:
    interfaces:
      - name: ens160
        type: ethernet
        state: up
        ipv4:
          enabled: true
          dhcp: false  # 明确禁用 DHCP
          # 不配置 address，保留现有的静态 IP（由 Netplan/NetworkManager 管理）
        ipv6:
          enabled: false
```

**优点**：
- 明确告诉 NMState 不要使用 DHCP
- 不配置静态 IP，让 Netplan/NetworkManager 继续管理 IP

**缺点**：
- 需要明确指定每个接口的配置

### 方案 2：使用 Capture 机制

NMState 支持使用 `capture` 来捕获现有配置：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
spec:
  capture:
    - name: ens160
      interfaces:
        - name: ens160
  desiredState:
    interfaces:
      - name: ens160
        type: ethernet
        state: up
        # 使用捕获的配置
```

**优点**：
- 自动保留现有配置
- 不需要手动指定所有配置

**缺点**：
- 配置更复杂
- 可能不是所有版本都支持

### 方案 3：不在 desiredState 中包含接口

如果接口不需要被 NMState 管理，可以不在 `desiredState` 中包含它：

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
spec:
  desiredState:
    interfaces:
      - name: br-management
        type: linux-bridge
        state: up
        bridge:
          port:
            - name: ens160  # 只作为桥接端口，不直接管理接口
```

**问题**：
- 如果接口需要被添加到桥接，NMState 仍然需要知道它的存在
- 可能无法完全避免管理

## 当前实现

在我们的实现中（`pkg/network/nmstate.go`），我们采用了**方案 1**：

```go
physicalInterfaceConfig := map[string]interface{}{
    "name":  physicalInterface,
    "type":  "ethernet",
    "state": "up",
    "ipv4": map[string]interface{}{
        "enabled": true,
        "dhcp":    false, // 明确禁用 DHCP，防止 NMState 将 IP 改为 DHCP
        // 不配置 address，保留现有的静态 IP 配置（由 Netplan/NetworkManager 管理）
    },
    "ipv6": map[string]interface{}{
        "enabled": false,
    },
}
```

**工作原理**：
1. 明确指定接口状态：`type: ethernet`, `state: up`
2. 明确禁用 DHCP：`dhcp: false`
3. **不配置静态 IP**：让 Netplan/NetworkManager 继续管理 IP 配置

这样，NMState 只负责：
- 将物理网卡添加到桥接
- 确保接口状态为 `up`
- 确保不使用 DHCP

而 IP 地址配置仍然由 Netplan/NetworkManager 管理。

## 最佳实践

### 1. 明确指定所有配置

在 `desiredState` 中明确指定所有需要管理的配置：

```yaml
interfaces:
  - name: ens160
    type: ethernet
    state: up
    ipv4:
      enabled: true
      dhcp: false  # 必须明确指定
    ipv6:
      enabled: false  # 必须明确指定
```

### 2. 分离关注点

- **NMState**：管理桥接、VLAN、接口状态
- **Netplan/NetworkManager**：管理 IP 地址、网关、DNS

### 3. 测试配置

在应用到生产环境前，先在测试环境验证：

```bash
# 检查生成的策略
kubectl get nodenetworkconfigurationpolicy -o yaml

# 检查接口状态
ip addr show ens160
nmcli connection show ens160
```

## 常见问题

### Q1: 为什么不能完全避免 NMState 管理接口？

**A**: 如果接口需要被添加到桥接，NMState 必须知道它的存在。但是，我们可以通过明确指定配置来避免改变 IP。

### Q2: 如果接口已经有静态 IP，NMState 会保留吗？

**A**: 如果我们在 `desiredState` 中明确禁用 DHCP但不配置静态 IP，NMState 应该不会改变现有的静态 IP。但是，为了更安全，建议在 Netplan 中配置桥接的 IP，而不是物理网卡的 IP。

### Q3: 如何验证 IP 没有被改变？

**A**: 
```bash
# 检查接口 IP
ip addr show ens160

# 检查 NetworkManager 连接
nmcli connection show ens160

# 检查 Netplan 配置
cat /etc/netplan/*.yaml
```

## 总结

NMState 会改变网卡 IP 的原因是：

1. **声明式配置模型**：必须明确指定所有配置
2. **默认行为**：未指定的配置可能被重置为默认值（DHCP）
3. **解决方案**：明确禁用 DHCP，但不配置静态 IP，让 Netplan/NetworkManager 继续管理

通过明确指定接口配置（禁用 DHCP），我们可以避免 NMState 改变 IP 配置，同时仍然允许 NMState 管理桥接和接口状态。


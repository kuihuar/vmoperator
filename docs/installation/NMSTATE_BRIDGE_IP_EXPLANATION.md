# NMState 桥接时 IP 配置说明

## 核心问题澄清

**❌ 误解**：ens192 必须改成 DHCP 才能让 VM 访问外网

**✅ 事实**：
- **不需要改成 DHCP**
- 问题是 **IP 配置的位置**，不是 DHCP vs 静态 IP
- IP 应该从物理网卡迁移到桥接，但仍然是**静态 IP**

## Linux Bridge 的工作原理

### 标准做法

当物理网卡被添加到 Linux Bridge 作为端口时：

1. **IP 地址应该配置在桥接上**，而不是物理网卡上
2. **物理网卡作为桥接端口**，不应该有 IP 地址
3. **节点通过桥接访问网络**，而不是直接通过物理网卡

### 为什么？

```
┌─────────────────────────────────────┐
│          Linux Bridge               │
│         (br-external)               │
│    IP: 192.168.0.121/24  ← 节点 IP  │
│                                     │
│  ┌──────────┐      ┌──────────┐   │
│  │  ens192  │      │   VM     │   │
│  │ (port)   │      │ (tap)    │   │
│  └──────────┘      └──────────┘   │
└─────────────────────────────────────┘
```

- **桥接是 L2 设备**，IP 应该在桥接上
- **物理网卡是桥接的端口**，不应该有 IP
- **VM 通过桥接访问网络**，与节点共享同一个 IP 段

## NMState 的行为

### 问题现象

当使用 NMState 创建桥接时：

1. **如果不在 `desiredState` 中明确配置 IP**：
   - NMState 会移除物理网卡的 IP（因为物理网卡被添加到桥接）
   - 但不会自动将 IP 迁移到桥接
   - **结果**：节点失去网络连接

2. **如果明确配置 IP 在桥接上**：
   - 物理网卡的 IP 被移除（这是正确的）
   - IP 配置在桥接上
   - **结果**：节点通过桥接访问网络，VM 也能访问外网

### 关键点

**IP 从 ens192 迁移到桥接，并不是"改成 DHCP"**，而是：
- ✅ IP 地址保持不变：`192.168.0.121/24`
- ✅ 仍然是静态 IP（不是 DHCP）
- ✅ 只是 IP 配置的位置改变了：从物理网卡 → 桥接

## 正确的配置方式

### NMState 策略示例

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
spec:
  desiredState:
    interfaces:
      # 桥接接口：配置节点 IP
      - name: br-external
        type: linux-bridge
        state: up
        ipv4:
          enabled: true
          address:
            - ip: 192.168.0.121      # ✅ 原 ens192 的 IP
              prefix-length: 24       # ✅ 仍然是静态 IP
        bridge:
          port:
            - name: ens192
      
      # 物理网卡：作为桥接端口，禁用 IP
      - name: ens192
        type: ethernet
        state: up
        ipv4:
          enabled: false  # ✅ 禁用 IP（IP 在桥接上）
```

### 结果

**节点网络状态**：
```bash
$ ip addr show br-external
br-external: inet 192.168.0.121/24  # ✅ IP 在桥接上

$ ip addr show ens192
ens192: <BROADCAST,MULTICAST,UP> master br-external  # ✅ 作为桥接端口，无 IP
```

**网络连接**：
- ✅ 节点可以访问外网（通过桥接）
- ✅ VM 可以访问外网（通过桥接）
- ✅ IP 地址仍然是 `192.168.0.121/24`（静态 IP）

## 常见误解

### 误解 1：ens192 必须改成 DHCP

**事实**：
- ❌ 不需要改成 DHCP
- ✅ IP 仍然是静态 IP
- ✅ 只是 IP 配置的位置改变了

### 误解 2：IP 在 ens192 上，VM 也能访问外网

**事实**：
- ❌ 如果 IP 在 ens192 上，桥接可能无法正常工作
- ✅ IP 应该在桥接上，这是 Linux Bridge 的标准做法

### 误解 3：节点会失去网络连接

**事实**：
- ❌ 如果正确配置，节点不会失去网络连接
- ✅ IP 从 ens192 迁移到桥接，节点通过桥接访问网络
- ✅ 网络功能完全正常

## 验证方法

### 1. 检查 IP 配置位置

```bash
# 桥接应该有 IP
ip addr show br-external
# 应该看到：inet 192.168.0.121/24

# 物理网卡应该没有 IP（作为桥接端口）
ip addr show ens192
# 应该看到：master br-external，但没有 inet
```

### 2. 检查网络连接

```bash
# 节点可以访问外网
ping 8.8.8.8

# VM 可以访问外网（在 VM 内测试）
ping 8.8.8.8
```

### 3. 检查路由

```bash
ip route show
# 默认路由应该通过 br-external（或 ens192，但实际流量走桥接）
```

## 总结

1. **不需要改成 DHCP**：IP 仍然是静态 IP `192.168.0.121/24`
2. **IP 配置位置改变**：从物理网卡 → 桥接（这是正确的）
3. **节点网络正常**：通过桥接访问网络
4. **VM 可以访问外网**：通过桥接访问网络

**关键点**：这是 Linux Bridge 的标准做法，不是 bug，而是正确的网络配置方式。


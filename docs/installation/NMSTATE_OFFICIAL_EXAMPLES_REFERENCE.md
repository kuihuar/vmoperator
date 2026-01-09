# NMState 官方示例参考

## 概述

本文档参考 [NMState 官方示例](https://nmstate.io/examples.html)，对比我们的实现与官方最佳实践。

## Linux Bridge 配置对比

### 官方示例

根据 [NMState 官方文档](https://nmstate.io/examples.html)，Linux Bridge 的配置示例：

```yaml
interfaces:
  - name: linux-br0
    type: linux-bridge
    state: up
    bridge:
      options:
        group-forward-mask: 0
        mac-ageing-time: 300
        multicast-snooping: true
        stp:
          enabled: true
          forward-delay: 15
          hello-time: 2
          max-age: 20
          priority: 32768
      port:
        - name: eth1
          stp-hairpin-mode: false
          stp-path-cost: 100
          stp-priority: 32
```

**简化版本**（只包含必需字段）：

```yaml
interfaces:
  - name: linux-br0
    type: linux-bridge
    state: up
    bridge:
      options:
        stp:
          enabled: true
      port:
        - name: eth1
```

### 我们的实现

```yaml
interfaces:
  - name: br-external
    type: linux-bridge
    state: up
    bridge:
      options:
        stp:
          enabled: false  # 禁用 STP，简化配置
      port:
        - name: ens192  # 物理网卡只在 port 中指定
```

## 关键发现

### ✅ 实现一致性

1. **物理网卡配置方式**：
   - ✅ 官方示例：物理网卡（`eth1`）只在 `port` 中指定，不在 `interfaces` 列表中单独配置
   - ✅ 我们的实现：物理网卡（`ens192`）只在 `port` 中指定，不在 `interfaces` 列表中单独配置
   - **结论**：我们的实现与官方文档一致！

2. **桥接配置结构**：
   - ✅ 官方示例：`bridge.options.stp.enabled` 控制 STP
   - ✅ 我们的实现：`bridge.options.stp.enabled: false`（禁用 STP）
   - **说明**：STP 的启用/禁用是配置选择，禁用可以简化配置并避免 STP 延迟

3. **物理网卡 IP 配置**：
   - ✅ 官方示例：未在 `interfaces` 列表中配置物理网卡的 IP
   - ✅ 我们的实现：不在 `desiredState` 中包含物理网卡的配置
   - **结论**：这样不会改变物理网卡的 IP 配置，符合我们的需求

## 配置差异说明

### STP (Spanning Tree Protocol)

| 配置 | 官方示例 | 我们的实现 | 说明 |
|------|----------|------------|------|
| STP 启用 | `enabled: true` | `enabled: false` | 禁用 STP 可以简化配置，避免 STP 延迟 |

**STP 的作用**：
- 防止网络环路
- 在复杂网络拓扑中很重要

**为什么我们禁用 STP**：
- 我们的场景是简单的单节点桥接
- 没有网络环路的风险
- 禁用可以避免 STP 的初始延迟（通常 30-50 秒）

### 端口配置

| 配置 | 官方示例 | 我们的实现 | 说明 |
|------|----------|------------|------|
| 端口名称 | `eth1` | `ens192` | 物理网卡名称，根据实际情况 |
| 端口 STP 配置 | 有详细配置 | 无（使用默认值） | 简化配置 |

**官方示例的端口 STP 配置**：
```yaml
port:
  - name: eth1
    stp-hairpin-mode: false
    stp-path-cost: 100
    stp-priority: 32
```

**我们的实现**：
```yaml
port:
  - name: ens192
  # 使用默认 STP 配置（因为 STP 已禁用）
```

## 最佳实践总结

根据官方文档和我们的实现，以下是 Linux Bridge 配置的最佳实践：

### 1. 物理网卡配置

✅ **正确做法**（与官方文档一致）：
- 物理网卡只在 `bridge.port` 中指定
- 不在 `interfaces` 列表中单独配置物理网卡
- 这样不会改变物理网卡的 IP 配置

❌ **错误做法**：
- 在 `interfaces` 列表中单独配置物理网卡的 IP
- 这会导致 NMState 管理物理网卡的 IP，可能改变现有配置

### 2. 桥接配置

✅ **最小化配置**（我们的实现）：
```yaml
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
```

✅ **完整配置**（官方示例）：
```yaml
interfaces:
  - name: linux-br0
    type: linux-bridge
    state: up
    bridge:
      options:
        stp:
          enabled: true
          forward-delay: 15
          hello-time: 2
          max-age: 20
          priority: 32768
      port:
        - name: eth1
          stp-hairpin-mode: false
          stp-path-cost: 100
          stp-priority: 32
```

### 3. 何时使用完整配置

- **简单场景**（我们的场景）：使用最小化配置即可
- **复杂网络拓扑**：需要启用 STP 并配置详细参数
- **多端口桥接**：需要为每个端口配置 STP 参数

## 参考链接

- [NMState 官方示例](https://nmstate.io/examples.html)
- [NMState 官方文档](https://nmstate.io/)

## 结论

✅ **我们的实现与官方文档一致**：
- 物理网卡只在 `port` 中指定，不单独配置
- 桥接配置结构正确
- 不会改变物理网卡的 IP 配置

✅ **配置简化合理**：
- 禁用 STP 适合简单场景
- 减少不必要的配置复杂度

✅ **可以放心使用**：
- 实现符合 NMState 最佳实践
- 配置方式与官方示例一致


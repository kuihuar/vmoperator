# NodeNetworkState 说明

## 1. NodeNetworkState 是什么？

`NodeNetworkState` 是 NMState Operator 创建的 Kubernetes 资源，用于**存储每个节点的实际网络状态信息**。

### 1.1 资源结构

- **资源名称**：通常是节点名称（如 `host1`）
- **命名空间**：无（集群级别资源）
- **OwnerReference**：指向对应的 Node 资源（由 NMState Operator 自动管理）
- **更新机制**：NMState Operator 会定期扫描节点网络状态并自动更新

### 1.3 自动更新机制

**NodeNetworkState 会随物理网卡的变化而自动更新**：

1. **定期扫描**：NMState Operator 运行在每个节点上，定期扫描节点的网络状态
2. **实时同步**：当检测到网络配置变化时（如 IP 地址改变、接口状态变化等），会自动更新 NodeNetworkState
3. **保持同步**：NodeNetworkState 的 `status.currentState` 始终反映节点的实际网络状态

**变化的场景包括**：
- 物理网卡 IP 地址改变（静态 IP 改变或 DHCP 获取新 IP）
- IP 配置方式改变（从静态 IP 改为 DHCP，或反之）
- 物理网卡状态改变（up/down）
- 新增或删除网络接口
- 桥接、VLAN 等虚拟接口的变化

**注意**：更新不是立即的，通常有短暂的延迟（几秒到几十秒），取决于 NMState Operator 的扫描频率。

### 1.2 存储的信息

`NodeNetworkState` 的 `status.currentState` 字段存储了节点的完整网络状态，包括：

1. **所有网络接口信息**（包括物理网卡和虚拟接口）：
   - **物理网卡**（`type: ethernet`）：如 `ens160`、`ens192` 等
   - **虚拟接口**：
     - 桥接（`type: linux-bridge`）：如 `br-external`、`cni0`
     - VLAN 接口（`type: vlan`）：如 `ens192.100`
     - VXLAN 接口（`type: vxlan`）：如 `flannel.1`
     - 回环接口（`type: loopback`）：如 `lo`
   
   每个接口的信息包括：
   - 接口名称（`name`）
   - 接口类型（`type`）
   - 接口状态（`state`：up、down）
   - MAC 地址（`mac-address`）
   - MTU（`mtu`）

2. **IP 配置信息**：
   - **IPv4 配置**（`ipv4`）：
     - `enabled`：是否启用 IPv4
     - `dhcp`：是否使用 DHCP（true/false）
     - `address`：IP 地址列表
       - `ip`：IP 地址（如 "192.168.0.105"）
       - `prefix-length`：子网掩码长度（如 24）
   - **IPv6 配置**（`ipv6`）：类似 IPv4

3. **其他网络信息**：
   - DNS 配置（`dns-resolver`）
   - 路由信息（通过接口的 IP 配置推断）

## 2. 为什么需要获取物理网卡信息？

在我们的代码中，`getIPConfigFromNodeNetworkState` 函数从 `NodeNetworkState` 获取物理网卡（如 `ens192`）的 IP 配置信息，主要有以下用途：

### 2.1 自动检测 IP 配置方式

当我们创建桥接网络时，需要知道物理网卡当前是如何配置 IP 的：
- **静态 IP**：物理网卡有固定的 IP 地址
- **DHCP**：物理网卡通过 DHCP 动态获取 IP

### 2.2 保持网络配置一致性

当我们将物理网卡的 IP 迁移到桥接上时，必须：
1. **保持相同的 IP 配置方式**：
   - 如果物理网卡是 DHCP，桥接也应该配置为 DHCP
   - 如果物理网卡是静态 IP，桥接也应该配置相同的静态 IP

2. **避免网络中断**：
   - 如果物理网卡是 DHCP，但桥接配置为静态 IP，可能导致 IP 冲突
   - 如果物理网卡是静态 IP，但桥接配置为 DHCP，节点可能失去网络连接

### 2.3 自动获取节点 IP 地址

如果不指定 `nodeIP`，代码会自动从 `NodeNetworkState` 获取物理网卡的实际 IP 地址，用于：
- 在桥接上配置相同的 IP 地址
- 确保节点网络不中断

## 3. 实际示例

### 3.1 NodeNetworkState 存储的所有接口

从节点 `host1` 的 NodeNetworkState 可以看到以下接口：

- **物理网卡**（`type: ethernet`）：
  - `ens160`：静态 IP（192.168.1.141/24）
  - `ens192`：DHCP IP（192.168.0.105/24）

- **虚拟接口**：
  - `br-external`：桥接接口（`type: linux-bridge`）
  - `cni0`：CNI 桥接（`type: linux-bridge`）
  - `flannel.1`：Flannel VXLAN（`type: vxlan`）
  - `lo`：回环接口（`type: loopback`）

### 3.2 NodeNetworkState 中的 ens192 信息

```yaml
apiVersion: nmstate.io/v1beta1
kind: NodeNetworkState
metadata:
  name: host1  # 节点名称
status:
  currentState:
    interfaces:
    - name: ens192
      type: ethernet
      state: up
      mac-address: 00:0C:29:1A:CA:B9
      ipv4:
        enabled: true
        dhcp: true  # 使用 DHCP
        address:
        - ip: 192.168.0.105
          prefix-length: 24
      ipv6:
        enabled: true
        address:
        - ip: fe80::2f9c:eb4f:a045:e512
          prefix-length: 64
```

### 3.2 代码如何使用这些信息

```go
// 从 NodeNetworkState 获取 ens192 的 IP 配置
ipInfo, err := getIPConfigFromNodeNetworkState(ctx, c, "ens192")

// 结果：
// ipInfo.ipAddress = "192.168.0.105/24"  // 当前 IP 地址
// ipInfo.useDHCP = true                  // 使用 DHCP

// 然后根据这些信息配置桥接
if ipInfo.useDHCP {
    // 桥接也配置为 DHCP
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "dhcp":    true,
    }
} else {
    // 桥接配置为静态 IP
    bridgeInterface["ipv4"] = map[string]interface{}{
        "enabled": true,
        "dhcp":    false,
        "address": []interface{}{
            map[string]interface{}{
                "ip":            "192.168.0.105",
                "prefix-length": 24,
            },
        },
    }
}
```

## 4. 总结

**NodeNetworkState** 存储了节点的实际网络状态，是我们了解节点网络配置的"真相来源"。

**获取物理网卡信息的作用**：
1. ✅ 自动检测 IP 配置方式（DHCP/静态）
2. ✅ 自动获取当前 IP 地址
3. ✅ 保持桥接配置与物理网卡一致
4. ✅ 避免网络中断

这样，即使物理网卡从静态 IP 改为 DHCP（或反之），我们的代码也能自动适应，确保节点网络正常。


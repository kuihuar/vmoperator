# DHCP 逻辑说明

## 概述

在当前实现中，DHCP 模式用于让 VM 自动从物理网络环境获取 IP 地址。DHCP 服务器来自**物理网络环境**（通常是网络中的路由器/网关），而不是 Kubernetes 集群提供的。

## DHCP 工作流程

### 1. 配置生成阶段（代码层面）

```go
// pkg/kubevirt/vm.go: buildCloudInitNetworkConfig
// 为 DHCP 模式的网络生成 Netplan 配置
networkConfig.WriteString("      dhcp4: true\n")
networkConfig.WriteString("      dhcp6: false\n")
```

**生成的 Cloud-Init 配置示例**：
```yaml
#cloud-config
network:
  version: 2
  ethernets:
    eth1:
      match:
        macaddress: fa:8b:64:25:1f:0c
      set-name: eth1
      dhcp4: true      # 启用 DHCP 客户端
      dhcp6: false
```

### 2. VM 启动阶段

```
VM 启动
  ↓
Cloud-Init 运行
  ↓
读取 cloudinitdisk volume 中的 userData
  ↓
解析 Netplan 配置
  ↓
应用网络配置到 VM 内的网络接口
  ↓
启用 DHCP 客户端（dhclient 或 systemd-networkd）
```

### 3. DHCP 请求阶段（VM 内部）

VM 内的 DHCP 客户端通过以下路径发送 DHCP 请求：

```
VM 内的网络接口 (eth1/enp2s0)
  ↓
KubeVirt Bridge 接口 (vnet0)
  ↓
节点上的 Linux Bridge (br-external)
  ↓
物理网卡 (ens192)
  ↓
物理网络交换机/路由器
  ↓
物理网络的 DHCP 服务器（通常是网关 192.168.0.1）
```

### 4. DHCP DORA 流程

VM 内的 DHCP 客户端遵循标准的 DHCP DORA 流程：

1. **Discovery（发现）**
   - VM 内的 DHCP 客户端发送 `DHCPDISCOVER` 广播包
   - 通过 bridge → 物理网卡 → 物理网络

2. **Offer（提供）**
   - 物理网络中的 DHCP 服务器（通常是网关）接收到请求
   - 从 IP 地址池中选择一个可用 IP
   - 发送 `DHCPOFFER` 响应，包含：
     - IP 地址（如：192.168.0.100）
     - 子网掩码（如：255.255.255.0）
     - 默认网关（如：192.168.0.1）
     - DNS 服务器（如：192.168.0.1, 8.8.8.8）

3. **Request（请求）**
   - VM 的 DHCP 客户端选择其中一个 offer
   - 发送 `DHCPREQUEST` 请求该 IP

4. **Acknowledgement（确认）**
   - DHCP 服务器发送 `DHCPACK` 确认
   - VM 应用网络配置
   - 网络接口获得 IP 地址

### 5. 网络配置应用

```
DHCP 服务器响应
  ↓
VM 内的 DHCP 客户端接收响应
  ↓
应用网络配置：
  - IP 地址：192.168.0.100/24
  - 网关：192.168.0.1
  - DNS：192.168.0.1, 8.8.8.8
  ↓
网络接口获得 IP 地址
  ↓
可以访问网络
```

## DHCP 服务器来源

### 关键点：DHCP 服务器来自物理网络环境

**不是 Kubernetes 集群提供的**，而是：

1. **物理网络中的设备**：
   - 路由器/网关（最常见）
   - 交换机（某些企业网络）
   - 专用的 DHCP 服务器（大型企业）

2. **网络拓扑**：
   ```
   VM (eth1)
     ↓
   KubeVirt Bridge (vnet0)
     ↓
   Linux Bridge (br-external)
     ↓
   物理网卡 (ens192)
     ↓
   物理交换机
     ↓
   物理路由器/网关 (192.168.0.1) ← DHCP 服务器
     ↓
   互联网
   ```

3. **配置要求**：
   - 物理网络必须有 DHCP 服务器
   - 物理网卡必须连接到有 DHCP 服务器的网络
   - 网络必须允许 DHCP 广播包通过

## 代码实现要点

### 1. Multus NetworkAttachmentDefinition

**重要**：对于 DHCP 模式，**不设置 IPAM**：

```go
// pkg/network/multus.go: buildCNIConfig
if netCfg.IPConfig.Mode == "dhcp" {
    // 对于 DHCP 模式，不设置 IPAM
    // Bridge CNI 不支持 DHCP IPAM（DHCP IPAM 是独立的 CNI 插件）
    // VM 内部的 IP 将通过 Cloud-Init 的 DHCP 配置获取
    // 不设置 IPAM，让接口在 VM 内部通过 DHCP 获取 IP
}
```

**原因**：
- Bridge CNI 本身不支持 DHCP IPAM
- DHCP IPAM 是独立的 CNI 插件（如 dhcp-daemon），通常用于容器
- KubeVirt VM 使用 Cloud-Init 在 VM 内部配置 DHCP 客户端，更符合虚拟机场景

### 2. Cloud-Init 网络配置

```go
// pkg/kubevirt/vm.go: buildCloudInitNetworkConfig
// 启用 DHCP
networkConfig.WriteString("      dhcp4: true\n")
networkConfig.WriteString("      dhcp6: false\n")
```

这会在 VM 内部启用 DHCP 客户端，让 VM 从物理网络获取 IP。

## 网络配置示例

### 配置示例

```yaml
# config/samples/vm_v1alpha1_wukong_dual_network_dhcp.yaml
networks:
  - name: external
    type: bridge
    bridgeName: "br-external"
    physicalInterface: "ens192"  # 物理网卡，连接到有 DHCP 服务器的网络
    ipConfig:
      mode: dhcp  # 使用 DHCP 自动获取 IP
      # 不需要指定 address、gateway 和 dnsServers
      # 系统会自动从 DHCP 服务器获取这些配置
```

### 生成的 Cloud-Init 配置

```yaml
network:
  version: 2
  ethernets:
    eth1:
      match:
        macaddress: fa:8b:64:25:1f:0c
      set-name: eth1
      dhcp4: true
      dhcp6: false
```

### VM 内实际获得的配置

```
eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 192.168.0.100/24 brd 192.168.0.255 scope global dynamic eth1
       valid_lft 86399sec preferred_lft 86399sec
    inet6 fe80::f88b:64ff:fe25:1f0c/64 scope link
       valid_lft forever preferred_lft forever
```

从 `dynamic` 可以看出，IP 是通过 DHCP 动态获取的。

## 与静态 IP 的区别

| 特性 | DHCP 模式 | 静态 IP 模式 |
|------|-----------|-------------|
| IP 地址来源 | 物理网络的 DHCP 服务器 | 用户指定 |
| 配置位置 | Cloud-Init (VM 内) | Cloud-Init (VM 内) |
| NetworkAttachmentDefinition | 不设置 IPAM | 设置 host-local IPAM |
| 网络配置 | `dhcp4: true` | `addresses: [...]` |
| 网关/DNS | 从 DHCP 服务器获取 | 用户指定 |
| 适用场景 | 动态 IP 分配 | 固定 IP 需求 |

## 常见问题

### Q1: DHCP 服务器在哪里？

**A**: DHCP 服务器在**物理网络环境**中，通常是：
- 路由器/网关（家庭/小型办公室）
- 交换机（某些企业网络）
- 专用 DHCP 服务器（大型企业）

**不是** Kubernetes 集群提供的。

### Q2: 为什么 VM 内看不到 IP 地址？

**A**: 可能的原因：
1. 物理网络没有 DHCP 服务器
2. 物理网卡没有连接到有 DHCP 服务器的网络
3. 网络配置未正确应用（检查 Cloud-Init 日志）
4. DHCP 请求被防火墙阻止

### Q3: 能否使用 Kubernetes 集群内的 DHCP 服务器？

**A**: 理论上可以，但需要：
1. 在集群内部署 DHCP 服务器（如 dhcp-daemon）
2. 配置 DHCP IPAM（但这不适用于 Bridge CNI）
3. 当前的实现方式是让 VM 从物理网络获取 IP，更符合虚拟机场景

### Q4: 如何调试 DHCP 问题？

**A**: 
1. 检查 VM 内的 DHCP 客户端日志：
   ```bash
   # 进入 VM
   journalctl -u systemd-networkd  # 如果使用 systemd-networkd
   # 或
   journalctl -u NetworkManager     # 如果使用 NetworkManager
   ```

2. 检查网络接口状态：
   ```bash
   ip addr show
   ip link show
   ```

3. 手动测试 DHCP：
   ```bash
   dhclient -v eth1  # 手动触发 DHCP 请求
   ```

4. 检查物理网络连接：
   ```bash
   # 在节点上
   ip addr show ens192
   ip link show br-external
   ```

## 总结

1. **DHCP 服务器来源**：物理网络环境（路由器/网关），不是 Kubernetes 集群
2. **工作流程**：VM 启动 → Cloud-Init 应用配置 → DHCP 客户端发送请求 → 物理网络 DHCP 服务器响应 → VM 获得 IP
3. **配置方式**：通过 Cloud-Init 的 Netplan 配置启用 DHCP 客户端
4. **关键点**：Multus NetworkAttachmentDefinition 不设置 IPAM，让 VM 内部通过 DHCP 获取 IP


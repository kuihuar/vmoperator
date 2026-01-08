# 修复 NMState 导致的网络配置问题

## 问题描述

安装 NMState Operator 后，Ubuntu 机器的 ens160 网卡 IP 变成了 DHCP，无法固定为原来的 192.168.1.141，且无法在 Ubuntu 设置中配置 IP。

## 问题原因

NMState Operator 会通过 `NodeNetworkConfigurationPolicy` CRD 管理节点网络配置，可能会覆盖传统的网络管理器（NetworkManager）或 netplan 配置。

## 解决方案

### 方案 1：使用 NMState 配置静态 IP（推荐）

通过创建 `NodeNetworkConfigurationPolicy` 来配置静态 IP，这是使用 NMState 的正确方式。

### 方案 2：禁用 NMState 对特定网卡的管理

如果不需要 NMState 管理该网卡，可以排除该网卡。

### 方案 3：临时恢复传统配置（不推荐）

临时禁用 NMState 并恢复传统网络配置，但可能会与 NMState 冲突。

## 快速修复脚本

使用提供的脚本快速修复：

```bash
# 运行修复脚本
bash docs/installation/fix-nmstate-static-ip.sh
```


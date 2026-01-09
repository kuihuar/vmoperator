# 桥接网络 netplan 配置指南

## 问题说明

当使用 `bridge` 类型的网络时，需要在节点上创建 Linux Bridge，并将物理接口（如 `ens160`）添加到桥接。

如果 `ens160` 已经被 netplan 配置了 IP 地址，需要修改 netplan 配置，将 IP 地址移到桥接上。

## 配置步骤

### 1. 备份当前配置

```bash
sudo cp /etc/netplan/*.yaml /etc/netplan/*.yaml.backup
```

### 2. 修改 netplan 配置

编辑 `/etc/netplan/00-installer-config.yaml`（或你的 netplan 配置文件）：

**修改前**（ens160 有 IP）：
```yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens160:
      dhcp4: false
      addresses:
        - 192.168.1.141/24
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
```

**修改后**（桥接有 IP，ens160 作为桥接端口）：
```yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens160:
      dhcp4: false
      # 不再在 ens160 上配置 IP
  bridges:
    br-external:
      dhcp4: false
      addresses:
        - 192.168.1.141/24  # 将原来的 IP 移到桥接上
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
      interfaces:
        - ens160  # 将 ens160 作为桥接的端口
    br-management:
      dhcp4: false
      interfaces:
        - ens160  # 如果需要，也可以将 ens160 添加到管理桥接
```

### 3. 应用配置

```bash
sudo netplan apply
```

### 4. 验证配置

```bash
# 检查桥接状态
ip addr show br-external
ip addr show br-management

# 检查 ens160 状态（应该没有 IP）
ip addr show ens160

# 检查桥接端口
bridge link show br-external
```

## 注意事项

### ⚠️ 重要警告

1. **网络中断风险**：修改 netplan 配置时，可能会暂时中断网络连接
   - 建议在物理控制台或通过其他网络接口操作
   - 或者使用 `screen` 或 `tmux` 保持会话

2. **IP 地址冲突**：确保桥接的 IP 地址与原来的 ens160 IP 地址相同
   - 如果 IP 地址不同，可能会导致无法访问节点

3. **多个桥接**：如果创建多个桥接（如 `br-external` 和 `br-management`），需要决定：
   - 是否将 ens160 同时添加到多个桥接（通常不推荐）
   - 或者使用 VLAN 来区分不同的网络

### 推荐配置（使用 VLAN）

如果需要在同一个物理接口上创建多个桥接，建议使用 VLAN：

```yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens160:
      dhcp4: false
  vlans:
    ens160.100:  # VLAN 100 用于管理网络
      id: 100
      link: ens160
    ens160.200:  # VLAN 200 用于外部网络
      id: 200
      link: ens160
  bridges:
    br-management:
      dhcp4: false
      addresses:
        - 192.168.100.141/24
      interfaces:
        - ens160.100
    br-external:
      dhcp4: false
      addresses:
        - 192.168.1.141/24
      interfaces:
        - ens160.200
```

## 与 NMState 的关系

修改 netplan 配置后：

1. **NMState 可以正常工作**：
   - 如果 NMState 创建的桥接名称与 netplan 配置的桥接名称相同，NMState 会检测到桥接已存在
   - NMState 会验证桥接配置是否符合期望状态

2. **避免冲突**：
   - 如果 netplan 已经配置了桥接，NMState 不需要再次创建
   - 但 NMState 仍然会尝试管理桥接配置，可能会与 netplan 冲突

3. **推荐做法**：
   - **方案 A**：完全使用 netplan 管理桥接，NMState 只用于验证
   - **方案 B**：完全使用 NMState 管理桥接，从 netplan 中移除桥接配置

## 故障排查

### 问题 1：应用配置后无法访问节点

**原因**：IP 地址配置错误或网关配置错误

**解决**：
1. 通过物理控制台或 IPMI 访问节点
2. 检查 `ip addr show` 和 `ip route` 输出
3. 恢复备份配置：`sudo cp /etc/netplan/*.yaml.backup /etc/netplan/*.yaml && sudo netplan apply`

### 问题 2：桥接创建失败

**原因**：NetworkManager 或 netplan 配置冲突

**解决**：
1. 检查 NetworkManager 状态：`systemctl status NetworkManager`
2. 检查 netplan 配置语法：`sudo netplan --debug apply`
3. 查看 NetworkManager 日志：`journalctl -u NetworkManager -n 50`

### 问题 3：NMState 仍然报错

**原因**：NMState 检测到配置与期望状态不一致

**解决**：
1. 检查 NMState 期望的桥接配置：`kubectl get nncp -o yaml`
2. 手动验证桥接配置是否符合期望
3. 如果符合，可以忽略 NMState 的错误（桥接已经正确配置）


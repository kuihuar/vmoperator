# VM 静态 IP 配置故障排查

## 问题现象

从 Cloud-Init 日志看：
- ✅ MAC 地址已匹配：`12:92:a7:aa:c5:cb`
- ❌ 但 `enp2s0` 状态是 `False (Down)`
- ❌ 没有 IP 地址
- ❌ 无法访问外网

## 问题分析

### 当前 Cloud-Init 配置

```yaml
network:
  version: 2
  ethernets:
    eth1:
      match:
        macaddress: 12:92:a7:aa:c5:cb
      dhcp4: false
      dhcp6: false
      optional: true      # ✅ 已添加
      addresses:
        - 192.168.0.200/24
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
          - 114.114.114.114
          - 8.8.8.8
```

### 可能原因

1. **接口未就绪**：Multus 接口可能在 Cloud-Init 运行时还未完全就绪
2. **Netplan 配置未应用**：虽然 MAC 地址匹配，但配置可能未正确应用
3. **接口名称不匹配**：使用 `eth1` 作为配置键，但实际接口是 `enp2s0`

## 解决方案

### 方案 1：在 VM 内手动应用 Netplan 配置

```bash
# 在 VM 内执行
sudo netplan apply

# 检查接口状态
ip addr show enp2s0

# 如果接口是 DOWN，手动启动
sudo ip link set enp2s0 up
```

### 方案 2：检查 Cloud-Init 日志

```bash
# 在 VM 内检查 Cloud-Init 日志
sudo cat /var/log/cloud-init.log | grep -i network
sudo cat /var/log/cloud-init-output.log | grep -i network
```

### 方案 3：检查 Netplan 配置

```bash
# 在 VM 内检查 Netplan 配置
sudo cat /etc/netplan/50-cloud-init.yaml

# 检查 Netplan 状态
sudo netplan status
```

### 方案 4：手动配置接口（临时方案）

```bash
# 在 VM 内手动配置
sudo ip addr add 192.168.0.200/24 dev enp2s0
sudo ip link set enp2s0 up
sudo ip route add default via 192.168.0.1 dev enp2s0
```

## 代码修复

### 已修复

1. ✅ 添加 `dhcp4: false` 和 `dhcp6: false`
2. ✅ 添加 `optional: true`（避免接口未就绪时配置失败）

### 待验证

- 重新创建 VM 后，检查接口是否正确配置
- 如果问题仍然存在，可能需要：
  - 添加 `set-name` 来确保接口名称
  - 或者等待接口就绪后再配置

## 验证步骤

1. **重新创建 VM**（使用修复后的代码）
2. **检查 Cloud-Init 日志**：
   ```bash
   sudo cat /var/log/cloud-init.log
   ```
3. **检查接口状态**：
   ```bash
   ip addr show
   ```
4. **检查路由**：
   ```bash
   ip route show
   ```
5. **测试网络连接**：
   ```bash
   ping 192.168.0.1
   ping 8.8.8.8
   ```

## 如果问题仍然存在

1. **检查 Multus 网络状态**：
   ```bash
   kubectl get network-attachment-definition
   kubectl get pods -o wide
   ```

2. **检查桥接状态**：
   ```bash
   ip addr show br-external
   ```

3. **检查 VMI 状态**：
   ```bash
   kubectl get vmi ubuntu-vm-dual-network-static-vm -o yaml
   ```


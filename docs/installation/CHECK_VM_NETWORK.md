# 检查 VM 内部网络配置

## 当前状态

- ✅ Cloud-Init 配置正确：使用 `eth1` 匹配接口，配置 `192.168.1.200/24`
- ✅ VMI 状态显示有 IP `192.168.1.200`
- ❌ 无法从外部访问 `192.168.1.200`

## 检查步骤

### 1. 通过 Pod IP 访问 VM

```bash
POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')
ssh ubuntu@$POD_IP
# 密码：ubuntu123
```

### 2. 在 VM 内部检查网络接口

```bash
# 查看所有网络接口
ip addr show

# 查看路由
ip route show

# 检查是否有 eth1 接口
ip link show eth1

# 检查 eth1 是否有 IP
ip addr show eth1
```

### 3. 如果 eth1 不存在，检查实际的接口名称

```bash
# 查看所有接口
ip link show

# 查看接口的 MAC 地址
ip link show | grep -A 1 "8e:3e:46:4a:d4:33"
```

### 4. 如果接口存在但没有 IP，手动配置测试

```bash
# 假设接口名称是 enp2s0 或其他
sudo ip addr add 192.168.1.200/24 dev <interface-name>
sudo ip route add default via 192.168.1.1 dev <interface-name>

# 测试连通性
ping -c 3 192.168.1.1
```

## 可能的问题和解决方案

### 问题 1：接口名称不是 eth1

**解决方案：** 修改 Cloud-Init 配置，使用通配符匹配：

```yaml
network:
  version: 2
  ethernets:
    enp*:  # 匹配所有 enp 开头的接口
      addresses:
        - 192.168.1.200/24
      gateway4: 192.168.1.1
```

### 问题 2：Cloud-Init 网络配置未生效

**检查 Cloud-Init 日志：**
```bash
kubectl logs <virt-launcher-pod> -c guest-console-log | grep -i "network\|cloud-init"
```

**手动触发 Cloud-Init 网络配置：**
```bash
sudo cloud-init clean
sudo cloud-init init --local
sudo cloud-init init
sudo cloud-init modules --mode config
```

### 问题 3：接口顺序问题

如果 VM 内部的接口顺序不是 eth0, eth1，可能需要：
- 使用 MAC 地址匹配（需要运行时获取 MAC）
- 使用接口的 MAC 地址从 VMI 状态获取

## 参考

- [Cloud-Init Network Configuration](https://cloudinit.readthedocs.io/en/latest/topics/network-config.html)
- [KubeVirt Networking](https://kubevirt.io/user-guide/virtual_machines/networking/)


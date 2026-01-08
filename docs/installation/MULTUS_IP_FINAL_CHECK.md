# Multus IP 192.168.1.200 最终检查清单

## 当前状态

- ✅ VM 运行正常
- ✅ VMI 状态显示有 IP `192.168.1.200`
- ✅ MAC 地址: `b6:0f:c8:bd:9f:97`
- ❌ 无法从外部访问 `192.168.1.200`

## 检查步骤

### 1. 检查 VM 内部的接口配置

```bash
# 通过 Pod IP 访问 VM
POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')
ssh ubuntu@$POD_IP
# 密码：ubuntu123

# 在 VM 内部检查
ip addr show enp2s0
ip route show
```

### 2. 检查 Cloud-Init 配置

```bash
# 查看 Cloud-Init 配置
kubectl get pod -l kubevirt.io=virt-launcher | grep ubuntu-rulai-multus | \
  awk '{print $1}' | xargs -I {} kubectl exec {} -c compute -- \
  cat /var/lib/kubevirt/configs/cloud-init/userdata | grep -A 15 "network:"
```

### 3. 如果 enp2s0 没有 IP，手动配置测试

```bash
# 在 VM 内部执行
sudo ip addr add 192.168.1.200/24 dev enp2s0
sudo ip link set enp2s0 up
sudo ip route add default via 192.168.1.1 dev enp2s0

# 测试连通性
ping -c 3 192.168.1.1
```

### 4. 检查 Cloud-Init 网络配置日志

```bash
kubectl logs <virt-launcher-pod> -c guest-console-log | grep -i "network\|enp2s0\|192.168.1.200"
```

## 可能的问题

### 问题 1：Cloud-Init 配置使用了错误的接口名称

**检查：** Cloud-Init 配置应该使用 `enp2s0` 或 MAC 地址匹配

**解决方案：** 如果配置错误，需要修改代码重新生成

### 问题 2：接口名称不匹配

**检查：** VM 内部的接口名称可能不是 `enp2s0`

**解决方案：** 使用 MAC 地址匹配（代码已实现）

### 问题 3：Cloud-Init 网络配置未生效

**检查：** Cloud-Init 日志中是否有错误

**解决方案：** 手动触发 Cloud-Init 网络配置或手动配置接口

## 代码修改说明

最新代码修改：
1. 尝试从现有 VMI 获取 MAC 地址
2. 使用 MAC 地址匹配接口，设置名称为 `enp2s0`
3. 如果 MAC 地址不可用，直接使用 `enp2s0`

## 下一步

1. 确认 VM 内部的 `enp2s0` 接口是否配置了 IP
2. 如果未配置，检查 Cloud-Init 配置是否正确
3. 如果配置正确但未生效，可能需要手动配置或检查 Cloud-Init 日志



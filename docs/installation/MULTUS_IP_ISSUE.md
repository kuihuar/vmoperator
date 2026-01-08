# Multus IP 192.168.1.200 无法访问问题分析

## 当前状态

- ✅ VM 运行正常
- ✅ VMI 状态显示有 IP `192.168.1.200`
- ✅ Pod 中的 `podfa96c2c1834` 接口有 IP `192.168.1.200/24`
- ❌ 但接口状态是 `DOWN`（这是正常的，因为它是 bridge 的一部分）
- ❌ 无法从外部访问 `192.168.1.200`

## 问题分析

### 1. 网络架构

对于 macvlan + bridge 组合：
- Multus 创建 macvlan 接口 `fa96c2c1834-nic` 在 Pod 网络命名空间中
- KubeVirt 创建 bridge `k6t-fa96c2c1834` 连接 macvlan 接口和 VM
- Pod 中的 `podfa96c2c1834` 接口是 bridge 的一部分，状态为 DOWN 是正常的
- **IP 地址应该在 VM 内部配置，而不是在 Pod 网络命名空间中**

### 2. 当前问题

1. **Cloud-Init 配置可能使用了错误的接口名称**
   - Cloud-Init 使用 `ubuntu-rulai-multus-external-nad` 作为接口名称
   - 但 VM 内部的接口名称可能不同

2. **IP 配置方式可能不正确**
   - 根据 KubeVirt 文档，静态 IP 可以通过 VMI 的 `networks.ipAddress` 字段配置
   - 或者通过 Cloud-Init 在 VM 内部配置

## 解决方案

### 方案 1：检查 VM 内部接口名称（推荐）

1. 通过 Pod IP 访问 VM：
   ```bash
   POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')
   ssh ubuntu@$POD_IP
   # 密码：ubuntu123
   ```

2. 在 VM 内部检查接口：
   ```bash
   ip addr show
   ip route show
   ```

3. 确认接口名称是否匹配 Cloud-Init 配置

### 方案 2：使用 KubeVirt 的 ipAddress 字段

修改代码，在 VMI 的 networks 部分直接指定 IP，而不是通过 Cloud-Init：

```go
// 在 buildNetworks 中
if net.IPConfig != nil && net.IPConfig.Mode == "static" && net.IPConfig.Address != nil {
    network.IPAddress = *net.IPConfig.Address
    if net.IPConfig.Gateway != nil {
        network.Gateway = *net.IPConfig.Gateway
    }
}
```

### 方案 3：修复 Cloud-Init 接口名称

如果 VM 内部的接口名称不是 `ubuntu-rulai-multus-external-nad`，需要：
1. 检查 VM 内部实际的接口名称
2. 修改 Cloud-Init 配置使用正确的接口名称
3. 或者使用通配符匹配（如 `enp*`）

## 验证步骤

1. **检查 VM 内部网络配置**：
   ```bash
   # 通过 Pod IP 访问
   ssh ubuntu@<POD_IP>
   ip addr show
   ```

2. **检查 Cloud-Init 日志**：
   ```bash
   kubectl logs <virt-launcher-pod> -c guest-console-log | grep -i network
   ```

3. **手动测试**：
   ```bash
   # 在 VM 内部手动配置 IP（如果接口存在）
   sudo ip addr add 192.168.1.200/24 dev <interface-name>
   sudo ip route add default via 192.168.1.1 dev <interface-name>
   ```

## 参考

- [KubeVirt Multus 网络配置](https://kubevirt.io/user-guide/virtual_machines/networking/)
- [Multus CNI 文档](https://github.com/k8snetworkplumbingwg/multus-cni)


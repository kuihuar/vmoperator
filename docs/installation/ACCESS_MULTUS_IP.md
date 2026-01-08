# 访问 VM 的 Multus IP 地址

## 当前状态

VM 配置了 Multus 网络，IP 地址为 `192.168.1.200`，但可能无法从外部直接访问。

## 查看 VM IP 的方法

### 方法 1：使用 kubectl 查看 VMI 状态（推荐）

```bash
# 查看所有网络接口
kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces}' | jq -r '.'

# 查看 Pod 网络 IP
kubectl get vmi ubuntu-rulai-multus-vm -o wide

# 查看 Multus 网络 IP
kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="ubuntu-rulai-multus-external-nad")].ipAddress}'
```

### 方法 2：查看 virt-launcher Pod 的网络接口

```bash
# 获取 Pod 名称
POD_NAME=$(kubectl get pod -l kubevirt.io=virt-launcher | grep ubuntu-rulai-multus | awk '{print $1}')

# 查看所有网络接口
kubectl exec $POD_NAME -c compute -- ip addr show

# 查看 Multus 接口
kubectl exec $POD_NAME -c compute -- ip addr show | grep -A 5 "fa96c2c1834"
```

### 方法 3：通过 Pod IP 访问 VM

```bash
# 获取 Pod IP
POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')

# 通过 Pod IP SSH 访问
ssh ubuntu@$POD_IP

# 或使用 virtctl
virtctl ssh ubuntu-rulai-multus-vm
```

## 访问 Multus IP (192.168.1.200)

### 问题诊断

如果无法访问 `192.168.1.200`，请检查：

1. **检查 ARP 表**
   ```bash
   arp -n | grep 192.168.1.200
   ```
   如果显示 `(incomplete)`，说明 ARP 请求没有收到响应。

2. **检查路由**
   ```bash
   ip route get 192.168.1.200
   ```

3. **检查 VM 内部网络配置**
   ```bash
   # 通过 Pod IP 访问 VM
   POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')
   ssh ubuntu@$POD_IP
   
   # 在 VM 内部检查网络接口
   ip addr show
   ip route show
   ```

4. **检查 macvlan 接口状态**
   ```bash
   # 在宿主机上检查
   ip link show | grep ens160
   
   # 检查 macvlan 子接口
   ip link show type macvlan
   ```

### 可能的原因

1. **VM 内部未配置 IP 地址**
   - macvlan 接口在 Pod 网络命名空间中创建
   - 但 IP 地址需要在 VM 内部配置
   - 检查 Cloud-Init 是否正确配置了网络

2. **macvlan 模式问题**
   - 当前配置使用 `bridge` 模式
   - 某些情况下可能需要 `passthru` 模式

3. **网络策略或防火墙**
   - 检查宿主机防火墙规则
   - 检查网络交换机配置

4. **IP 地址冲突**
   - 确认 `192.168.1.200` 未被其他设备占用
   ```bash
   ping 192.168.1.200
   arp -a | grep 192.168.1.200
   ```

### 解决方案

#### 方案 1：通过 Pod IP 访问（推荐）

如果 Multus IP 无法直接访问，可以先通过 Pod IP 访问 VM，然后在 VM 内部检查网络配置：

```bash
# 获取 Pod IP
POD_IP=$(kubectl get vmi ubuntu-rulai-multus-vm -o jsonpath='{.status.interfaces[?(@.name=="default")].ipAddress}')

# SSH 访问
ssh ubuntu@$POD_IP
# 密码：ubuntu123

# 在 VM 内部检查网络
ip addr show
ip route show

# 手动配置 Multus 接口 IP（如果需要）
sudo ip addr add 192.168.1.200/24 dev <interface_name>
sudo ip route add default via 192.168.1.1 dev <interface_name>
```

#### 方案 2：检查 Cloud-Init 网络配置

确保 Cloud-Init 正确配置了网络接口。检查 VM 配置中的 `networks` 部分：

```yaml
networks:
  - name: external
    type: macvlan
    bridgeName: "ens160"
    ipConfig:
      mode: static
      address: "192.168.1.200/24"
      gateway: "192.168.1.1"
      dnsServers:
        - "192.168.1.1"
        - "114.114.114.114"
```

#### 方案 3：使用 virtctl console 检查

```bash
virtctl console ubuntu-rulai-multus-vm
# 在控制台中检查网络配置
```

#### 方案 4：检查 Multus 接口名称

Multus 接口在 Pod 中的名称可能与 VM 内部不同：

```bash
# Pod 中的接口名称
kubectl exec <pod-name> -c compute -- ip link show | grep fa96c2c1834

# VM 内部的接口名称可能不同
# 需要通过 console 或 SSH 进入 VM 查看
```

## 验证网络连通性

### 从宿主机测试

```bash
# Ping 测试
ping -c 3 192.168.1.200

# 检查 ARP
arp -n | grep 192.168.1.200

# 检查路由
ip route get 192.168.1.200
```

### 从 VM 内部测试

```bash
# 通过 Pod IP SSH 进入 VM
ssh ubuntu@<POD_IP>

# 测试外部网络
ping -c 3 192.168.1.1
ping -c 3 8.8.8.8

# 检查网络接口
ip addr show
ip route show
```

## 常见问题

### Q: 为什么 VMI 状态显示有 IP，但无法访问？

A: VMI 状态中的 IP 地址是从 Multus 的 `networks-status` 注解中读取的，但实际网络配置可能在 VM 内部未生效。需要检查 VM 内部的网络配置。

### Q: macvlan 接口在 Pod 中，IP 地址在哪里配置？

A: macvlan 接口在 Pod 网络命名空间中创建，但 IP 地址应该在 VM 内部配置。KubeVirt 会通过 Cloud-Init 或网络配置将 IP 地址传递给 VM。

### Q: 如何确认 VM 内部是否配置了 IP？

A: 通过 SSH 或 console 进入 VM，执行 `ip addr show` 查看网络接口配置。

## 参考

- [KubeVirt 网络配置文档](https://kubevirt.io/user-guide/virtual_machines/networking/)
- [Multus CNI 文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [macvlan 网络模式](https://www.kernel.org/doc/Documentation/networking/macvlan.txt)


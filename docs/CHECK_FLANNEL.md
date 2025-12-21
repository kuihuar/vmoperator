# 检查 Flannel 网络命令

## 快速检查

### 方法 1: 检查 Flannel Pods

```bash
# 检查 Flannel Pods
kubectl get pods -n kube-system | grep flannel

# 或更详细
kubectl get pods -n kube-system -l app=flannel -o wide
```

**结果说明**:
- **有输出**: Flannel 正在运行
- **无输出**: 可能使用 k3s 内置 Flannel（不显示为独立 Pod，但功能正常）

### 方法 2: 检查 Flannel DaemonSet

```bash
# 检查 Flannel DaemonSet
kubectl get daemonset -n kube-system kube-flannel-ds

# 详细状态
kubectl get daemonset -n kube-system kube-flannel-ds -o wide
```

**结果说明**:
- **存在**: 手动安装的标准 Flannel
- **不存在**: k3s 内置 Flannel（正常）

### 方法 3: 使用检查脚本（推荐）

```bash
./scripts/check-flannel.sh
```

## 详细检查命令

### 1. 检查 Flannel 组件

```bash
# 检查 DaemonSet
kubectl get daemonset -n kube-system | grep flannel

# 检查 Pods
kubectl get pods -n kube-system | grep flannel

# 检查 ServiceAccount
kubectl get serviceaccount -n kube-system | grep flannel

# 检查 ClusterRole
kubectl get clusterrole | grep flannel
```

### 2. 检查 Flannel 配置

```bash
# 检查 ConfigMap
kubectl get configmap -n kube-system kube-flannel-cfg

# 查看配置内容
kubectl get configmap -n kube-system kube-flannel-cfg -o yaml

# 查看网络配置
kubectl get configmap -n kube-system kube-flannel-cfg -o jsonpath='{.data.net-conf}'
```

### 3. 检查 CNI 配置文件

```bash
# 查看 CNI 配置目录
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

# 查看 Flannel 配置
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*flannel*.conf

# 或查看所有 CNI 配置
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf
```

### 4. 检查网络接口（在节点上）

```bash
# 检查 Flannel 接口
ip addr show flannel.1

# 检查 CNI bridge
ip addr show cni0

# 检查所有网络接口
ip addr show

# 或使用 ifconfig
ifconfig flannel.1
ifconfig cni0
```

### 5. 检查路由

```bash
# 查看路由表
ip route show

# 查看 Flannel 相关路由
ip route show | grep flannel

# 查看 Pod 网络路由
ip route show | grep cni0
```

### 6. 检查网络连接

```bash
# 测试 Pod 网络
kubectl run test-pod --image=busybox --rm -it -- sh
# 在 Pod 内:
# ip addr show
# ping <另一个 Pod IP>

# 测试 Service 网络
kubectl run test-pod --image=busybox --rm -it -- sh
# 在 Pod 内:
# nslookup kubernetes.default
# wget -qO- http://kubernetes.default
```

### 7. 检查 Pod 网络配置

```bash
# 查看 Pod CIDR
kubectl cluster-info dump | grep cluster-cidr

# 查看节点 Pod CIDR
kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}'

# 查看所有节点的 Pod CIDR
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
```

### 8. 检查 Flannel 日志

```bash
# 查看 Flannel Pod 日志
kubectl logs -n kube-system -l app=flannel --tail=50

# 查看特定 Pod 日志
kubectl logs -n kube-system <flannel-pod-name> --tail=50
```

## k3s 内置 Flannel 检查

k3s 内置 Flannel 可能不显示为独立的 Pod，但可以通过以下方式检查：

### 1. 检查 CNI 配置

```bash
# k3s CNI 配置路径
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

# 查看配置
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf
```

### 2. 检查网络接口

```bash
# 检查 flannel.1 接口
ip addr show flannel.1

# 检查 cni0 bridge
ip addr show cni0
brctl show cni0
```

### 3. 检查 k3s 服务

```bash
# 检查 k3s 服务状态
sudo systemctl status k3s

# 查看 k3s 日志（可能包含网络信息）
sudo journalctl -u k3s -n 50 | grep -i flannel
```

## 常用检查命令总结

### 快速检查（一行命令）

```bash
# 检查 Flannel Pods
kubectl get pods -n kube-system | grep flannel

# 检查 Flannel DaemonSet
kubectl get daemonset -n kube-system kube-flannel-ds

# 检查网络接口
ip addr show | grep -E "flannel|cni0"

# 检查 CNI 配置
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
```

### 完整检查

```bash
# 使用脚本
./scripts/check-flannel.sh

# 或使用 k3s CNI 检查脚本
./scripts/check-k3s-cni.sh
```

## 判断 Flannel 是否正常工作

### 检查清单

- [ ] Flannel Pods 运行（如果是标准安装）
- [ ] flannel.1 接口存在（在节点上）
- [ ] cni0 bridge 存在（在节点上）
- [ ] Pod 可以创建并获取 IP
- [ ] Pod 可以跨节点通信
- [ ] Service 可以正常访问

### 验证命令

```bash
# 1. 创建测试 Pod
kubectl run test-pod --image=busybox --rm -it -- sh

# 2. 在 Pod 内检查网络
# ip addr show
# ping 8.8.8.8
# nslookup kubernetes.default

# 3. 检查 Pod IP 是否在 Pod CIDR 范围内
kubectl get pods -o wide
```

## 常见问题

### Q: `kubectl get pods -n kube-system | grep flannel` 没有输出

**A**: 这是正常的。k3s 内置 Flannel 不显示为独立的 Pod，但网络功能正常。

### Q: 如何确认 Flannel 是否工作？

**A**: 检查网络接口和 Pod 网络：
```bash
# 检查接口
ip addr show flannel.1
ip addr show cni0

# 检查 Pod 是否可以创建
kubectl get pods -o wide
```

### Q: k3s 内置 Flannel 和标准 Flannel 有什么区别？

**A**: 
- **功能**: 完全相同
- **显示**: k3s 内置版本不显示为独立 Pod
- **配置**: k3s 内置版本配置更简单
- **性能**: 相同

## 总结

**最常用的检查命令**:

```bash
# 1. 检查 Pods（最简单）
kubectl get pods -n kube-system | grep flannel

# 2. 检查网络接口（在节点上）
ip addr show flannel.1

# 3. 使用脚本（最全面）
./scripts/check-flannel.sh
```

**k3s 默认情况**:
- ✅ 使用内置 Flannel
- ✅ 不显示为独立 Pod（正常）
- ✅ 网络功能正常
- ✅ 无需额外配置

## 参考

- 检查脚本: `./scripts/check-flannel.sh`
- k3s CNI 检查: `./scripts/check-k3s-cni.sh`
- k3s 网络说明: `docs/K3S_NETWORK_EXPLAIN.md`


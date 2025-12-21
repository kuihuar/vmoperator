# k3s 网络说明

## k3s 默认网络

k3s **默认使用内置的 Flannel CNI**，无需额外安装。

### 特点

- ✅ **内置**: 无需单独安装 CNI 插件
- ✅ **轻量级**: 资源占用小
- ✅ **简单**: 开箱即用，无需配置
- ✅ **兼容**: 与标准 Kubernetes 网络兼容

### 网络模式

k3s 的 Flannel 支持两种模式：

1. **VXLAN 模式**（默认）
   - 使用 VXLAN 隧道封装
   - 跨节点通信通过 VXLAN
   - 适合大多数场景

2. **主机网关模式**（Host Gateway）
   - 直接路由，性能更好
   - 要求节点在同一 L2 网络
   - 适合私有网络环境

## 检查 k3s 使用的网络

### 方法 1: 使用检查脚本（推荐）

```bash
./scripts/check-k3s-cni.sh
```

### 方法 2: 使用您提供的命令

```bash
kubectl get pods -n kube-system | grep -E '(flannel|canal|calico|cilium)'
```

**结果说明**:
- **有输出**: 安装了标准 CNI（Flannel/Calico/Cilium）
- **无输出**: 使用 k3s 内置 Flannel（这是正常的）

### 方法 3: 检查 CNI 配置文件

```bash
# 查看 CNI 配置
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

# 查看配置内容
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf
```

### 方法 4: 检查网络接口

```bash
# 在节点上检查网络接口
ip addr show | grep -E "flannel|cni0|veth"

# 或
ifconfig | grep -E "flannel|cni0"
```

## k3s 网络架构

### 默认配置

```
节点
├── flannel.1 (VXLAN 接口)
├── cni0 (CNI bridge)
└── veth* (Pod 网络接口)
```

### Pod 网络流程

1. **Pod 创建** → CNI 插件配置网络
2. **Pod 连接到 cni0 bridge**
3. **跨节点通信** → 通过 flannel.1 (VXLAN)
4. **Service 访问** → 通过 kube-proxy (iptables/ipvs)

## 网络配置

### 查看当前网络配置

```bash
# Pod CIDR
kubectl cluster-info dump | grep cluster-cidr

# Service CIDR
kubectl cluster-info dump | grep service-cluster-ip-range

# 节点 Pod CIDR
kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}'
```

### 自定义网络配置

k3s 启动时可以指定网络配置：

```bash
# 自定义 Pod CIDR
sudo k3s server --cluster-cidr=10.42.0.0/16

# 自定义 Service CIDR
sudo k3s server --service-cidr=10.43.0.0/16
```

## 对 Longhorn 的影响

### k3s 内置 Flannel 与 Longhorn

- ✅ **完全兼容**: Longhorn 在 k3s 内置 Flannel 上运行正常
- ✅ **无需额外配置**: 不需要安装其他 CNI
- ✅ **Pod 网络正常**: Longhorn 组件可以正常通信
- ✅ **Service 网络正常**: longhorn-backend Service 正常工作

### 网络问题排查

如果 Longhorn 遇到网络问题，通常不是 CNI 的问题，而是：

1. **Service 未就绪**: longhorn-backend Service 没有 Endpoints
2. **DNS 解析问题**: Pod 无法解析 Service 名称
3. **防火墙规则**: 节点防火墙阻止了 Pod 间通信

## 检查网络连接

### 测试 Pod 网络

```bash
# 创建一个测试 Pod
kubectl run test-pod --image=busybox --rm -it -- sh

# 在 Pod 内测试
# ping <另一个 Pod IP>
# nslookup <Service 名称>
```

### 测试 Service 网络

```bash
# 测试 longhorn-backend Service
kubectl run test-pod --image=busybox --rm -it -- sh
# 在 Pod 内:
# wget -qO- http://longhorn-backend:9500/v1
```

## 常见问题

### Q: k3s 默认使用什么网络？

**A**: k3s 默认使用内置的 Flannel CNI，无需额外安装。

### Q: 为什么 `kubectl get pods -n kube-system | grep flannel` 没有输出？

**A**: 这是正常的。k3s 内置的 Flannel 不会显示为标准的 DaemonSet，但网络功能是正常的。

### Q: 需要安装 Flannel 吗？

**A**: 不需要。k3s 已经内置了 Flannel，开箱即用。

### Q: 可以替换为其他 CNI 吗？

**A**: 可以，但不推荐。k3s 内置 Flannel 已经足够，替换可能引入兼容性问题。

### Q: k3s 网络对 Longhorn 有影响吗？

**A**: 没有负面影响。k3s 内置 Flannel 与 Longhorn 完全兼容。

## 总结

| 项目 | k3s 默认 |
|------|----------|
| **CNI** | Flannel (内置) |
| **模式** | VXLAN |
| **Pod CIDR** | 10.42.0.0/16 |
| **Service CIDR** | 10.43.0.0/16 |
| **需要安装** | 否 |
| **Longhorn 兼容** | ✅ 完全兼容 |

**关键点**:
- ✅ k3s 默认使用内置 Flannel
- ✅ 无需额外安装 CNI
- ✅ 与 Longhorn 完全兼容
- ✅ 网络问题通常不是 CNI 问题

## 参考

- 检查脚本: `./scripts/check-k3s-cni.sh`
- k3s 网络文档: https://docs.k3s.io/networking/networking
- Flannel 文档: https://github.com/flannel-io/flannel


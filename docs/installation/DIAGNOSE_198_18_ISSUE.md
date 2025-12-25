# 198.18.x.x 地址问题诊断指南

## 问题现象

- DNS 解析 `kubernetes.default.svc.cluster.local` 得到 `198.18.0.47`
- 但实际 Service ClusterIP 是 `10.43.0.1`
- 连接测试失败：`wget: got bad TLS record`

## 诊断步骤

### 1. 检查当前 k3s 实际运行参数

```bash
# 查看 k3s 进程的启动参数
sudo ps aux | grep "k3s server" | grep -v grep

# 重点关注：
# - cluster-cidr
# - service-cidr
# - 是否有 --disable servicelb
# - 是否有其他网络相关参数
```

### 2. 检查 ServiceLB 状态

```bash
# 检查 ServiceLB Pod
kubectl get pods -n kube-system -l app=svclb

# 检查 ServiceLB 配置
kubectl get daemonset -n kube-system svclb-traefik -o yaml 2>/dev/null || \
kubectl get daemonset -n kube-system -l app=svclb -o yaml
```

### 3. 检查 CoreDNS 配置

```bash
# 查看 CoreDNS 配置
kubectl get configmap coredns -n kube-system -o yaml

# 检查是否有 hosts 插件或其他特殊配置
kubectl get configmap coredns -n kube-system -o yaml | grep -A 50 "Corefile:"
```

### 4. 检查实际网络路由

```bash
# 检查节点路由表
ip route | grep 198.18

# 检查网络接口
ip addr show | grep 198.18

# 检查 iptables 规则（如果有）
sudo iptables -t nat -L | grep 198.18
```

### 5. 检查 Service 和 Endpoints

```bash
# 检查 kubernetes Service
kubectl get svc kubernetes -n default -o yaml

# 检查 Endpoints
kubectl get endpoints kubernetes -n default -o yaml

# 检查所有 Service 的 IP 分配
kubectl get svc -A -o wide | grep 198.18
```

## 可能的原因分析

### 原因 1: k3s ServiceLB 默认行为

**假设**：k3s 的 ServiceLB 可能在某些情况下会使用 198.18.0.0/15 作为虚拟 IP 范围。

**验证**：
```bash
# 检查是否有 LoadBalancer 类型的 Service
kubectl get svc -A | grep LoadBalancer

# 检查 ServiceLB 是否在运行
kubectl get pods -n kube-system -l app=svclb
```

### 原因 2: CoreDNS hosts 插件配置

**假设**：CoreDNS 可能配置了 hosts 插件，将某些域名映射到 198.18.x.x。

**验证**：
```bash
kubectl get configmap coredns -n kube-system -o yaml | grep -A 20 "hosts"
```

### 原因 3: 网络代理或 NAT 配置

**假设**：节点上可能有网络代理或 NAT 规则导致地址转换。

**验证**：
```bash
# 检查代理设置
env | grep -i proxy

# 检查 iptables NAT 规则
sudo iptables -t nat -L -n -v | head -30
```

### 原因 4: k3s 版本或配置问题

**假设**：特定版本的 k3s 可能有网络配置问题。

**验证**：
```bash
# 检查 k3s 版本
k3s --version

# 检查 k3s 配置文件
sudo cat /etc/rancher/k3s/k3s.yaml | grep -E "cluster-cidr|service-cidr"
```

## 安装方法检查

### 当前安装脚本分析

查看 `install-k3s-only.sh` 第 43 行：

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_EXEC="server --tls-san ${SERVER_IP}" sh -
```

**分析**：
- ✅ 使用官方安装脚本：正确
- ✅ 指定版本：正确
- ✅ 添加 `--tls-san`：正确（用于远程访问）
- ⚠️ 没有指定 `--cluster-cidr` 和 `--service-cidr`：使用默认值（10.42.0.0/16 和 10.43.0.0/16）
- ⚠️ 没有 `--disable servicelb`：ServiceLB 默认启用

### k3s 官方默认配置

根据 k3s 官方文档：
- `--cluster-cidr`: 默认 `10.42.0.0/16`（Pod 网络）
- `--service-cidr`: 默认 `10.43.0.0/16`（Service 网络）
- ServiceLB: 默认启用（用于 LoadBalancer 类型的 Service）

### 198.18.0.0/15 地址范围

- 这是 IANA 保留的测试地址范围（TEST-NET-1 和 TEST-NET-2）
- 不应该出现在正常的 Kubernetes Service DNS 解析中
- 如果出现，可能是：
  1. ServiceLB 的虚拟 IP 分配
  2. 网络配置错误
  3. CoreDNS 配置问题

## 诊断命令汇总

运行以下命令收集完整信息：

```bash
echo "=== 1. k3s 进程参数 ==="
sudo ps aux | grep "k3s server" | grep -v grep

echo ""
echo "=== 2. ServiceLB 状态 ==="
kubectl get pods -n kube-system -l app=svclb

echo ""
echo "=== 3. CoreDNS 配置 ==="
kubectl get configmap coredns -n kube-system -o yaml | grep -A 50 "Corefile:"

echo ""
echo "=== 4. kubernetes Service ==="
kubectl get svc kubernetes -n default -o yaml

echo ""
echo "=== 5. DNS 解析测试 ==="
kubectl run -it --rm test-dns-$(date +%s) --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local

echo ""
echo "=== 6. 网络路由 ==="
ip route | grep -E "198.18|10.42|10.43"

echo ""
echo "=== 7. k3s 版本 ==="
k3s --version
```

## 下一步

1. **先运行诊断命令**，收集完整信息
2. **分析结果**，确定 198.18.x.x 的真正来源
3. **根据诊断结果**，决定是否需要修改安装脚本
4. **如果需要修改**，确保所有节点使用相同的配置值

## 注意事项

根据 k3s 官方文档，以下配置必须在所有节点上保持一致：
- `--cluster-cidr`
- `--service-cidr`
- `--disable servicelb`（如果禁用）

如果当前是单节点集群，这些配置暂时不是问题。但如果将来要扩展为多节点，必须确保所有节点使用相同的网络配置。


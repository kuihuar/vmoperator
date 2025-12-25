# 198.18.x.x 问题诊断结果分析

## 诊断结果

### 1. ServiceLB 状态
```
No resources found in kube-system namespace.
```
**分析**：
- ServiceLB Pod 未找到（可能标签不对，或 ServiceLB 未运行）
- 但存在 LoadBalancer 类型的 Service（traefik），说明 ServiceLB 功能可能在工作

### 2. CoreDNS 配置
```yaml
Corefile: |
  .:53 {
      errors
      health
      ready
      kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
      }
      hosts /etc/coredns/NodeHosts {
        ttl 60
        reload 15s
        fallthrough
      }
      prometheus :9153
      forward . /etc/resolv.conf
      cache 30
      loop
      reload
      loadbalance
      import /etc/coredns/custom/*.override
  }
  import /etc/coredns/custom/*.server
NodeHosts: |
  192.168.1.141 host1
```

**分析**：
- ✅ CoreDNS 配置正常，没有 hosts 插件映射 198.18.x.x
- ✅ NodeHosts 只包含节点 IP 映射（192.168.1.141 host1）
- ⚠️ 有 `import /etc/coredns/custom/*.server`，可能有自定义配置

### 3. LoadBalancer Service
```
kube-system   traefik   LoadBalancer   10.43.65.56   192.168.1.141   80:30521/TCP,443:30274/TCP
```

**分析**：
- ✅ traefik 的 External IP 是 192.168.1.141（节点 IP），这是正常的
- ✅ ClusterIP 是 10.43.65.56（在 service-cidr 范围内），正常
- 说明 ServiceLB 功能在工作，但 Pod 可能用了不同的标签

## 进一步诊断建议

### 1. 检查所有 ServiceLB 相关的 Pod

```bash
# 检查所有可能的 ServiceLB 标签
kubectl get pods -n kube-system | grep -i svc
kubectl get pods -n kube-system | grep -i lb
kubectl get pods -n kube-system | grep -i traefik

# 检查 DaemonSet
kubectl get daemonset -n kube-system | grep -i svc
```

### 2. 检查 k3s 实际运行的参数

```bash
# 这个很重要，看实际使用了什么参数
sudo ps aux | grep "k3s server" | grep -v grep
```

### 3. 检查 CoreDNS 的自定义配置

```bash
# 检查是否有自定义配置文件
kubectl exec -n kube-system <coredns-pod> -- ls -la /etc/coredns/custom/ 2>/dev/null || echo "无法检查"
```

### 4. 检查实际 DNS 解析过程

```bash
# 在 Pod 内详细测试 DNS 解析
kubectl run -it --rm test-dns-debug --image=busybox --restart=Never -- sh -c "
  echo '=== 测试 DNS 解析 ==='
  nslookup kubernetes.default.svc.cluster.local
  echo ''
  echo '=== 检查 /etc/resolv.conf ==='
  cat /etc/resolv.conf
  echo ''
  echo '=== 测试直接访问 Service IP ==='
  wget -O- --timeout=3 https://10.43.0.1:443 2>&1 | head -5
"
```

### 5. 检查网络路由和接口

```bash
# 检查是否有 198.18 相关的路由
ip route | grep 198.18

# 检查网络接口
ip addr show | grep 198.18

# 检查 iptables NAT 规则
sudo iptables -t nat -L -n -v | grep 198.18
```

## 可能的原因分析

### 假设 1: ServiceLB 使用了不同的实现方式

虽然没找到 `app=svclb` 的 Pod，但 traefik LoadBalancer 工作正常，说明：
- ServiceLB 可能以其他方式实现（如 k3s 内置）
- 或者使用了不同的标签

### 假设 2: CoreDNS 的自定义配置

`import /etc/coredns/custom/*.server` 可能导入了自定义配置，需要检查。

### 假设 3: 网络代理或 NAT

节点上可能有网络代理或 NAT 规则导致地址转换。

### 假设 4: k3s 版本特定的行为

特定版本的 k3s 可能有特殊的网络处理逻辑。

## 关键问题

**为什么 DNS 解析到 198.18.0.47，而不是 Service ClusterIP 10.43.0.1？**

这需要进一步检查：
1. k3s 实际运行的参数
2. CoreDNS 的自定义配置
3. 网络路由和 NAT 规则

## 下一步行动

请运行以下命令，收集更多信息：

```bash
# 1. k3s 进程参数（最重要）
sudo ps aux | grep "k3s server" | grep -v grep

# 2. 所有 kube-system 的 Pod
kubectl get pods -n kube-system

# 3. 检查 CoreDNS Pod 内的自定义配置
COREDNS_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name | head -1)
kubectl exec -n kube-system ${COREDNS_POD} -- ls -la /etc/coredns/custom/ 2>/dev/null || echo "目录不存在或无法访问"

# 4. 详细 DNS 解析测试
kubectl run -it --rm test-dns-$(date +%s) --image=busybox --restart=Never -- sh -c "
  cat /etc/resolv.conf
  echo ''
  nslookup kubernetes.default.svc.cluster.local
  echo ''
  nslookup kubernetes.default.svc
  echo ''
  nslookup kubernetes
"
```


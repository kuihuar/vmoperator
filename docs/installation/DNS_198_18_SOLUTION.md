# DNS 解析到 198.18.x.x 问题解决方案

## 问题现象

```bash
$ kubectl exec -it dns-test -- nslookup kube-dns.kube-system.svc
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	kube-dns.kube-system.svc
Address: 198.18.0.44  # ❌ 错误：应该是 10.43.x.x 范围内的 IP
```

## 问题分析

### 1. 明确指定 `--service-cidr` 的作用

✅ **有帮助，但不是根本解决方案**

- `--service-cidr 10.43.0.0/16` 确保 Service 的 ClusterIP 从正确范围分配
- 但 **不能阻止 ServiceLB 影响 DNS 解析**

### 2. 根本原因：ServiceLB

**ServiceLB 使用 `198.18.0.0/15` 作为虚拟 IP 范围**

- ServiceLB 是 k3s 的 LoadBalancer 实现
- 它会为 LoadBalancer 类型的 Service 分配 198.18.x.x 的 IP
- **在某些情况下，ServiceLB 可能影响 DNS 解析**，导致解析到 198.18.x.x

### 3. 为什么明确指定 service-cidr 不够？

```
Service CIDR: 10.43.0.0/16  ← 我们指定的
ServiceLB IP:  198.18.0.0/15 ← ServiceLB 使用的（独立范围）
```

- Service CIDR 只控制 ClusterIP 的分配
- ServiceLB 使用自己的 IP 范围（198.18.0.0/15）
- 两者是独立的，但 ServiceLB 可能影响 DNS 解析逻辑

## 解决方案

### 方案 1：禁用 ServiceLB（推荐，如果不需要 LoadBalancer）

**这是最彻底的解决方案**

```bash
# 重新安装 k3s，禁用 ServiceLB
DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh
```

**优点**：
- ✅ 彻底解决 198.18.x.x 问题
- ✅ DNS 解析正常
- ✅ 减少资源占用

**缺点**：
- ❌ 无法使用 LoadBalancer 类型的 Service
- ⚠️ 需要重新安装（会清理现有集群）

### 方案 2：保持 ServiceLB，但明确指定 service-cidr

**可能部分缓解，但不保证完全解决**

```bash
# 明确指定 service-cidr（当前脚本已支持）
./docs/installation/install-k3s-only.sh
# 或
SERVICE_CIDR=10.43.0.0/16 ./docs/installation/install-k3s-only.sh
```

**优点**：
- ✅ 保持 LoadBalancer 功能
- ✅ 明确配置，便于管理

**缺点**：
- ⚠️ 可能仍然出现 198.18.x.x 解析问题
- ⚠️ 不是根本解决方案

## 当前脚本配置分析

### 当前配置

```bash
# 明确指定网络配置
--cluster-cidr 10.42.0.0/16
--service-cidr 10.43.0.0/16

# ServiceLB 控制（可选）
DISABLE_SERVICELB=true  # 如果设置，会添加 --disable servicelb
```

### 配置效果

1. **明确指定 service-cidr**：
   - ✅ Service ClusterIP 从 10.43.0.0/16 分配
   - ✅ 配置清晰，便于管理
   - ⚠️ 但可能不足以解决 198.18.x.x 问题

2. **禁用 ServiceLB**：
   - ✅ 彻底解决 198.18.x.x 问题
   - ✅ DNS 解析正常
   - ❌ 但失去 LoadBalancer 功能

## 推荐方案

### 如果不需要 LoadBalancer

**使用方案 1：禁用 ServiceLB**

```bash
# 1. 卸载现有 k3s
./docs/installation/uninstall-k3s.sh

# 2. 重新安装，禁用 ServiceLB
DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh
```

### 如果需要 LoadBalancer

**使用方案 2：明确指定 service-cidr + 诊断**

```bash
# 1. 重新安装，明确指定 service-cidr
./docs/installation/install-k3s-only.sh

# 2. 测试 DNS 解析
kubectl run -it --rm test-dns --image=busybox --restart=Never -- \
  nslookup kube-dns.kube-system.svc

# 3. 如果仍然解析到 198.18.x.x，考虑：
#    - 检查 ServiceLB Pods
#    - 检查 CoreDNS 配置
#    - 或者最终选择禁用 ServiceLB
```

## 验证步骤

### 安装后验证

```bash
# 1. 检查 Service ClusterIP 是否在正确范围
kubectl get svc -A | grep -E "10.43\." | head -5

# 2. 测试 DNS 解析
kubectl run -it --rm test-dns --image=busybox --restart=Never -- \
  nslookup kube-dns.kube-system.svc

# 3. 检查是否还有 198.18.x.x
kubectl get svc -A | grep "198.18"

# 4. 如果禁用 ServiceLB，检查是否还有 ServiceLB Pods
kubectl get pods -n kube-system | grep svclb
```

## 总结

### 关于明确指定 service-cidr

✅ **有帮助，但不是根本解决方案**
- 明确指定 `--service-cidr` 是好的实践
- 确保 Service ClusterIP 从正确范围分配
- 但可能不足以解决 ServiceLB 导致的 DNS 解析问题

### 根本解决方案

✅ **禁用 ServiceLB**（如果不需要 LoadBalancer）
- 这是最彻底的解决方案
- 可以完全避免 198.18.x.x 问题
- 当前脚本已支持：`DISABLE_SERVICELB=true`

### 当前脚本的优势

1. ✅ 明确指定 `--service-cidr` 和 `--cluster-cidr`
2. ✅ 支持通过 `DISABLE_SERVICELB=true` 禁用 ServiceLB
3. ✅ 配置清晰，便于管理和诊断

## 建议

**基于你之前遇到的问题，建议使用：**

```bash
# 禁用 ServiceLB 重新安装
DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh
```

这样可以：
- ✅ 彻底解决 198.18.x.x DNS 解析问题
- ✅ 确保 DNS 解析到正确的 Service ClusterIP（10.43.x.x）
- ✅ 避免 Longhorn webhook 连接失败的问题


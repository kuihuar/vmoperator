# k3s 上下文规则和重要知识点

本文档记录 k3s 相关的关键知识点和规则，避免常见错误。

## 重要规则

### 1. ServiceLB 不是 Pod

**❌ 错误理解**：ServiceLB 是独立的 Pod 运行在 kube-system 命名空间

**✅ 正确理解**：
- ServiceLB 是 k3s 的**内置组件**，集成在 k3s server 进程中
- **不是以 Pod 形式运行**
- 通过 k3s 启动参数 `--disable servicelb` 控制启用/禁用

**检查方法**：
```bash
# 正确：检查 k3s 启动参数
sudo systemctl cat k3s | grep "ExecStart" | grep -E "disable.*servicelb|--disable servicelb"

# 错误：不要检查 Pod（k3s ServiceLB 不是 Pod）
kubectl get pods -n kube-system -l app=svclb  # ❌ 这个不会找到 ServiceLB
```

### 2. ServiceLB 使用 198.18.0.0/15 网段

**重要**：
- ServiceLB 使用 `198.18.0.0/15` 作为虚拟 IP 范围
- 这个网段是 IANA 保留的测试地址范围
- **不应该用于正常的 Service ClusterIP**
- Service ClusterIP 应该从 `--service-cidr` 指定的范围分配（默认 `10.43.0.0/16`）

**问题现象**：
- DNS 解析到 `198.18.x.x` 而不是 `10.43.x.x`
- 连接 `198.18.x.x` 失败（`Connection reset by peer`）

### 3. Service CIDR 和 Pod CIDR 必须不同

**规则**：
- `--cluster-cidr`（Pod 网络）和 `--service-cidr`（Service 网络）**必须不同网段**
- 这是 Kubernetes 的硬性要求
- 它们可以正常通信，通过 kube-proxy 转发

**示例**：
```bash
--cluster-cidr 10.42.0.0/16    # Pod IP: 10.42.x.x
--service-cidr 10.43.0.0/16    # Service IP: 10.43.x.x
```

### 4. k3s 默认网络配置

**默认值**：
- `--cluster-cidr`: `10.42.0.0/16`（Pod 网络）
- `--service-cidr`: `10.43.0.0/16`（Service 网络）
- ServiceLB: **默认启用**

**明确指定的好处**：
- 配置清晰，便于管理
- 多节点集群时确保一致性
- 避免默认值变更的影响

### 5. 检查 k3s 实际配置的方法

**正确方法**：
```bash
# 方法 1：检查 systemd 服务配置（推荐）
sudo systemctl cat k3s | grep "ExecStart"

# 方法 2：检查 k3s 进程命令行
sudo ps aux | grep "k3s server" | grep -v grep

# 方法 3：检查配置文件（如果存在）
sudo cat /etc/rancher/k3s/config.yaml
```

**注意**：
- k3s 可能没有独立的配置文件
- 启动参数在 systemd service 文件中

### 6. DNS 解析到 198.18.x.x 的原因

**可能原因**：
1. ServiceLB 影响 DNS 解析逻辑
2. k3s 版本的 bug 或特殊行为
3. CoreDNS 配置问题（较少见）

**解决方案**：
- 禁用 ServiceLB：`--disable servicelb`
- 如果不需要 LoadBalancer 功能，建议禁用

### 7. LoadBalancer 类型 Service

**注意**：
- 如果禁用了 ServiceLB，LoadBalancer 类型的 Service 将**无法工作**
- 禁用 ServiceLB 后，LoadBalancer 类型的 Service 会一直处于 `pending` 状态

**判断是否需要 ServiceLB**：
- 如果不需要 LoadBalancer 功能，可以安全禁用
- 单节点集群通常不需要 LoadBalancer

## 常见错误

### ❌ 错误 1：通过 Pod 检查 ServiceLB

```bash
# 错误
kubectl get pods -n kube-system -l app=svclb

# 正确
sudo systemctl cat k3s | grep "disable.*servicelb"
```

### ❌ 错误 2：认为明确指定 service-cidr 就能解决 198.18.x.x 问题

```bash
# 明确指定 service-cidr 有帮助，但不是根本解决方案
--service-cidr 10.43.0.0/16  # ✅ 好的实践，但可能不足以解决问题

# 根本解决方案是禁用 ServiceLB
--disable servicelb  # ✅ 彻底解决问题
```

### ❌ 错误 3：认为 Service CIDR 和 Pod CIDR 必须相同网段

```bash
# 错误：相同网段会导致冲突
--cluster-cidr 10.42.0.0/16
--service-cidr 10.42.0.0/16  # ❌ 错误！

# 正确：必须不同网段
--cluster-cidr 10.42.0.0/16
--service-cidr 10.43.0.0/16  # ✅ 正确
```

## 检测脚本注意事项

在编写检测脚本时，注意：

1. **不要通过 Pod 检查 ServiceLB**
   ```bash
   # ❌ 错误
   kubectl get pods -n kube-system -l app=svclb
   
   # ✅ 正确
   sudo systemctl cat k3s | grep "disable.*servicelb"
   ```

2. **检查 k3s 启动参数**
   ```bash
   sudo systemctl cat k3s | grep "ExecStart"
   ```

3. **检查 Service ClusterIP 范围**
   ```bash
   kubectl get svc -A -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\n"}{end}' | grep "^198.18"
   ```

4. **DNS 解析测试**
   ```bash
   kubectl run -it --rm test-dns --image=busybox --restart=Never -- \
     nslookup kubernetes.default.svc.cluster.local
   ```

## 相关文档

- [k3s 网络配置](https://docs.k3s.io/networking)
- [k3s ServiceLB 文档](https://docs.k3s.io/networking/service-lb)
- [DNS 198.18 问题解决方案](./DNS_198_18_SOLUTION.md)
- [k3s 网络配置说明](./K3S_NETWORK_EXPLANATION.md)

## 快速参考

### 安装 k3s（禁用 ServiceLB）

```bash
DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh
```

### 检查 ServiceLB 状态

```bash
sudo systemctl cat k3s | grep "ExecStart" | grep -E "disable.*servicelb|--disable servicelb"
```

### 检查 DNS 解析

```bash
kubectl run -it --rm test-dns --image=busybox --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
```

### 检查 Service ClusterIP

```bash
kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.clusterIP}{"\n"}{end}' | grep "198.18"
```


# k3s 网络配置说明：Service CIDR 和 Pod CIDR

## 核心问题

**问：Service CIDR 和 Pod CIDR 不在一个网段，可以通信吗？**

**答：✅ 可以，而且必须不同网段！这是 Kubernetes 网络设计的基本原则。**

## 两个网段的区别和作用

### 1. Pod CIDR (`--cluster-cidr`)

- **作用**：Pod 实际分配的 IP 地址范围
- **示例**：`10.42.0.0/16`
- **特点**：
  - Pod 会从这个网段获取真实的 IP 地址
  - 例如：Pod IP 可能是 `10.42.0.5`、`10.42.0.6` 等
  - 这些 IP 是 Pod 容器的实际网络接口 IP

### 2. Service CIDR (`--service-cidr`)

- **作用**：Service 的 ClusterIP 地址范围
- **示例**：`10.43.0.0/16`
- **特点**：
  - Service 的 ClusterIP 从这个网段分配
  - 例如：Service IP 可能是 `10.43.0.1`（kubernetes Service）、`10.43.0.100` 等
  - **这些 IP 是虚拟 IP，不存在于任何网络接口上**

## 为什么必须不同网段？

### 1. 避免 IP 冲突

如果 Service CIDR 和 Pod CIDR 相同，会导致：
- Service 的 ClusterIP 可能与 Pod IP 冲突
- 无法区分是访问 Service 还是直接访问 Pod

### 2. 网络路由清晰

- **Pod IP**：真实存在，可以直接路由
- **Service IP**：虚拟 IP，需要通过 kube-proxy 转发

### 3. Kubernetes 设计原则

Kubernetes 要求这两个网段必须不同，这是硬性要求。

## 它们如何通信？

### 通信流程

```
Pod (10.42.0.5) 
    ↓ 访问 Service
Service ClusterIP (10.43.0.100)
    ↓ kube-proxy 转发（通过 iptables/ipvs）
实际 Pod (10.42.0.8)
```

### 实现机制

1. **kube-proxy**：
   - 监听 Service 和 Endpoint 变化
   - 在节点上配置 iptables 或 ipvs 规则
   - 将 Service IP 的流量转发到实际 Pod IP

2. **iptables/ipvs 规则**：
   ```
   # 当访问 10.43.0.100:80 时
   # iptables 规则会将流量转发到 10.42.0.8:8080
   ```

3. **DNS 解析**：
   - CoreDNS 将 Service 名称解析为 ClusterIP
   - Pod 通过 Service 名称访问，自动解析到 ClusterIP
   - kube-proxy 再将 ClusterIP 转发到实际 Pod

## 当前配置分析

### 我们的配置

```bash
--cluster-cidr 10.42.0.0/16    # Pod 网络
--service-cidr 10.43.0.0/16    # Service 网络
```

### 配置正确性

✅ **完全正确**：
- 两个网段不同：`10.42.x.x` vs `10.43.x.x`
- 网段不重叠：`10.42.0.0/16` 和 `10.43.0.0/16` 是独立的
- 符合 Kubernetes 要求

### 实际示例

```bash
# Pod IP（从 10.42.0.0/16 分配）
$ kubectl get pod -o wide
NAME           IP           NODE
my-pod         10.42.0.5    host1

# Service ClusterIP（从 10.43.0.0/16 分配）
$ kubectl get svc
NAME           CLUSTER-IP    PORT(S)
my-service     10.43.0.100   80/TCP

# Pod 访问 Service（可以正常通信）
# Pod 10.42.0.5 访问 10.43.0.100:80
# → kube-proxy 转发到实际 Pod 10.42.0.8:8080
```

## 常见问题

### Q1: 如果设置相同的网段会怎样？

**A**: k3s 会拒绝启动，报错类似：
```
Error: cluster-cidr and service-cidr must not overlap
```

### Q2: 可以设置其他网段吗？

**A**: 可以，只要满足：
- 两个网段不重叠
- 不与节点网络冲突
- 不与现有网络冲突

示例：
```bash
--cluster-cidr 172.16.0.0/16
--service-cidr 172.17.0.0/16
```

### Q3: Pod 如何访问 Service？

**A**: 通过以下方式都可以：

1. **Service 名称**（推荐）：
   ```bash
   curl http://my-service.default.svc.cluster.local
   ```

2. **ClusterIP**：
   ```bash
   curl http://10.43.0.100
   ```

3. **环境变量**（已废弃，不推荐）

### Q4: 不同网段如何路由？

**A**: 通过 kube-proxy 和 iptables/ipvs：
- Service IP 是虚拟 IP，不存在于网络接口
- kube-proxy 在节点上配置转发规则
- 流量在节点内核层面转发，不经过实际网络

## 验证配置

### 检查当前配置

```bash
# 查看 k3s 实际配置
sudo systemctl cat k3s | grep ExecStart

# 查看 Pod IP 范围
kubectl get pods -o wide | grep -oP '\d+\.\d+\.\d+\.\d+' | head -5

# 查看 Service IP 范围
kubectl get svc -A | grep -oP '\d+\.\d+\.\d+\.\d+' | head -5
```

### 测试通信

```bash
# 创建一个测试 Pod
kubectl run test-pod --image=busybox --rm -it -- sh

# 在 Pod 内测试访问 Service
# 例如访问 kubernetes Service
wget -O- https://kubernetes.default.svc.cluster.local:443
```

## 总结

1. ✅ **Service CIDR 和 Pod CIDR 必须不同网段**
2. ✅ **它们可以正常通信**，通过 kube-proxy 转发
3. ✅ **当前配置（10.42.0.0/16 和 10.43.0.0/16）完全正确**
4. ✅ **这是 Kubernetes 的标准设计，不是问题**

## 相关文档

- [k3s 网络配置](https://docs.k3s.io/networking)
- [Kubernetes Service 概念](https://kubernetes.io/docs/concepts/services-networking/service/)
- [kube-proxy 工作原理](https://kubernetes.io/docs/concepts/services-networking/service/#virtual-ips-and-service-proxies)


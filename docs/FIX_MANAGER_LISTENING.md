# 修复 Manager 监听问题

## 问题描述

Manager 日志显示：
```
Listening on 10.42.0.194:9500
```

但 `netstat` 检查显示未监听 `localhost:9500`，这可能导致 API 无法访问。

## 问题分析

### Manager 监听地址

Manager 正在监听 **Pod IP** (`10.42.0.194:9500`)，而不是 `0.0.0.0:9500` 或 `localhost:9500`。

这是**正常行为**，因为：
- Manager 监听 Pod IP 是正确的
- Service 会通过 Endpoints 路由到 Pod IP
- 问题可能在于 Service 到 Pod 的网络连接

### 可能的原因

1. **k3s CNI 网络问题**: Service 到 Pod 的网络连接可能有问题
2. **Endpoints 不匹配**: Service 的 Endpoints 可能未正确指向 Pod
3. **网络策略**: 可能有网络策略阻止连接
4. **临时网络问题**: k3s 网络可能暂时有问题

## 诊断步骤

### 1. 运行诊断脚本

```bash
./scripts/diagnose-manager-listening.sh
```

### 2. 检查 Service 和 Endpoints

```bash
# 检查 Service
kubectl get svc -n longhorn-system longhorn-backend -o yaml

# 检查 Endpoints
kubectl get endpoints -n longhorn-system longhorn-backend -o yaml

# 验证 Endpoints 指向正确的 Pod IP
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
POD_IP=$(kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{.status.podIP}')
echo "Pod IP: $POD_IP"

ENDPOINTS_IP=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[*].addresses[*].ip}')
echo "Endpoints IP: $ENDPOINTS_IP"
```

### 3. 测试网络连接

```bash
# 从 manager Pod 内部测试 Service
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- curl -v http://longhorn-backend:9500/v1

# 从 driver-deployer Init Container 测试
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager -- curl -v http://longhorn-backend:9500/v1
```

## 解决方案

### 方案 1: 重启相关组件（推荐）

```bash
# 1. 重启 manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 2. 等待 manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# 3. 重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer

# 4. 等待 driver-deployer 就绪
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -w
```

### 方案 2: 检查 k3s CNI

```bash
# 检查 k3s CNI 配置
ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/

# 检查 CNI Pods
kubectl get pods -n kube-system | grep -E "flannel|calico|cilium"

# 如果 CNI 有问题，可能需要重启 k3s
sudo systemctl restart k3s
```

### 方案 3: 等待网络恢复

有时 k3s 网络需要一些时间稳定：

```bash
# 等待 5-10 分钟，然后重试
sleep 300

# 检查 Service 连接
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://longhorn-backend:9500/v1 | head -5
```

### 方案 4: 忽略（如果 StorageClass 已存在）

如果 `longhorn` StorageClass 已创建，可以忽略 `driver-deployer` 的状态：

```bash
# 验证 StorageClass
kubectl get storageclass longhorn

# 如果存在，可以直接使用
# 在 Wukong 中使用: storageClassName: longhorn
```

## 关于 k3s 网络

### k3s 默认 CNI

k3s 使用 **Flannel** 作为默认 CNI，提供 Pod 网络。

### 常见问题

1. **Service DNS 解析失败**: CoreDNS 可能未就绪
2. **Service 到 Pod 连接失败**: Flannel 网络可能有问题
3. **Endpoints 未更新**: kube-proxy 可能未同步

### 检查 k3s 网络

```bash
# 检查 CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 检查 kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# 检查 Flannel（如果使用）
kubectl get pods -n kube-system -l app=flannel
```

## 临时解决方案

如果网络问题持续，可以：

### 选项 1: 直接使用 Pod IP（不推荐，仅用于测试）

```bash
# 获取 manager Pod IP
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
POD_IP=$(kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{.status.podIP}')

# 测试从 Pod IP 访问
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://$POD_IP:9500/v1 | head -5
```

### 选项 2: 使用 StorageClass（推荐）

即使 API 不可访问，如果 StorageClass 已存在，可以正常使用：

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn  # 可以使用
    boot: true
```

## 验证修复

修复后，验证：

```bash
# 1. 检查 Service 连接
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://longhorn-backend:9500/v1 | head -5

# 2. 检查 driver-deployer
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer

# 3. 测试创建 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

## 总结

| 问题 | 状态 | 影响 |
|------|------|------|
| Manager 监听 Pod IP | ✅ 正常 | 这是正确的行为 |
| Service 连接 | ⚠️ 可能有问题 | driver-deployer 会等待 |
| StorageClass | ✅ 已创建 | 可以正常使用 |

**关键点**:
- ✅ Manager 监听 Pod IP 是正常行为
- ⚠️ 问题可能在于 Service 到 Pod 的网络连接
- ✅ 如果 StorageClass 已存在，可以忽略 driver-deployer 状态
- ⚠️ 可能是 k3s CNI 的临时问题

**建议**: 
1. 先检查 StorageClass 是否存在
2. 如果存在，直接使用（忽略 driver-deployer）
3. 如果不存在，重启相关组件或检查 k3s 网络


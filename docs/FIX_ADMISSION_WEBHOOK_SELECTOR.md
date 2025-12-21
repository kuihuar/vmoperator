# 修复 Longhorn admission-webhook Service 选择器问题

## 问题描述

- ✅ `longhorn-admission-webhook` Service 存在
- ✅ Service 选择器：`longhorn.io/admission-webhook: longhorn-admission-webhook`
- ❌ Endpoints 为空（没有 Pod 匹配该选择器）
- ✅ Manager Pod 监听 9502 端口
- ❌ Manager Pod 没有 `longhorn.io/admission-webhook` 标签

## 问题分析

根据检查结果：

1. **Service 选择器**：`longhorn.io/admission-webhook: longhorn-admission-webhook`
2. **Manager Pod**：监听 9502 端口，说明 webhook 功能在 Manager 中
3. **标签不匹配**：Manager Pod 没有 `longhorn.io/admission-webhook` 标签，所以 Service 无法选择它

## 解决方案

### 方案 1: 给 Manager Pod 添加标签（临时方案）

如果确认 webhook 功能在 Manager 中，可以给 Manager Pod 添加标签：

```bash
# 注意：直接给 Pod 添加标签是临时性的，Pod 重建后会丢失
# 需要修改 Deployment/DaemonSet 的标签选择器

# 检查 Manager 是 Deployment 还是 DaemonSet
kubectl get deployment,daemonset -n longhorn-system -l app=longhorn-manager

# 如果是 Deployment
kubectl patch deployment -n longhorn-system longhorn-manager -p '{"spec":{"template":{"metadata":{"labels":{"longhorn.io/admission-webhook":"longhorn-admission-webhook"}}}}}'

# 如果是 DaemonSet
kubectl patch daemonset -n longhorn-system longhorn-manager -p '{"spec":{"template":{"metadata":{"labels":{"longhorn.io/admission-webhook":"longhorn-admission-webhook"}}}}}'
```

**注意**：这需要确认 Manager 确实应该提供 webhook 服务。

### 方案 2: 修改 Service 选择器（不推荐）

如果 webhook 确实在 Manager 中，可以修改 Service 选择器指向 Manager：

```bash
# 查看 Manager Pod 的标签
kubectl get pod -n longhorn-system -l app=longhorn-manager --show-labels

# 修改 Service 选择器（假设 Manager 有 app=longhorn-manager 标签）
kubectl patch svc -n longhorn-system longhorn-admission-webhook -p '{"spec":{"selector":{"app":"longhorn-manager"}}}'
```

**注意**：这可能会在 Longhorn 升级时被覆盖。

### 方案 3: 检查是否有独立的 Deployment 应该存在

如果应该有独立的 Deployment/DaemonSet 但没有创建：

```bash
# 检查 Helm Chart 是否应该创建独立的 Deployment
./scripts/check-webhook-selector-and-fix.sh 1.10.1

# 检查 Helm 发布的实际资源
helm get manifest longhorn -n longhorn-system | grep -B 10 -A 50 "longhorn.io/admission-webhook"
```

如果应该有但未创建，需要重新安装或修复安装。

### 方案 4: 重新安装 Longhorn（推荐）

如果安装不完整，最安全的方式是重新安装：

```bash
# 卸载
helm uninstall longhorn -n longhorn-system
kubectl delete namespace longhorn-system

# 等待清理
sleep 60

# 重新安装
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.10.1 \
  --values config/longhorn-values.yaml

# 等待并验证
kubectl wait --for=condition=ready pod -l app=longhorn-admission-webhook -n longhorn-system --timeout=300s 2>/dev/null || echo "可能没有独立的 Pod"
kubectl get endpoints -n longhorn-system longhorn-admission-webhook
```

## 推荐步骤

### 步骤 1: 检查 Helm Chart 实际定义

```bash
# 检查 Chart 中是否定义了独立的 Deployment
helm template longhorn longhorn/longhorn \
  --version 1.10.1 \
  --namespace longhorn-system \
  | grep -B 10 -A 50 "longhorn.io/admission-webhook.*longhorn-admission-webhook" | grep -E "kind:|name:|replicas:"
```

### 步骤 2: 检查当前安装的资源

```bash
# 查看所有 Deployment/DaemonSet
kubectl get deployment,daemonset -n longhorn-system

# 查看是否有应该创建 admission-webhook Pod 的资源
kubectl get deployment,daemonset -n longhorn-system -o yaml | grep -i "admission\|webhook"
```

### 步骤 3: 根据结果决定

**如果 Chart 中应该有独立的 Deployment**：
- 重新安装 Longhorn

**如果 Chart 中没有独立的 Deployment（webhook 在 Manager 中）**：
- 给 Manager 添加标签（方案 1）
- 或修改 Service 选择器（方案 2）

## 验证修复

```bash
# 检查 Endpoints
kubectl get endpoints -n longhorn-system longhorn-admission-webhook

# 应该看到 Endpoints 有值
# NAME                          ENDPOINTS          AGE
# longhorn-admission-webhook    10.42.0.x:9502     Xm

# 检查 Manager Pod 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 应该看到 Running 状态
```

## 参考

- Service 选择器文档: https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service
- Longhorn 组件文档: [LONGHORN_COMPONENTS_CHECKLIST.md](LONGHORN_COMPONENTS_CHECKLIST.md)


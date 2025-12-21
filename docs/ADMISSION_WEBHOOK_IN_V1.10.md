# Longhorn v1.10.1 admission-webhook 实现说明

## 重要发现

在 Longhorn v1.10.1 中，`admission-webhook` 的实现方式可能已经改变。

## 可能的情况

### 情况 1: 集成在 longhorn-manager 中（最可能）

在较新版本的 Longhorn 中，admission-webhook 功能可能已经**集成到 `longhorn-manager` Pod 中**，而不是作为独立的 Pod 运行。

**证据**：
- Helm Chart 中可能没有独立的 admission-webhook Deployment/DaemonSet
- `longhorn-admission-webhook` Service 的选择器可能指向 `longhorn-manager`
- Manager Pod 可能监听多个端口（包括 9502）

### 情况 2: 独立的 Pod（传统方式）

在某些版本中，admission-webhook 仍然是独立的 Pod。

## 如何确认

### 方法 1: 检查 Service 的选择器

```bash
# 查看 Service 的选择器指向哪个 Pod
kubectl get svc -n longhorn-system longhorn-admission-webhook -o yaml | grep -A 10 "selector:"

# 检查 Endpoints 指向哪个 Pod
kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o yaml | grep -A 10 "targetRef:"
```

### 方法 2: 检查 Manager Pod 的端口

```bash
# 查看 Manager Pod 监听的端口
kubectl get pod -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].spec.containers[0].ports[*]}'

# 或查看完整定义
kubectl get pod -n longhorn-system -l app=longhorn-manager -o yaml | grep -A 10 "ports:"
```

### 方法 3: 使用检查脚本

```bash
# 检查 admission-webhook 的实现方式
./scripts/check-admission-webhook-in-manager.sh 1.10.1
```

## 当前问题的分析

根据您的症状：
- ✅ `longhorn-admission-webhook` Service 存在
- ❌ 没有对应的 Pod
- ❌ `longhorn-manager` 无法连接到 webhook

**可能的原因**：

1. **如果集成在 Manager 中**：
   - Manager Pod 可能未正确启动 webhook 服务
   - 端口 9502 可能未正确监听
   - Manager 启动顺序问题（需要先启动 Manager 才能提供 webhook）

2. **如果是独立 Pod**：
   - Deployment/DaemonSet 未创建
   - Pod 无法调度
   - 镜像拉取失败

## 解决方案

### 如果集成在 Manager 中

这种情况下，Manager 的启动顺序是关键：

1. Manager Pod 需要先启动并监听 9502 端口
2. 然后才能注册 admission-webhook
3. 如果 Manager 启动失败，webhook 就无法工作

**检查 Manager 日志**：
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100 | grep -i "webhook\|9502\|admission"
```

**可能的修复**：
- 修复导致 Manager 无法启动的问题（DNS、资源等）
- 确保 Manager Pod 能够正常运行

### 如果是独立 Pod

需要确保 Deployment/DaemonSet 被正确创建和调度。

## 建议的下一步

1. **先检查 Service 选择器**：
   ```bash
   kubectl get svc -n longhorn-system longhorn-admission-webhook -o yaml
   ```

2. **检查 Endpoints**：
   ```bash
   kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o yaml
   ```

3. **运行深度检查脚本**：
   ```bash
   ./scripts/check-admission-webhook-in-manager.sh 1.10.1
   ```

4. **根据结果决定修复方案**

## 参考

- [Longhorn GitHub Issues](https://github.com/longhorn/longhorn/issues) - 搜索 "admission webhook"
- Longhorn v1.10.1 发布说明


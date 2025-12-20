# 修复 longhorn-manager API 问题

## 问题描述

`longhorn-manager` Pod 是 `Running` 状态，但 API (`http://localhost:9500/v1`) 无法访问，返回 curl exit code 52。

## 诊断步骤

### 1. 检查 manager 日志

```bash
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $MANAGER_POD --tail=100
```

查找：
- API 服务器启动信息
- 错误或警告信息
- 端口监听信息

### 2. 检查 manager 是否监听 9500 端口

```bash
kubectl exec -n longhorn-system $MANAGER_POD -- netstat -tlnp | grep 9500
```

如果未监听，说明 API 服务未启动。

### 3. 检查 manager 进程

```bash
kubectl exec -n longhorn-system $MANAGER_POD -- ps aux | grep longhorn
```

### 4. 使用诊断脚本

```bash
./scripts/check-manager-api.sh
```

## 可能的原因

### 原因 1: Manager 还在启动中

Manager 可能需要一些时间完全启动。

**检查**:
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50 | grep -i "started\|ready\|listening"
```

**解决**: 等待几分钟，然后重试。

### 原因 2: Manager 遇到错误

Manager 可能遇到了启动错误。

**检查**:
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100 | grep -i "error\|fatal\|panic"
```

**解决**: 根据错误信息修复问题。

### 原因 3: 资源不足

Manager 可能因为资源不足而无法启动 API 服务。

**检查**:
```bash
kubectl describe pod -n longhorn-system -l app=longhorn-manager | grep -A 10 "Limits\|Requests"
kubectl top pod -n longhorn-system -l app=longhorn-manager
```

**解决**: 增加节点资源或调整 manager 的资源限制。

### 原因 4: 配置问题

Manager 的配置可能有问题。

**检查**:
```bash
kubectl get configmap -n longhorn-system
kubectl get setting -n longhorn-system
```

## 解决方案

### 方案 1: 等待并重试

如果 manager 刚启动，等待几分钟：

```bash
# 等待 manager 完全启动
sleep 60

# 重试 API 访问
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://localhost:9500/v1 | head -5
```

### 方案 2: 重启 manager

如果等待后仍无法访问：

```bash
# 重启 manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 等待重启
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# 检查 API
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://localhost:9500/v1 | head -5
```

### 方案 3: 检查 Longhorn 配置

```bash
# 检查 Longhorn CR
kubectl get longhorn -n longhorn-system -o yaml

# 检查设置
kubectl get setting -n longhorn-system
```

### 方案 4: 查看完整日志

```bash
# 查看 manager 完整日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=200 > manager.log

# 查找关键信息
grep -i "api\|server\|listen\|9500\|error\|fatal" manager.log
```

## 临时解决方案

如果 manager API 暂时无法访问，但 StorageClass 已创建：

### 选项 1: 继续使用（推荐）

StorageClass 已存在，可以继续使用 Longhorn。`driver-deployer` 的 Init Container 会一直等待，但不影响基本功能。

### 选项 2: 手动完成 driver-deployer

如果确实需要 driver-deployer 完成：

```bash
# 等待 manager API 可用
# 然后重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

## 验证修复

修复后，验证：

```bash
# 1. 检查 manager 监听端口
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- netstat -tlnp | grep 9500

# 2. 测试 API
kubectl exec -n longhorn-system $MANAGER_POD -- curl -s http://localhost:9500/v1 | head -5

# 3. 从 driver-deployer 测试
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager -- curl -s http://longhorn-backend:9500/v1 | head -5
```

## 总结

| 问题 | 状态 | 影响 |
|------|------|------|
| Manager API 不可访问 | ⚠️ | driver-deployer Init Container 会等待 |
| StorageClass 已创建 | ✅ | 可以正常使用 |
| CSI Driver 已安装 | ✅ | 可以创建 PVC |

**关键点**:
- ✅ StorageClass 已创建，Longhorn 基本功能可用
- ⚠️ Manager API 暂时不可访问，但不影响基本使用
- ⚠️ driver-deployer 会等待，但可以忽略

**建议**: 即使 manager API 暂时不可访问，也可以继续使用 Longhorn。StorageClass 已可用，可以创建 PVC 和 VM。


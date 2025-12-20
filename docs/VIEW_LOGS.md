# 查看 Longhorn 日志指南

## 问题：如何查看 Init Container 的日志？

当 Pod 处于 `PodInitializing` 状态时，主容器还未启动，需要查看 Init Container 的日志。

## 正确的方法

### 1. 查看 Init Container 日志（关键）

```bash
# 使用 -c 参数指定 Init Container 名称
kubectl logs -n longhorn-system <pod-name> -c wait-longhorn-manager
```

**示例**:
```bash
kubectl logs -n longhorn-system longhorn-driver-deployer-7586c8d85b-xxgpd -c wait-longhorn-manager
```

### 2. 查看所有容器的日志

```bash
# 列出 Pod 中的所有容器
kubectl get pod -n longhorn-system <pod-name> -o jsonpath='{.spec.containers[*].name}'
kubectl get pod -n longhorn-system <pod-name> -o jsonpath='{.spec.initContainers[*].name}'

# 查看每个容器的日志
kubectl logs -n longhorn-system <pod-name> -c <container-name>
```

### 3. 查看 Pod 详情和事件

```bash
# 查看 Pod 详情（包含所有容器状态）
kubectl describe pod -n longhorn-system <pod-name>

# 查看 Pod 事件
kubectl get events -n longhorn-system --field-selector involvedObject.name=<pod-name>
```

### 4. 使用脚本查看

```bash
# 使用项目提供的脚本
./scripts/view-driver-deployer-logs.sh
```

## 常见场景

### 场景 1: longhorn-driver-deployer PodInitializing

```bash
# 1. 查看 Init Container 日志
kubectl logs -n longhorn-system longhorn-driver-deployer-xxx -c wait-longhorn-manager

# 2. 查看 Pod 详情
kubectl describe pod -n longhorn-system longhorn-driver-deployer-xxx

# 3. 检查 manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager
```

### 场景 2: longhorn-manager CrashLoopBackOff

```bash
# 1. 查看 manager 日志
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $MANAGER_POD --tail=50

# 2. 查看前一个容器的日志（如果容器重启了）
kubectl logs -n longhorn-system $MANAGER_POD --previous

# 3. 查看 Pod 详情
kubectl describe pod -n longhorn-system $MANAGER_POD
```

### 场景 3: 查看所有 Longhorn 组件日志

```bash
# 查看所有 Pods 状态
kubectl get pods -n longhorn-system

# 查看特定组件的日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=20
kubectl logs -n longhorn-system -l app=longhorn-ui --tail=20
```

## 有用的命令

### 实时查看日志

```bash
# 实时跟踪 Init Container 日志
kubectl logs -n longhorn-system <pod-name> -c wait-longhorn-manager -f

# 实时跟踪 manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager -f
```

### 查看最近的日志

```bash
# 查看最后 100 行
kubectl logs -n longhorn-system <pod-name> -c wait-longhorn-manager --tail=100

# 查看最近 5 分钟的日志
kubectl logs -n longhorn-system <pod-name> -c wait-longhorn-manager --since=5m
```

### 导出日志到文件

```bash
# 导出 Init Container 日志
kubectl logs -n longhorn-system <pod-name> -c wait-longhorn-manager > init-container.log

# 导出所有容器日志
kubectl logs -n longhorn-system <pod-name> --all-containers=true > all-containers.log
```

## 调试技巧

### 1. 检查容器状态

```bash
# 查看 Pod 的 JSON 输出（包含所有容器状态）
kubectl get pod -n longhorn-system <pod-name> -o json | jq '.status'

# 查看 Init Container 状态
kubectl get pod -n longhorn-system <pod-name> -o jsonpath='{.status.initContainerStatuses[*]}' | jq '.'
```

### 2. 检查容器退出码

```bash
# 查看容器的退出码
kubectl get pod -n longhorn-system <pod-name> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.exitCode}'
kubectl get pod -n longhorn-system <pod-name> -o jsonpath='{.status.initContainerStatuses[*].lastState.terminated.exitCode}'
```

### 3. 进入容器调试（如果容器运行中）

```bash
# 进入 Init Container（如果还在运行）
kubectl exec -n longhorn-system <pod-name> -c wait-longhorn-manager -- /bin/sh

# 进入主容器（如果已启动）
kubectl exec -n longhorn-system <pod-name> -c longhorn-driver-deployer -- /bin/sh
```

## 快速参考

| 命令 | 说明 |
|------|------|
| `kubectl logs -n longhorn-system <pod> -c <container>` | 查看指定容器的日志 |
| `kubectl describe pod -n longhorn-system <pod>` | 查看 Pod 详情和事件 |
| `kubectl get events -n longhorn-system` | 查看所有事件 |
| `kubectl get pod -n longhorn-system <pod> -o yaml` | 查看 Pod 完整配置 |

## 关键点

1. ✅ **使用 `-c` 参数**: 查看 Init Container 日志必须使用 `-c wait-longhorn-manager`
2. ✅ **主容器未启动**: 如果 Pod 是 `PodInitializing`，主容器日志不可用
3. ✅ **查看 Pod 详情**: `kubectl describe` 包含所有容器状态和事件
4. ✅ **检查事件**: `kubectl get events` 显示 Pod 生命周期事件


# longhorn-driver-deployer 等待问题

## 问题描述

`longhorn-driver-deployer` Pod 一直处于 `Init:0/1` 或 `PodInitializing` 状态。

## 原因

`longhorn-driver-deployer` 有一个 Init Container 叫 `wait-longhorn-manager`，它会一直等待直到 `longhorn-manager` 就绪。这是**正常行为**，但需要确保 `longhorn-manager` 能够正常启动。

## 诊断步骤

### 1. 查看 Init Container 日志（关键）

```bash
# 获取 Pod 名称
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')

# 查看 Init Container 日志
kubectl logs -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager
```

**注意**: 必须使用 `-c wait-longhorn-manager` 参数查看 Init Container 的日志，而不是主容器的日志。

### 2. 检查 longhorn-manager 状态

```bash
kubectl get pods -n longhorn-system -l app=longhorn-manager
```

如果 `longhorn-manager` 是 `CrashLoopBackOff`，需要先修复它。

### 3. 使用诊断脚本

```bash
./scripts/check-driver-deployer.sh
```

## 解决方案

### 情况 1: longhorn-manager 未就绪

如果 `longhorn-manager` 是 `CrashLoopBackOff` 或 `Pending`：

#### 步骤 1: 检查 manager 日志

```bash
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $MANAGER_POD --tail=50
```

#### 步骤 2: 如果是 iscsi 问题

如果日志显示 `iscsiadm` 或 `open-iscsi` 错误：

```bash
# 在所有节点上安装 open-iscsi
# Ubuntu/Debian:
sudo apt-get update && sudo apt-get install -y open-iscsi && sudo systemctl enable iscsid && sudo systemctl start iscsid

# CentOS/RHEL:
sudo yum install -y iscsi-initiator-utils && sudo systemctl enable iscsid && sudo systemctl start iscsid
```

#### 步骤 3: 重启 manager

```bash
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

#### 步骤 4: 等待 manager 就绪

```bash
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```

#### 步骤 5: driver-deployer 会自动继续

一旦 `longhorn-manager` 就绪，`driver-deployer` 的 Init Container 会自动完成。

### 情况 2: longhorn-manager 已就绪但 driver-deployer 仍卡住

如果 `longhorn-manager` 已经 `Running`，但 `driver-deployer` 仍然卡住超过 5 分钟：

#### 重启 driver-deployer

```bash
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

## 常见错误

### 错误 1: 查看主容器日志失败

```bash
kubectl logs -n longhorn-system longhorn-driver-deployer-xxx
# Error: container "longhorn-driver-deployer" is waiting to start: PodInitializing
```

**原因**: 主容器还未启动，因为 Init Container 还在运行。

**解决**: 查看 Init Container 日志：
```bash
kubectl logs -n longhorn-system longhorn-driver-deployer-xxx -c wait-longhorn-manager
```

### 错误 2: Init Container 一直等待

**原因**: `longhorn-manager` 未就绪。

**解决**: 先修复 `longhorn-manager`（见情况 1）。

## 验证

修复后，检查状态：

```bash
# 检查所有 Pods
kubectl get pods -n longhorn-system

# 应该看到:
# longhorn-manager-xxx           1/1     Running
# longhorn-driver-deployer-xxx   1/1     Running
# longhorn-ui-xxx                1/1     Running
```

## 关键点

1. ✅ **Init Container 等待是正常的**: `wait-longhorn-manager` 会等待 manager 就绪
2. ✅ **必须先修复 manager**: driver-deployer 依赖于 manager
3. ✅ **查看正确的日志**: 使用 `-c wait-longhorn-manager` 查看 Init Container 日志
4. ✅ **自动恢复**: manager 就绪后，driver-deployer 会自动继续

## 快速命令

```bash
# 1. 检查状态
./scripts/check-driver-deployer.sh

# 2. 查看 Init Container 日志
kubectl logs -n longhorn-system $(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}') -c wait-longhorn-manager

# 3. 检查 manager 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 4. 如果 manager 已就绪但 driver-deployer 卡住，重启它
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```


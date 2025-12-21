# Longhorn 组件清单和验证

## 概述

本文档说明 Longhorn Helm Chart 安装后应该包含的所有组件，以及如何验证每个组件是否正确安装。

## 核心组件列表

### 必需组件（核心功能）

| 组件 | 类型 | 说明 | 是否必需 |
|------|------|------|---------|
| **longhorn-manager** | DaemonSet | 存储管理器，每个节点一个 | ✅ 必需 |
| **longhorn-ui** | Deployment | Web 管理界面 | ✅ 必需 |
| **longhorn-admission-webhook** | Deployment/DaemonSet | Kubernetes 准入控制器 | ✅ **必需** ⭐ |
| **longhorn-driver-deployer** | Job | CSI Driver 安装器 | ✅ 必需（一次性） |
| **longhorn-csi-plugin** | DaemonSet | CSI 插件，每个节点一个 | ✅ 必需 |
| **longhorn-csi-attacher** | Deployment | CSI 附加器 | ✅ 必需 |
| **longhorn-csi-provisioner** | Deployment | CSI 供应器 | ✅ 必需 |
| **longhorn-csi-resizer** | Deployment | CSI 扩展器 | ✅ 必需 |
| **longhorn-backing-image-manager** | DaemonSet | 备份镜像管理器 | ✅ 必需 |
| **longhorn-engine-image** | DaemonSet | 引擎镜像 | ✅ 必需 |

### 可选组件

| 组件 | 类型 | 说明 | 是否必需 |
|------|------|------|---------|
| **longhorn-csi-snapshotter** | Deployment | CSI 快照器 | ⚪ 可选（快照功能） |

## 重要说明

### admission-webhook 是必需的

**⚠️ 重要**：`longhorn-admission-webhook` 是 Longhorn 的必需组件，**不能禁用**。

**原因**：
1. **资源验证**：验证 Longhorn CRD 资源的正确性
2. **默认值设置**：为资源设置默认值
3. **Manager 依赖**：`longhorn-manager` 启动时**必须**能够访问 admission-webhook 服务
4. **API 网关**：作为 Kubernetes 准入控制的入口

**如果 admission-webhook Pod 不存在**，`longhorn-manager` 会一直重启，错误信息：
```
Error starting webhooks: admission webhook service is not accessible on cluster after 2m0s sec: timed out waiting for endpoint https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/healthz to be available
```

## 验证安装的组件

### 方法 1: 使用检查脚本（推荐）

```bash
# 检查 Helm Chart 包含的组件
./scripts/check-longhorn-chart-components.sh 1.10.1
```

### 方法 2: 手动检查已安装的组件

```bash
# 检查所有 Pods
kubectl get pods -n longhorn-system

# 检查所有 Deployments
kubectl get deployment -n longhorn-system

# 检查所有 DaemonSets
kubectl get daemonset -n longhorn-system

# 检查所有 Jobs
kubectl get jobs -n longhorn-system

# 检查所有 Services
kubectl get svc -n longhorn-system
```

### 方法 3: 从 Helm Chart 清单检查

```bash
# 获取 Chart 清单
helm template longhorn longhorn/longhorn \
  --version 1.10.1 \
  --namespace longhorn-system \
  | grep -E "^kind:|^\s+name:" | grep -A 1 "kind: Deployment" | grep "name:"
```

## 完整的 Pod 清单检查

### 安装后应该看到的 Pods

```bash
kubectl get pods -n longhorn-system
```

**预期输出**（单节点环境）：

```
NAME                                        READY   STATUS      RESTARTS   AGE
longhorn-manager-xxx                        1/1     Running     0          5m
longhorn-ui-xxx                             1/1     Running     0          5m
longhorn-admission-webhook-xxx              1/1     Running     0          5m    # ⭐ 必需
longhorn-driver-deployer-xxx                0/1     Completed   0          5m
longhorn-csi-plugin-xxx                     2/2     Running     0          5m
longhorn-csi-attacher-xxx                   1/1     Running     0          5m
longhorn-csi-provisioner-xxx                1/1     Running     0          5m
longhorn-csi-resizer-xxx                    1/1     Running     0          5m
longhorn-backing-image-manager-xxx          1/1     Running     0          5m
longhorn-engine-image-xxx                   1/1     Running     0          5m
```

### 检查清单命令

```bash
#!/bin/bash
# 完整的组件检查脚本

echo "=== 检查所有 Deployments ==="
kubectl get deployment -n longhorn-system

echo ""
echo "=== 检查所有 DaemonSets ==="
kubectl get daemonset -n longhorn-system

echo ""
echo "=== 检查所有 Jobs ==="
kubectl get jobs -n longhorn-system

echo ""
echo "=== 检查所有 Services ==="
kubectl get svc -n longhorn-system

echo ""
echo "=== 检查所有 Pods ==="
kubectl get pods -n longhorn-system

echo ""
echo "=== 重点检查 admission-webhook ==="
echo "Service:"
kubectl get svc -n longhorn-system longhorn-admission-webhook
echo ""
echo "Endpoints:"
kubectl get endpoints -n longhorn-system longhorn-admission-webhook
echo ""
echo "Pods:"
kubectl get pods -n longhorn-system -l app=longhorn-admission-webhook
```

## 如果 admission-webhook Pod 不存在

### 诊断步骤

```bash
# 1. 检查是否有 DaemonSet/Deployment 定义
kubectl get daemonset,deployment -n longhorn-system | grep admission-webhook

# 2. 检查 Helm 清单中是否有定义
helm get manifest longhorn -n longhorn-system | grep -A 20 "admission-webhook"

# 3. 检查 Helm values 是否有禁用选项
helm get values longhorn -n longhorn-system

# 4. 检查事件
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | grep admission
```

### 可能的原因

1. **Helm Chart 安装不完整** - 资源未完全创建
2. **资源被误删除** - Pod/Deployment 被手动删除
3. **调度失败** - Pod 无法调度到节点（资源不足、污点等）
4. **镜像拉取失败** - 无法拉取 admission-webhook 镜像

### 解决方案

如果 admission-webhook Pod 不存在，**必须重新安装 Longhorn**：

```bash
# 1. 卸载
helm uninstall longhorn -n longhorn-system
kubectl delete namespace longhorn-system

# 2. 等待清理
sleep 60

# 3. 重新安装
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.10.1 \
  --values config/longhorn-values.yaml

# 4. 验证 admission-webhook 已创建
kubectl wait --for=condition=ready pod -l app=longhorn-admission-webhook -n longhorn-system --timeout=300s
```

## 验证脚本

使用项目提供的验证脚本：

```bash
# 检查 Chart 组件
./scripts/check-longhorn-chart-components.sh 1.10.1

# 诊断 Manager 重启问题
./scripts/diagnose-longhorn-manager-restart.sh

# 修复 admission-webhook 缺失
./scripts/fix-longhorn-admission-webhook-missing.sh
```

## 总结

- ✅ **admission-webhook 是必需组件**，不能禁用
- ✅ 如果 admission-webhook Pod 不存在，Manager 会一直重启
- ✅ 正常情况下，所有列出的组件都应该存在并运行
- ✅ 如果缺少任何必需组件，需要重新安装 Longhorn

## 参考

- Longhorn 官方文档: https://longhorn.io/docs/
- Helm Chart: https://github.com/longhorn/longhorn/tree/master/chart
- 问题排查: [K3S_LONGHORN_ISSUES.md](K3S_LONGHORN_ISSUES.md)


# 修复 longhorn-driver-deployer 问题

## 问题描述

`longhorn-driver-deployer` 一直卡在 `Init:0/1` 状态，Init Container 无法完成。

## 重要说明

### ✅ 即使 driver-deployer 卡住，Longhorn 仍然可用

如果 `longhorn` StorageClass 已存在，说明：
- ✅ CSI 驱动已安装
- ✅ 可以创建 PVC
- ✅ 可以正常使用

`driver-deployer` 是**可选组件**，用于部署 CSI 驱动。如果 StorageClass 已创建，说明驱动已部署成功。

## 可能的原因

### 原因 1: Manager API 未正常启动

虽然 manager Pod 是 `Running`，但 API 服务可能未正常启动。

**检查**:
```bash
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- netstat -tlnp | grep 9500
kubectl logs -n longhorn-system $MANAGER_POD --tail=100 | grep -i "api\|server\|listen"
```

### 原因 2: 版本兼容性问题

Longhorn v1.6.0 可能与某些 Kubernetes/k3s 版本不兼容。

**检查版本**:
```bash
./scripts/check-longhorn-version.sh
```

### 原因 3: 网络问题

Init Container 无法访问 `longhorn-backend:9500`。

**检查**:
```bash
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $DEPLOYER_POD -c wait-longhorn-manager -- nslookup longhorn-backend
```

### 原因 4: 单节点环境问题

单节点环境可能需要特殊配置。

## 解决方案

### 方案 1: 忽略（推荐，如果 StorageClass 已存在）

如果 `longhorn` StorageClass 已创建，可以忽略 `driver-deployer` 的状态：

```bash
# 验证 StorageClass 存在
kubectl get storageclass longhorn

# 如果存在，可以直接使用
# 在 Wukong 中使用: storageClassName: longhorn
```

### 方案 2: 等待更长时间

Manager API 可能需要更多时间启动（10-15 分钟）：

```bash
# 等待并监控
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -w
```

### 方案 3: 重启相关组件

```bash
# 1. 重启 manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 2. 等待 manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# 3. 重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

### 方案 4: 检查并修复 Manager API

```bash
# 运行诊断脚本
./scripts/check-manager-api.sh

# 根据诊断结果修复
```

### 方案 5: 尝试不同版本

如果确实是版本问题，可以尝试：

#### 选项 A: 降级到稳定版本

```bash
# 卸载当前版本
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 安装 v1.5.0（更稳定的版本）
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.0/deploy/longhorn.yaml
```

#### 选项 B: 升级到最新版本

```bash
# 检查最新版本
# https://github.com/longhorn/longhorn/releases

# 卸载当前版本
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 安装最新版本（例如 v1.6.1）
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.1/deploy/longhorn.yaml
```

### 方案 6: 使用修复脚本

```bash
# 运行完整修复脚本
./scripts/fix-driver-deployer-final.sh
```

## 验证修复

修复后，验证：

```bash
# 1. 检查 driver-deployer 状态
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer

# 2. 检查 StorageClass
kubectl get storageclass longhorn

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

kubectl get pvc test-pvc
```

## 如果无法修复

如果所有方法都尝试过，但 `driver-deployer` 仍然卡住：

### 选项 1: 继续使用（推荐）

如果 StorageClass 已存在，可以继续使用 Longhorn：

```yaml
# 在 Wukong 中使用
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn  # 可以使用
    boot: true
```

### 选项 2: 使用 local-path（临时方案）

如果 Longhorn 无法正常工作，可以临时使用 `local-path`：

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: local-path  # 临时使用
    boot: true
```

**注意**: `local-path` 不支持卷扩展。

## 版本兼容性

### Longhorn v1.6.0 要求

- Kubernetes: 1.21+
- k3s: 1.21+

### 已知问题

某些 k3s 版本可能与 Longhorn v1.6.0 有兼容性问题。如果遇到问题，可以尝试：

1. **降级到 v1.5.0**（更稳定）
2. **升级 k3s** 到最新版本
3. **等待 Longhorn 更新**修复兼容性问题

## 总结

| 情况 | 解决方案 | 优先级 |
|------|---------|--------|
| StorageClass 已存在 | 忽略 driver-deployer | ⭐⭐⭐ |
| Manager API 未启动 | 重启 manager | ⭐⭐ |
| 版本兼容性问题 | 尝试不同版本 | ⭐ |
| 网络问题 | 检查网络配置 | ⭐ |

**关键点**:
- ✅ 如果 StorageClass 已存在，Longhorn 可以使用
- ✅ driver-deployer 是可选组件
- ⚠️ 如果 StorageClass 不存在，需要修复 driver-deployer
- ⚠️ 版本兼容性问题可能需要尝试不同版本

## 快速决策

```bash
# 1. 检查 StorageClass
kubectl get storageclass longhorn

# 2. 如果存在，直接使用（忽略 driver-deployer）
# 3. 如果不存在，运行修复脚本
./scripts/fix-driver-deployer-final.sh
```


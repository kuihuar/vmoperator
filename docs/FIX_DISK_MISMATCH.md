# 修复 Longhorn 磁盘配置不一致

## 问题描述

Manager 日志显示：
```
Failed to sync with disk monitor due to mismatching disks
error="mismatching disks in node resource object and monitor collected data"
```

这个错误表示 Longhorn Node 资源中记录的磁盘配置与实际扫描到的物理磁盘信息不一致。

## 问题原因

### 可能的原因

1. **首次安装**: Longhorn 首次安装时，Node 资源可能未正确初始化
2. **磁盘路径变更**: 节点上的磁盘路径发生了变化
3. **环境初始化不完整**: Longhorn 初始化过程中断
4. **单节点环境**: 单节点环境可能需要特殊配置

## 诊断步骤

### 1. 检查 Longhorn Node 资源

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 检查 Node 资源
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml

# 查看磁盘配置
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"
```

### 2. 检查节点上的实际磁盘

在节点上执行：

```bash
# 检查磁盘
df -h
lsblk

# 检查 Longhorn 存储路径
ls -la /var/lib/longhorn
df -h /var/lib/longhorn
```

### 3. 检查 Manager 日志

```bash
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $MANAGER_POD --tail=100 | grep -i "disk\|mismatching"
```

## 解决方案

### 方案 1: 删除并重建 Node 资源（推荐）

```bash
# 1. 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 2. 删除 Longhorn Node 资源（会自动重建）
kubectl delete nodes.longhorn.io -n longhorn-system $NODE_NAME

# 3. 等待 Node 资源重建
kubectl wait --for=condition=ready nodes.longhorn.io/$NODE_NAME -n longhorn-system --timeout=300s

# 4. 重启 manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 方案 2: 通过 Longhorn UI 配置

```bash
# 1. 访问 Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# 2. 在浏览器中访问: http://localhost:8080
# 3. 进入 Nodes → <node-name> → Disks
# 4. 配置磁盘路径（例如: /var/lib/longhorn）
# 5. 保存配置
```

### 方案 3: 通过 kubectl 手动配置

```bash
# 1. 编辑 Node 资源
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME

# 2. 在 disks 字段中添加磁盘配置，例如:
# disks:
#   default-disk:
#     allowScheduling: true
#     evictionRequested: false
#     path: /var/lib/longhorn
#     storageReserved: 0
#     tags: []
```

### 方案 4: 使用修复脚本

```bash
./scripts/fix-longhorn-disk-mismatch.sh
```

## 单节点环境特殊配置

### 配置默认磁盘路径

```bash
# 检查设置
kubectl get setting -n longhorn-system default-data-path

# 如果需要，更新默认路径
kubectl patch setting -n longhorn-system default-data-path --type merge -p '{"value":"/var/lib/longhorn"}'
```

### 配置节点磁盘

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 创建或更新 Node 资源
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: $NODE_NAME
  namespace: longhorn-system
spec:
  allowScheduling: true
  disks:
    default-disk:
      allowScheduling: true
      evictionRequested: false
      path: /var/lib/longhorn
      storageReserved: 0
      tags: []
EOF
```

## 验证修复

修复后，验证：

```bash
# 1. 检查 Node 资源状态
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME

# 2. 检查 Manager 日志
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $MANAGER_POD --tail=50 | grep -i "disk\|mismatching"

# 3. 应该不再有 "mismatching disks" 错误
```

## 常见问题

### 问题 1: Node 资源不存在

如果 `kubectl get nodes.longhorn.io` 返回空，说明 Node 资源还未创建。

**解决**: 等待 Longhorn 自动创建，或手动创建（见方案 3）。

### 问题 2: 磁盘路径不存在

如果 `/var/lib/longhorn` 不存在：

```bash
# 在节点上创建
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn
```

### 问题 3: 磁盘空间不足

检查磁盘空间：

```bash
df -h /var/lib/longhorn
```

确保有足够的空间（建议至少 10GB）。

## 总结

| 问题 | 原因 | 解决 |
|------|------|------|
| 磁盘配置不一致 | Node 资源未正确初始化 | 删除并重建 Node 资源 |
| 磁盘路径不存在 | 路径未创建 | 创建路径并配置 |
| 单节点环境 | 需要特殊配置 | 手动配置磁盘 |

**关键点**:
- ✅ 这个错误可能导致 Manager 功能异常
- ✅ 删除并重建 Node 资源通常可以解决
- ✅ 单节点环境需要手动配置磁盘
- ✅ 修复后，Manager API 应该能正常工作

## 快速修复

```bash
# 运行修复脚本
./scripts/fix-longhorn-disk-mismatch.sh

# 或手动修复
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl delete nodes.longhorn.io -n longhorn-system $NODE_NAME
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

修复后，Manager 应该能正常工作，`driver-deployer` 的 Init Container 也应该能完成。


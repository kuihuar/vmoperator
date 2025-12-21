# 修复 PVC Pending 问题

## 问题描述

PVC 一直处于 `Pending` 状态，无法绑定到 PV。

## 常见原因

### 原因 1: Longhorn Node 没有磁盘配置（最常见）⭐

**症状**:
```
PVC Status: Pending
Events: (无事件或等待 provisioner)
```

**检查**:
```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"
```

如果 `disks:` 为空或不存在，这就是问题所在。

**解决**:

#### 方法 1: 通过 Longhorn UI（推荐）

```bash
# 1. 访问 Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80

# 2. 在浏览器中访问: http://192.168.1.141:8088
# 3. 进入 Nodes → <node-name> → Disks
# 4. 点击 Add Disk
# 5. 配置:
#    - Path: /var/lib/longhorn
#    - Allow Scheduling: true
# 6. 保存
```

#### 方法 2: 使用脚本

```bash
./scripts/fix-longhorn-disk-mismatch.sh
```

#### 方法 3: 手动配置

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME
```

添加或更新 `disks` 字段：

```yaml
spec:
  disks:
    default-disk:
      allowScheduling: true
      evictionRequested: false
      path: /var/lib/longhorn
      storageReserved: 0
      tags: []
```

### 原因 2: 存储空间不足

**检查**:
```bash
# 在节点上检查
df -h /var/lib/longhorn
```

**解决**: 清理空间或扩展磁盘。

### 原因 3: Longhorn Node 未就绪

**检查**:
```bash
kubectl get nodes.longhorn.io -n longhorn-system <node-name>
kubectl describe nodes.longhorn.io -n longhorn-system <node-name>
```

**解决**: 等待 Node 就绪或修复 Node 问题。

### 原因 4: CSI Driver 未安装

**检查**:
```bash
kubectl get csidriver
kubectl get pods -n longhorn-system | grep csi
```

**解决**: 等待 CSI Driver 安装完成。

## 诊断步骤

### 1. 运行诊断脚本

```bash
./scripts/diagnose-pvc-pending.sh ubuntu-longhorn-test-system
```

### 2. 检查 PVC 事件

```bash
kubectl describe pvc ubuntu-longhorn-test-system | grep -A 20 "Events:"
```

### 3. 检查 Longhorn Node

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml
```

## 快速修复

### 如果 Node 没有磁盘配置

```bash
# 方法 1: 通过 UI（推荐）
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80
# 然后在浏览器中配置磁盘

# 方法 2: 使用脚本
./scripts/fix-longhorn-disk-mismatch.sh

# 方法 3: 手动配置
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{
  "spec": {
    "disks": {
      "default-disk": {
        "allowScheduling": true,
        "path": "/var/lib/longhorn",
        "storageReserved": 0
      }
    }
  }
}'
```

## 验证修复

修复后，验证：

```bash
# 1. 检查 Node 磁盘配置
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 10 "disks:"

# 2. 检查 PVC 状态
kubectl get pvc ubuntu-longhorn-test-system

# 3. 应该很快变为 Bound
# 如果仍然是 Pending，等待几分钟或检查事件
kubectl describe pvc ubuntu-longhorn-test-system
```

## 总结

| 问题 | 原因 | 解决 |
|------|------|------|
| PVC Pending | Node 没有磁盘配置 | 在 Longhorn UI 中配置磁盘 |
| PVC Pending | 存储空间不足 | 清理空间或扩展磁盘 |
| PVC Pending | Node 未就绪 | 等待或修复 Node |

**关键点**:
- ✅ 最常见的原因是 Longhorn Node 没有磁盘配置
- ✅ 通过 Longhorn UI 配置磁盘是最简单的方法
- ✅ 配置磁盘后，PVC 应该很快绑定

## 快速修复命令

```bash
# 1. 诊断问题
./scripts/diagnose-pvc-pending.sh ubuntu-longhorn-test-system

# 2. 如果 Node 没有磁盘配置，通过 UI 配置
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80
# 然后在浏览器中: Nodes → <node> → Disks → Add Disk → /var/lib/longhorn

# 3. 或使用脚本修复
./scripts/fix-longhorn-disk-mismatch.sh
```


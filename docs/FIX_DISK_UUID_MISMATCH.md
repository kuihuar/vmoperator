# 修复 Longhorn 磁盘 UUID 不匹配错误

## 错误信息

```
Disk data-disk(/mnt/longhorn) on node host1 is not ready: record diskUUID doesn't match the one on the disk
```

## 问题原因

这个错误通常发生在以下情况：

1. **磁盘被重新格式化或重新分区**
   - 磁盘的 UUID 发生了变化
   - Longhorn 记录的 UUID 与实际磁盘 UUID 不匹配

2. **磁盘被替换**
   - 使用了新的磁盘替换了旧的
   - Longhorn 仍然记录着旧磁盘的 UUID

3. **磁盘路径被重新配置**
   - 磁盘路径指向了不同的物理设备
   - UUID 不匹配

## 解决方案

### 方法 1: 使用修复脚本（推荐）⭐

```bash
./scripts/fix-longhorn-disk-uuid.sh /mnt/longhorn
```

脚本会自动：
1. 删除旧的磁盘配置
2. 清理磁盘路径（可选）
3. 重新配置磁盘
4. 验证配置

### 方法 2: 手动修复

#### 步骤 1: 删除旧磁盘配置

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 清空磁盘配置
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{"spec":{"disks":null}}'
```

#### 步骤 2: 清理磁盘路径（可选）

如果磁盘路径中有旧的 Longhorn 数据，建议清理：

```bash
# 备份旧数据
sudo mv /mnt/longhorn /mnt/longhorn.backup.$(date +%Y%m%d_%H%M%S)

# 重新创建目录
sudo mkdir -p /mnt/longhorn
sudo chmod 755 /mnt/longhorn
```

#### 步骤 3: 重新配置磁盘

```bash
# 重新配置磁盘
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{
  "spec": {
    "disks": {
      "data-disk": {
        "allowScheduling": true,
        "evictionRequested": false,
        "path": "/mnt/longhorn",
        "storageReserved": 0,
        "tags": []
      }
    }
  }
}'
```

#### 步骤 4: 验证配置

```bash
# 检查配置
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"

# 检查磁盘状态
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 30 "diskStatus:"
```

### 方法 3: 通过 Longhorn UI 修复

1. **访问 Longhorn UI**
   ```bash
   kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80
   ```
   访问: http://192.168.1.141:8088

2. **删除旧磁盘**
   - 进入: Nodes → host1 → Disks
   - 找到有问题的磁盘（data-disk）
   - 点击删除

3. **重新添加磁盘**
   - 点击 Add Disk
   - 配置:
     - Path: `/mnt/longhorn`
     - Allow Scheduling: true
     - Storage Reserved: 0
   - 保存

## 验证修复

### 1. 检查磁盘状态

```bash
# 查看节点状态
kubectl get nodes.longhorn.io -n longhorn-system host1 -o yaml | grep -A 30 "diskStatus:"
```

应该看到磁盘状态为 `Ready`，而不是 `not ready`。

### 2. 检查 Longhorn UI

在 Longhorn UI 中：
- Nodes → host1 → Disks
- 应该看到磁盘状态为绿色（Ready）

### 3. 测试 PVC 创建

```bash
# 创建测试 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# 检查 PVC 状态
kubectl get pvc test-pvc

# 应该很快变为 Bound

# 清理测试 PVC
kubectl delete pvc test-pvc
```

## 常见问题

### 问题 1: 修复后仍然显示 "not ready"

**可能原因**:
- 磁盘路径权限问题
- Longhorn Manager 未同步
- 磁盘空间不足

**解决**:
```bash
# 检查权限
ls -la /mnt/longhorn

# 修复权限
sudo chmod 755 /mnt/longhorn

# 重启 Longhorn Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 等待 Manager 重新启动
kubectl get pods -n longhorn-system -l app=longhorn-manager
```

### 问题 2: 无法删除磁盘配置

**解决**:
```bash
# 直接编辑 Node 资源
kubectl edit nodes.longhorn.io -n longhorn-system host1

# 删除 spec.disks 字段，保存退出
```

### 问题 3: 磁盘路径中有数据，不想清理

**解决**:
- 跳过清理步骤
- 直接重新配置磁盘
- Longhorn 会自动识别新的 UUID

## 预防措施

1. **避免重新格式化磁盘**
   - 如果需要重新配置，先删除 Longhorn 配置
   - 然后再格式化

2. **使用稳定的磁盘路径**
   - 使用 UUID 挂载（在 /etc/fstab 中使用 UUID）
   - 避免使用设备名（如 /dev/sdb1）

3. **配置自动挂载**
   ```bash
   # 在 /etc/fstab 中使用 UUID
   UUID=xxxx-xxxx /mnt/longhorn ext4 defaults 0 2
   ```

## 总结

| 方法 | 优点 | 缺点 |
|------|------|------|
| **修复脚本** | 自动化，快速 | 需要确认操作 |
| **手动修复** | 可控性强 | 步骤较多 |
| **UI 修复** | 可视化 | 需要访问 UI |

**推荐**: 使用修复脚本 `./scripts/fix-longhorn-disk-uuid.sh /mnt/longhorn`

## 快速修复命令

```bash
# 一键修复
./scripts/fix-longhorn-disk-uuid.sh /mnt/longhorn

# 或手动修复
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{"spec":{"disks":null}}'
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{
  "spec": {
    "disks": {
      "data-disk": {
        "allowScheduling": true,
        "path": "/mnt/longhorn",
        "storageReserved": 0
      }
    }
  }
}'
```


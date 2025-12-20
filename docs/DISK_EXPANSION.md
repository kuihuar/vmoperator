# 磁盘扩展指南

## 概述

Wukong 支持动态扩展磁盘大小，前提是 StorageClass 支持卷扩展（`allowVolumeExpansion: true`）。

## 前提条件

### 1. StorageClass 支持扩展

检查 StorageClass 是否支持扩展：

```bash
kubectl get storageclass <storage-class-name> -o yaml | grep allowVolumeExpansion
```

如果输出为 `allowVolumeExpansion: true`，则支持扩展。

### 2. PVC 已绑定

只有已绑定的 PVC 才能扩展：

```bash
kubectl get pvc <pvc-name>
```

状态应该是 `Bound`。

## 扩展方法

### 方法 1: 使用脚本（推荐）

```bash
./scripts/expand-disk.sh <wukong-name> <disk-name> <new-size>
```

**示例**:
```bash
# 扩展系统盘从 20Gi 到 50Gi
./scripts/expand-disk.sh ubuntu-noble-local system 50Gi

# 扩展数据盘从 100Gi 到 200Gi
./scripts/expand-disk.sh ubuntu-noble-local data 200Gi
```

### 方法 2: 直接编辑 Wukong

```bash
# 1. 编辑 Wukong 配置
kubectl edit wukong <wukong-name>

# 2. 找到要扩展的磁盘，修改 size 字段
# 例如：
#   disks:
#     - name: system
#       size: 50Gi  # 从 20Gi 改为 50Gi
```

Controller 会自动检测大小变化并扩展 PVC。

### 方法 3: 使用 kubectl patch

```bash
kubectl patch wukong <wukong-name> --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/disks/0/size",
    "value": "50Gi"
  }
]'
```

## 扩展流程

### 1. 更新 Wukong 配置

修改 Wukong 中的磁盘大小：

```yaml
disks:
  - name: system
    size: 50Gi  # 从 20Gi 改为 50Gi
```

### 2. Controller 检测变化

Controller 在下次 reconcile 时会检测到大小变化，并调用 `ReconcileDiskExpansion`。

### 3. 扩展 PVC

Controller 会更新 PVC 的 `spec.resources.requests.storage` 字段。

### 4. StorageClass 处理扩展

StorageClass 的 provisioner 会处理实际的卷扩展。

### 5. 文件系统扩展

PVC 扩展完成后，需要在 VM 内部扩展文件系统。

## 在 VM 内部扩展文件系统

### 连接到 VM

```bash
virtctl console <vm-name>
```

### 扩展 ext4 文件系统

```bash
# 1. 检查磁盘分区
lsblk

# 2. 扩展分区
sudo growpart /dev/vda 1

# 3. 扩展文件系统
sudo resize2fs /dev/vda1

# 4. 验证
df -h
```

### 扩展 xfs 文件系统

```bash
# 1. 扩展文件系统（xfs 不需要先扩展分区）
sudo xfs_growfs /

# 2. 验证
df -h
```

### 扩展多磁盘

如果 VM 有多个磁盘（系统盘和数据盘分离），需要分别扩展：

```bash
# 系统盘（通常是 /dev/vda）
sudo growpart /dev/vda 1
sudo resize2fs /dev/vda1

# 数据盘（通常是 /dev/vdb）
sudo growpart /dev/vdb 1
sudo resize2fs /dev/vdb1
```

## 监控扩展进度

### 检查 PVC 状态

```bash
# 查看 PVC 状态
kubectl get pvc <pvc-name>

# 查看详细状态
kubectl describe pvc <pvc-name>
```

### 检查扩展条件

```bash
# 检查是否正在扩展
kubectl get pvc <pvc-name> -o jsonpath='{.status.conditions[?(@.type=="Resizing")]}'

# 检查文件系统扩展是否待处理
kubectl get pvc <pvc-name> -o jsonpath='{.status.conditions[?(@.type=="FileSystemResizePending")]}'
```

## 系统盘和数据盘分离扩展

### 配置示例

```yaml
disks:
  # 系统盘：操作系统
  - name: system
    size: 20Gi
    storageClassName: local-path
    boot: true
  
  # 数据盘：用户数据
  - name: data
    size: 100Gi
    storageClassName: local-path
    boot: false
```

### 独立扩展

可以单独扩展数据盘，不影响系统盘：

```bash
# 只扩展数据盘
./scripts/expand-disk.sh ubuntu-separated-disks data 200Gi
```

### 优势

1. **独立管理**: 系统盘和数据盘可以独立扩展
2. **灵活配置**: 可以为不同磁盘使用不同的 StorageClass
3. **易于迁移**: 数据盘可以使用网络存储，便于迁移

## 故障排查

### 问题 1: StorageClass 不支持扩展

**错误信息**:
```
StorageClass does not allow volume expansion
```

**解决方案**:
1. 检查 StorageClass 配置
2. 如果使用本地存储（local-path），可能需要手动扩展
3. 考虑迁移到支持扩展的 StorageClass

### 问题 2: PVC 未绑定

**错误信息**:
```
PVC is not bound, cannot expand
```

**解决方案**:
1. 等待 PVC 绑定
2. 检查 StorageClass 配置
3. 检查节点资源

### 问题 3: 扩展后文件系统未更新

**现象**: PVC 已扩展，但 VM 内部 `df -h` 显示大小未变

**解决方案**:
1. 在 VM 内部扩展文件系统（见上文）
2. 检查文件系统类型
3. 确保使用正确的扩展命令

## 最佳实践

### 1. 预留空间

在创建磁盘时，预留一些空间，避免频繁扩展：

```yaml
disks:
  - name: system
    size: 30Gi  # 而不是 20Gi
```

### 2. 监控使用情况

定期检查磁盘使用情况：

```bash
# 在 VM 内部
df -h

# 在 Kubernetes 中
kubectl get pvc
```

### 3. 使用网络存储

对于需要频繁扩展的场景，使用网络存储（NFS、Ceph 等）：

```yaml
disks:
  - name: data
    size: 100Gi
    storageClassName: nfs-storage  # 网络存储
```

### 4. 系统盘和数据盘分离

将系统盘和数据盘分离，便于独立管理：

```yaml
disks:
  - name: system
    size: 20Gi
    boot: true
  - name: data
    size: 100Gi
    boot: false
```

## 总结

| 操作 | 命令 | 说明 |
|------|------|------|
| 扩展磁盘 | `./scripts/expand-disk.sh <wukong> <disk> <size>` | 使用脚本扩展 |
| 编辑配置 | `kubectl edit wukong <name>` | 直接编辑 Wukong |
| 检查状态 | `kubectl get pvc <pvc-name>` | 查看 PVC 状态 |
| 扩展文件系统 | `sudo resize2fs /dev/vda1` | 在 VM 内部扩展 |

**关键点**:
- ✅ 需要 StorageClass 支持扩展
- ✅ PVC 必须已绑定
- ✅ 扩展后需要在 VM 内部扩展文件系统
- ✅ 系统盘和数据盘可以独立扩展


# Longhorn 磁盘和节点要求

## 节点要求

### 1. 硬件要求

| 资源 | 最低要求 | 推荐配置 |
|------|----------|----------|
| **CPU** | 1 核心 | 2+ 核心 |
| **内存** | 1GB | 4GB+ |
| **磁盘空间** | 10GB | 50GB+ |
| **网络** | 1Gbps | 10Gbps（生产环境） |

### 2. 软件要求

- **操作系统**: Linux（Ubuntu 20.04+, CentOS 7+, RHEL 8+）
- **Kubernetes**: 1.21+
- **容器运行时**: containerd, Docker, CRI-O
- **必需工具**: `open-iscsi` 或 `iscsi-initiator-utils`

## 磁盘要求

### 1. 磁盘类型

Longhorn 支持以下磁盘类型：

| 磁盘类型 | 性能 | 适用场景 | 推荐 |
|---------|------|----------|------|
| **SSD** | 高 | 生产环境、高性能需求 | ✅ 推荐 |
| **NVMe** | 极高 | 高性能生产环境 | ✅ 强烈推荐 |
| **HDD** | 低 | 开发测试、归档存储 | ⚠️ 不推荐生产环境 |

### 2. 磁盘空间要求

- **最小空间**: 10GB（仅用于测试）
- **推荐空间**: 50GB+（开发环境）
- **生产环境**: 100GB+（根据实际需求）

### 3. 磁盘路径

Longhorn 默认使用 `/var/lib/longhorn` 作为存储路径。

**注意**:
- 路径必须存在且有写权限
- 建议使用独立的数据盘，而不是系统盘
- 可以使用挂载点（如 `/mnt/longhorn`）

## 配置磁盘选项

### 选项 1: 使用默认路径（系统盘）

**适用场景**: 开发测试环境

```bash
# 使用系统盘上的默认路径
# 路径: /var/lib/longhorn
# 优点: 简单，无需额外配置
# 缺点: 与系统共享磁盘，可能影响性能
```

**配置**:
```bash
# 确保路径存在
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn

# 检查空间
df -h /var/lib/longhorn
```

### 选项 2: 使用独立数据盘（推荐）⭐

**适用场景**: 生产环境

**步骤**:

#### 1. 准备新磁盘

```bash
# 1. 查看可用磁盘
lsblk
# 或
fdisk -l

# 2. 假设新磁盘是 /dev/sdb
# 创建分区
sudo fdisk /dev/sdb
# 在 fdisk 中:
#   - 输入 'n' 创建新分区
#   - 输入 'p' 主分区
#   - 输入 '1' 分区号
#   - 按 Enter 使用默认起始扇区
#   - 按 Enter 使用默认结束扇区
#   - 输入 'w' 写入并退出

# 3. 格式化分区
sudo mkfs.ext4 /dev/sdb1

# 4. 创建挂载点
sudo mkdir -p /mnt/longhorn

# 5. 挂载磁盘
sudo mount /dev/sdb1 /mnt/longhorn

# 6. 设置自动挂载（编辑 /etc/fstab）
echo "/dev/sdb1 /mnt/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab

# 7. 设置权限
sudo chmod 755 /mnt/longhorn
```

#### 2. 配置 Longhorn 使用新路径

**方法 A: 通过 Longhorn UI（推荐）**

```bash
# 1. 访问 Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80

# 2. 在浏览器中访问: http://192.168.1.141:8088
# 3. 进入 Nodes → <node-name> → Disks
# 4. 点击 Add Disk
# 5. 配置:
#    - Path: /mnt/longhorn
#    - Allow Scheduling: true
#    - Storage Reserved: 0 (或根据需要设置)
# 6. 保存
```

**方法 B: 通过 kubectl（命令行）**

```bash
# 1. 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 2. 编辑 Longhorn Node 资源
kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME
```

添加或更新 `disks` 字段：

```yaml
spec:
  disks:
    default-disk:
      allowScheduling: true
      evictionRequested: false
      path: /var/lib/longhorn  # 默认路径
      storageReserved: 0
      tags: []
    data-disk:  # 新数据盘
      allowScheduling: true
      evictionRequested: false
      path: /mnt/longhorn  # 新磁盘路径
      storageReserved: 0
      tags: []
```

**方法 C: 使用脚本（自动化）**

```bash
# 使用项目提供的脚本
./scripts/configure-longhorn-disk.sh /mnt/longhorn
```

### 选项 3: 使用多个磁盘（高性能）

**适用场景**: 高性能生产环境，需要多个磁盘

```bash
# 配置多个磁盘路径
# 例如: /mnt/longhorn-ssd1, /mnt/longhorn-ssd2, /mnt/longhorn-ssd3

# 在 Longhorn UI 中为每个磁盘添加配置
# 或在 Node 资源中添加多个磁盘条目
```

## 磁盘配置最佳实践

### 1. 磁盘选择

- ✅ **使用 SSD**: 提供更好的 I/O 性能
- ✅ **独立数据盘**: 避免与系统盘竞争
- ✅ **足够的空间**: 预留 20-30% 空间用于快照和备份
- ❌ **避免使用系统盘**: 可能影响系统性能

### 2. 路径配置

- ✅ **使用挂载点**: `/mnt/longhorn` 比 `/var/lib/longhorn` 更清晰
- ✅ **设置权限**: `chmod 755` 确保 Longhorn 可以访问
- ✅ **自动挂载**: 配置 `/etc/fstab` 确保重启后自动挂载

### 3. 存储预留

在 Longhorn UI 中配置 `Storage Reserved`:

- **0**: 不预留（默认，推荐）
- **10%**: 预留 10% 空间（推荐用于生产环境）
- **20%**: 预留 20% 空间（保守策略）

## 验证磁盘配置

### 1. 检查磁盘挂载

```bash
# 查看挂载点
df -h | grep longhorn

# 应该看到类似:
# /dev/sdb1  100G  1.0G   99G   1% /mnt/longhorn
```

### 2. 检查 Longhorn Node 配置

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 查看 Node 配置
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"
```

### 3. 检查磁盘状态

```bash
# 在 Longhorn UI 中:
# Nodes → <node-name> → Disks
# 应该看到配置的磁盘，状态为 "Ready"
```

### 4. 测试 PVC 创建

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

### 问题 1: 磁盘空间不足

**症状**: PVC 无法创建，提示空间不足

**解决**:
```bash
# 1. 检查磁盘空间
df -h /mnt/longhorn

# 2. 清理不需要的卷和快照
# 在 Longhorn UI 中删除不需要的卷

# 3. 扩展磁盘（如果可能）
# 或添加新磁盘
```

### 问题 2: 权限问题

**症状**: Longhorn Manager 无法访问磁盘路径

**解决**:
```bash
# 检查权限
ls -la /mnt/longhorn

# 修复权限
sudo chmod 755 /mnt/longhorn
sudo chown root:root /mnt/longhorn
```

### 问题 3: 磁盘未挂载

**症状**: 重启后磁盘未自动挂载

**解决**:
```bash
# 1. 检查 /etc/fstab
cat /etc/fstab | grep longhorn

# 2. 手动挂载
sudo mount /dev/sdb1 /mnt/longhorn

# 3. 验证自动挂载
sudo mount -a
```

### 问题 4: 多个磁盘配置冲突

**症状**: Longhorn 无法识别新磁盘

**解决**:
```bash
# 1. 删除旧的磁盘配置
# 在 Longhorn UI 中删除旧磁盘

# 2. 重新添加磁盘
# 确保路径正确且可访问

# 3. 重启 Longhorn Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

## 快速配置脚本

项目提供了自动化脚本：

```bash
# 1. 配置新数据盘
./scripts/configure-longhorn-disk.sh /mnt/longhorn

# 2. 验证配置
./scripts/verify-longhorn-disk.sh

# 3. 检查磁盘状态
./scripts/check-longhorn-disk-status.sh
```

## 总结

| 配置选项 | 适用场景 | 优点 | 缺点 |
|---------|----------|------|------|
| **默认路径** | 开发测试 | 简单，无需配置 | 与系统共享磁盘 |
| **独立数据盘** | 生产环境 | 性能好，隔离 | 需要额外配置 |
| **多个磁盘** | 高性能生产 | 最高性能 | 配置复杂 |

**推荐配置**:
- ✅ 生产环境: 使用独立 SSD 数据盘，路径 `/mnt/longhorn`
- ✅ 开发测试: 使用默认路径 `/var/lib/longhorn`
- ✅ 预留空间: 10-20% 用于快照和备份

## 下一步

1. **准备磁盘**: 按照上述步骤准备新数据盘
2. **配置 Longhorn**: 使用 UI 或脚本配置磁盘路径
3. **验证配置**: 运行验证脚本确保配置正确
4. **创建测试 PVC**: 验证 Longhorn 可以正常使用新磁盘


# 虚拟机迁移机制

## 概述

在 Kubernetes + KubeVirt 环境中，虚拟机的迁移主要依赖于以下几个方面：

1. **存储迁移**: PVC 可以在不同节点间共享（如果使用网络存储）
2. **VM 实例迁移**: KubeVirt 支持 Live Migration（实时迁移）
3. **节点故障恢复**: 通过重新调度到其他节点

## 迁移类型

### 1. 存储迁移（PVC 迁移）

**前提条件**:
- 使用网络存储（NFS、Ceph、云存储等）
- StorageClass 支持跨节点访问

**迁移方式**:
```bash
# 1. 停止 VM
virtctl stop ubuntu-noble-local-vm

# 2. 删除 VM（不删除 PVC）
kubectl delete vm ubuntu-noble-local-vm

# 3. 在新的节点上重新创建 VM（使用相同的 Wukong）
# Controller 会自动创建 VM，并挂载相同的 PVC
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

**数据保留**:
- ✅ 所有数据（系统盘、数据盘）都保留在 PVC 中
- ✅ 重新创建 VM 时，会挂载相同的 PVC
- ✅ 数据完全保留

### 2. Live Migration（实时迁移）

**前提条件**:
- KubeVirt 已启用 Live Migration
- 使用网络存储（PVC 可以在节点间共享）
- 源节点和目标节点都可用

**迁移方式**:
```bash
# 使用 virtctl 进行实时迁移
virtctl migrate ubuntu-noble-local-vm

# 或指定目标节点
virtctl migrate ubuntu-noble-local-vm --target-node=<node-name>
```

**特点**:
- ✅ VM 在迁移过程中保持运行
- ✅ 几乎零停机时间
- ✅ 需要网络存储支持

### 3. 节点故障恢复

**自动恢复**:
- KubeVirt 会自动检测节点故障
- 如果使用网络存储，VM 会自动在健康节点上重新创建
- 如果使用本地存储，需要手动迁移

**手动恢复**:
```bash
# 1. 检查节点状态
kubectl get nodes

# 2. 如果节点故障，删除 VM（不删除 PVC）
kubectl delete vm ubuntu-noble-local-vm

# 3. Controller 会自动在健康节点上重新创建 VM
```

## 存储类型对迁移的影响

### 网络存储（推荐用于迁移）

**支持的 StorageClass**:
- NFS
- Ceph
- GlusterFS
- 云存储（AWS EBS、Azure Disk、GCP Persistent Disk）

**优势**:
- ✅ PVC 可以在不同节点间共享
- ✅ 支持 Live Migration
- ✅ 节点故障时自动恢复

**示例配置**:
```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: nfs-storage  # 网络存储
    boot: true
```

### 本地存储（限制迁移）

**StorageClass**:
- `local-path` (k3s)
- `hostpath` (Docker Desktop)

**限制**:
- ❌ PVC 绑定到特定节点
- ❌ 不支持 Live Migration
- ❌ 节点故障时数据可能丢失

**迁移方式**:
```bash
# 1. 备份数据（在 VM 内部）
virtctl console ubuntu-noble-local-vm
# 执行备份命令

# 2. 停止 VM
virtctl stop ubuntu-noble-local-vm

# 3. 在新节点上创建新的 PVC
# 4. 恢复数据
```

## 系统盘和数据盘分离的优势

### 设计示例

```yaml
disks:
  # 系统盘：操作系统和系统软件
  - name: system
    size: 20Gi
    storageClassName: local-path
    boot: true
    image: "http://..."
  
  # 数据盘：用户数据
  - name: data
    size: 100Gi
    storageClassName: nfs-storage  # 使用网络存储
    boot: false
```

### 优势

1. **独立迁移**:
   - 系统盘可以保留在本地（快速启动）
   - 数据盘使用网络存储（易于迁移）

2. **独立扩展**:
   - 可以单独扩展数据盘大小
   - 不影响系统盘

3. **独立备份**:
   - 可以单独备份数据盘
   - 系统盘可以快速重建

4. **独立管理**:
   - 数据盘可以挂载到不同的 VM
   - 系统重装时，数据盘数据保留

## 迁移步骤详解

### 场景 1: 使用网络存储的完整迁移

```bash
# 1. 检查当前 VM 状态
kubectl get vm ubuntu-noble-local-vm
kubectl get vmi ubuntu-noble-local-vm

# 2. 检查 PVC 状态
kubectl get pvc | grep ubuntu-noble-local

# 3. 执行 Live Migration（如果支持）
virtctl migrate ubuntu-noble-local-vm

# 或手动迁移：
# 3a. 停止 VM
virtctl stop ubuntu-noble-local-vm

# 3b. 删除 VM（不删除 PVC）
kubectl delete vm ubuntu-noble-local-vm

# 3c. 在新节点上重新创建（Controller 会自动处理）
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

### 场景 2: 本地存储的数据迁移

```bash
# 1. 在 VM 内部备份数据
virtctl console ubuntu-noble-local-vm
# 执行: tar -czf /tmp/backup.tar.gz /data

# 2. 导出备份（通过其他方式，如 SCP、NFS 等）

# 3. 在新节点上创建新的 Wukong（使用网络存储）
kubectl apply -f new-wukong-with-nfs.yaml

# 4. 在新 VM 中恢复数据
virtctl console new-vm
# 执行: tar -xzf /tmp/backup.tar.gz -C /
```

## 迁移检查清单

### 迁移前检查

- [ ] 确认目标节点可用
- [ ] 确认 StorageClass 支持跨节点访问（如果是网络存储）
- [ ] 确认有足够的资源（CPU、内存、存储）
- [ ] 备份重要数据（如果是本地存储）

### 迁移后验证

- [ ] VM 成功启动
- [ ] 所有磁盘正常挂载
- [ ] 网络连接正常
- [ ] 数据完整性验证
- [ ] 应用功能正常

## 最佳实践

### 1. 使用网络存储

**推荐配置**:
```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: nfs-storage  # 网络存储
    boot: true
  - name: data
    size: 100Gi
    storageClassName: nfs-storage  # 网络存储
    boot: false
```

### 2. 系统盘和数据盘分离

**优势**:
- 系统盘可以快速重建
- 数据盘可以独立迁移和管理

### 3. 定期备份

**方法**:
- 使用 VolumeSnapshot（如果 StorageClass 支持）
- 在 VM 内部定期备份
- 使用外部备份工具

### 4. 监控和告警

**监控指标**:
- VM 运行状态
- 节点健康状态
- 存储使用情况
- 网络连接状态

## 故障恢复

### 节点故障

```bash
# 1. 检查节点状态
kubectl get nodes

# 2. 如果节点故障，删除 VM
kubectl delete vm ubuntu-noble-local-vm

# 3. Controller 会自动在健康节点上重新创建
# （如果使用网络存储）
```

### 存储故障

```bash
# 1. 检查 PVC 状态
kubectl get pvc
kubectl describe pvc <pvc-name>

# 2. 如果 PVC 故障，需要从备份恢复
# 3. 或重新创建 PVC 并恢复数据
```

## 总结

| 存储类型 | Live Migration | 节点故障恢复 | 数据持久化 |
|---------|----------------|-------------|-----------|
| 网络存储 | ✅ 支持 | ✅ 自动 | ✅ 是 |
| 本地存储 | ❌ 不支持 | ⚠️ 手动 | ⚠️ 可能丢失 |

**关键点**:
- ✅ 使用网络存储可以实现无缝迁移
- ✅ 系统盘和数据盘分离便于管理
- ✅ Live Migration 提供零停机迁移
- ⚠️ 本地存储需要手动迁移和备份


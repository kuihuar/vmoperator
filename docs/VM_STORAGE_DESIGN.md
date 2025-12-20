# VM 存储设计说明

## 存储架构概述

### 当前设计

Wukong VM 使用 Kubernetes PersistentVolume (PV) 和 PersistentVolumeClaim (PVC) 来提供持久化存储。

```
Wukong Spec
  └─> Disks 配置
       └─> Controller 创建 PVC/DataVolume
            └─> StorageClass 分配 PV
                 └─> 实际存储（节点磁盘）
                      └─> VM 挂载为虚拟磁盘
```

## 存储流程

### 1. 用户定义磁盘

在 Wukong 资源中定义：

```yaml
spec:
  disks:
    - name: system        # 系统盘
      size: 20Gi
      storageClassName: local-path
      boot: true
      image: "http://..." # 可选：从镜像创建
    - name: data         # 数据盘
      size: 100Gi
      storageClassName: local-path
```

### 2. Controller 创建存储资源

Controller 会根据配置创建：

- **如果指定了 `image`**: 创建 `DataVolume`（CDI）
  - DataVolume 会导入镜像到 PVC
  - 导入完成后，PVC 绑定到 PV
  
- **如果未指定 `image`**: 直接创建 `PVC`
  - PVC 等待绑定到 PV

### 3. StorageClass 分配存储

StorageClass（如 `local-path`）会根据配置分配实际的存储：

- **local-path**: 存储到节点的 `/var/local-path-provisioner/` 目录
- **hostpath**: 存储到节点的 `/var/lib/rancher/k3s/storage/` 目录
- **其他 StorageClass**: 根据配置（如 NFS、云存储等）

### 4. VM 挂载磁盘

KubeVirt 将 PVC 挂载为 VM 的虚拟磁盘：

```yaml
spec:
  template:
    spec:
      domain:
        devices:
          disks:
            - name: system
              disk:
                bus: virtio
      volumes:
        - name: system
          persistentVolumeClaim:
            claimName: ubuntu-noble-local-system
```

## 数据持久化机制

### 1. 系统盘（boot disk）

**位置**: PVC 名称格式为 `<wukong-name>-<disk-name>`

**示例**:
- Wukong: `ubuntu-noble-local`
- 磁盘: `system`
- PVC: `ubuntu-noble-local-system`

**数据存储**:
- 所有系统数据（操作系统、安装的软件、用户数据）都存储在 PVC 中
- PVC 绑定到 PV，PV 映射到节点的实际存储位置

**持久化**:
- ✅ **持久化**: 即使 VM 删除，PVC 和 PV 仍然存在
- ✅ **数据保留**: 重新创建 VM 时，可以挂载同一个 PVC，数据会保留
- ⚠️ **删除行为**: 如果删除 PVC，数据会丢失（取决于 StorageClass 的 reclaimPolicy）

### 2. 数据盘（data disk）

**用途**: 专门用于存储用户数据

**配置示例**:
```yaml
disks:
  - name: system
    size: 20Gi
    boot: true
  - name: data
    size: 100Gi
    boot: false
```

**优势**:
- 系统盘和数据盘分离
- 可以独立扩展、备份、迁移数据盘
- 系统重装时，数据盘数据可以保留

## 实际存储位置

### k3s + local-path StorageClass

**存储位置**: `/var/local-path-provisioner/pvc-<uuid>/`

**查看方法**:
```bash
# 1. 查看 PVC
kubectl get pvc ubuntu-noble-local-system

# 2. 查看 PV
kubectl get pv

# 3. 查看 PV 详情，找到实际路径
kubectl get pv <pv-name> -o yaml | grep path

# 4. 在节点上查看（需要 root 权限）
sudo ls -la /var/local-path-provisioner/
```

### Docker Desktop + hostpath StorageClass

**存储位置**: Docker Desktop 的虚拟磁盘中

**查看方法**:
```bash
# Docker Desktop 的存储位置在虚拟磁盘中
# 通常位于: ~/Library/Containers/com.docker.docker/Data/vms/0/
```

## 用户数据持久化

### 场景 1: 用户在 VM 中安装软件

**流程**:
1. 用户通过 `virtctl console` 或 SSH 登录 VM
2. 在 VM 中安装软件（如 `apt install nginx`）
3. 软件和数据存储在系统盘的 PVC 中
4. **数据持久化**: 即使 VM 停止、删除，PVC 仍然存在，数据保留

**验证**:
```bash
# 1. 在 VM 中安装软件
virtctl console ubuntu-noble-local-vm
# 登录后执行: sudo apt install nginx

# 2. 停止 VM
virtctl stop ubuntu-noble-local-vm

# 3. 删除 VM（不删除 PVC）
kubectl delete vm ubuntu-noble-local-vm

# 4. 重新创建 VM（使用相同的 Wukong，会挂载同一个 PVC）
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml

# 5. 登录 VM 验证
virtctl console ubuntu-noble-local-vm
# nginx 应该还在
```

### 场景 2: 用户创建文件和数据

**流程**:
1. 用户在 VM 中创建文件（如 `/home/ubuntu/data.txt`）
2. 文件存储在系统盘的 PVC 中
3. **数据持久化**: 文件会保留在 PVC 中

**验证**:
```bash
# 在 VM 中创建文件
echo "test data" > /home/ubuntu/test.txt

# 停止并重新创建 VM
# 文件应该还在
```

### 场景 3: 使用独立数据盘

**配置**:
```yaml
disks:
  - name: system
    size: 20Gi
    boot: true
  - name: data
    size: 100Gi
    boot: false
```

**优势**:
- 系统盘和数据盘分离
- 可以独立管理、备份、迁移数据盘
- 系统重装时，数据盘数据保留

## 数据管理操作

### 1. 查看存储使用情况

```bash
# 查看 PVC 状态
kubectl get pvc

# 查看 PVC 详情
kubectl describe pvc ubuntu-noble-local-system

# 在 VM 内部查看磁盘使用
virtctl console ubuntu-noble-local-vm
# 执行: df -h
```

### 2. 扩展磁盘大小

**当前限制**: Wukong CRD 还不支持动态扩展磁盘

**手动扩展**:
```bash
# 1. 编辑 PVC
kubectl edit pvc ubuntu-noble-local-system

# 2. 修改 size（需要 StorageClass 支持扩展）
# spec:
#   resources:
#     requests:
#       storage: 50Gi  # 从 20Gi 改为 50Gi

# 3. 在 VM 内部扩展文件系统
virtctl console ubuntu-noble-local-vm
# 执行: sudo growpart /dev/vda 1
# 执行: sudo resize2fs /dev/vda1
```

### 3. 备份数据

**方法 1: 备份 PVC**

```bash
# 1. 停止 VM
virtctl stop ubuntu-noble-local-vm

# 2. 创建 PVC 快照（如果 StorageClass 支持）
kubectl create volumesnapshot ...

# 3. 或直接复制 PVC 数据（需要访问节点）
```

**方法 2: 在 VM 内部备份**

```bash
virtctl console ubuntu-noble-local-vm
# 执行: tar -czf /tmp/backup.tar.gz /home/ubuntu
# 然后通过其他方式导出
```

### 4. 迁移数据

**场景**: 将数据迁移到新的 VM

```bash
# 1. 创建新的 Wukong，使用新的 PVC
# 2. 在旧 VM 中导出数据
# 3. 在新 VM 中导入数据
```

## 存储类（StorageClass）说明

### local-path (k3s 默认)

**特点**:
- 使用节点本地存储
- 数据存储在 `/var/local-path-provisioner/`
- 适合开发环境
- ⚠️ **限制**: 数据绑定到特定节点，节点故障可能导致数据丢失

### hostpath

**特点**:
- 使用节点本地存储
- 数据存储在节点的指定路径
- 适合单节点环境

### 生产环境推荐

**云存储**:
- AWS EBS
- Azure Disk
- GCP Persistent Disk

**网络存储**:
- NFS
- Ceph
- GlusterFS

**分布式存储**:
- Ceph
- Longhorn
- Rook

## 数据持久化保证

### ✅ 数据会保留的情况

1. **VM 停止**: 数据保留在 PVC 中
2. **VM 删除**: 如果只删除 VM，PVC 仍然存在，数据保留
3. **VM 重建**: 使用相同的 Wukong 配置，会挂载同一个 PVC，数据保留
4. **节点重启**: 数据保留在节点的存储中

### ⚠️ 数据可能丢失的情况

1. **删除 PVC**: 数据会丢失（取决于 StorageClass 的 reclaimPolicy）
2. **节点故障**: 如果使用本地存储（local-path），节点故障可能导致数据丢失
3. **StorageClass 清理**: 某些 StorageClass 可能会自动清理未使用的 PV

## 最佳实践

### 1. 系统盘和数据盘分离

```yaml
disks:
  - name: system
    size: 20Gi
    boot: true
  - name: data
    size: 100Gi
    boot: false
```

### 2. 定期备份

- 使用 VolumeSnapshot（如果支持）
- 在 VM 内部定期备份重要数据
- 使用外部备份工具

### 3. 使用可靠的 StorageClass

- 生产环境使用网络存储或云存储
- 避免使用单节点本地存储

### 4. 监控存储使用

```bash
# 监控 PVC 使用情况
kubectl get pvc
kubectl describe pvc

# 在 VM 内部监控
df -h
du -sh /home/*
```

## 总结

| 操作 | 数据持久化 | 说明 |
|------|-----------|------|
| VM 停止 | ✅ 是 | 数据保留在 PVC 中 |
| VM 删除 | ✅ 是 | PVC 仍然存在，数据保留 |
| VM 重建 | ✅ 是 | 挂载同一个 PVC，数据保留 |
| PVC 删除 | ❌ 否 | 数据会丢失 |
| 节点故障（本地存储） | ⚠️ 可能 | 取决于存储类型 |

**关键点**:
- ✅ 用户在 VM 中安装的软件和创建的数据都存储在 PVC 中
- ✅ 数据持久化在 Kubernetes 的 PV 中
- ✅ 即使 VM 删除重建，只要 PVC 存在，数据就会保留
- ⚠️ 删除 PVC 会导致数据丢失
- ⚠️ 使用本地存储时，节点故障可能导致数据丢失


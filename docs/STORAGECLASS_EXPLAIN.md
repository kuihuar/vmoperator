# StorageClass 详解

## 📋 什么是 StorageClass？

**StorageClass** 是 Kubernetes 中定义**存储类型**的资源，它告诉 Kubernetes：
- 使用什么存储系统（如本地存储、网络存储、云存储）
- 如何创建和管理持久卷（PersistentVolume）
- 存储的性能特性（如 SSD、HDD）

## 🎯 storageClassName: docker-desktop 的含义

### 在 Docker Desktop 环境中

`docker-desktop` 是 **Docker Desktop 的 Kubernetes** 提供的默认 StorageClass。

### 作用

当你在 Wukong 中指定 `storageClassName: docker-desktop` 时：

```yaml
disks:
  - name: system
    size: 30Gi
    storageClassName: docker-desktop  # ← 这里
    boot: true
```

Kubernetes 会：
1. 使用 `docker-desktop` StorageClass 创建 PVC
2. 根据 StorageClass 的配置创建 PersistentVolume
3. 将存储绑定到 PVC

## 🔍 查看可用的 StorageClass

### 查看所有 StorageClass

```bash
kubectl get storageclass
```

**典型输出**（Docker Desktop）:
```
NAME             PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
docker-desktop   docker.io/hostpath   Delete        Immediate           false                  10d
```

### 查看详细信息

```bash
kubectl describe storageclass docker-desktop
```

**输出示例**:
```
Name:            docker-desktop
IsDefaultClass:  Yes
Annotations:     storageclass.kubernetes.io/is-default-class=true
Provisioner:     docker.io/hostpath
Parameters:      <none>
AllowVolumeExpansion:  false
MountOptions:    <none>
ReclaimPolicy:  Delete
VolumeBindingMode:  Immediate
Events:          <none>
```

## 📝 StorageClass 字段说明

| 字段 | 说明 | docker-desktop 的值 |
|------|------|---------------------|
| **Provisioner** | 存储提供者 | `docker.io/hostpath` |
| **ReclaimPolicy** | 回收策略 | `Delete`（删除 PVC 时自动删除 PV） |
| **VolumeBindingMode** | 绑定模式 | `Immediate`（立即绑定） |
| **AllowVolumeExpansion** | 允许扩容 | `false`（不允许） |

## 🎯 为什么使用 docker-desktop？

### 1. Docker Desktop 默认提供

Docker Desktop 的 Kubernetes 自动创建 `docker-desktop` StorageClass，无需额外配置。

### 2. 使用本地存储

`docker-desktop` 使用 **hostpath** 提供者，将数据存储在：
- **Mac**: `/var/lib/docker/volumes/` 或 Docker Desktop 的虚拟磁盘中
- **Windows**: Docker Desktop 的虚拟磁盘中

### 3. 适合开发测试

- ✅ 简单易用
- ✅ 无需额外配置
- ✅ 适合开发环境

## 🔧 其他常见的 StorageClass

### 1. local-path（k3s 常用）

```yaml
storageClassName: local-path
```

**特点**:
- k3s 默认提供
- 使用节点本地路径
- 适合单节点或开发环境

### 2. 云存储（生产环境）

```yaml
# AWS EBS
storageClassName: gp3

# Azure Disk
storageClassName: managed-premium

# GCE Persistent Disk
storageClassName: standard
```

### 3. 网络存储（如华美存储）

```yaml
storageClassName: huamei-sc-ssd
```

**特点**:
- 分布式存储
- 高可用
- 适合生产环境

## ⚙️ 如何选择合适的 StorageClass？

### 开发环境（Docker Desktop）

```yaml
storageClassName: docker-desktop  # ✅ 推荐
```

### k3s 环境

```yaml
storageClassName: local-path  # ✅ 推荐
```

### 生产环境

```yaml
storageClassName: huamei-sc-ssd  # 或你的存储系统
```

## 🔍 检查你的环境

### 1. 查看可用的 StorageClass

```bash
kubectl get storageclass
```

### 2. 查看默认 StorageClass

```bash
kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

### 3. 如果不指定 storageClassName

如果 Wukong 中不指定 `storageClassName`，Kubernetes 会：
- 使用**默认的 StorageClass**（如果有）
- 如果没有默认 StorageClass，PVC 会一直处于 `Pending` 状态

## 📝 在 Wukong 中使用

### 示例 1: Docker Desktop 环境

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
spec:
  disks:
    - name: system
      size: 30Gi
      storageClassName: docker-desktop  # Docker Desktop 默认
      boot: true
```

### 示例 2: k3s 环境

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
spec:
  disks:
    - name: system
      size: 30Gi
      storageClassName: local-path  # k3s 默认
      boot: true
```

### 示例 3: 生产环境（华美存储）

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
spec:
  disks:
    - name: system
      size: 80Gi
      storageClassName: huamei-sc-ssd  # 华美存储 SSD
      boot: true
    - name: data
      size: 500Gi
      storageClassName: huamei-sc-hdd  # 华美存储 HDD
      boot: false
```

## 🐛 常见问题

### 问题 1: PVC 一直处于 Pending

**症状**:
```bash
kubectl get pvc
NAME      STATUS    VOLUME   CAPACITY
system    Pending                                   
```

**原因**:
- StorageClass 不存在
- 存储系统未配置
- 资源不足

**解决**:
```bash
# 1. 检查 StorageClass 是否存在
kubectl get storageclass

# 2. 如果不存在，创建或使用其他 StorageClass
# 修改 Wukong 配置中的 storageClassName

# 3. 检查存储系统状态
kubectl get pods -n <storage-namespace>
```

### 问题 2: 存储空间不足

**症状**:
```
Events:
  Warning  ProvisioningFailed  persistentvolume-controller  storage quota exceeded
```

**解决**:
- 清理未使用的 PVC
- 增加存储空间
- 使用其他 StorageClass

### 问题 3: 存储性能问题

**症状**: VM 运行缓慢，I/O 性能差

**解决**:
- 使用 SSD StorageClass（如果可用）
- 检查存储系统配置
- 优化存储参数

## ✅ 验证 StorageClass 配置

### 测试创建 PVC

```bash
# 创建测试 PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: docker-desktop
  resources:
    requests:
      storage: 1Gi
EOF

# 检查状态
kubectl get pvc test-pvc

# 清理
kubectl delete pvc test-pvc
```

## 📚 相关资源

- [Kubernetes StorageClass 文档](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Docker Desktop 存储](https://docs.docker.com/desktop/kubernetes/)
- [k3s 存储](https://docs.k3s.io/storage)

## 🎯 总结

| 环境 | 推荐 StorageClass | 说明 |
|------|------------------|------|
| **Docker Desktop** | `docker-desktop` | 默认提供，使用本地存储 |
| **k3s** | `local-path` | 默认提供，使用节点本地路径 |
| **生产环境** | 根据存储系统 | 如 `huamei-sc-ssd` |

**关键点**:
- `storageClassName` 指定使用哪个存储系统
- `docker-desktop` 是 Docker Desktop 的默认 StorageClass
- 必须确保 StorageClass 存在，否则 PVC 无法绑定

---

**提示**: 如果不确定使用哪个 StorageClass，先运行 `kubectl get storageclass` 查看可用的选项。


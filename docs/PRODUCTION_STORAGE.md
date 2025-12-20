# 生产环境存储方案

## 问题分析

### k3s 默认 StorageClass 的限制

k3s 默认的 `local-path` StorageClass 有以下限制：

1. **不支持卷扩展**: `allowVolumeExpansion: false`
2. **本地存储**: 数据绑定到特定节点，节点故障可能导致数据丢失
3. **不适合生产**: 缺乏高可用性和数据保护

### 生产环境需求

- ✅ 支持卷扩展
- ✅ 高可用性（跨节点）
- ✅ 数据持久化保证
- ✅ 支持 Live Migration
- ✅ 性能要求

## 解决方案

### 方案 1: 使用 NFS StorageClass（推荐用于中小规模）

#### 优势

- ✅ 支持卷扩展
- ✅ 跨节点共享
- ✅ 支持 Live Migration
- ✅ 配置简单
- ✅ 成本较低

#### 安装步骤

**1. 安装 NFS Server（如果还没有）**

```bash
# 在 NFS 服务器上
sudo apt-get update
sudo apt-get install -y nfs-kernel-server

# 创建共享目录
sudo mkdir -p /mnt/nfs-share
sudo chown nobody:nogroup /mnt/nfs-share
sudo chmod 777 /mnt/nfs-share

# 配置导出
echo "/mnt/nfs-share *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

**2. 安装 NFS Client Provisioner**

```bash
# 使用 Helm 安装
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=<nfs-server-ip> \
  --set nfs.path=/mnt/nfs-share \
  --set storageClass.defaultClass=true
```

**3. 验证 StorageClass**

```bash
kubectl get storageclass
# 应该看到 nfs-client (default)

kubectl get storageclass nfs-client -o yaml | grep allowVolumeExpansion
# 应该输出: allowVolumeExpansion: true
```

**4. 在 Wukong 中使用**

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: nfs-client  # 使用 NFS StorageClass
    boot: true
  - name: data
    size: 100Gi
    storageClassName: nfs-client
    boot: false
```

### 方案 2: 使用 Longhorn（推荐用于 k3s 生产环境）

#### 优势

- ✅ 专为 k3s 设计
- ✅ 支持卷扩展
- ✅ 分布式块存储
- ✅ 自动备份和快照
- ✅ 高可用性
- ✅ 易于管理

#### 安装步骤

**1. 安装 Longhorn**

```bash
# 使用 kubectl 安装
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 等待安装完成
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```

**2. 配置 Longhorn StorageClass**

Longhorn 会自动创建 StorageClass，默认支持卷扩展。

**3. 验证**

```bash
kubectl get storageclass longhorn
kubectl get storageclass longhorn -o yaml | grep allowVolumeExpansion
# 应该输出: allowVolumeExpansion: true
```

**4. 在 Wukong 中使用**

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 100Gi
    storageClassName: longhorn
    boot: false
```

### 方案 3: 使用 Ceph (Rook)（推荐用于大规模生产环境）

#### 优势

- ✅ 企业级分布式存储
- ✅ 支持卷扩展
- ✅ 高可用性和数据保护
- ✅ 支持多种存储类型（块、文件、对象）
- ✅ 自动故障恢复

#### 安装步骤

**1. 安装 Rook Operator**

```bash
git clone --single-branch --branch v1.13.0 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
```

**2. 创建 Ceph Cluster**

```bash
kubectl create -f cluster.yaml
```

**3. 创建 StorageClass**

```bash
kubectl create -f csi/rbd/storageclass.yaml
```

**4. 在 Wukong 中使用**

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: rook-ceph-block
    boot: true
```

### 方案 4: 使用云存储（AWS EBS、Azure Disk、GCP Persistent Disk）

#### 优势

- ✅ 完全托管
- ✅ 自动备份
- ✅ 高可用性
- ✅ 支持卷扩展
- ✅ 按需付费

#### 配置示例（AWS EBS）

**1. 安装 AWS EBS CSI Driver**

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.28"
```

**2. 创建 StorageClass**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

**3. 在 Wukong 中使用**

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: ebs-sc
    boot: true
```

## 产品化存储设计

### 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                    Wukong Operator                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  系统盘       │  │  数据盘 1     │  │  数据盘 2     │ │
│  │  (20Gi)      │  │  (100Gi)     │  │  (50Gi)      │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Kubernetes Storage Layer                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   PVC        │  │   PVC        │  │   PVC        │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│            StorageClass (生产环境)                        │
│  • Longhorn (k3s 推荐)                                   │
│  • NFS (中小规模)                                        │
│  • Ceph/Rook (大规模)                                    │
│  • 云存储 (AWS/Azure/GCP)                                │
└─────────────────────────────────────────────────────────┘
```

### 存储策略

#### 1. 系统盘和数据盘分离

```yaml
disks:
  # 系统盘：使用快速存储（SSD）
  - name: system
    size: 20Gi
    storageClassName: fast-ssd  # 高性能 StorageClass
    boot: true
  
  # 数据盘：使用标准存储
  - name: data
    size: 100Gi
    storageClassName: standard  # 标准 StorageClass
    boot: false
```

#### 2. 多存储层

```yaml
# 高性能层（系统盘、数据库）
storageClassName: fast-ssd

# 标准层（应用数据）
storageClassName: standard

# 归档层（日志、备份）
storageClassName: archive
```

#### 3. 自动扩展策略

```yaml
# 在 Wukong 中支持自动扩展配置
spec:
  disks:
    - name: data
      size: 100Gi
      storageClassName: longhorn
      autoExpand: true  # 未来可以支持
      maxSize: 500Gi   # 最大扩展大小
```

## 实施建议

### 阶段 1: 开发/测试环境

**使用**: k3s 默认 `local-path`

```yaml
disks:
  - name: system
    size: 5Gi
    storageClassName: local-path
    boot: true
```

**特点**:
- 简单快速
- 适合开发测试
- 不支持扩展

### 阶段 2: 预生产环境

**使用**: Longhorn 或 NFS

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn  # 或 nfs-client
    boot: true
  - name: data
    size: 100Gi
    storageClassName: longhorn
    boot: false
```

**特点**:
- 支持扩展
- 跨节点共享
- 适合预生产验证

### 阶段 3: 生产环境

**使用**: Ceph/Rook 或云存储

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: rook-ceph-block
    boot: true
  - name: data
    size: 100Gi
    storageClassName: rook-ceph-block
    boot: false
```

**特点**:
- 企业级存储
- 高可用性
- 自动备份和恢复

## 代码改进建议

### 1. 添加 StorageClass 验证

在 Controller 中验证 StorageClass 是否支持扩展：

```go
// pkg/storage/expand.go
func ValidateStorageClassForExpansion(ctx context.Context, c client.Client, storageClassName string) (bool, error) {
    sc := &storagev1.StorageClass{}
    key := client.ObjectKey{Name: storageClassName}
    if err := c.Get(ctx, key, sc); err != nil {
        return false, err
    }
    return sc.AllowVolumeExpansion != nil && *sc.AllowVolumeExpansion, nil
}
```

### 2. 添加存储策略配置

在 Wukong CRD 中添加存储策略：

```go
// api/v1alpha1/wukong_types.go
type DiskConfig struct {
    // ... existing fields ...
    
    // StoragePolicy defines storage policy (fast, standard, archive)
    // +optional
    StoragePolicy string `json:"storagePolicy,omitempty"`
    
    // AutoExpand enables automatic expansion when disk usage exceeds threshold
    // +optional
    AutoExpand bool `json:"autoExpand,omitempty"`
    
    // MaxSize is the maximum size for auto-expansion
    // +optional
    MaxSize string `json:"maxSize,omitempty"`
}
```

### 3. 添加存储监控

集成 Prometheus 监控存储使用情况：

```go
// 监控 PVC 使用率
// 当使用率超过阈值时，自动触发扩展
```

## 迁移方案

### 从 local-path 迁移到 Longhorn

**步骤**:

1. **安装 Longhorn**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
   ```

2. **创建新的 Wukong（使用 Longhorn）**
   ```yaml
   disks:
     - name: system
       size: 20Gi
       storageClassName: longhorn
       boot: true
   ```

3. **迁移数据**（在 VM 内部）
   ```bash
   # 在旧 VM 中备份数据
   tar -czf /tmp/backup.tar.gz /data
   
   # 在新 VM 中恢复数据
   tar -xzf /tmp/backup.tar.gz -C /
   ```

## 总结

| 方案 | 适用场景 | 支持扩展 | 高可用 | 复杂度 | 成本 |
|------|---------|---------|--------|--------|------|
| local-path | 开发/测试 | ❌ | ❌ | 低 | 低 |
| NFS | 中小规模 | ✅ | ✅ | 中 | 中 |
| **Longhorn** | **k3s 生产（推荐）** | ✅ | ✅ | 中 | 中 |
| Ceph/Rook | 大规模 | ✅ | ✅ | 高 | 高 |
| 云存储 | 云环境 | ✅ | ✅ | 低 | 按需 |

**推荐方案**:
- **开发/测试**: `local-path`（k3s 默认）
- **生产环境（k3s）**: **`Longhorn`（已选择）** ⭐
- **大规模生产**: `Ceph/Rook` 或云存储

**当前选择**: Longhorn - 专为 k3s 设计，支持卷扩展，提供高可用性和数据保护。

**关键点**:
- ✅ 生产环境必须使用支持扩展的 StorageClass
- ✅ 系统盘和数据盘分离设计
- ✅ 根据场景选择合适的存储方案
- ✅ 考虑高可用性和数据保护


# Ceph (Rook) 安装指南

本文档详细说明如何在 k3s 集群上使用 Rook 安装和配置 Ceph 存储。

## 目录

- [前置要求](#前置要求)
- [安装步骤](#安装步骤)
- [配置选项](#配置选项)
- [存储设备准备](#存储设备准备)
- [验证安装](#验证安装)
- [启用 Dashboard](#启用-dashboard)
- [常见问题](#常见问题)
- [配置注意事项](#配置注意事项)

---

## 前置要求

### 1. 系统要求

- **k3s**: >= 1.24（已安装并运行）
- **kubectl**: 已配置并可以访问集群
- **Helm**: >= 3.0（可选，推荐）
- **存储设备**: 
  - 生产环境：至少一个未格式化的裸设备（如 `/dev/sdb`）
  - 开发/测试：至少 50GB 可用磁盘空间

### 2. 设备要求

#### 生产环境（推荐）

- **裸设备**: 未格式化的块设备（如 `/dev/sdb`）
- **设备大小**: 建议至少 100GB
- **设备状态**: 未被挂载、未被使用、无文件系统

#### 开发/测试环境

- **目录存储**: 可以使用目录作为存储（性能较低）
- **磁盘空间**: 至少 50GB 可用空间

### 3. 检查清单

在开始安装前，请确认：

- [ ] k3s 集群运行正常
- [ ] kubectl 可以访问集群
- [ ] 存储设备已准备好（生产环境）
- [ ] 有足够的磁盘空间（开发/测试环境）

---

## 安装步骤

### 方法 1: 使用安装脚本（推荐）

```bash
# 运行安装脚本
sudo ./scripts/install-ceph-rook.sh
```

脚本会自动：
1. 检查前置条件
2. 配置 Helm Repository（如果使用 Helm）
3. 创建命名空间
4. 安装 Rook Operator
5. 创建 CephCluster
6. 安装 CSI Driver
7. 创建 StorageClass

### 方法 2: 手动安装

#### 步骤 1: 配置 Helm Repository

```bash
helm repo add rook-release https://charts.rook.io/release
helm repo update
```

#### 步骤 2: 创建命名空间

```bash
kubectl create namespace rook-ceph
```

#### 步骤 3: 安装 Rook Operator

**使用 Helm（推荐）:**

```bash
helm install rook-ceph rook-release/rook-ceph \
  --namespace rook-ceph \
  --set operatorNamespace=rook-ceph \
  --wait \
  --timeout 10m
```

**使用 kubectl apply:**

```bash
# 安装 CRDs
kubectl apply -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/crds.yaml

# 安装 Common manifests
kubectl apply -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/common.yaml

# 安装 Operator
kubectl apply -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/operator.yaml
```

#### 步骤 4: 等待 Operator 就绪

```bash
kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=600s
```

#### 步骤 5: 创建 CephCluster

根据你的需求选择配置方式（见 [配置选项](#配置选项)）。

#### 步骤 6: 等待 Ceph 集群就绪

```bash
# 等待集群状态变为 Ready
kubectl wait --for=condition=ready cephcluster rook-ceph -n rook-ceph --timeout=600s

# 或手动检查
kubectl get cephcluster -n rook-ceph
```

#### 步骤 7: 创建 StorageClass

```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
```

---

## 配置选项

### 选项 1: 使用指定设备（生产环境，推荐）

适用于有独立数据盘的场景（如 `/dev/sdb`）。

**配置示例:**

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1  # 单节点使用 1 个 mon
  storage:
    useAllNodes: false
    useAllDevices: false
    nodes:
    - name: "host1"  # 替换为你的节点名称
      devices:
      - name: "sdb"  # 设备名称（不含 /dev/ 前缀）
      config:
        databaseSizeMB: "1024"
        journalSizeMB: "1024"
```

**注意事项:**
- 设备必须是未格式化的裸设备
- 设备名称使用 `sdb` 而不是 `/dev/sdb`
- 确保设备未被挂载或使用

### 选项 2: 使用所有可用设备

适用于有多个未使用设备的场景。

**配置示例:**

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1
  storage:
    useAllNodes: true
    useAllDevices: true
    config:
      databaseSizeMB: "1024"
      journalSizeMB: "1024"
```

**注意事项:**
- 会使用所有未格式化的设备
- 确保没有重要数据在设备上
- 生产环境谨慎使用

### 选项 3: 使用目录存储（开发/测试）

适用于开发/测试环境，不需要独立数据盘。

**配置示例:**

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1
  storage:
    useAllNodes: false
    useAllDevices: false
    nodes:
    - name: "host1"
      directories:
      - path: "/var/lib/rook/ceph-data"
      config:
        databaseSizeMB: "1024"
        journalSizeMB: "1024"
```

**注意事项:**
- 性能较低，不适合生产环境
- 需要确保目录有足够空间
- 目录会自动创建

---

## 存储设备准备

### 检查设备状态

```bash
# 1. 列出所有块设备
lsblk

# 2. 检查设备信息
sudo fdisk -l /dev/sdb

# 3. 检查设备是否被挂载
mount | grep sdb

# 4. 检查设备是否被使用
sudo lsof /dev/sdb

# 5. 检查设备文件系统
sudo blkid /dev/sdb
```

### 准备裸设备

如果设备已被格式化，需要清除文件系统：

```bash
# ⚠️ 警告：这会删除设备上的所有数据！

# 方法 1: 使用 wipefs（推荐）
sudo wipefs -a /dev/sdb

# 方法 2: 使用 dd（更彻底，但更慢）
sudo dd if=/dev/zero of=/dev/sdb bs=1M count=100

# 验证设备已清除
sudo blkid /dev/sdb  # 应该没有输出
```

### 验证设备可用性

```bash
# 运行检查脚本
sudo ./scripts/check-ceph-storage-device.sh
```

---

## 验证安装

### 1. 检查 Ceph 集群状态

```bash
# 查看 CephCluster 状态
kubectl get cephcluster -n rook-ceph

# 查看详细状态
kubectl get cephcluster rook-ceph -n rook-ceph -o yaml
```

**预期输出:**
- `PHASE`: `Ready`
- `HEALTH`: `HEALTH_OK` 或 `HEALTH_WARN`（单节点可能是 WARN）

### 2. 检查 Pods 状态

```bash
# 查看所有 Rook-Ceph Pods
kubectl get pods -n rook-ceph

# 检查关键组件
kubectl get pods -n rook-ceph -l app=rook-ceph-operator
kubectl get pods -n rook-ceph -l app=rook-ceph-osd
kubectl get pods -n rook-ceph -l app=rook-ceph-mon
```

**预期状态:**
- Operator: `Running`
- OSD: `Running`（至少 1 个）
- Mon: `Running`（至少 1 个）

### 3. 检查存储设备使用情况

```bash
# 检查设备是否被 Ceph 使用
sudo lsof /dev/sdb | grep ceph-osd

# 检查设备文件系统类型
sudo blkid /dev/sdb
# 应该显示: TYPE="ceph_bluestore"
```

### 4. 检查 StorageClass

```bash
# 查看 StorageClass
kubectl get storageclass

# 查看详细信息
kubectl describe storageclass rook-ceph-block
```

### 5. 测试 PVC 创建

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
  storageClassName: rook-ceph-block
  resources:
    requests:
      storage: 1Gi
EOF

# 检查 PVC 状态
kubectl get pvc test-pvc

# 清理测试
kubectl delete pvc test-pvc
```

---

## 启用 Dashboard

Ceph 提供了 Web UI（类似 Longhorn），可以通过 Dashboard 管理集群。

### 检查 Dashboard 状态

```bash
./scripts/check-ceph-dashboard.sh
```

### 启用 Dashboard

```bash
./scripts/enable-ceph-dashboard.sh
```

### 访问 Dashboard

#### 方法 1: 端口转发（推荐）

```bash
# 启用端口转发
kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443

# 浏览器访问
# https://localhost:8443
```

#### 方法 2: NodePort

```bash
# 修改 Service 为 NodePort
kubectl patch svc rook-ceph-mgr-dashboard -n rook-ceph -p '{"spec":{"type":"NodePort"}}'

# 查看端口
kubectl get svc -n rook-ceph rook-ceph-mgr-dashboard

# 访问（使用节点 IP 和 NodePort）
# https://<节点IP>:<NodePort>
```

### 获取登录凭据

```bash
# 获取用户名
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{.data.user}" | base64 --decode && echo

# 获取密码
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{.data.password}" | base64 --decode && echo
```

---

## 常见问题

### 1. CSI Plugin 无法启动（rbd 模块错误）

**错误信息:**
```
modprobe: ERROR: could not insert 'rbd': Exec format error
```

**原因:**
- 容器内的内核模块与主机内核不兼容
- DaemonSet 未挂载主机的 `/lib/modules`

**解决方案:**
- 检查主机 rbd 模块: `ls /lib/modules/$(uname -r)/kernel/drivers/block/rbd.ko*`
- 如果模块存在，检查 CSI DaemonSet 是否挂载了 `/lib/modules`
- 如果问题持续，考虑使用 CephFS 而不是 RBD

### 2. OSD Pod 无法启动

**检查步骤:**
```bash
# 查看 OSD Pod 日志
kubectl logs -n rook-ceph -l app=rook-ceph-osd --tail=50

# 检查设备是否可用
sudo lsof /dev/sdb

# 检查设备权限
ls -l /dev/sdb
```

**常见原因:**
- 设备已被使用
- 设备权限不足
- 设备已有文件系统

### 3. Ceph 集群健康状态为 WARN

**单节点环境:**
- 单节点部署时，`HEALTH_WARN` 是正常的
- 这是因为 Ceph 推荐至少 3 个节点以获得最佳性能
- 功能不受影响

**多节点环境:**
- 检查 OSD 数量是否足够
- 检查网络连接
- 使用 tools Pod 查看详细状态

### 4. 存储设备未被使用

**验证方法:**
```bash
# 检查设备是否被 ceph-osd 使用
sudo lsof /dev/sdb | grep ceph-osd

# 检查设备文件系统类型
sudo blkid /dev/sdb
# 应该显示: TYPE="ceph_bluestore"
```

**如果设备未被使用:**
- 检查 CephCluster 配置是否正确
- 检查设备是否在配置的设备列表中
- 查看 Rook Operator 日志

---

## 配置注意事项

### 1. 存储设备选择

#### 生产环境

- ✅ **推荐**: 使用独立的未格式化裸设备（如 `/dev/sdb`）
- ✅ **优势**: 性能最佳，数据隔离
- ⚠️ **注意**: 设备必须未格式化，无文件系统

#### 开发/测试环境

- ✅ **可选**: 使用目录存储
- ⚠️ **注意**: 性能较低，不适合生产

### 2. Mon 节点数量

- **单节点集群**: `count: 1`
- **多节点集群**: `count: 3`（推荐）或 `count: 5`（大规模）

### 3. 数据目录

- **默认路径**: `/var/lib/rook`
- **作用**: 存储 Ceph 元数据（配置、日志等）
- **大小**: 通常很小（几十 MB）
- **注意**: 实际数据存储在 OSD 设备上，不在这个目录

### 4. Ceph 版本

- **当前使用**: `quay.io/ceph/ceph:v18.2.0` (Ceph Pacific)
- **更新**: 可以修改 `spec.cephVersion.image` 来使用其他版本
- **注意**: 版本升级需要谨慎，建议先测试

### 5. StorageClass 配置

#### 默认配置

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
reclaimPolicy: Delete
allowVolumeExpansion: true
```

#### 关键参数

- **clusterID**: 必须与 CephCluster 名称匹配
- **pool**: 存储池名称（默认 `replicapool`）
- **reclaimPolicy**: `Delete`（删除 PVC 时删除数据）或 `Retain`（保留数据）
- **allowVolumeExpansion**: 是否允许扩容

### 6. 单节点限制

在单节点环境中：

- ✅ **功能**: 所有功能都可用
- ⚠️ **性能**: 性能可能不如多节点集群
- ⚠️ **高可用**: 无高可用性（单点故障）
- ⚠️ **健康状态**: 可能显示 `HEALTH_WARN`（正常）

### 7. 网络要求

- **集群内部通信**: Ceph 组件需要能够互相通信
- **端口**: 
  - Mon: 6789
  - OSD: 6800-7300
  - MGR: 9283 (Dashboard)

### 8. 资源要求

#### 最小资源

- **CPU**: 2 核
- **内存**: 4GB
- **存储**: 50GB（开发/测试）或 100GB+（生产）

#### 推荐资源

- **CPU**: 4+ 核
- **内存**: 8GB+
- **存储**: 200GB+（生产环境）

---

## 验证脚本

项目提供了多个验证脚本：

```bash
# 检查存储设备
sudo ./scripts/check-ceph-storage-device.sh

# 验证设备使用情况
sudo ./scripts/verify-ceph-using-sdb.sh

# 检查 Dashboard
./scripts/check-ceph-dashboard.sh

# 诊断 CSI 问题
./scripts/diagnose-ceph-csi.sh
```

---

## 相关文档

- [k3s 安装指南](INSTALL_K3S.md)
- [KubeVirt 安装指南](INSTALL_KUBEVIRT.md)
- [完整安装清单](INSTALLATION_CHECKLIST.md)
- [Ceph 存储验证指南](VERIFY_CEPH_STORAGE.md) - **重要：创建 VM 前请先验证**

---

## 参考资源

- [Rook 官方文档](https://rook.io/docs/rook/latest/)
- [Ceph 官方文档](https://docs.ceph.com/)
- [Rook GitHub](https://github.com/rook/rook)

---

**最后更新**: 2024-12-22  
**维护者**: VM Operator Team


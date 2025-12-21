# Ceph 存储配置指南

使用 Rook 在 k3s 上部署 Ceph 存储集群。

## 概述

Rook 是 Kubernetes 原生的 Ceph 编排器，可以：
- 在 Kubernetes 中自动部署 Ceph 集群
- 管理 Ceph 存储池和配置
- 提供 Ceph-CSI 驱动用于 Kubernetes 持久化存储

## 安装方式

### 方法 1: 使用安装脚本（推荐）

```bash
./scripts/install-ceph-rook.sh
```

脚本会自动：
1. 安装 Rook Operator
2. 创建 Ceph Cluster
3. 安装 Ceph CSI Driver
4. 创建 StorageClass

### 方法 2: 使用 Helm 安装

```bash
# 1. 添加 Helm Repository
helm repo add rook-release https://charts.rook.io/release
helm repo update

# 2. 安装 Rook Operator
helm install rook-ceph rook-release/rook-ceph \
    --namespace rook-ceph \
    --create-namespace \
    --set operatorNamespace=rook-ceph

# 3. 等待 Operator 就绪
kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s

# 4. 创建 Ceph Cluster
kubectl apply -f config/ceph-cluster.yaml

# 5. 创建 StorageClass
kubectl apply -f config/ceph-storageclass.yaml
```

### 方法 3: 使用 kubectl apply

```bash
# 1. 安装 CRDs
kubectl apply -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/crds.yaml

# 2. 安装 Common manifests
kubectl apply -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/common.yaml

# 3. 安装 Operator
kubectl apply -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/operator.yaml

# 4. 等待 Operator 就绪
kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s

# 5. 创建 Ceph Cluster
kubectl apply -f config/ceph-cluster.yaml

# 6. 创建 StorageClass
kubectl apply -f config/ceph-storageclass.yaml
```

## 配置选项

### 单节点开发/测试环境

使用目录存储（适合开发/测试）：

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  mon:
    count: 1  # 单节点只需要 1 个 monitor
  storage:
    useAllNodes: true
    useAllDevices: false
    directories:
    - path: /var/lib/rook/ceph-data
```

### 多节点生产环境

使用设备存储（适合生产）：

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  mon:
    count: 3  # 生产环境推荐 3 个 monitor
  storage:
    useAllNodes: true
    useAllDevices: true  # 使用所有可用设备
    config:
      databaseSizeMB: "2048"
      journalSizeMB: "2048"
```

## 验证安装

### 检查 Ceph Cluster 状态

```bash
# 查看 Ceph Cluster
kubectl get cephcluster -n rook-ceph

# 查看详细状态
kubectl describe cephcluster rook-ceph -n rook-ceph

# 查看 Pods
kubectl get pods -n rook-ceph
```

### 检查 Ceph 健康状态

```bash
# 使用 Ceph tools pod
kubectl exec -n rook-ceph -it $(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}') -- ceph status

# 查看存储池
kubectl exec -n rook-ceph -it $(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}') -- ceph osd pool ls
```

### 测试 PVC

```bash
# 创建测试 PVC
kubectl apply -f config/ceph-test-pvc.yaml

# 检查 PVC 状态
kubectl get pvc ceph-test-pvc

# 检查 Pod
kubectl get pod ceph-test-pod

# 清理测试
kubectl delete -f config/ceph-test-pvc.yaml
```

## 使用 Ceph 存储

### 创建 PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: rook-ceph-block
```

### 在 Pod 中使用

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

## 设置为默认 StorageClass

```bash
# 设置为默认
kubectl patch storageclass rook-ceph-block -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 取消默认
kubectl patch storageclass rook-ceph-block -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

## 访问 Ceph Dashboard

```bash
# 端口转发
kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443

# 获取登录信息
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo

# 访问: https://localhost:8443
# 用户名: admin
```

## 故障排查

### Pod 无法启动

```bash
# 查看 Pod 日志
kubectl logs -n rook-ceph -l app=rook-ceph-operator
kubectl logs -n rook-ceph -l app=rook-ceph-osd

# 查看事件
kubectl get events -n rook-ceph --sort-by='.lastTimestamp'
```

### PVC 处于 Pending 状态

```bash
# 检查 StorageClass
kubectl get storageclass rook-ceph-block

# 检查 PVC 详情
kubectl describe pvc <pvc-name>

# 检查 CSI Driver Pods
kubectl get pods -n rook-ceph -l app=csi-rbdplugin
```

### Ceph Cluster 不健康

```bash
# 查看 Ceph 状态
kubectl exec -n rook-ceph -it $(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}') -- ceph health detail

# 查看 OSD 状态
kubectl exec -n rook-ceph -it $(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}') -- ceph osd tree
```

## 卸载

```bash
# 1. 删除所有 PVC（如果不再需要数据）
kubectl get pvc --all-namespaces | grep rook-ceph

# 2. 删除 Ceph Cluster
kubectl delete cephcluster rook-ceph -n rook-ceph

# 3. 删除 StorageClass
kubectl delete storageclass rook-ceph-block rook-cephfs

# 4. 卸载 Rook Operator（Helm）
helm uninstall rook-ceph -n rook-ceph

# 或使用 kubectl
kubectl delete -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/operator.yaml
kubectl delete -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/common.yaml
kubectl delete -f https://raw.githubusercontent.com/rook/rook/v1.13.0/deploy/examples/crds.yaml

# 5. 删除命名空间
kubectl delete namespace rook-ceph

# 6. 清理节点数据（在每个节点上）
sudo rm -rf /var/lib/rook
```

## 资源要求

- **CPU**: 至少 2 核心（推荐 4+）
- **内存**: 至少 4GB（推荐 8GB+）
- **存储**: 至少 10GB 可用空间（推荐 50GB+）
- **磁盘**: 如果使用设备存储，需要未格式化的磁盘或分区

## 参考文档

- [Rook 官方文档](https://rook.io/docs/rook/latest/)
- [Ceph 文档](https://docs.ceph.com/)
- [Ceph-CSI 文档](https://github.com/ceph/ceph-csi)


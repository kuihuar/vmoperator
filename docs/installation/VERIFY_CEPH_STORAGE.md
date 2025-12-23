# Ceph 存储验证指南

本文档详细说明如何验证 Ceph 存储配置和 PVC 绑定，以及常见问题的排查方法。

## 目录

- [验证清单](#验证清单)
- [详细验证步骤](#详细验证步骤)
- [PVC 绑定问题排查](#pvc-绑定问题排查)
- [常见问题及解决方案](#常见问题及解决方案)
- [验证脚本](#验证脚本)

---

## 验证清单

在创建使用 Ceph 存储的 VM 之前，请确保以下项目都已正确配置：

- [ ] Ceph 集群状态为 `Ready`
- [ ] OSD Pods 正在运行
- [ ] CSI Provisioner Pods 正在运行
- [ ] CSI Secret 存在且有内容
- [ ] StorageClass 配置了 Secret 引用
- [ ] 节点调度配置正确（单节点环境）

---

## 详细验证步骤

### 1. 验证 Ceph 集群状态

```bash
# 检查 CephCluster 状态
kubectl get cephcluster rook-ceph -n rook-ceph

# 预期输出：
# NAME        DATADIRHOSTPATH   MONCOUNT   AGE   PHASE   HEALTH
# rook-ceph   /var/lib/rook     1          10m   Ready   HEALTH_OK 或 HEALTH_WARN
```

**验证点：**
- `PHASE` 应该是 `Ready`
- `HEALTH` 可以是 `HEALTH_OK` 或 `HEALTH_WARN`（单节点环境 `HEALTH_WARN` 是正常的）

**如果未就绪：**
```bash
# 查看详细状态
kubectl get cephcluster rook-ceph -n rook-ceph -o yaml | grep -A 20 "status:"

# 查看 Rook Operator 日志
kubectl logs -n rook-ceph -l app=rook-ceph-operator --tail=50
```

---

### 2. 验证 OSD Pods

```bash
# 检查 OSD Pods
kubectl get pods -n rook-ceph -l app=rook-ceph-osd

# 预期输出：
# NAME                              READY   STATUS    RESTARTS   AGE
# rook-ceph-osd-0-7fb9cf8dd-69g9q   1/1     Running   0          10m
```

**验证点：**
- 至少有一个 OSD Pod 状态为 `Running`
- `READY` 应该是 `1/1`

**如果没有运行中的 OSD：**
```bash
# 查看 OSD Pod 日志
kubectl logs -n rook-ceph <osd-pod-name>

# 查看 OSD Pod 事件
kubectl describe pod -n rook-ceph <osd-pod-name>
```

---

### 3. 验证存储设备使用情况

```bash
# 检查设备是否被 Ceph 使用
sudo lsof /dev/sdb | grep ceph-osd

# 检查设备文件系统类型
sudo blkid /dev/sdb
# 应该显示: TYPE="ceph_bluestore"
```

**验证点：**
- 设备被 `ceph-osd` 进程使用
- 设备文件系统类型是 `ceph_bluestore`

**验证脚本：**
```bash
sudo ./scripts/verify-ceph-using-sdb.sh
```

---

### 4. 验证 CSI Driver

#### 4.1 检查 CSI Provisioner Pods

```bash
# 检查 CSI Provisioner Pods
kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner

# 预期输出：
# NAME                                      READY   STATUS    RESTARTS   AGE
# csi-rbdplugin-provisioner-5cbdfbdf5c-xxx  5/5     Running   0          10m
```

**验证点：**
- 至少有一个 Provisioner Pod 状态为 `Running`
- `READY` 应该是 `5/5`（5 个容器都就绪）

**如果未运行：**
```bash
# 查看 Provisioner Pod 日志
kubectl logs -n rook-ceph <provisioner-pod> -c csi-rbdplugin-provisioner --tail=50

# 查看 Pod 事件
kubectl describe pod -n rook-ceph <provisioner-pod>
```

#### 4.2 检查 CSI Driver CRD

```bash
# 检查 CSI Driver
kubectl get csidriver rook-ceph.rbd.csi.ceph.com

# 预期输出：
# NAME                           ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
# rook-ceph.rbd.csi.ceph.com     true             false            false             <unset>         false                Persistent   10m
```

**验证点：**
- CSI Driver 存在
- `MODES` 应该是 `Persistent`

---

### 5. 验证 CSI Secret

```bash
# 检查 CSI Secret 是否存在
kubectl get secret rook-csi-rbd-provisioner -n rook-ceph

# 检查 Secret 内容（应该包含以下 keys）
kubectl get secret rook-csi-rbd-provisioner -n rook-ceph -o jsonpath='{.data}' | jq 'keys'

# 预期输出：
# [
#   "clusterID",
#   "monValue",
#   "userID",
#   "userKey"
# ]
```

**验证点：**
- Secret 存在
- Secret 包含 `userID`、`userKey`、`clusterID`、`monValue` 四个 keys
- Secret 内容不为空

**如果 Secret 不存在或为空：**
```bash
# 运行修复脚本
sudo ./scripts/fix-ceph-csi-secret.sh
```

---

### 6. 验证 StorageClass

```bash
# 检查 StorageClass
kubectl get storageclass rook-ceph-block

# 查看详细配置
kubectl get storageclass rook-ceph-block -o yaml
```

**验证点：**
- StorageClass 存在
- `provisioner` 是 `rook-ceph.rbd.csi.ceph.com`
- `parameters` 中包含以下 Secret 配置：
  - `csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner`
  - `csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph`
  - `csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner`
  - `csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph`
  - `csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-provisioner`
  - `csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph`
  - `csi.storage.k8s.io/node-publish-secret-name: rook-csi-rbd-provisioner`
  - `csi.storage.k8s.io/node-publish-secret-namespace: rook-ceph`

**如果 StorageClass 未配置 Secret：**
```bash
# 删除并重新创建 StorageClass
kubectl delete storageclass rook-ceph-block
./scripts/create-storageclass-with-secret.sh
```

---

### 7. 验证节点调度配置（单节点环境）

```bash
# 检查节点 Labels
kubectl get nodes --show-labels | grep kubevirt

# 应该看到：
# kubevirt.io/schedulable=true
```

**验证点：**
- 节点有 `kubevirt.io/schedulable=true` label

**如果没有：**
```bash
# 添加 label
./scripts/fix-kubevirt-single-node.sh
```

---

### 8. 验证 PVC 绑定

```bash
# 检查所有 PVC 状态
kubectl get pvc --all-namespaces

# 预期输出：
# NAMESPACE   NAME                      STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS      AGE
# default     ubuntu-ceph-test-system   Bound    pvc-xxx  5Gi        RWO            rook-ceph-block   5m
# default     ubuntu-ceph-test-data     Bound    pvc-xxx  2Gi        RWO            rook-ceph-block   5m
```

**验证点：**
- PVC 状态是 `Bound`
- `VOLUME` 列有值（PV 名称）
- `STORAGECLASS` 是 `rook-ceph-block`

**如果 PVC 未绑定：**
```bash
# 查看 PVC 详细事件
kubectl describe pvc <pvc-name>

# 查看相关 PV
kubectl get pv
```

---

## PVC 绑定问题排查

### 问题 1: PVC 状态为 Pending

**症状：**
```
NAME                      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS      AGE
ubuntu-ceph-test-system   Pending                                      rook-ceph-block   10m
```

**排查步骤：**

1. **查看 PVC 事件：**
```bash
kubectl describe pvc ubuntu-ceph-test-system | grep -A 20 "Events:"
```

2. **检查常见错误：**
   - `provided secret is empty` → 需要创建 CSI Secret
   - `provisioning failed` → 检查 CSI Provisioner 日志
   - `waiting for a volume to be created` → 检查 Ceph 集群状态

3. **运行诊断脚本：**
```bash
./scripts/diagnose-pvc-unbound.sh
./scripts/check-ceph-csi-provisioner.sh
```

---

### 问题 2: Secret is Empty 错误

**错误信息：**
```
failed to provision volume with StorageClass "rook-ceph-block": 
rpc error: code = InvalidArgument desc = provided secret is empty
```

**解决方案：**

1. **运行修复脚本：**
```bash
sudo ./scripts/fix-ceph-csi-secret.sh
```

2. **手动创建 Secret：**
```bash
# 获取 Ceph 认证信息
CEPH_USER=$(kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data.ceph-username}' | base64 -d)
CEPH_KEY=$(kubectl get secret rook-ceph-mon -n rook-ceph -o jsonpath='{.data.ceph-secret}' | base64 -d)
CEPH_MON_ENDPOINTS=$(kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph -o jsonpath='{.data.data}')

# 创建 Secret
kubectl create secret generic rook-csi-rbd-provisioner \
  --from-literal=userID="${CEPH_USER:-admin}" \
  --from-literal=userKey="$CEPH_KEY" \
  --from-literal=clusterID="rook-ceph" \
  --from-literal=monValue="$CEPH_MON_ENDPOINTS" \
  -n rook-ceph \
  --dry-run=client -o yaml | kubectl apply -f -
```

3. **更新 StorageClass：**
```bash
# 删除并重新创建 StorageClass
kubectl delete storageclass rook-ceph-block
./scripts/create-storageclass-with-secret.sh
```

---

### 问题 3: CSI Provisioner 未运行

**症状：**
- PVC 一直处于 `Pending` 状态
- 没有 PV 被创建

**排查步骤：**

1. **检查 Provisioner Pods：**
```bash
kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner
```

2. **如果 Pod 未运行，查看日志：**
```bash
kubectl logs -n rook-ceph <provisioner-pod> -c csi-rbdplugin-provisioner --tail=50
```

3. **常见原因：**
   - Ceph 集群未就绪
   - CSI Secret 不存在或为空
   - 资源不足

---

### 问题 4: Ceph 集群未就绪

**症状：**
- CephCluster 状态不是 `Ready`
- OSD Pods 未运行

**解决方案：**

1. **检查 Ceph 集群状态：**
```bash
kubectl get cephcluster rook-ceph -n rook-ceph
```

2. **等待集群就绪：**
```bash
kubectl wait --for=condition=ready cephcluster rook-ceph -n rook-ceph --timeout=600s
```

3. **检查 OSD Pods：**
```bash
kubectl get pods -n rook-ceph -l app=rook-ceph-osd
kubectl logs -n rook-ceph <osd-pod-name>
```

---

## 常见问题及解决方案

### Q1: StorageClass 无法更新 parameters

**错误：**
```
The StorageClass "rook-ceph-block" is invalid: 
parameters: Forbidden: updates to parameters are forbidden.
```

**解决方案：**
StorageClass 的 `parameters` 字段不允许更新，需要删除并重新创建：

```bash
# 删除现有 StorageClass
kubectl delete storageclass rook-ceph-block

# 重新创建（使用脚本）
./scripts/create-storageclass-with-secret.sh
```

---

### Q2: Pod 无法调度（unbound PVC）

**错误：**
```
0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims.
```

**解决方案：**

1. **先修复 PVC 绑定问题**（参考上面的排查步骤）

2. **删除并重新创建 PVC：**
```bash
# 删除未绑定的 PVC
kubectl delete pvc <pvc-name>

# 重新创建（Wukong Controller 会自动重新创建）
# 或手动重新应用 Wukong 资源
kubectl delete wukong ubuntu-ceph-test
kubectl apply -f config/samples/vm_v1alpha1_wukong_ceph_test.yaml
```

---

### Q3: Tools Pod 镜像版本

**问题**: Tools Pod 应该使用什么镜像版本？

**答案**: 
- Tools Pod 镜像版本必须与 Rook Operator 版本一致
- Rook Operator v1.13.0 → Tools Pod: `rook/ceph:v1.13.0`
- 不要使用 `quay.io/ceph/ceph:v18.2.0`（这是原生 Ceph 镜像，用于 CephCluster，不用于 Tools Pod）

**版本对应关系：**
| Rook Operator 版本 | Tools Pod 镜像 | Ceph 版本（CephCluster） |
|-------------------|---------------|------------------------|
| v1.13.0 | `rook/ceph:v1.13.0` | `quay.io/ceph/ceph:v18.2.0` |

---

### Q4: 如何验证数据是否存储在数据盘上

**验证步骤：**

1. **检查设备使用情况：**
```bash
sudo lsof /dev/sdb | grep ceph-osd
sudo blkid /dev/sdb
# 应该显示: TYPE="ceph_bluestore"
```

2. **使用验证脚本：**
```bash
sudo ./scripts/verify-ceph-using-sdb.sh
```

3. **检查 Ceph 存储使用情况（如果 tools Pod 可用）：**
```bash
kubectl exec -n rook-ceph rook-ceph-tools -- ceph df
kubectl exec -n rook-ceph rook-ceph-tools -- ceph osd df tree
```

---

## 验证脚本

项目提供了多个验证脚本：

### 1. 完整诊断脚本

```bash
# 诊断 PVC 未绑定问题
./scripts/diagnose-pvc-unbound.sh

# 检查 CSI Provisioner 状态
./scripts/check-ceph-csi-provisioner.sh

# 验证 Ceph 使用数据盘
sudo ./scripts/verify-ceph-using-sdb.sh
```

### 2. 修复脚本

```bash
# 修复 CSI Secret 问题
sudo ./scripts/fix-ceph-csi-secret.sh

# 修复单节点调度
./scripts/fix-kubevirt-single-node.sh

# 修复 PVC 未绑定问题
./scripts/fix-pvc-unbound.sh
```

### 3. 一键验证脚本

```bash
# 检查 Ceph 存储设备
sudo ./scripts/check-ceph-storage-device.sh

# 检查 Ceph 完整状态
./scripts/check-ceph-status.sh
```

---

## 验证流程

### 创建 VM 前的验证流程

1. **基础验证：**
```bash
# 1. 检查 Ceph 集群
kubectl get cephcluster rook-ceph -n rook-ceph

# 2. 检查 OSD
kubectl get pods -n rook-ceph -l app=rook-ceph-osd

# 3. 检查 CSI Provisioner
kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner

# 4. 检查 Secret
kubectl get secret rook-csi-rbd-provisioner -n rook-ceph

# 5. 检查 StorageClass
kubectl get storageclass rook-ceph-block -o yaml | grep -A 2 "provisioner-secret-name"
```

2. **如果发现问题，运行修复脚本：**
```bash
sudo ./scripts/fix-ceph-csi-secret.sh
```

3. **创建 VM 后验证：**
```bash
# 检查 PVC 状态
kubectl get pvc

# 检查 PV 状态
kubectl get pv

# 检查 VM 状态
kubectl get wukong,vm,vmi
```

---

## 快速检查命令

```bash
# 一键检查所有关键组件
echo "=== Ceph 集群 ==="
kubectl get cephcluster -n rook-ceph

echo "=== OSD Pods ==="
kubectl get pods -n rook-ceph -l app=rook-ceph-osd

echo "=== CSI Provisioner ==="
kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner

echo "=== CSI Secret ==="
kubectl get secret rook-csi-rbd-provisioner -n rook-ceph

echo "=== StorageClass ==="
kubectl get storageclass rook-ceph-block

echo "=== PVC 状态 ==="
kubectl get pvc

echo "=== PV 状态 ==="
kubectl get pv
```

---

## 相关文档

- [Ceph 安装指南](INSTALL_CEPH_ROOK.md)
- [安装清单](INSTALLATION_CHECKLIST.md)
- [KubeVirt 安装指南](INSTALL_KUBEVIRT.md)

---

**最后更新**: 2024-12-22  
**维护者**: VM Operator Team


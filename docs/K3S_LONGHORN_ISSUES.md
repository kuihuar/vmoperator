# k3s 安装 Longhorn 常见问题汇总

## 概述

本文档汇总了在 k3s 环境中安装和使用 Longhorn 存储系统时遇到的所有常见问题，并提供相应的解决方案。每个问题都按照**问题描述**、**原因分析**、**解决方案**和**验证步骤**的结构组织。

---

## 📋 问题分类索引

### 🔴 安装前问题
1. [缺少 open-iscsi 依赖](#问题1-缺少-open-iscsi-依赖)
2. [节点资源不足](#问题2-节点资源不足)
3. [存储路径配置问题](#问题3-存储路径配置问题)

### 🟠 安装过程问题
4. [longhorn-manager CrashLoopBackOff](#问题4-longhorn-manager-crashloopbackoff)
5. [longhorn-driver-deployer 卡在 Init:0/1](#问题5-longhorn-driver-deployer-卡在-init01)
6. [CSI Driver 未安装](#问题6-csi-driver-未安装)

### 🟡 安装后问题
7. [PVC 一直处于 Pending 状态](#问题7-pvc-一直处于-pending-状态)
8. [磁盘 UUID 不匹配](#问题8-磁盘-uuid-不匹配)
9. [单节点环境配置问题](#问题9-单节点环境配置问题)
10. [网络连接问题](#问题10-网络连接问题)
11. [磁盘空间不足](#问题11-磁盘空间不足)

### 🟢 运行时问题
12. [卷扩展失败](#问题12-卷扩展失败)
13. [备份失败](#问题13-备份失败)
14. [性能问题](#问题14-性能问题)

---

## 🔴 安装前问题

### 问题 1: 缺少 open-iscsi 依赖

**问题描述**:
```
在安装 Longhorn 之前，节点必须安装 open-iscsi 或 iscsi-initiator-utils
```

**原因分析**:
- Longhorn 使用 iSCSI 协议管理存储卷
- k3s 默认不会安装这个依赖
- 每个节点都必须安装并启动 iscsid 服务

**解决方案**:

#### Ubuntu/Debian 系统:
```bash
# SSH 到节点
ssh user@node-ip

# 安装 open-iscsi
sudo apt-get update
sudo apt-get install -y open-iscsi

# 启动并启用服务
sudo systemctl enable iscsid
sudo systemctl start iscsid

# 验证安装
iscsiadm --version
sudo systemctl status iscsid
```

#### CentOS/RHEL/Rocky 系统:
```bash
# SSH 到节点
ssh user@node-ip

# 安装 iscsi-initiator-utils
sudo yum install -y iscsi-initiator-utils
# 或对于较新版本
sudo dnf install -y iscsi-initiator-utils

# 启动并启用服务
sudo systemctl enable iscsid
sudo systemctl start iscsid

# 验证安装
iscsiadm --version
sudo systemctl status iscsid
```

#### Fedora 系统:
```bash
sudo dnf install -y iscsi-initiator-utils
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

**验证步骤**:
```bash
# 在所有节点上验证
for node in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
  echo "检查节点: $node"
  ssh user@$node "iscsiadm --version && sudo systemctl is-active iscsid"
done
```

**参考文档**: 
- [LONGHORN_PREREQUISITES.md](LONGHORN_PREREQUISITES.md)
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md#21-安装-open-iscsi必需)

---

### 问题 2: 节点资源不足

**问题描述**:
```
节点 CPU 或内存资源不足，导致 Longhorn 组件无法正常运行
```

**原因分析**:
- Longhorn Manager 需要一定的 CPU 和内存资源
- 如果节点资源不足，Pod 可能无法调度或频繁重启

**解决方案**:

#### 检查节点资源:
```bash
# 查看节点资源使用情况
kubectl top nodes

# 查看节点详细资源信息
kubectl describe nodes

# 查看 Longhorn 组件资源请求
kubectl get pods -n longhorn-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests}{"\n"}{end}'
```

#### 资源优化:
```bash
# 如果资源不足，可以：
# 1. 增加节点资源（添加更多 CPU/内存）
# 2. 减少其他工作负载
# 3. 在较小的节点上调整 Longhorn 资源限制（不推荐）
```

**最小资源要求**:
- CPU: 1 核心（推荐 2+ 核心）
- 内存: 1GB（推荐 4GB+）
- 磁盘: 10GB（推荐 50GB+）

**参考文档**: 
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md#1-系统要求)

---

### 问题 3: 存储路径配置问题

**问题描述**:
```
存储路径不存在、不可写或权限不正确
```

**原因分析**:
- Longhorn 需要在节点上有可写的存储路径
- 默认路径是 `/var/lib/longhorn`
- 如果路径不存在或权限不正确，Manager 无法启动

**解决方案**:

#### 使用默认路径:
```bash
# 在每个节点上执行
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn

# 检查磁盘空间
df -h /var/lib/longhorn
```

#### 使用自定义路径（推荐生产环境）:
```bash
# 1. 准备独立数据盘（例如 /dev/sdb）
lsblk

# 2. 格式化磁盘
sudo parted -s /dev/sdb mklabel gpt
sudo parted -s /dev/sdb mkpart primary ext4 0% 100%
sudo mkfs.ext4 -F /dev/sdb1

# 3. 创建挂载点
sudo mkdir -p /mnt/longhorn

# 4. 挂载磁盘
sudo mount /dev/sdb1 /mnt/longhorn

# 5. 配置自动挂载
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID /mnt/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab

# 6. 设置权限
sudo chmod 755 /mnt/longhorn
```

**验证步骤**:
```bash
# 检查路径是否存在且可写
[ -d "/var/lib/longhorn" ] && [ -w "/var/lib/longhorn" ] && echo "✓ 默认路径就绪" || echo "❌ 路径问题"
# 或
[ -d "/mnt/longhorn" ] && [ -w "/mnt/longhorn" ] && echo "✓ 自定义路径就绪" || echo "❌ 路径问题"
```

**参考文档**: 
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md#22-准备存储磁盘可选但推荐)
- [LONGHORN_DISK_REQUIREMENTS.md](LONGHORN_DISK_REQUIREMENTS.md)

---

## 🟠 安装过程问题

### 问题 4: longhorn-manager CrashLoopBackOff

**问题描述**:
```
longhorn-manager Pod 一直重启，状态为 CrashLoopBackOff
```

**常见错误信息**:
```
# 错误 1: 缺少 open-iscsi（最常见）
Error starting manager: Failed environment check, please make sure you have iscsiadm/open-iscsi installed on the host

# 错误 2: Admission Webhook 不可用
Error starting webhooks: admission webhook service is not accessible on cluster after 2m0s sec: timed out waiting for endpoint https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/healthz to be available
```

**原因分析**:
1. **缺少 open-iscsi**（最常见）⭐
2. **Admission Webhook 服务不可用**（较常见）⭐
   - `longhorn-admission-webhook` Service 没有 Endpoints
   - Webhook Pod 未运行或未就绪
   - Webhook 服务启动顺序问题
3. 节点资源不足
4. 存储路径配置问题
5. 节点标签缺失
6. 权限问题

**解决方案**:

#### 步骤 1: 检查日志
```bash
# 获取 Manager Pod 名称
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')

# 查看日志
kubectl logs -n longhorn-system $MANAGER_POD --tail=100

# 查看 Pod 详情
kubectl describe pod -n longhorn-system $MANAGER_POD
```

#### 步骤 2: 根据错误类型选择解决方案

**如果是缺少 open-iscsi 错误**，参考[问题 1: 缺少 open-iscsi 依赖](#问题1-缺少-open-iscsi-依赖)的解决方案

**如果是 Admission Webhook 不可用错误**，继续下面的步骤：

##### 步骤 2.1: 检查 admission-webhook Service 和 Pod
```bash
# 检查 Service
kubectl get svc -n longhorn-system longhorn-admission-webhook

# 检查 Endpoints（关键）
kubectl get endpoints -n longhorn-system longhorn-admission-webhook

# 检查 Webhook Pod
kubectl get pods -n longhorn-system -l app=longhorn-admission-webhook

# 查看 Webhook Pod 日志
kubectl logs -n longhorn-system -l app=longhorn-admission-webhook --tail=50
```

##### 步骤 2.2: 如果 Webhook Pod 未运行或不存在，检查原因

**如果 Pod 不存在（您当前的情况）**，需要检查 DaemonSet/Deployment：

```bash
# 检查是否有 DaemonSet 或 Deployment
kubectl get daemonset,deployment -n longhorn-system | grep admission-webhook

# 检查是否有 ReplicaSet（Deployment 会创建 ReplicaSet）
kubectl get replicaset -n longhorn-system | grep admission

# 检查所有相关资源
kubectl get all -n longhorn-system | grep admission

# 如果有 DaemonSet/Deployment，查看详情
if kubectl get daemonset -n longhorn-system longhorn-admission-webhook &>/dev/null; then
    echo "=== DaemonSet 详情 ==="
    kubectl describe daemonset -n longhorn-system longhorn-admission-webhook
elif kubectl get deployment -n longhorn-system longhorn-admission-webhook &>/dev/null; then
    echo "=== Deployment 详情 ==="
    kubectl describe deployment -n longhorn-system longhorn-admission-webhook
fi

# 查看相关事件
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | grep admission-webhook | tail -20
```

**如果根本没有 DaemonSet/Deployment**，可能是 Longhorn 安装不完整，需要重新安装（参考步骤 2.5）。

**如果 Pod 存在但未运行**：

```bash
# 查看 Pod 详情
WEBHOOK_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-admission-webhook -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$WEBHOOK_POD" ]; then
    kubectl describe pod -n longhorn-system $WEBHOOK_POD
fi

# 查看 Pod 事件
kubectl get events -n longhorn-system --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | grep admission-webhook
```

##### 步骤 2.3: 等待或修复 Webhook Pod
```bash
# 如果 Webhook Pod 正在启动，等待它就绪
kubectl wait --for=condition=ready pod -l app=longhorn-admission-webhook -n longhorn-system --timeout=300s

# 如果 Webhook Pod 有问题，删除它让其重建
kubectl delete pod -n longhorn-system -l app=longhorn-admission-webhook

# 等待 Endpoints 创建
for i in {1..60}; do
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [ -n "$ENDPOINTS" ]; then
        echo "✓ Admission Webhook Endpoints 已创建: $ENDPOINTS"
        break
    fi
    echo "等待中... ($i/60)"
    sleep 2
done
```

##### 步骤 2.4: 如果 Webhook Pod 一直失败，检查依赖
```bash
# Webhook 可能也依赖 open-iscsi，检查是否安装
# 参考步骤 2.1（如果是 open-iscsi 问题）

# 或者检查 Webhook 的特定错误
kubectl logs -n longhorn-system -l app=longhorn-admission-webhook --tail=100
```

##### 步骤 2.5: 如果 Webhook Pod/DaemonSet/Deployment 完全不存在（需要重新安装）

**这是最严重的情况，表示 Longhorn 安装不完整**。

**诊断**：
```bash
# 检查所有 Longhorn 资源
kubectl get all -n longhorn-system

# 检查 Longhorn 安装状态
kubectl get pods -n longhorn-system

# 检查是否有其他关键资源缺失
kubectl get crd | grep longhorn
```

**解决方案**：

**选项 1: 重新安装 Longhorn（推荐）**
```bash
# 参考重新安装指南
# 文档: docs/LONGHORN_REINSTALL_GUIDE.md

# 快速重新安装步骤：
# 1. 卸载现有 Longhorn
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 2. 等待清理完成
sleep 60

# 3. 重新安装
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 4. 等待所有组件就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s
kubectl wait --for=condition=ready pod -l app=longhorn-admission-webhook -n longhorn-system --timeout=300s
```

**选项 2: 检查安装版本并手动补全缺失资源（高级用户）**
```bash
# 1. 确定 Longhorn 版本
kubectl get deployment -n longhorn-system longhorn-manager -o jsonpath='{.spec.template.spec.containers[0].image}'

# 2. 获取完整清单
LONGHORN_VERSION="v1.6.0"  # 根据实际情况修改
curl -s https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml > /tmp/longhorn.yaml

# 3. 提取 admission-webhook 相关资源并应用
# 需要仔细检查资源定义
```

#### 步骤 3: 修复后重启 Manager
```bash
# 在所有节点安装 open-iscsi 后，重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager

# 等待 Pod 重建
kubectl get pods -n longhorn-system -l app=longhorn-manager -w
```

**验证步骤**:
```bash
# 等待 Manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 检查状态
kubectl get pods -n longhorn-system -l app=longhorn-manager
# 应该看到: longhorn-manager-xxx   1/1     Running
```

**参考文档**: 
- [FIX_LONGHORN_ISSUES.md](FIX_LONGHORN_ISSUES.md#问题-1-longhorn-manager-crashloopbackoff)
- [FIX_DRIVER_DEPLOYER_INIT.md](FIX_DRIVER_DEPLOYER_INIT.md)

---

### 问题 5: longhorn-driver-deployer 卡在 Init:0/1

**问题描述**:
```
longhorn-driver-deployer Pod 一直卡在 Init:0/1 状态，无法完成初始化
```

**原因分析**:
- `driver-deployer` 的 Init Container `wait-for-backend` 在等待 `longhorn-backend` API 返回 HTTP 200
- 常见原因：
  1. **longhorn-backend Service 没有 Endpoints**（最常见）
     - Manager Pod 未运行
     - Manager Pod 未就绪
     - Manager 无法绑定 9500 端口
  2. 网络连接问题
  3. Manager API 未就绪

**解决方案**:

#### 方法 1: 使用深度诊断脚本（推荐）
```bash
# 自动诊断
./scripts/deep-diagnose-driver-deployer.sh

# 或指定 Pod 名称
./scripts/deep-diagnose-driver-deployer.sh longhorn-driver-deployer-xxx
```

#### 方法 2: 手动诊断和修复

**步骤 1: 检查 driver-deployer 状态**
```bash
# 查看 Pod 状态
kubectl get pod -n longhorn-system -l app=longhorn-driver-deployer

# 查看详细状态
kubectl describe pod -n longhorn-system -l app=longhorn-driver-deployer
```

**步骤 2: 查看 Init Container 日志**
```bash
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n longhorn-system $DEPLOYER_POD -c wait-for-backend
```

**步骤 3: 检查 longhorn-backend Service**
```bash
# 检查 Service
kubectl get svc -n longhorn-system longhorn-backend

# 检查 Endpoints（关键）
kubectl get endpoints -n longhorn-system longhorn-backend

# 如果 Endpoints 为空 → Manager Pod 未运行或未就绪
# 如果 Endpoints 有值 → 继续检查网络连接
```

**步骤 4: 检查 Manager Pods**
```bash
# 检查 Manager Pods
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 查看 Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 如果 Manager 未运行，先修复 Manager（参考问题 4）
```

**步骤 5: 等待 Manager 就绪并重启 driver-deployer**
```bash
# 等待 Manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 等待 Endpoints 创建
for i in {1..60}; do
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-backend -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [ -n "$ENDPOINTS" ]; then
        echo "✓ Endpoints 已创建"
        break
    fi
    echo "等待中... ($i/60)"
    sleep 2
done

# 重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

**验证步骤**:
```bash
# 检查 driver-deployer 状态（应该为 Succeeded）
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer

# 检查 CSI Driver（应该已创建）
kubectl get csidriver driver.longhorn.io
```

**参考文档**: 
- [FIX_DRIVER_DEPLOYER_INIT.md](FIX_DRIVER_DEPLOYER_INIT.md)
- [LONGHORN_BACKEND_WAIT.md](LONGHORN_BACKEND_WAIT.md)
- [DRIVER_DEPLOYER_WAIT.md](DRIVER_DEPLOYER_WAIT.md)

---

### 问题 6: CSI Driver 未安装

**问题描述**:
```
kubectl get csidriver 返回空，或 PVC 创建时提示找不到 CSI Driver
```

**原因分析**:
- `longhorn-driver-deployer` 未完成
- `driver-deployer` 失败或卡住
- 依赖组件未就绪

**解决方案**:

#### 步骤 1: 检查 driver-deployer 状态
```bash
# 检查 Pod 状态
kubectl get pods -n longhorn-system | grep driver-deployer

# 查看日志
kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true --tail=50
```

#### 步骤 2: 修复 driver-deployer
如果 driver-deployer 卡在 Init:0/1，参考[问题 5](#问题5-longhorn-driver-deployer-卡在-init01)的解决方案

#### 步骤 3: 如果失败，重新部署
```bash
# 删除 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer

# 等待重建并查看日志
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -w
```

**验证步骤**:
```bash
# 检查 CSI Driver
kubectl get csidriver driver.longhorn.io

# 应该看到:
# NAME                  ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
# driver.longhorn.io    true             false            true              <unset>         false               Persistent    Xm

# 检查 CSI 组件
kubectl get pods -n longhorn-system | grep csi

# 应该看到:
# - longhorn-csi-attacher-*
# - longhorn-csi-provisioner-*
# - longhorn-csi-resizer-*
# - longhorn-csi-plugin-* (每个节点一个)
```

**参考文档**: 
- [CSI_DRIVER_EXPLAIN.md](CSI_DRIVER_EXPLAIN.md)
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md#问题-5-csi-driver-未安装)

---

## 🟡 安装后问题

### 问题 7: PVC 一直处于 Pending 状态

**问题描述**:
```
创建的 PVC 一直处于 Pending 状态，无法绑定到 PV
```

**原因分析**:
1. Longhorn Node 没有磁盘配置
2. 磁盘未就绪
3. 存储空间不足
4. StorageClass 配置问题

**解决方案**:

#### 步骤 1: 检查 PVC 状态
```bash
# 查看 PVC 详情
kubectl describe pvc <pvc-name>

# 查看事件
kubectl get events --field-selector involvedObject.name=<pvc-name> --sort-by='.lastTimestamp'
```

#### 步骤 2: 检查 Longhorn Node 磁盘配置
```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 检查磁盘配置
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"

# 如果没有配置，需要配置磁盘
```

#### 步骤 3: 配置磁盘
```bash
# 使用脚本配置（推荐）
./scripts/configure-longhorn-disk.sh /mnt/longhorn

# 或手动配置
DISK_PATH="/mnt/longhorn"  # 或 "/var/lib/longhorn"
DISK_NAME="data-disk"
if [ "$DISK_PATH" = "/var/lib/longhorn" ]; then
    DISK_NAME="default-disk"
fi

kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p "{
  \"spec\": {
    \"disks\": {
      \"$DISK_NAME\": {
        \"allowScheduling\": true,
        \"evictionRequested\": false,
        \"path\": \"$DISK_PATH\",
        \"storageReserved\": 0,
        \"tags\": []
      }
    }
  }
}"

# 等待磁盘就绪
for i in {1..60}; do
    DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o jsonpath="{.status.diskStatus.$DISK_NAME.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
    if [ "$DISK_STATUS" = "True" ]; then
        echo "✓ 磁盘已就绪"
        break
    fi
    echo "等待中... ($i/60)"
    sleep 2
done
```

#### 步骤 4: 检查存储空间
```bash
# 在节点上检查
df -h /mnt/longhorn  # 或 /var/lib/longhorn
```

**验证步骤**:
```bash
# 检查 PVC 状态（应该变为 Bound）
kubectl get pvc <pvc-name>

# 检查对应的 PV
kubectl get pv
```

**参考文档**: 
- [FIX_PVC_PENDING.md](FIX_PVC_PENDING.md)
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md#问题-3-pvc-一直-pending)

---

### 问题 8: 磁盘 UUID 不匹配

**问题描述**:
```
错误信息: Disk data-disk(/mnt/longhorn) on node host1 is not ready: record diskUUID doesn't match the one on the disk
```

**原因分析**:
- 磁盘被重新格式化，UUID 发生变化
- Longhorn 记录的磁盘 UUID 与实际磁盘 UUID 不匹配

**解决方案**:

#### 使用修复脚本（推荐）
```bash
# 使用项目脚本修复
./scripts/fix-longhorn-disk-uuid.sh /mnt/longhorn
```

#### 手动修复步骤

**步骤 1: 查看当前磁盘 UUID**
```bash
# 在节点上查看磁盘 UUID
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "磁盘 UUID: $UUID"
```

**步骤 2: 查看 Longhorn 记录的 UUID**
```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 10 "diskUUID"
```

**步骤 3: 更新磁盘配置**
```bash
# 方法 1: 删除磁盘配置后重新添加（推荐）
# 先备份数据（如果有重要数据）
# 然后删除磁盘配置
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type json -p='[
  {"op": "remove", "path": "/spec/disks/data-disk"}
]'

# 等待清理后重新添加
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

**验证步骤**:
```bash
# 检查磁盘状态（应该变为 Ready）
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o jsonpath='{.status.diskStatus.data-disk.conditions[?(@.type=="Ready")].status}'
# 应该输出: True
```

**参考文档**: 
- [FIX_DISK_UUID_MISMATCH.md](FIX_DISK_UUID_MISMATCH.md)
- [fix-longhorn-disk-uuid.sh](../scripts/fix-longhorn-disk-uuid.sh)

---

### 问题 9: 单节点环境配置问题

**问题描述**:
```
单节点 k3s 环境中，Longhorn 要求至少 3 个副本，导致无法创建卷
```

**原因分析**:
- Longhorn 默认需要 3 个副本以实现高可用
- 单节点环境无法满足 3 个副本的要求
- 需要将默认副本数设置为 1

**解决方案**:

#### 方法 1: 通过 kubectl 配置（推荐）
```bash
# 设置默认副本数为 1
kubectl patch settings.longhorn.io default-replica-count -n longhorn-system --type merge -p '{"value":"1"}'

# 验证
kubectl get settings.longhorn.io default-replica-count -n longhorn-system -o jsonpath='{.value}'
# 应该输出: 1
```

#### 方法 2: 使用项目脚本
```bash
./scripts/configure-longhorn-single-node.sh
```

#### 方法 3: 通过 Longhorn UI 配置
```bash
# 访问 UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# 在浏览器中访问 http://localhost:8080
# 进入: Settings → General → Default Replica Count → 设置为 1
```

#### 方法 4: 安装时配置（Helm）
```yaml
# longhorn-values.yaml
defaultSettings:
  defaultReplicaCount: 1
```

```bash
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --values longhorn-values.yaml
```

**验证步骤**:
```bash
# 检查设置
kubectl get settings.longhorn.io default-replica-count -n longhorn-system

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

# 检查 PVC 状态（应该很快变为 Bound）
kubectl get pvc test-pvc

# 清理测试
kubectl delete pvc test-pvc
```

**参考文档**: 
- [LONGHORN_SINGLE_NODE.md](LONGHORN_SINGLE_NODE.md)
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md#1-单节点环境配置)

---

### 问题 10: 网络连接问题

**问题描述**:
```
Longhorn 组件之间无法通信，或 Pod 无法访问 Service
```

**原因分析**:
1. CNI 网络配置问题
2. 防火墙规则阻止
3. DNS 解析失败
4. Service/Endpoints 配置问题

**解决方案**:

#### 步骤 1: 检查 Pod 网络
```bash
# 检查 Pod 状态和 IP
kubectl get pods -n longhorn-system -o wide

# 检查 Service
kubectl get svc -n longhorn-system

# 检查 Endpoints
kubectl get endpoints -n longhorn-system
```

#### 步骤 2: 检查 CNI 配置
```bash
# 查看 CNI 配置
ls -la /etc/cni/net.d/

# 检查 Flannel（k3s 默认 CNI）
kubectl get pods -n kube-system | grep flannel

# 查看 Flannel 日志
kubectl logs -n kube-system -l app=flannel
```

#### 步骤 3: 测试网络连接
```bash
# 从 Pod 内测试 DNS 解析
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $DEPLOYER_POD -c wait-for-backend -- nslookup longhorn-backend

# 测试 HTTP 连接
kubectl exec -n longhorn-system $DEPLOYER_POD -c wait-for-backend -- wget -qO- --timeout=5 "http://longhorn-backend:9500/v1"
```

#### 步骤 4: 检查防火墙（在节点上）
```bash
# SSH 到节点
ssh user@node-ip

# 检查防火墙规则
sudo iptables -L -n | grep -E "9500|longhorn"
sudo ufw status  # Ubuntu
sudo firewall-cmd --list-all  # CentOS/RHEL
```

#### 步骤 5: 检查网络策略
```bash
# 查看网络策略
kubectl get networkpolicies -n longhorn-system

# 如果有网络策略，可能需要调整规则
```

**验证步骤**:
```bash
# 检查所有 Pod 是否正常运行
kubectl get pods -n longhorn-system

# 检查 Service 是否有 Endpoints
kubectl get endpoints -n longhorn-system longhorn-backend
```

**参考文档**: 
- [FIX_DRIVER_DEPLOYER_INIT.md](FIX_DRIVER_DEPLOYER_INIT.md#问题-3-网络连接失败)
- [K3S_NETWORK_EXPLAIN.md](K3S_NETWORK_EXPLAIN.md)
- [scripts/diagnose-driver-deployer-network.sh](../scripts/diagnose-driver-deployer-network.sh)

---

### 问题 11: 磁盘空间不足

**问题描述**:
```
磁盘空间不足，无法创建新的卷或扩展现有卷
```

**原因分析**:
- Longhorn 数据目录磁盘空间不足
- 没有预留足够的存储空间

**解决方案**:

#### 步骤 1: 检查磁盘使用情况
```bash
# 在节点上检查
df -h /var/lib/longhorn  # 默认路径
# 或
df -h /mnt/longhorn  # 自定义路径

# 使用项目脚本检查
./scripts/check-disk-usage.sh
```

#### 步骤 2: 清理不需要的卷和快照
```bash
# 列出所有卷
kubectl get volumes.longhorn.io -n longhorn-system

# 删除不需要的卷
kubectl delete volumes.longhorn.io <volume-name> -n longhorn-system

# 在 Longhorn UI 中删除快照和备份
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# 访问 http://localhost:8080 清理快照和备份
```

#### 步骤 3: 扩展磁盘（如果可能）
```bash
# 如果使用 LVM 或云磁盘，可以扩展
# 扩展物理磁盘后，扩展文件系统
sudo resize2fs /dev/sdb1  # ext4
# 或
sudo xfs_growfs /mnt/longhorn  # xfs
```

#### 步骤 4: 配置存储预留
```bash
# 配置 Longhorn 预留部分存储空间（例如预留 20%）
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p '{
  "spec": {
    "disks": {
      "data-disk": {
        "storageReserved": 10737418240  # 10GB，单位是字节
      }
    }
  }
}'
```

#### 步骤 5: 迁移到更大的磁盘（如果需要）
```bash
# 1. 准备新磁盘并挂载
# 2. 备份数据
# 3. 使用项目脚本迁移
./scripts/migrate-longhorn-disk.sh /mnt/longhorn /mnt/longhorn-new
```

**验证步骤**:
```bash
# 检查磁盘空间
df -h /mnt/longhorn

# 尝试创建测试 PVC
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

kubectl get pvc test-pvc
kubectl delete pvc test-pvc
```

**参考文档**: 
- [DISK_CAPACITY_PLANNING.md](DISK_CAPACITY_PLANNING.md)
- [scripts/check-disk-usage.sh](../scripts/check-disk-usage.sh)

---

## 🟢 运行时问题

### 问题 12: 卷扩展失败

**问题描述**:
```
尝试扩展 PVC 大小后，扩展操作失败或 PVC 一直处于扩展状态
```

**原因分析**:
1. StorageClass 未启用卷扩展
2. Longhorn 卷扩展功能问题
3. 磁盘空间不足

**解决方案**:

#### 步骤 1: 检查 StorageClass 配置
```bash
# 检查是否支持卷扩展
kubectl get storageclass longhorn -o yaml | grep allowVolumeExpansion
# 应该输出: allowVolumeExpansion: true

# 如果不支持，需要更新 StorageClass（不推荐，建议重新安装时配置）
```

#### 步骤 2: 检查磁盘空间
参考[问题 11: 磁盘空间不足](#问题11-磁盘空间不足)

#### 步骤 3: 检查卷状态
```bash
# 查看 PVC 状态
kubectl describe pvc <pvc-name>

# 查看 Longhorn 卷状态
VOLUME_NAME=$(kubectl get pvc <pvc-name> -o jsonpath='{.spec.volumeName}')
kubectl get volumes.longhorn.io -n longhorn-system $VOLUME_NAME -o yaml
```

#### 步骤 4: 在 VM 内部扩展文件系统
```bash
# 1. 连接到 VM
virtctl console <vm-name>

# 2. 查看磁盘分区
lsblk

# 3. 扩展分区（如果需要）
sudo growpart /dev/vdb 1  # 假设是 /dev/vdb1

# 4. 扩展文件系统
sudo resize2fs /dev/vdb1  # ext4
# 或
sudo xfs_growfs /  # xfs
```

**验证步骤**:
```bash
# 检查 PVC 大小
kubectl get pvc <pvc-name>

# 在 VM 内部检查文件系统大小
virtctl console <vm-name>
df -h
```

**参考文档**: 
- [DISK_EXPANSION.md](DISK_EXPANSION.md)
- [LONGHORN_SETUP.md](LONGHORN_SETUP.md#磁盘扩展)

---

### 问题 13: 备份失败

**问题描述**:
```
Longhorn 备份操作失败，无法创建或恢复备份
```

**原因分析**:
1. 备份目标未配置
2. 备份目标访问权限问题
3. 网络连接问题
4. 备份空间不足

**解决方案**:

#### 步骤 1: 检查备份目标配置
```bash
# 查看备份目标设置
kubectl get settings.longhorn.io backup-target -n longhorn-system -o yaml

# 或在 Longhorn UI 中查看
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# 访问 http://localhost:8080
# 进入: Settings → General → Backup Target
```

#### 步骤 2: 配置备份目标（如果未配置）
```bash
# 例如配置 S3 备份目标
kubectl patch settings.longhorn.io backup-target -n longhorn-system --type merge -p '{
  "value": "s3://backup-bucket@us-west-2/backup?accessKey=xxx&secretKey=xxx"
}'
```

#### 步骤 3: 测试备份目标连接
在 Longhorn UI 中：
1. 进入 Settings → General → Backup Target
2. 点击 "Test" 按钮测试连接

#### 步骤 4: 检查备份引擎状态
```bash
# 查看备份引擎 Pod
kubectl get pods -n longhorn-system | grep backup

# 查看备份引擎日志
kubectl logs -n longhorn-system -l app=longhorn-backup-engine
```

**验证步骤**:
```bash
# 在 Longhorn UI 中尝试创建备份
# 进入 Volume → 选择卷 → 点击 "Create Backup"

# 或使用 kubectl
kubectl create volumesnapshot <snapshot-name> \
  --source-pvc=<pvc-name> \
  --snapshot-class=longhorn-snapshot-class
```

**参考文档**: 
- [Longhorn 官方文档 - 备份](https://longhorn.io/docs/1.6.0/snapshots-and-backups/backup-and-restore/)

---

### 问题 14: 性能问题

**问题描述**:
```
Longhorn 存储性能较差，读写速度慢
```

**原因分析**:
1. 使用机械硬盘而非 SSD
2. 网络带宽不足
3. 副本数配置不当
4. 资源限制过严

**解决方案**:

#### 步骤 1: 检查磁盘类型
```bash
# 在节点上检查磁盘类型
lsblk -d -o name,rota
# rota=0 表示 SSD，rota=1 表示机械硬盘

# 如果使用机械硬盘，考虑迁移到 SSD
```

#### 步骤 2: 优化副本数配置
```bash
# 对于单节点环境，使用 1 个副本
kubectl patch settings.longhorn.io default-replica-count -n longhorn-system --type merge -p '{"value":"1"}'

# 对于多节点环境，根据需求调整（1-3 个副本）
# 更多副本 = 更好的可用性但更慢的写入性能
```

#### 步骤 3: 调整资源限制
```bash
# 检查 Manager 资源限制
kubectl get deployment longhorn-manager -n longhorn-system -o yaml | grep -A 5 resources

# 如果资源不足，可以考虑增加（需要修改部署）
```

#### 步骤 4: 使用独立数据盘
确保 Longhorn 使用独立的 SSD 数据盘，而不是与系统盘共享

#### 步骤 5: 网络优化
确保节点之间有足够的网络带宽，特别是对于多副本配置

**性能基准测试**:
```bash
# 在 Pod 中测试 I/O 性能
kubectl run -it --rm perf-test --image=ubuntu --restart=Never -- bash
# 然后安装 fio 并测试
apt-get update && apt-get install -y fio
fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k --size=1G --runtime=60 --time_based
```

**参考文档**: 
- [Longhorn 官方文档 - 性能调优](https://longhorn.io/docs/1.6.0/advanced-resources/deploy/taint-toleration/)
- [LONGHORN_SETUP.md](LONGHORN_SETUP.md#性能优化)

---

## 🔧 通用诊断工具

### 快速诊断脚本

项目提供了多个诊断脚本，可以帮助快速定位问题：

```bash
# 深度诊断 driver-deployer
./scripts/deep-diagnose-driver-deployer.sh

# 网络诊断
./scripts/diagnose-driver-deployer-network.sh

# 检查 Flannel 网络
./scripts/check-flannel.sh

# 检查磁盘使用情况
./scripts/check-disk-usage.sh
```

### 通用检查清单

在遇到问题时，可以按照以下清单逐步检查：

```bash
# 1. 检查 k3s 集群状态
kubectl get nodes
kubectl cluster-info

# 2. 检查 Longhorn 命名空间
kubectl get namespace longhorn-system

# 3. 检查所有 Longhorn Pods
kubectl get pods -n longhorn-system

# 4. 检查 Longhorn Services
kubectl get svc -n longhorn-system

# 5. 检查 StorageClass
kubectl get storageclass longhorn

# 6. 检查 CSI Driver
kubectl get csidriver driver.longhorn.io

# 7. 检查 Longhorn Nodes
kubectl get nodes.longhorn.io -n longhorn-system

# 8. 检查事件
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | tail -30

# 9. 在节点上检查 open-iscsi
ssh user@node-ip "iscsiadm --version && sudo systemctl status iscsid"

# 10. 检查磁盘空间
ssh user@node-ip "df -h /var/lib/longhorn"
```

---

## 📚 相关文档索引

### 安装相关
- [LONGHORN_INSTALLATION_GUIDE.md](LONGHORN_INSTALLATION_GUIDE.md) - 完整安装指南
- [LONGHORN_PREREQUISITES.md](LONGHORN_PREREQUISITES.md) - 前置要求
- [LONGHORN_REINSTALL_GUIDE.md](LONGHORN_REINSTALL_GUIDE.md) - 重新安装指南
- [LONGHORN_SETUP.md](LONGHORN_SETUP.md) - 设置和使用指南

### 问题修复相关
- [FIX_LONGHORN_ISSUES.md](FIX_LONGHORN_ISSUES.md) - 故障排查指南
- [FIX_DRIVER_DEPLOYER_INIT.md](FIX_DRIVER_DEPLOYER_INIT.md) - driver-deployer 初始化问题
- [FIX_PVC_PENDING.md](FIX_PVC_PENDING.md) - PVC 挂起问题
- [FIX_DISK_UUID_MISMATCH.md](FIX_DISK_UUID_MISMATCH.md) - 磁盘 UUID 不匹配
- [FIX_DISK_MISMATCH.md](FIX_DISK_MISMATCH.md) - 磁盘不匹配问题

### 配置相关
- [LONGHORN_SINGLE_NODE.md](LONGHORN_SINGLE_NODE.md) - 单节点配置
- [LONGHORN_DISK_REQUIREMENTS.md](LONGHORN_DISK_REQUIREMENTS.md) - 磁盘要求
- [DISK_CAPACITY_PLANNING.md](DISK_CAPACITY_PLANNING.md) - 磁盘容量规划
- [DISK_EXPANSION.md](DISK_EXPANSION.md) - 磁盘扩展指南

### 其他
- [ACCESS_LONGHORN_UI.md](ACCESS_LONGHORN_UI.md) - 访问 Longhorn UI
- [CSI_DRIVER_EXPLAIN.md](CSI_DRIVER_EXPLAIN.md) - CSI Driver 说明
- [STORAGECLASS_EXPLAIN.md](STORAGECLASS_EXPLAIN.md) - StorageClass 说明

---

## 🎯 快速修复流程

遇到问题时，可以按照以下流程快速定位和修复：

```
1. 运行诊断脚本
   ↓
2. 查看 Pod 状态和日志
   ↓
3. 检查前置要求（open-iscsi、磁盘空间等）
   ↓
4. 根据问题类型查找对应解决方案
   ↓
5. 应用修复方案
   ↓
6. 验证修复结果
```

---

## 💡 最佳实践建议

### 安装前
- ✅ 在所有节点安装 `open-iscsi` 并启动服务
- ✅ 准备独立的 SSD 数据盘（生产环境）
- ✅ 确保节点有足够的 CPU/内存资源
- ✅ 检查网络连接正常

### 安装时
- ✅ 使用最新稳定版本
- ✅ 单节点环境设置副本数为 1
- ✅ 配置自定义数据路径（生产环境）

### 安装后
- ✅ 配置磁盘并等待就绪
- ✅ 测试 PVC 创建
- ✅ 配置备份目标（生产环境）
- ✅ 监控存储使用情况

### 运行时
- ✅ 定期清理不需要的卷和快照
- ✅ 监控磁盘空间使用
- ✅ 定期备份重要数据
- ✅ 根据需求调整性能配置

---

## 📞 获取帮助

如果问题仍未解决：

1. **查看官方文档**: https://longhorn.io/docs/
2. **查看 GitHub Issues**: https://github.com/longhorn/longhorn/issues
3. **收集诊断信息**:
   ```bash
   # 运行诊断脚本
   ./scripts/deep-diagnose-driver-deployer.sh > diagnosis.txt
   
   # 收集日志
   kubectl logs -n longhorn-system -l app=longhorn-manager > manager.log
   kubectl describe pods -n longhorn-system > pods-describe.txt
   ```

---

**文档版本**: v1.0.0  
**最后更新**: 2024-01-01  
**维护者**: VM Operator Team


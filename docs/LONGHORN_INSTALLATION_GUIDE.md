# Longhorn 安装指南（k3s 环境）

## 概述

本指南详细说明在 k3s 环境中安装 Longhorn 存储系统的完整步骤，包括前置要求、两种安装方法（Helm 和 kubectl）以及验证和故障排查。

## 前置要求

### 1. 系统要求

| 资源 | 最低要求 | 推荐配置 |
|------|----------|----------|
| **CPU** | 1 核心 | 2+ 核心 |
| **内存** | 1GB | 4GB+ |
| **磁盘空间** | 10GB | 50GB+ |
| **操作系统** | Linux (Ubuntu 20.04+, CentOS 7+, RHEL 8+) | - |

### 2. 必需软件

#### 2.1 安装 open-iscsi（必需）⭐

Longhorn 使用 iSCSI 协议管理存储卷，每个节点都必须安装 `open-iscsi`。

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y open-iscsi

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

**CentOS/RHEL/Rocky:**
```bash
sudo yum install -y iscsi-initiator-utils

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

**Fedora:**
```bash
sudo dnf install -y iscsi-initiator-utils

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

**验证安装:**
```bash
iscsiadm --version
# 应该输出: iscsiadm version 2.0-xxx
```

#### 2.2 准备存储磁盘（可选但推荐）

**使用独立数据盘（推荐）:**
```bash
# 1. 查看可用磁盘
lsblk

# 2. 准备新磁盘（例如 /dev/sdb）
sudo parted -s /dev/sdb mklabel gpt
sudo parted -s /dev/sdb mkpart primary ext4 0% 100%

# 3. 格式化
sudo mkfs.ext4 -F /dev/sdb1

# 4. 创建挂载点
sudo mkdir -p /mnt/longhorn

# 5. 挂载
sudo mount /dev/sdb1 /mnt/longhorn

# 6. 配置自动挂载
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID /mnt/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab

# 7. 设置权限
sudo chmod 755 /mnt/longhorn
```

**使用默认路径（开发测试）:**
```bash
# 创建默认路径
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn
```

### 3. 安装前检查清单

在安装 Longhorn 之前，请确保：

- [ ] 所有节点已安装 `open-iscsi` 或 `iscsi-initiator-utils`
- [ ] `iscsid` 服务已启动
- [ ] 节点有足够的 CPU/内存资源
- [ ] 节点有足够的磁盘空间
- [ ] 存储路径可写（`/var/lib/longhorn` 或自定义路径）
- [ ] k3s 集群正常运行
- [ ] 节点网络连接正常

**快速检查脚本:**
```bash
# 检查 iscsiadm
iscsiadm --version || echo "❌ 需要安装 open-iscsi"

# 检查 iscsid 服务
sudo systemctl status iscsid || echo "❌ 需要启动 iscsid 服务"

# 检查磁盘空间
df -h | grep -E "longhorn|/$" | head -2

# 检查 k3s
kubectl get nodes
```

## 安装方法

### 方法 1: 使用 kubectl apply（简单直接）⭐

这是最常用的安装方法，适合大多数场景。

#### 步骤 1: 确定 Longhorn 版本

```bash
# 查看最新版本（推荐使用稳定版本）
LONGHORN_VERSION="v1.6.0"  # 或使用最新版本

# 或者从 GitHub 获取最新版本
LONGHORN_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
echo "Longhorn 版本: $LONGHORN_VERSION"
```

#### 步骤 2: 安装 Longhorn

```bash
# 应用 Longhorn 清单
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml
```

#### 步骤 3: 等待安装完成

```bash
# 等待 Longhorn Manager 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 或者监控安装进度
watch kubectl get pods -n longhorn-system
```

#### 步骤 4: 验证安装

```bash
# 检查所有 Pods 状态
kubectl get pods -n longhorn-system

# 应该看到以下组件运行：
# - longhorn-manager-* (Running)
# - longhorn-ui-* (Running)
# - longhorn-driver-deployer-* (Running 或 Completed)
# - longhorn-csi-plugin-* (Running, 每个节点一个)
# - longhorn-csi-attacher-* (Running)
# - longhorn-csi-provisioner-* (Running)
# - longhorn-csi-resizer-* (Running)

# 检查 StorageClass
kubectl get storageclass longhorn

# 应该看到:
# NAME      PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
# longhorn  driver.longhorn.io   Delete          Immediate           true                   Xm
```

#### 步骤 5: 配置磁盘（如果使用自定义路径）

如果使用自定义磁盘路径（如 `/mnt/longhorn`），需要配置：

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 等待 Longhorn Node 资源创建
kubectl wait --for=condition=ready nodes.longhorn.io -n longhorn-system $NODE_NAME --timeout=300s

# 配置磁盘
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

**或使用项目脚本:**
```bash
./scripts/configure-longhorn-disk.sh /mnt/longhorn
```

### 方法 2: 使用 Helm（推荐用于生产环境）⭐

Helm 安装方式提供更多配置选项，适合生产环境。

#### 步骤 1: 安装 Helm（如果未安装）

```bash
# 安装 Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 验证安装
helm version
```

#### 步骤 2: 添加 Longhorn Helm Repository

```bash
# 添加 Longhorn Helm 仓库
helm repo add longhorn https://charts.longhorn.io

# 更新仓库
helm repo update

# 查看可用版本
helm search repo longhorn/longhorn --versions
```

#### 步骤 3: 创建 values.yaml（可选）

创建自定义配置文件 `longhorn-values.yaml`:

```yaml
# longhorn-values.yaml
# 单节点配置
defaultSettings:
  defaultReplicaCount: 1  # 单节点环境设置为 1
  defaultDataPath: /mnt/longhorn  # 自定义数据路径（可选）

# 持久化存储配置
persistence:
  defaultClass: true
  defaultClassReplicaCount: 1

# 资源限制（根据实际情况调整）
resources:
  manager:
    requests:
      cpu: 100m
      memory: 100Mi
  ui:
    requests:
      cpu: 50m
      memory: 50Mi
```

#### 步骤 4: 安装 Longhorn

**使用默认配置:**
```bash
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.6.0
```

**使用自定义配置:**
```bash
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.6.0 \
  --values longhorn-values.yaml
```

#### 步骤 5: 等待安装完成

```bash
# 监控安装进度
watch kubectl get pods -n longhorn-system

# 或等待所有 Pods 就绪
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s
```

#### 步骤 6: 验证安装

```bash
# 检查 Helm 发布状态
helm list -n longhorn-system

# 检查 Pods
kubectl get pods -n longhorn-system

# 检查 StorageClass
kubectl get storageclass longhorn
```

#### 步骤 7: 配置磁盘（如果使用自定义路径）

同方法 1 的步骤 5。

## 安装后配置

### 1. 单节点环境配置

如果是单节点 k3s 环境，需要配置副本数为 1:

```bash
# 方法 1: 通过 Longhorn UI
# 访问 UI: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# 进入: Settings → General → Default Replica Count → 设置为 1

# 方法 2: 通过 kubectl
kubectl patch settings.longhorn.io default-replica-count -n longhorn-system --type merge -p '{"value":"1"}'
```

**或使用项目脚本:**
```bash
./scripts/configure-longhorn-single-node.sh
```

### 2. 配置磁盘路径

如果使用自定义磁盘路径，参考"方法 1: 步骤 5"。

### 3. 访问 Longhorn UI

```bash
# 端口转发
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80

# 访问: http://192.168.1.141:8088
```

**或使用项目脚本:**
```bash
./scripts/access-longhorn-ui.sh
```

## 验证安装

### 1. 检查所有组件

```bash
# 检查 Pods
kubectl get pods -n longhorn-system

# 检查 CSI Driver
kubectl get csidriver driver.longhorn.io

# 检查 StorageClass
kubectl get storageclass longhorn -o yaml | grep -E "provisioner|allowVolumeExpansion"
```

### 2. 测试 PVC 创建

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

### 3. 检查磁盘状态

```bash
# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 检查磁盘状态
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 30 "diskStatus:"

# 应该看到磁盘状态为 Ready: True
```

## 常见问题排查

### 问题 1: longhorn-manager Pod CrashLoopBackOff

**症状:**
```
Error starting manager: Failed environment check, please make sure you have iscsiadm/open-iscsi installed on the host
```

**原因:** 节点未安装 `open-iscsi`

**解决:**
```bash
# 安装 open-iscsi
sudo apt-get install -y open-iscsi  # Ubuntu/Debian
# 或
sudo yum install -y iscsi-initiator-utils  # CentOS/RHEL

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid

# 重启 longhorn-manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 2: longhorn-driver-deployer 卡在 Init:0/1

**症状:** `longhorn-driver-deployer` Pod 一直处于 `Init:0/1` 状态

**原因:** Init Container 等待 `longhorn-backend` API

**解决:**
```bash
# 检查 longhorn-manager 是否运行
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 检查 longhorn-backend Service
kubectl get svc -n longhorn-system longhorn-backend

# 如果 Manager 运行正常，重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

### 问题 3: PVC 一直 Pending

**症状:** PVC 无法绑定到 PV

**原因:** Longhorn Node 没有磁盘配置

**解决:**
```bash
# 检查 Node 磁盘配置
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"

# 如果没有配置，添加磁盘配置
./scripts/configure-longhorn-disk.sh /mnt/longhorn
```

### 问题 4: 磁盘 UUID 不匹配

**症状:**
```
Disk data-disk(/mnt/longhorn) on node host1 is not ready: record diskUUID doesn't match the one on the disk
```

**原因:** 磁盘被重新格式化，UUID 变化

**解决:**
```bash
./scripts/fix-longhorn-disk-uuid.sh /mnt/longhorn
```

### 问题 5: CSI Driver 未安装

**症状:** `kubectl get csidriver` 返回空

**原因:** `longhorn-driver-deployer` 未完成

**解决:**
```bash
# 检查 driver-deployer 状态
kubectl get pods -n longhorn-system | grep driver-deployer

# 查看日志
kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true

# 如果卡住，重启
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

## 卸载 Longhorn

### 方法 1: kubectl 安装的卸载

```bash
# 删除 Longhorn
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 清理命名空间
kubectl delete namespace longhorn-system
```

### 方法 2: Helm 安装的卸载

```bash
# 卸载 Longhorn
helm uninstall longhorn -n longhorn-system

# 清理命名空间
kubectl delete namespace longhorn-system
```

## 快速安装脚本

项目提供了自动化安装脚本：

```bash
# 使用项目脚本安装
./scripts/setup-longhorn.sh

# 脚本会自动：
# 1. 检查前置要求
# 2. 安装 open-iscsi（如果需要）
# 3. 安装 Longhorn
# 4. 等待组件就绪
# 5. 验证安装
```

## 安装方法对比

| 特性 | kubectl apply | Helm |
|------|---------------|------|
| **简单性** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **配置灵活性** | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **生产环境** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **版本管理** | 手动 | 自动 |
| **升级** | 手动 | 简单 |
| **推荐场景** | 开发测试 | 生产环境 |

## 最佳实践

### 1. 生产环境建议

- ✅ 使用 Helm 安装，便于管理和升级
- ✅ 使用独立数据盘，避免与系统盘竞争
- ✅ 配置多个副本（3 个）以实现高可用
- ✅ 定期备份重要数据
- ✅ 监控存储使用情况

### 2. 开发测试环境建议

- ✅ 使用 kubectl apply 安装，简单快速
- ✅ 使用默认路径 `/var/lib/longhorn`
- ✅ 配置单副本以节省资源
- ✅ 定期清理不需要的卷

### 3. 单节点环境建议

- ✅ 设置 `defaultReplicaCount: 1`
- ✅ 使用独立数据盘
- ✅ 定期备份到外部存储

## 总结

**推荐安装流程:**

1. **安装前置要求** → 安装 `open-iscsi`
2. **准备存储磁盘** → 准备独立数据盘（推荐）
3. **安装 Longhorn** → 使用 kubectl apply（简单）或 Helm（生产）
4. **配置磁盘** → 配置自定义磁盘路径（如果使用）
5. **单节点配置** → 设置副本数为 1（单节点环境）
6. **验证安装** → 测试 PVC 创建

**快速开始:**
```bash
# 1. 安装前置要求
sudo apt-get install -y open-iscsi
sudo systemctl enable iscsid && sudo systemctl start iscsid

# 2. 安装 Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# 3. 等待安装完成
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

# 4. 验证
kubectl get storageclass longhorn
```

## 参考资源

- Longhorn 官方文档: https://longhorn.io/docs/
- Longhorn GitHub: https://github.com/longhorn/longhorn
- Helm Chart: https://github.com/longhorn/longhorn/tree/master/chart
- 项目脚本: `./scripts/setup-longhorn.sh`


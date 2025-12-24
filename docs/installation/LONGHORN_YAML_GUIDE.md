# Longhorn v1.8.1 YAML 文件详解

本文档详细说明 `longhorn_v1.8.1.yaml` 文件的内容、结构和各个组件的作用。

## 文件概述

`longhorn_v1.8.1.yaml` 是 Longhorn v1.8.1 的完整安装清单，包含了在 Kubernetes 集群中部署 Longhorn 分布式存储系统所需的所有资源。文件总共有 **5181 行**，包含 **40+ 个 Kubernetes 资源对象**。

## 文件结构

文件使用 `---` 分隔符将多个 Kubernetes 资源对象组合在一起，这是标准的 Kubernetes 多资源 YAML 格式。

## 资源组件详解

### 1. 基础资源（Foundation Resources）

#### 1.1 Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: longhorn-system
```
- **作用**: 创建 `longhorn-system` 命名空间，所有 Longhorn 组件都部署在这个命名空间中
- **位置**: 文件开头（第 1-6 行）

#### 1.2 PriorityClass
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: "longhorn-critical"
  value: 1000000000
```
- **作用**: 定义优先级类，确保 Longhorn Pod 具有最高优先级，防止在节点压力下被 Kubernetes 调度器意外驱逐
- **优先级值**: 1000000000（最高优先级）
- **位置**: 第 8-20 行

#### 1.3 ServiceAccount（服务账户）

文件包含 3 个 ServiceAccount：

1. **longhorn-service-account** (第 22-31 行)
   - 用于 `longhorn-manager` DaemonSet
   - 提供 Longhorn 核心组件的身份认证

2. **longhorn-ui-service-account** (第 33-42 行)
   - 用于 `longhorn-ui` Deployment
   - 提供 Web UI 的身份认证

3. **longhorn-support-bundle** (第 44-53 行)
   - 用于支持包收集功能
   - 需要 cluster-admin 权限以收集集群诊断信息

### 2. 配置资源（Configuration Resources）

#### 2.1 ConfigMap

文件包含 3 个 ConfigMap：

1. **longhorn-default-resource** (第 55-66 行)
   - 定义 Longhorn 的默认资源限制
   - 包含 CPU、内存等资源配置

2. **longhorn-default-setting** (第 68-81 行)
   - 定义 Longhorn 的默认设置
   - 包含：
     - `priority-class: longhorn-critical` - 使用高优先级类
     - `disable-revision-counter: true` - 禁用修订计数器

3. **longhorn-storageclass** (第 83-115 行)
   - 定义默认的 StorageClass 配置
   - 包含 `longhorn` StorageClass 的完整定义
   - 设置为默认存储类（`is-default-class: "true"`）

### 3. 自定义资源定义（CustomResourceDefinitions）

文件包含 **20+ 个 CRD**，这些是 Longhorn 的核心 API 资源：

#### 3.1 存储相关 CRD

1. **volumes.longhorn.io** (约第 4322 行)
   - 定义 Longhorn 卷（Volume）资源
   - 核心存储资源，代表一个持久化存储卷

2. **replicas.longhorn.io** (约第 3115 行)
   - 定义卷副本（Replica）资源
   - 每个卷可以有多个副本，分布在不同节点上

3. **engines.longhorn.io** (约第 1769 行)
   - 定义存储引擎（Engine）资源
   - 负责实际的数据读写操作

4. **snapshots.longhorn.io** (约第 3652 行)
   - 定义快照（Snapshot）资源
   - 用于创建卷的时间点快照

#### 3.2 备份相关 CRD

5. **backups.longhorn.io** (约第 920 行)
   - 定义备份（Backup）资源
   - 用于备份卷数据到外部存储

6. **backuptargets.longhorn.io** (约第 1154 行)
   - 定义备份目标（BackupTarget）资源
   - 配置备份存储位置（如 S3、NFS）

7. **backupvolumes.longhorn.io** (约第 1359 行)
   - 定义备份卷（BackupVolume）资源
   - 管理卷的备份状态

8. **backupbackingimages.longhorn.io** (约第 747 行)
   - 定义备份基础镜像资源

#### 3.3 节点和实例管理 CRD

9. **nodes.longhorn.io** (约第 2511 行)
   - 定义节点（Node）资源
   - 管理 Longhorn 集群中的节点信息

10. **instancemanagers.longhorn.io** (约第 2169 行)
    - 定义实例管理器（InstanceManager）资源
    - 管理引擎和副本实例的生命周期

11. **sharemanagers.longhorn.io** (约第 3521 行)
    - 定义共享管理器（ShareManager）资源
    - 用于 ReadWriteMany (RWX) 卷

#### 3.4 镜像和基础镜像 CRD

12. **engineimages.longhorn.io** (约第 1553 行)
    - 定义引擎镜像（EngineImage）资源
    - 管理 Longhorn 引擎的容器镜像版本

13. **backingimages.longhorn.io** (约第 513 行)
    - 定义基础镜像（BackingImage）资源
    - 用于从容器镜像创建卷

14. **backingimagedatasources.longhorn.io** (约第 126 行)
    - 定义基础镜像数据源资源

15. **backingimagemanagers.longhorn.io** (约第 316 行)
    - 定义基础镜像管理器资源

#### 3.5 任务和作业 CRD

16. **recurringjobs.longhorn.io** (约第 2915 行)
    - 定义定期作业（RecurringJob）资源
    - 用于定期备份、快照等任务

17. **orphans.longhorn.io** (约第 2800 行)
    - 定义孤儿资源（Orphan）资源
    - 管理孤立的数据块

#### 3.6 系统管理 CRD

18. **settings.longhorn.io** (约第 3404 行)
    - 定义设置（Setting）资源
    - 管理 Longhorn 系统配置

19. **systembackups.longhorn.io** (约第 3920 行)
    - 定义系统备份资源
    - 用于备份 Longhorn 系统配置

20. **systemrestores.longhorn.io** (约第 4061 行)
    - 定义系统恢复资源
    - 用于恢复 Longhorn 系统配置

#### 3.7 其他 CRD

21. **volumeattachments.longhorn.io** (约第 4174 行)
    - 定义卷附件资源
    - 管理卷与 Pod 的挂载关系

22. **supportbundles.longhorn.io** (约第 3785 行)
    - 定义支持包资源
    - 用于收集诊断信息

### 4. 权限和访问控制（RBAC）

#### 4.1 ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: longhorn-role
```
- **作用**: 定义 Longhorn 在集群级别需要的权限
- **权限范围**: 
  - 管理所有 CRD 资源
  - 访问节点、持久卷等资源
  - 管理存储类
- **位置**: 约第 4723 行

#### 4.2 ClusterRoleBinding

文件包含 2 个 ClusterRoleBinding：

1. **longhorn-bind** (约第 4789 行)
   - 将 `longhorn-role` 绑定到 `longhorn-service-account`
   - 为 Longhorn Manager 提供集群级别权限

2. **longhorn-support-bundle** (约第 4807 行)
   - 将 `cluster-admin` 角色绑定到 `longhorn-support-bundle` ServiceAccount
   - 为支持包收集功能提供完全权限

### 5. 服务（Services）

文件包含 5 个 Service：

1. **longhorn-backend** (约第 4832 行)
   - 类型: ClusterIP
   - 端口: 9500
   - 作用: 提供 Longhorn Manager API 访问
   - 选择器: `app: longhorn-manager`

2. **longhorn-frontend** (约第 4852 行)
   - 类型: ClusterIP
   - 端口: 80
   - 作用: 提供 Longhorn Web UI 访问
   - 选择器: `app: longhorn-ui`

3. **longhorn-conversion-webhook** (约第 4873 行)
   - 类型: ClusterIP
   - 端口: 9501
   - 作用: 提供 CRD 版本转换 Webhook
   - 选择器: `longhorn.io/conversion-webhook: longhorn-conversion-webhook`

4. **longhorn-admission-webhook** (约第 4893 行)
   - 类型: ClusterIP
   - 端口: 9502
   - 作用: 提供准入控制 Webhook（验证和变更）
   - 选择器: `longhorn.io/admission-webhook: longhorn-admission-webhook`

5. **longhorn-recovery-backend** (约第 4913 行)
   - 类型: ClusterIP
   - 端口: 9503
   - 作用: 提供恢复后端服务
   - 选择器: `longhorn.io/recovery-backend: longhorn-recovery-backend`

### 6. 工作负载（Workloads）

#### 6.1 DaemonSet: longhorn-manager

**位置**: 约第 4926-5044 行

**作用**: Longhorn 的核心管理组件，在每个节点上运行一个 Pod

**关键配置**:
- **镜像**: `longhornio/longhorn-manager:v1.8.1`
- **特权模式**: `privileged: true`（需要访问主机设备）
- **端口**:
  - 9500: Manager API
  - 9501: Conversion Webhook
  - 9502: Admission Webhook
  - 9503: Recovery Backend
- **卷挂载**:
  - `/host/boot/` - 只读，访问主机引导目录
  - `/host/dev/` - 访问主机设备
  - `/host/proc/` - 只读，访问主机进程信息
  - `/host/etc/` - 只读，访问主机配置
  - `/var/lib/longhorn/` - 数据存储目录（可配置）
- **环境变量**:
  - `POD_NAME`, `POD_NAMESPACE`, `POD_IP`, `NODE_NAME` - 自动注入的 Pod 信息
- **修改说明**: 
  - ✅ **已去掉 `readinessProbe`**（适配当前 k3s 环境，避免 healthz 检查问题）

**辅助容器**:
- `pre-pull-share-manager-image`: 预拉取共享管理器镜像

#### 6.2 Deployment: longhorn-driver-deployer

**位置**: 约第 5047-5114 行

**作用**: 部署 Longhorn CSI 驱动

**关键配置**:
- **副本数**: 1
- **镜像**: `longhornio/longhorn-manager:v1.8.1`
- **Init 容器**: `wait-longhorn-manager`
  - **作用**: 等待 longhorn-manager 就绪
  - **修改说明**: 
    - ✅ **已添加超时机制**（最多等待 5 分钟，避免无限等待）
    - 原逻辑: 无限循环等待
    - 新逻辑: 最多尝试 150 次（每次 2 秒），超时后继续执行

**主容器**:
- 执行 `longhorn-manager -d deploy-driver` 命令
- 部署 CSI 驱动到集群

#### 6.3 Deployment: longhorn-ui

**位置**: 约第 5116-5181 行

**作用**: 提供 Longhorn Web 管理界面

**关键配置**:
- **副本数**: 2（高可用）
- **镜像**: `longhornio/longhorn-ui:v1.8.1`
- **端口**: 8000
- **服务**: 通过 `longhorn-frontend` Service 暴露

## 文件修改说明

相比官方原始版本，本文件进行了以下修改以适配当前 k3s 环境：

### 1. 去掉 readinessProbe
- **位置**: `longhorn-manager` DaemonSet (原第 4981-4985 行)
- **原因**: 避免 `/v1/healthz` 健康检查在 k3s 环境下的兼容性问题
- **影响**: Pod 不会因为 readinessProbe 失败而一直处于 NotReady 状态

### 2. 优化 driver-deployer init 容器
- **位置**: `longhorn-driver-deployer` Deployment (第 5069-5071 行)
- **修改**: 添加超时机制（最多等待 5 分钟）
- **原因**: 避免在 manager 有问题时无限等待，导致 Pod 一直卡在 `Init:0/1`
- **新逻辑**: 
  ```bash
  max_attempts=150; attempt=0; 
  while [ $attempt -lt $max_attempts ]; do 
    # 检查 manager 是否就绪
    # 如果就绪，立即退出
    # 如果超时，打印警告但继续执行
  done
  ```

## 数据存储路径配置

### 默认路径
- **容器内挂载点**: `/var/lib/longhorn/`
- **主机路径**: `/var/lib/longhorn/`（可通过环境变量 `LONGHORN_DATA_PATH` 自定义）

### 配置方式
安装脚本会自动替换 YAML 文件中的数据存储路径：
```bash
# 使用默认路径
./install-longhorn.sh

# 使用自定义路径
LONGHORN_DATA_PATH=/data/longhorn ./install-longhorn.sh
```

## 安装顺序

资源对象的安装顺序很重要，Kubernetes 会按照以下顺序处理：

1. **Namespace** - 首先创建命名空间
2. **PriorityClass** - 定义优先级类
3. **ServiceAccount** - 创建服务账户
4. **ConfigMap** - 配置信息
5. **CRD** - 自定义资源定义（必须先于使用它们的资源创建）
6. **RBAC** - 权限绑定
7. **Service** - 服务定义
8. **DaemonSet/Deployment** - 工作负载

## 依赖关系

```
Namespace
  ├── ServiceAccount
  │   ├── ClusterRoleBinding
  │   └── Pod (使用 ServiceAccount)
  ├── ConfigMap
  │   └── Pod (挂载 ConfigMap)
  ├── Service
  │   └── Pod (通过 Service 暴露)
  └── CRD
      └── 自定义资源实例（由 Manager 创建）
```

## 关键组件交互

1. **longhorn-manager** (DaemonSet)
   - 在每个节点上运行
   - 管理卷、副本、引擎等资源
   - 提供 API 和 Webhook 服务

2. **longhorn-driver-deployer** (Deployment)
   - 部署 CSI 驱动
   - 使 Kubernetes 能够使用 Longhorn 作为存储后端

3. **longhorn-ui** (Deployment)
   - 提供 Web 管理界面
   - 通过 `longhorn-frontend` Service 访问

4. **CRD 资源**
   - 由 longhorn-manager 创建和管理
   - 定义卷、副本、备份等存储资源

## 验证安装

安装完成后，可以通过以下命令验证：

```bash
# 检查命名空间
kubectl get ns longhorn-system

# 检查 Pod 状态
kubectl get pods -n longhorn-system

# 检查 CRD
kubectl get crd | grep longhorn

# 检查 StorageClass
kubectl get sc longhorn

# 检查 Service
kubectl get svc -n longhorn-system
```

## 常见问题

### 1. Pod 一直处于 Init:0/1
- **原因**: `wait-longhorn-manager` init 容器在等待 manager 就绪
- **解决**: 已添加超时机制，最多等待 5 分钟后继续

### 2. Manager Pod CrashLoopBackOff
- **原因**: 可能是 webhook 健康检查失败
- **解决**: 已去掉 readinessProbe，避免 healthz 检查问题

### 3. 数据存储路径问题
- **原因**: 主机路径不存在或权限不足
- **解决**: 使用安装脚本自动检查和修复

## 相关文档

- [Longhorn 官方文档](https://longhorn.io/docs/)
- [安装脚本说明](./install-longhorn.sh)
- [K3s 存储文档](https://docs.k3s.io/add-ons/storage)

## 版本信息

- **Longhorn 版本**: v1.8.1
- **文件大小**: 5181 行
- **资源数量**: 40+ 个 Kubernetes 资源对象
- **最后更新**: 2025-12-23


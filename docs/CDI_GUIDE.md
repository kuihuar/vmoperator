# CDI (Containerized Data Importer) 详解

## 📋 什么是 CDI？

**CDI (Containerized Data Importer)** 是 KubeVirt 生态系统中的一个核心组件，专门用于**虚拟机磁盘数据的导入、导出和管理**。

### 核心作用

CDI 的主要作用是**将各种格式的数据源转换为虚拟机可用的磁盘**，并自动创建和管理相关的 Kubernetes 资源（如 PVC）。

## 🎯 CDI 的主要功能

### 1. 从容器镜像创建磁盘

**场景**: 当你有一个包含操作系统镜像的容器镜像时，CDI 可以：
- 从容器镜像仓库拉取镜像
- 提取镜像中的磁盘文件（qcow2/raw 格式）
- 将磁盘文件写入 PVC
- 供虚拟机使用

**示例**:
```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ubuntu-disk
spec:
  source:
    registry:
      url: "docker://quay.io/kubevirt/ubuntu-container-disk:latest"
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: local-path
    resources:
      requests:
        storage: 20Gi
```

### 2. 从 HTTP/HTTPS URL 导入磁盘

**场景**: 从网上下载的镜像文件（.img, .qcow2 等）

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ubuntu-disk
spec:
  source:
    http:
      url: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: local-path
    resources:
      requests:
        storage: 30Gi
```

### 3. 磁盘克隆

**场景**: 从现有的 PVC 克隆一个新的磁盘

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: cloned-disk
spec:
  source:
    pvc:
      name: source-disk
      namespace: default
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: local-path
    resources:
      requests:
        storage: 20Gi
```

### 4. 从 S3 对象存储导入

**场景**: 从 S3 兼容的对象存储导入数据

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: s3-disk
spec:
  source:
    s3:
      url: "s3://bucket-name/path/to/image.qcow2"
      secretRef: s3-secret
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: local-path
    resources:
      requests:
        storage: 20Gi
```

## 🔧 CDI 的关键资源

### 1. DataVolume

**作用**: 定义数据导入任务，CDI 会自动处理并创建 PVC

**生命周期**:
```
Pending → ImportScheduled → ImportInProgress → Succeeded
                                    ↓
                              (如果失败)
                                    ↓
                                Failed
```

**关键字段**:
- `spec.source`: 数据源（registry/http/pvc/s3）
- `spec.pvc`: 目标 PVC 配置
- `spec.storage`: 存储配置（可选）

### 2. DataSource

**作用**: 定义可重用的数据源，可以被多个 DataVolume 引用

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataSource
metadata:
  name: ubuntu-noble
spec:
  source:
    registry:
      url: "docker://localhost:5000/ubuntu-noble:latest"
```

### 3. DataImportCron

**作用**: 定期同步数据源（如定期拉取最新镜像）

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataImportCron
metadata:
  name: ubuntu-noble-cron
spec:
  schedule: "0 0 * * *"  # 每天同步
  template:
    spec:
      source:
        registry:
          url: "docker://localhost:5000/ubuntu-noble:latest"
      pvc:
        accessModes:
          - ReadWriteOnce
        storageClassName: local-path
        resources:
          requests:
            storage: 30Gi
```

## 🔄 CDI 工作流程

### 从容器镜像创建磁盘的完整流程

```
1. 用户创建 DataVolume
   │
   ▼
2. CDI Controller 检测到 DataVolume
   │
   ▼
3. 创建 Importer Pod
   │
   ├─→ 从镜像仓库拉取容器镜像
   │
   ├─→ 提取镜像中的磁盘文件
   │     (通常在 /disk.img 或 /disk/ 目录)
   │
   ├─→ 转换为合适的格式 (qcow2/raw)
   │
   └─→ 写入 PVC
   │
   ▼
4. DataVolume 状态变为 Succeeded
   │
   ▼
5. PVC 自动创建并绑定
   │
   ▼
6. 虚拟机可以使用这个 PVC 作为磁盘
```

### 在 Wukong 中的集成

当你在 Wukong 中指定 `disk.image` 时：

```yaml
spec:
  disks:
    - name: system
      size: 20Gi
      storageClassName: local-path
      boot: true
      image: "docker://localhost:5000/ubuntu-noble:latest"
```

**Wukong Controller 的处理流程**:

```
1. Controller 检测到 disk.image 字段
   │
   ▼
2. 调用 pkg/storage/datavolume.go::ReconcileDataVolume()
   │
   ▼
3. 创建 DataVolume 资源
   │
   ├─→ spec.source.registry.url = disk.image
   ├─→ spec.pvc.storageClassName = disk.StorageClassName
   └─→ spec.pvc.resources.requests.storage = disk.Size
   │
   ▼
4. CDI Controller 处理 DataVolume
   │
   ├─→ 创建 Importer Pod
   ├─→ 拉取镜像并导入数据
   └─→ 创建 PVC
   │
   ▼
5. 等待 DataVolume 状态变为 Succeeded
   │
   ▼
6. 返回 PVC 名称，供 VM 使用
```

## 📦 CDI 组件架构

### 核心组件

1. **CDI Operator**
   - 管理 CDI 的生命周期
   - 部署和管理其他 CDI 组件

2. **CDI Controller**
   - 监听 DataVolume 资源
   - 创建和管理 Importer/Uploader Pod
   - 更新 DataVolume 状态

3. **Importer Pod**
   - 执行实际的数据导入任务
   - 从各种源（registry/http/s3）拉取数据
   - 写入 PVC

4. **Uploader Pod**
   - 处理数据上传任务（导出）

5. **Cloner Pod**
   - 处理磁盘克隆任务

### 命名空间

CDI 默认安装在 `cdi` 命名空间：

```bash
# 查看 CDI 组件
kubectl get pods -n cdi

# 查看 DataVolume
kubectl get datavolume -A

# 查看 CDI 配置
kubectl get cdi -n cdi
```

## 🎯 在项目中的使用场景

### 场景 1: 从容器镜像创建系统盘

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
spec:
  disks:
    - name: system
      size: 30Gi
      storageClassName: local-path
      boot: true
      image: "docker://quay.io/kubevirt/ubuntu-container-disk:latest"
```

**CDI 处理**:
- 创建 DataVolume
- 从容器镜像导入数据到 PVC
- VM 使用 PVC 作为启动盘

### 场景 2: 从本地镜像文件创建磁盘

```yaml
# 先将本地 .img 文件转换为容器镜像
# docker build -t localhost:5000/ubuntu-noble:latest .

# 然后在 Wukong 中使用
spec:
  disks:
    - name: system
      size: 30Gi
      storageClassName: local-path
      boot: true
      image: "docker://localhost:5000/ubuntu-noble:latest"
```

### 场景 3: 创建空磁盘（不使用 CDI）

```yaml
spec:
  disks:
    - name: data
      size: 100Gi
      storageClassName: local-path
      boot: false
      # 不指定 image，直接创建空 PVC
```

## 🔍 监控和调试

### 查看 DataVolume 状态

```bash
# 列出所有 DataVolume
kubectl get datavolume -A

# 查看详细信息
kubectl describe datavolume <name> -n <namespace>

# 查看 DataVolume 事件
kubectl get events -n <namespace> --field-selector involvedObject.kind=DataVolume
```

### 查看 Importer Pod 日志

```bash
# 查找 Importer Pod
kubectl get pods -n <namespace> | grep importer

# 查看日志
kubectl logs -n <namespace> <importer-pod-name>
```

### 常见状态

- **Pending**: DataVolume 已创建，等待处理
- **ImportScheduled**: 导入任务已调度
- **ImportInProgress**: 正在导入数据
- **Succeeded**: 导入成功，PVC 已创建
- **Failed**: 导入失败，查看事件和日志

## ⚙️ 配置选项

### DataVolume 配置

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: example
spec:
  source:
    registry:
      url: "docker://example.com/image:tag"
      pullMethod: node  # 或 pod
      # secretRef: my-secret  # 私有镜像仓库
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: local-path
    resources:
      requests:
        storage: 20Gi
  # 可选：存储配置
  storage:
    resources:
      requests:
        storage: 20Gi
```

### CDI 全局配置

```bash
# 查看 CDI 配置
kubectl get cdi cdi -n cdi -o yaml

# 配置项包括：
# - 默认存储类
# - 上传/导入超时时间
# - 资源限制
```

## 🐛 故障排查

### 问题 1: DataVolume 一直处于 Pending 状态

**可能原因**:
- CDI Controller 未运行
- 资源配额不足
- StorageClass 不存在

**排查**:
```bash
# 检查 CDI Controller
kubectl get pods -n cdi

# 检查资源配额
kubectl describe quota -n <namespace>

# 检查 StorageClass
kubectl get storageclass
```

### 问题 2: 导入失败

**可能原因**:
- 镜像 URL 错误
- 网络连接问题
- 镜像格式不支持

**排查**:
```bash
# 查看 Importer Pod 日志
kubectl logs -n <namespace> <importer-pod>

# 查看 DataVolume 事件
kubectl describe datavolume <name> -n <namespace>
```

### 问题 3: 导入速度慢

**优化建议**:
- 使用本地镜像仓库
- 增加 Importer Pod 的资源限制
- 使用更快的存储后端

## 📚 参考资源

- [CDI 官方文档](https://github.com/kubevirt/containerized-data-importer)
- [CDI 用户指南](https://kubevirt.io/user-guide/operations/containerized_data_importer/)
- [DataVolume API 参考](https://kubevirt.io/api-reference/main/definitions.html#_v1beta1_datavolume)
- [KubeVirt 容器镜像格式](https://kubevirt.io/user-guide/virtual_machines/disks_and_volumes/#containerdisk)

## ✅ 总结

CDI 的核心价值：

1. **自动化**: 自动处理数据导入，无需手动操作
2. **统一接口**: 通过 DataVolume 统一管理各种数据源
3. **Kubernetes 原生**: 完全基于 Kubernetes 资源，易于集成
4. **灵活**: 支持多种数据源（容器镜像、HTTP、S3、PVC 克隆）
5. **可靠**: 提供状态监控、错误处理和重试机制

在 Wukong 项目中，CDI 使得用户只需指定 `disk.image` 字段，就能自动从容器镜像创建虚拟机磁盘，大大简化了虚拟机部署流程。

---

**提示**: CDI 是 KubeVirt 的必需组件，必须先安装 CDI 才能使用 Wukong 的镜像导入功能。


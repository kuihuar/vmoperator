# 虚拟机镜像指定指南

本文档说明如何在 Wukong 资源中指定虚拟机镜像。

## 📋 概述

在 Wukong 中，虚拟机镜像通过 **磁盘配置** 中的 `image` 字段指定。系统使用 **CDI (Containerized Data Importer)** 的 `DataVolume` 从容器镜像导入数据到 PVC，然后挂载到虚拟机。

## 🎯 两种磁盘创建方式

### 方式 1: 从容器镜像创建磁盘（推荐）

当指定 `disk.image` 时，系统会：
1. 创建 `DataVolume`（CDI 资源）
2. DataVolume 从容器镜像导入数据到 PVC
3. VM 使用这个 PVC 作为磁盘

**适用场景**：
- 需要从预制的操作系统镜像启动
- 需要快速部署标准化的虚拟机
- 使用 KubeVirt 官方或社区提供的镜像

### 方式 2: 创建空磁盘

当不指定 `disk.image` 时，系统会：
1. 直接创建空的 `PersistentVolumeClaim`
2. VM 使用这个空 PVC 作为磁盘

**适用场景**：
- 需要完全自定义的虚拟机
- 后续手动安装操作系统
- 从其他源导入数据

## 📝 配置示例

### 示例 1: 从容器镜像创建系统盘

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 20Gi
      storageClassName: local-path
      boot: true
      # 指定容器镜像 URL
      image: "docker://quay.io/kubevirt/fedora-cloud-container-disk-demo:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
```

### 示例 2: 多磁盘配置（系统盘 + 数据盘）

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: multi-disk-vm
spec:
  cpu: 4
  memory: 8Gi
  disks:
    # 系统盘：从镜像创建
    - name: system
      size: 40Gi
      storageClassName: huamei-sc-ssd
      boot: true
      image: "docker://quay.io/kubevirt/centos8-stream-container-disk:latest"
    # 数据盘：空磁盘
    - name: data
      size: 100Gi
      storageClassName: huamei-sc-ssd
      boot: false
      # 不指定 image，创建空磁盘
  networks:
    - name: mgmt
      type: bridge
      ipConfig:
        mode: static
        address: "192.168.100.10/24"
        gateway: "192.168.100.1"
```

### 示例 3: 使用私有镜像仓库

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: private-image-vm
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 30Gi
      storageClassName: local-path
      boot: true
      # 使用私有镜像仓库
      image: "docker://registry.example.com/my-org/ubuntu-22.04:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
```

## 🔍 镜像 URL 格式

### Docker 镜像格式

```
docker://<registry>/<repository>:<tag>
```

**示例**：
- `docker://quay.io/kubevirt/fedora-cloud-container-disk-demo:latest`
- `docker://registry.example.com/centos:8`
- `docker://docker.io/library/ubuntu:22.04`

### 支持的镜像格式

CDI 支持多种镜像格式：

1. **Docker 镜像**（最常用）：
   ```
   docker://registry.example.com/image:tag
   ```

2. **OCI 镜像**：
   ```
   oci://registry.example.com/image:tag
   ```

3. **HTTP/HTTPS URL**（直接下载）：
   ```
   http://example.com/image.qcow2
   https://example.com/image.raw
   ```

## 📦 常用 KubeVirt 镜像

### 官方镜像

KubeVirt 社区提供了一些预制的容器镜像：

1. **Fedora Cloud**:
   ```
   docker://quay.io/kubevirt/fedora-cloud-container-disk-demo:latest
   ```

2. **CentOS Stream 8**:
   ```
   docker://quay.io/kubevirt/centos8-stream-container-disk:latest
   ```

3. **Ubuntu**:
   ```
   docker://quay.io/kubevirt/ubuntu-container-disk:latest
   ```

### 查找更多镜像

访问 [KubeVirt 容器镜像仓库](https://quay.io/organization/kubevirt) 查找更多镜像。

## 🔧 工作原理

### 从镜像创建磁盘的流程

```
1. 用户在 Wukong 中指定 disk.image
   ↓
2. Controller 检测到 image 字段
   ↓
3. 创建 DataVolume 资源
   ↓
4. CDI Controller 处理 DataVolume
   ├─→ 从镜像仓库拉取容器镜像
   ├─→ 提取镜像中的磁盘文件（qcow2/raw）
   ├─→ 转换为合适的格式
   └─→ 写入 PVC
   ↓
5. DataVolume 状态变为 Succeeded
   ↓
6. PVC 绑定完成
   ↓
7. VM 使用 PVC 作为启动盘
```

### DataVolume 自动创建

当指定 `disk.image` 时，系统会自动创建类似以下的 DataVolume：

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: wukong-sample-system
spec:
  source:
    registry:
      url: "docker://quay.io/kubevirt/fedora-cloud-container-disk-demo:latest"
      pullMethod: node  # 在节点上拉取镜像
  pvc:
    accessModes:
      - ReadWriteOnce
    storageClassName: local-path
    resources:
      requests:
        storage: 20Gi
```

## ⚙️ 高级配置

### 使用 ImagePullSecret（私有镜像）

如果使用私有镜像仓库，需要创建 Secret：

```bash
# 创建镜像拉取 Secret
kubectl create secret docker-registry my-registry-secret \
  --docker-server=registry.example.com \
  --docker-username=username \
  --docker-password=password \
  --docker-email=email@example.com
```

**注意**：当前实现中，DataVolume 的 `pullMethod: node` 模式需要在节点上配置镜像拉取凭证。如果需要使用 Secret，可能需要修改代码以支持 `pullMethod: pod` 模式。

### 镜像拉取方法

当前实现使用 `pullMethod: node`，这意味着：
- 镜像在节点上拉取
- 需要节点有访问镜像仓库的权限
- 适合公开镜像或节点已配置凭证的情况

如果需要使用 Pod 模式（在 Pod 中使用 Secret）：
- 需要修改 `pkg/storage/datavolume.go` 中的 `pullMethod`
- 需要添加 `imagePullSecrets` 配置

## 📊 完整示例

### 示例：创建 Ubuntu 22.04 虚拟机

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-server
spec:
  cpu: 2
  memory: 4Gi
  
  # 系统盘：从 Ubuntu 镜像创建
  disks:
    - name: system
      size: 30Gi
      storageClassName: local-path
      boot: true
      image: "docker://quay.io/kubevirt/ubuntu-container-disk:latest"
  
  # 网络配置
  networks:
    - name: mgmt
      type: bridge
      ipConfig:
        mode: static
        address: "192.168.100.20/24"
        gateway: "192.168.100.1"
        dnsServers:
          - "8.8.8.8"
          - "8.8.4.4"
  
  # SSH 密钥（可选）
  sshKeySecret: my-ssh-keys
  
  # 启动策略
  startStrategy:
    autoStart: true
```

## 🐛 故障排查

### 问题 1: DataVolume 创建失败

**症状**: DataVolume 状态为 `Failed`

**排查**:
```bash
# 查看 DataVolume 状态
kubectl get datavolume
kubectl describe datavolume <name>

# 查看 CDI Pod 日志
kubectl logs -n cdi -l cdi.kubevirt.io=importer
```

**常见原因**:
- 镜像 URL 格式错误
- 镜像仓库不可访问
- 镜像不存在或标签错误

### 问题 2: 镜像拉取超时

**症状**: DataVolume 长时间处于 `ImportInProgress` 状态

**排查**:
```bash
# 检查网络连接
kubectl exec -n cdi <importer-pod> -- ping registry.example.com

# 检查镜像是否存在
curl -I https://registry.example.com/v2/<image>/manifests/<tag>
```

### 问题 3: 磁盘格式不支持

**症状**: VM 无法启动

**排查**:
- 确保镜像包含有效的磁盘文件（qcow2 或 raw 格式）
- 检查镜像是否是为 KubeVirt 准备的容器镜像

## 📚 参考资源

- [CDI 官方文档](https://github.com/kubevirt/containerized-data-importer)
- [KubeVirt 容器镜像](https://quay.io/organization/kubevirt)
- [DataVolume 配置参考](https://kubevirt.io/user-guide/operations/clone_api/)
- [使用本地下载的镜像文件](./LOCAL_IMAGE_GUIDE.md) - 如何将本地 .img 文件转换为容器镜像

## ✅ 最佳实践

1. **使用官方镜像**：优先使用 KubeVirt 官方或社区维护的镜像
2. **指定具体标签**：避免使用 `latest`，使用具体版本标签
3. **合理设置磁盘大小**：确保磁盘大小足够安装操作系统和应用
4. **使用合适的 StorageClass**：根据性能需求选择 SSD 或 HDD
5. **监控 DataVolume 状态**：在创建 VM 前确保 DataVolume 完成

---

**提示**: 如果不确定使用哪个镜像，可以从 KubeVirt 官方镜像开始测试。


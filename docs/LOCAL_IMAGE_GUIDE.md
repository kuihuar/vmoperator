# 使用本地下载的镜像文件指南

本文档说明如何将本地下载的虚拟机镜像文件（.img 文件）转换为容器镜像，以便在 Wukong 中使用。

## 📋 概述

如果你已经从网上下载了镜像文件（如 `noble-server-cloudimg-amd64.img`），需要将其转换为容器镜像格式，然后推送到容器镜像仓库，才能在 Wukong 中使用。

## 🎯 方法 1: 转换为容器镜像并推送到仓库（推荐）

### 步骤 1: 准备 Dockerfile

创建一个 Dockerfile 来将 .img 文件打包成容器镜像：

```dockerfile
FROM scratch
ADD noble-server-cloudimg-amd64.img /disk/
```

**说明**：
- `FROM scratch` 表示从空镜像开始
- `ADD` 将本地镜像文件复制到容器的 `/disk/` 目录

### 步骤 2: 构建容器镜像

```bash
# 假设镜像文件在当前目录
docker build -t localhost:5000/ubuntu-noble:latest .
```

或者使用 Podman（如果使用 k3s）：

```bash
podman build -t localhost:5000/ubuntu-noble:latest .
```

### 步骤 3: 推送到本地仓库

#### 如果使用 k3s 的本地仓库

k3s 默认启用本地镜像仓库（端口 5000），可以直接推送：

```bash
# 标记镜像
docker tag localhost:5000/ubuntu-noble:latest localhost:5000/ubuntu-noble:latest

# 推送到本地仓库
docker push localhost:5000/ubuntu-noble:latest
```

#### 如果使用其他仓库

```bash
# 推送到远程仓库
docker push your-registry.com/ubuntu-noble:latest

# 或推送到 Docker Hub
docker tag localhost:5000/ubuntu-noble:latest your-username/ubuntu-noble:latest
docker push your-username/ubuntu-noble:latest
```

### 步骤 4: 在 Wukong 中使用

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-vm
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 20Gi
      storageClassName: local-path
      boot: true
      # 使用本地仓库的镜像
      image: "docker://localhost:5000/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
```

## 🎯 方法 2: 使用 KubeVirt 容器镜像格式

KubeVirt 期望容器镜像中的磁盘文件位于特定路径。标准的 KubeVirt 容器镜像格式是：

```dockerfile
FROM scratch
ADD noble-server-cloudimg-amd64.img /disk.img
```

或者使用 KubeVirt 推荐的路径：

```dockerfile
FROM scratch
ADD noble-server-cloudimg-amd64.img /disk/
```

### 完整示例脚本

创建一个脚本 `build-image.sh`：

```bash
#!/bin/bash

IMAGE_FILE="noble-server-cloudimg-amd64.img"
IMAGE_NAME="localhost:5000/ubuntu-noble"
IMAGE_TAG="latest"

# 创建临时目录
TMP_DIR=$(mktemp -d)
cd $TMP_DIR

# 复制镜像文件
cp /path/to/$IMAGE_FILE ./disk.img

# 创建 Dockerfile
cat > Dockerfile <<EOF
FROM scratch
ADD disk.img /disk.img
EOF

# 构建镜像
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# 推送到本地仓库
docker push $IMAGE_NAME:$IMAGE_TAG

# 清理
cd -
rm -rf $TMP_DIR

echo "镜像已构建并推送: $IMAGE_NAME:$IMAGE_TAG"
```

## 🎯 方法 3: 直接导入到 PVC（不推荐，但可行）

如果不想使用容器镜像，也可以手动将镜像文件导入到 PVC：

### 步骤 1: 创建 PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ubuntu-noble-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 20Gi
```

### 步骤 2: 创建临时 Pod 并复制文件

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: image-importer
spec:
  containers:
  - name: importer
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: pvc
      mountPath: /data
  volumes:
  - name: pvc
    persistentVolumeClaim:
      claimName: ubuntu-noble-pvc
```

### 步骤 3: 复制镜像文件到 Pod

```bash
# 将本地镜像文件复制到 Pod
kubectl cp /path/to/noble-server-cloudimg-amd64.img image-importer:/data/disk.img
```

### 步骤 4: 在 Wukong 中使用现有 PVC

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-vm
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 20Gi
      storageClassName: local-path
      boot: true
      # 不指定 image，使用空 PVC
      # 然后手动导入镜像文件
```

**注意**：这种方法需要手动处理，不推荐用于生产环境。

## 🔧 使用 k3s 本地仓库

### 检查 k3s 本地仓库

k3s 默认在端口 5000 运行本地镜像仓库。检查是否启用：

```bash
# 检查 k3s 配置
cat /etc/rancher/k3s/registries.yaml
```

如果没有配置，可以创建：

```yaml
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
```

### 推送镜像到 k3s 本地仓库

```bash
# 标记镜像
docker tag ubuntu-noble:latest localhost:5000/ubuntu-noble:latest

# 推送到本地仓库
docker push localhost:5000/ubuntu-noble:latest

# 验证镜像
curl http://localhost:5000/v2/_catalog
```

## 📝 完整工作流程示例

### 示例：将 Ubuntu Noble 镜像转换为容器镜像

```bash
# 1. 创建临时目录
mkdir -p /tmp/ubuntu-image
cd /tmp/ubuntu-image

# 2. 复制镜像文件（假设已下载到 ~/Downloads）
cp ~/Downloads/noble-server-cloudimg-amd64.img ./disk.img

# 3. 创建 Dockerfile
cat > Dockerfile <<EOF
FROM scratch
ADD disk.img /disk.img
EOF

# 4. 构建镜像
docker build -t localhost:5000/ubuntu-noble:latest .

# 5. 推送到本地仓库
docker push localhost:5000/ubuntu-noble:latest

# 6. 验证
docker images | grep ubuntu-noble
```

### 在 Wukong 中使用

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-vm
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 30Gi
      storageClassName: local-path
      boot: true
      image: "docker://localhost:5000/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
  startStrategy:
    autoStart: true
```

## ⚠️ 注意事项

1. **镜像格式**：确保下载的 .img 文件是 KubeVirt 兼容的格式（qcow2 或 raw）
2. **磁盘大小**：PVC 的大小应该大于或等于镜像文件的大小
3. **本地仓库**：如果使用 k3s 本地仓库，确保所有节点都能访问
4. **镜像路径**：KubeVirt 容器镜像通常期望磁盘文件在 `/disk.img` 或 `/disk/` 目录
5. **权限**：确保有权限推送到镜像仓库

## 🐛 故障排查

### 问题 1: 无法推送到本地仓库

**症状**: `docker push` 失败

**解决**:
```bash
# 检查 k3s 仓库是否运行
curl http://localhost:5000/v2/_catalog

# 检查 Docker 配置
cat ~/.docker/config.json
```

### 问题 2: CDI 无法拉取镜像

**症状**: DataVolume 状态为 `Failed`

**排查**:
```bash
# 查看 DataVolume 状态
kubectl get datavolume
kubectl describe datavolume <name>

# 查看 CDI importer Pod 日志
kubectl logs -n cdi -l cdi.kubevirt.io=importer
```

### 问题 3: 镜像格式不支持

**症状**: VM 无法启动

**解决**:
- 确保镜像文件是 qcow2 或 raw 格式
- 检查镜像文件完整性：`file noble-server-cloudimg-amd64.img`

## 📚 参考资源

- [KubeVirt 容器镜像格式](https://kubevirt.io/user-guide/virtual_machines/disks_and_volumes/#containerdisk)
- [CDI 数据导入](https://github.com/kubevirt/containerized-data-importer)
- [k3s 镜像仓库配置](https://docs.k3s.io/installation/private-registry)

## ✅ 推荐流程

1. **下载镜像文件** ✅（已完成）
2. **转换为容器镜像**（使用 Dockerfile）
3. **推送到镜像仓库**（本地或远程）
4. **在 Wukong 中使用**（指定 `image` 字段）

---

**提示**: 最简单的方式是使用方法 1，将 .img 文件打包成容器镜像并推送到本地仓库。


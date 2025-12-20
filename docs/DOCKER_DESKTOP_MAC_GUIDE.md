# Docker Desktop + Mac 环境处理 Ubuntu qcow2 镜像指南

本文档专门针对 **Mac 系统 + Docker Desktop Kubernetes** 环境，说明如何处理下载的 Ubuntu qcow2 镜像。

## 📋 环境说明

- **操作系统**: macOS
- **容器运行时**: Docker Desktop
- **Kubernetes**: Docker Desktop 内置 Kubernetes
- **镜像文件**: Ubuntu qcow2 格式（如 `noble-server-cloudimg-amd64.img`）

## 🎯 方法 1: 转换为容器镜像并推送到 Docker Hub（推荐）

这是最简单且可靠的方法，适合 Docker Desktop 环境。

### 步骤 1: 准备 Dockerfile

在包含 qcow2 文件的目录中创建 Dockerfile：

```bash
# 假设镜像文件在当前目录
cd ~/Downloads  # 或你的镜像文件所在目录

# 创建 Dockerfile
cat > Dockerfile <<EOF
FROM scratch
ADD noble-server-cloudimg-amd64.img /disk.img
EOF
```

**说明**:
- `FROM scratch`: 从空镜像开始，最小化镜像大小
- `ADD`: 将 qcow2 文件复制到容器的 `/disk.img` 路径

### 步骤 2: 构建容器镜像

```bash
# 构建镜像（使用 Docker Hub 用户名）
docker build -t your-dockerhub-username/ubuntu-noble:latest .

# 例如：
# docker build -t jianfenliu/ubuntu-noble:latest .
```

**注意**: 
- 镜像文件较大，构建可能需要一些时间
- 确保有足够的磁盘空间

### 步骤 3: 推送到 Docker Hub

```bash
# 登录 Docker Hub（如果还没登录）
docker login

# 推送镜像
docker push your-dockerhub-username/ubuntu-noble:latest
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
      size: 30Gi
      storageClassName: local-path  # 或你的 StorageClass
      boot: true
      # 使用 Docker Hub 的镜像
      image: "docker://docker.io/your-dockerhub-username/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
```

## 🎯 方法 2: 使用本地 Docker Registry（开发测试）

如果不想推送到 Docker Hub，可以在本地运行一个 registry。

### 步骤 1: 启动本地 Registry

```bash
# 启动本地 registry（端口 5000）
docker run -d -p 5000:5000 --name local-registry registry:2

# 验证 registry 运行
curl http://localhost:5000/v2/_catalog
```

### 步骤 2: 配置 Docker Desktop 允许不安全仓库

**重要**: Docker Desktop 默认不允许访问 `localhost:5000`，需要配置。

1. 打开 Docker Desktop
2. 进入 **Settings** → **Docker Engine**
3. 添加以下配置：

```json
{
  "insecure-registries": ["localhost:5000"]
}
```

4. 点击 **Apply & Restart**

### 步骤 3: 构建并推送镜像

```bash
# 构建镜像
docker build -t localhost:5000/ubuntu-noble:latest .

# 推送到本地 registry
docker push localhost:5000/ubuntu-noble:latest

# 验证
curl http://localhost:5000/v2/_catalog
```

### 步骤 4: 配置 Kubernetes 使用本地 Registry

Docker Desktop 的 Kubernetes 需要配置才能访问本地 registry。

**方法 A: 使用 `host.docker.internal`**

```bash
# 构建时使用 host.docker.internal
docker build -t host.docker.internal:5000/ubuntu-noble:latest .

# 推送
docker push host.docker.internal:5000/ubuntu-noble:latest
```

**方法 B: 配置 Kubernetes 节点访问本地 registry**

创建 ConfigMap 配置镜像拉取：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosts
  namespace: kube-system
data:
  hosts.toml: |
    server = "http://host.docker.internal:5000"
    [host."http://host.docker.internal:5000"]
      insecure = true
```

### 步骤 5: 在 Wukong 中使用

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
      # 使用本地 registry
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
      # 或者（如果配置了）
      # image: "docker://localhost:5000/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
```

## 🎯 方法 3: 直接使用 HTTP URL（需要代码支持）

如果不想转换镜像，可以直接使用 HTTP URL。但**当前代码不支持**，需要修改 `pkg/storage/datavolume.go`。

**注意**: 如果你需要这个功能，我可以帮你修改代码支持 HTTP 源。

## 🔧 完整工作流程示例

### 示例：处理 Ubuntu Noble 镜像

```bash
# 1. 进入镜像文件目录
cd ~/Downloads

# 2. 检查文件
ls -lh noble-server-cloudimg-amd64.img
file noble-server-cloudimg-amd64.img

# 3. 创建 Dockerfile
cat > Dockerfile <<EOF
FROM scratch
ADD noble-server-cloudimg-amd64.img /disk.img
EOF

# 4. 构建镜像（推送到 Docker Hub）
docker build -t your-username/ubuntu-noble:latest .
docker push your-username/ubuntu-noble:latest

# 5. 验证镜像
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
      storageClassName: docker-desktop  # Docker Desktop 默认 StorageClass
      boot: true
      image: "docker://docker.io/your-username/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
  startStrategy:
    autoStart: true
```

## ⚠️ Docker Desktop 特殊注意事项

### 1. StorageClass 配置

Docker Desktop 的 Kubernetes 默认使用 `docker-desktop` StorageClass：

```bash
# 查看可用的 StorageClass
kubectl get storageclass

# 通常会有：
# - docker-desktop (默认)
# - local-path (如果安装了)
```

### 2. 资源限制

Docker Desktop 默认资源限制可能较小，建议：

1. 打开 Docker Desktop
2. 进入 **Settings** → **Resources**
3. 调整：
   - **Memory**: 至少 8GB（推荐 16GB+）
   - **CPU**: 至少 4 核
   - **Disk**: 至少 50GB

### 3. 网络配置

Docker Desktop 使用自己的网络栈，Multus 可能需要额外配置。

### 4. 文件路径

在 Mac 上，Docker Desktop 的文件系统是虚拟的，注意：
- 镜像文件路径要使用绝对路径或相对路径
- 确保文件在 Docker 可以访问的位置

## 🐛 故障排查

### 问题 1: 无法推送到 localhost:5000

**错误**: `dial tcp: lookup localhost: no such host`

**解决**:
```bash
# 使用 host.docker.internal 代替 localhost
docker push host.docker.internal:5000/ubuntu-noble:latest
```

### 问题 2: Kubernetes 无法拉取本地镜像

**错误**: `Failed to pull image`

**解决**:
1. 确保 registry 运行：`docker ps | grep registry`
2. 配置 Docker Desktop 允许不安全仓库
3. 使用 `host.docker.internal:5000` 而不是 `localhost:5000`

### 问题 3: 构建镜像时文件太大

**错误**: 磁盘空间不足

**解决**:
```bash
# 检查 Docker 磁盘使用
docker system df

# 清理未使用的资源
docker system prune -a

# 增加 Docker Desktop 磁盘限制
# Settings → Resources → Advanced → Disk image size
```

### 问题 4: CDI 无法拉取镜像

**排查步骤**:

```bash
# 1. 检查 DataVolume 状态
kubectl get datavolume -A

# 2. 查看 DataVolume 详情
kubectl describe datavolume <name> -n <namespace>

# 3. 查看 Importer Pod 日志
kubectl get pods -n <namespace> | grep importer
kubectl logs -n <namespace> <importer-pod-name>

# 4. 检查网络连接
kubectl exec -n <namespace> <importer-pod-name> -- ping docker.io
```

## 📝 快速脚本

创建一个自动化脚本 `build-and-push.sh`:

```bash
#!/bin/bash

# 配置
IMAGE_FILE="noble-server-cloudimg-amd64.img"
DOCKER_USERNAME="your-username"  # 替换为你的 Docker Hub 用户名
IMAGE_NAME="ubuntu-noble"
IMAGE_TAG="latest"

# 检查文件是否存在
if [ ! -f "$IMAGE_FILE" ]; then
    echo "错误: 找不到文件 $IMAGE_FILE"
    exit 1
fi

# 创建 Dockerfile
cat > Dockerfile <<EOF
FROM scratch
ADD $IMAGE_FILE /disk.img
EOF

# 构建镜像
echo "构建镜像..."
docker build -t $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG .

# 推送到 Docker Hub
echo "推送到 Docker Hub..."
docker push $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG

# 清理
rm Dockerfile

echo "完成！"
echo "在 Wukong 中使用: docker://docker.io/$DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
```

使用：

```bash
chmod +x build-and-push.sh
./build-and-push.sh
```

## ✅ 推荐方案

对于 **Mac + Docker Desktop** 环境，推荐使用 **方法 1（Docker Hub）**：

1. ✅ **简单**: 无需配置本地 registry
2. ✅ **可靠**: Docker Hub 稳定可靠
3. ✅ **跨环境**: 可以在任何地方使用
4. ✅ **免费**: Docker Hub 免费账户足够使用

### 完整命令示例

```bash
# 1. 准备
cd ~/Downloads
cat > Dockerfile <<EOF
FROM scratch
ADD noble-server-cloudimg-amd64.img /disk.img
EOF

# 2. 构建和推送
docker build -t your-username/ubuntu-noble:latest .
docker login
docker push your-username/ubuntu-noble:latest

# 3. 在 Wukong 中使用
# image: "docker://docker.io/your-username/ubuntu-noble:latest"
```

## 📚 相关文档

- [Docker Desktop 文档](https://docs.docker.com/desktop/)
- [Docker Hub 使用指南](https://docs.docker.com/docker-hub/)
- [CDI 指南](./CDI_GUIDE.md)
- [本地镜像处理指南](./LOCAL_IMAGE_GUIDE.md)

---

**提示**: 如果镜像文件很大（>5GB），推送到 Docker Hub 可能需要较长时间。可以考虑使用本地 registry 或私有仓库。


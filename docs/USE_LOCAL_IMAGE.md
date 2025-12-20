# 使用本地镜像 novasphere/ubuntu-noble:latest

你已经创建了本地镜像，现在需要让 Kubernetes 能够访问它。

## 🎯 方案 1: 使用本地 Registry（推荐）

这是最简单可靠的方法，适合开发测试。

### 步骤 1: 启动本地 Registry

**如果容器已存在**，先检查状态：

```bash
# 检查容器状态
docker ps -a | grep local-registry

# 如果容器已停止，启动它
docker start local-registry

# 如果容器正在运行，直接使用即可
# 如果需要重新创建，先删除旧容器
docker stop local-registry
docker rm local-registry
docker run -d -p 5000:5000 --name local-registry registry:2
```

**或者使用自动检查脚本**：

```bash
# 使用项目提供的检查脚本（会自动处理）
chmod +x scripts/check-registry.sh
./scripts/check-registry.sh
```

**验证 registry 运行**：

```bash
curl http://localhost:5000/v2/_catalog
```

### 步骤 2: 标记并推送镜像到本地 Registry

```bash
# 标记镜像（使用 host.docker.internal，这样 Kubernetes 可以访问）
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest

# 推送到本地 registry
docker push host.docker.internal:5000/ubuntu-noble:latest

# 验证
curl http://localhost:5000/v2/_catalog
```

**注意**: 如果 `docker push` 失败（出现 `https://` 或 `EOF` 错误），需要配置 Docker Desktop 允许不安全仓库（见下一步）。这是**必须的步骤**。

### 步骤 3: 配置 Docker Desktop（**必须步骤**）

**重要**: 如果推送失败（出现 `https://` 或 `EOF` 错误），**必须**配置 Docker Desktop：

1. 打开 **Docker Desktop**
2. 进入 **Settings** → **Docker Engine**
3. 在 JSON 配置中添加：

```json
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
```

**注意**: 如果已有其他配置，只需添加 `insecure-registries` 字段，不要删除现有配置。

4. 点击 **Apply & Restart**（Docker 会重启）
5. **等待 Docker 完全启动**（状态栏显示 "Docker Desktop is running"）
6. 验证配置：
   ```bash
   docker info | grep -A 10 "Insecure Registries"
   ```
7. 重新推送镜像

**详细配置步骤**: 参考 [Docker Desktop Registry 配置指南](./DOCKER_DESKTOP_REGISTRY_SETUP.md)

### 步骤 4: 在 Wukong 中使用

创建或更新 Wukong 资源：

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
      storageClassName: docker-desktop  # 或你的 StorageClass
      boot: true
      # 使用本地 registry 的镜像
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
  startStrategy:
    autoStart: true
```

应用配置：

```bash
kubectl apply -f wukong-ubuntu-noble.yaml
```

## 🎯 方案 2: 直接使用镜像名称（可能不工作）

在 Docker Desktop 环境中，Kubernetes 使用 containerd，可能无法直接访问 Docker 本地镜像。但可以尝试：

```yaml
spec:
  disks:
    - name: system
      size: 30Gi
      storageClassName: docker-desktop
      boot: true
      # 直接使用镜像名称（可能不工作）
      image: "docker://novasphere/ubuntu-noble:latest"
```

如果失败，会看到错误信息，然后使用方案 1。

## 🔧 快速操作脚本

创建一个脚本 `setup-local-registry.sh`:

```bash
#!/bin/bash

echo "1. 检查本地 registry..."
if ! docker ps | grep -q local-registry; then
    echo "   启动本地 registry..."
    docker run -d -p 5000:5000 --name local-registry registry:2
    sleep 2
else
    echo "   本地 registry 已运行"
fi

echo "2. 标记镜像..."
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest

echo "3. 推送镜像到本地 registry..."
docker push host.docker.internal:5000/ubuntu-noble:latest

echo "4. 验证..."
curl -s http://localhost:5000/v2/_catalog | jq .

echo ""
echo "✅ 完成！"
echo "在 Wukong 中使用: docker://host.docker.internal:5000/ubuntu-noble:latest"
```

使用：

```bash
chmod +x setup-local-registry.sh
./setup-local-registry.sh
```

## 📝 创建示例 Wukong 资源

创建文件 `config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml`:

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-local
  labels:
    app.kubernetes.io/name: novasphere
spec:
  cpu: 2
  memory: 4Gi
  disks:
    - name: system
      size: 30Gi
      storageClassName: docker-desktop
      boot: true
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
  networks:
    - name: default
      type: bridge
      ipConfig:
        mode: dhcp
  startStrategy:
    autoStart: true
```

应用：

```bash
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

## 🔍 验证和监控

### 检查 DataVolume 状态

```bash
# 查看 DataVolume
kubectl get datavolume -A

# 查看详细信息
kubectl describe datavolume ubuntu-noble-local-system -n default

# 查看事件
kubectl get events -n default --field-selector involvedObject.kind=DataVolume
```

### 查看 Importer Pod 日志

```bash
# 查找 Importer Pod
kubectl get pods -n default | grep importer

# 查看日志
kubectl logs -n default <importer-pod-name>
```

### 检查 Wukong 状态

```bash
# 查看 Wukong 资源
kubectl get wukong ubuntu-noble-local

# 查看详细信息
kubectl describe wukong ubuntu-noble-local
```

## 🐛 故障排查

### 问题 0: 容器名称冲突

**错误**: `Conflict. The container name "/local-registry" is already in use`

**解决**:

```bash
# 方法 1: 检查容器状态，如果已运行就直接使用
docker ps | grep local-registry

# 如果容器正在运行，直接使用即可，无需重新创建

# 方法 2: 如果容器已停止，启动它
docker start local-registry

# 方法 3: 如果需要重新创建，先删除旧容器
docker stop local-registry
docker rm local-registry
docker run -d -p 5000:5000 --name local-registry registry:2

# 方法 4: 使用自动检查脚本
chmod +x scripts/check-registry.sh
./scripts/check-registry.sh
```

### 问题 1: 无法推送到 localhost:5000

**错误**: `dial tcp: lookup localhost: no such host`

**解决**: 使用 `host.docker.internal:5000` 代替 `localhost:5000`

### 问题 2: 推送被拒绝

**错误**: `http: server gave HTTP response to HTTPS client`

**解决**: 配置 Docker Desktop 允许不安全仓库（见方案 1 步骤 3）

### 问题 3: CDI 无法拉取镜像

**错误**: DataVolume 状态为 `Failed`

**排查**:
```bash
# 1. 检查 registry 是否运行
docker ps | grep local-registry

# 2. 测试从 Kubernetes 节点访问 registry
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- curl http://host.docker.internal:5000/v2/_catalog

# 3. 查看 Importer Pod 日志
kubectl logs -n default <importer-pod-name>
```

### 问题 4: 镜像格式问题

**错误**: 导入成功但 VM 无法启动

**检查**:
```bash
# 检查镜像文件是否正确
docker run --rm -it --entrypoint sh novasphere/ubuntu-noble:latest -c "ls -lh /disk.img"
```

## ✅ 推荐操作流程

1. **启动本地 registry**（如果还没启动）
   ```bash
   docker run -d -p 5000:5000 --name local-registry registry:2
   ```

2. **标记并推送镜像**
   ```bash
   docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest
   docker push host.docker.internal:5000/ubuntu-noble:latest
   ```

3. **创建 Wukong 资源**
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```

4. **监控状态**
   ```bash
   kubectl get datavolume -w
   kubectl get wukong ubuntu-noble-local -w
   ```

## 📚 下一步

镜像成功导入后，你可以：

1. **查看 VM 状态**: `kubectl get vm`
2. **查看 VMI**: `kubectl get vmi`
3. **连接到 VM**: 使用 `virtctl console` 或配置 SSH
4. **测试网络**: 检查网络配置是否正确

---

**提示**: 如果遇到问题，查看 DataVolume 和 Importer Pod 的日志，通常能找到原因。


# 解决本地 Registry 推送问题

## 🔴 错误信息

```
failed to do request: Head "https://host.docker.internal:5000/v2/ubuntu-noble/blobs/...": EOF
```

## 📋 问题原因

Docker 尝试使用 **HTTPS** 连接本地 registry，但本地 registry 默认使用 **HTTP**，导致连接失败。

## ✅ 解决方案

### 方法 1: 配置 Docker Desktop 允许不安全仓库（推荐）

1. **打开 Docker Desktop**
2. **进入 Settings** → **Docker Engine**
3. **添加以下配置**：

```json
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
```

4. **点击 "Apply & Restart"**（Docker 会重启）
5. **等待 Docker 完全启动后，重新推送**：

```bash
docker push host.docker.internal:5000/ubuntu-noble:latest
```

### 方法 2: 使用 localhost 代替 host.docker.internal

如果方法 1 不行，尝试使用 `localhost`：

```bash
# 重新标记镜像
docker tag novasphere/ubuntu-noble:latest localhost:5000/ubuntu-noble:latest

# 推送
docker push localhost:5000/ubuntu-noble:latest
```

**注意**: 在 Wukong 中也需要使用 `localhost:5000`，但 Kubernetes 可能无法访问 `localhost`，所以还是推荐使用方法 1。

### 方法 3: 使用 127.0.0.1

```bash
# 重新标记镜像
docker tag novasphere/ubuntu-noble:latest 127.0.0.1:5000/ubuntu-noble:latest

# 推送
docker push 127.0.0.1:5000/ubuntu-noble:latest
```

## 🔍 验证配置

### 检查 Docker 配置

```bash
# 查看 Docker 配置
docker info | grep -A 5 "Insecure Registries"
```

应该看到：
```
Insecure Registries:
 localhost:5000
 host.docker.internal:5000
 127.0.0.1:5000
```

### 测试 Registry 连接

```bash
# 测试 HTTP 连接
curl http://localhost:5000/v2/_catalog

# 应该返回 JSON 格式的镜像列表
```

## 📝 完整操作流程

### 1. 配置 Docker Desktop

1. 打开 Docker Desktop
2. Settings → Docker Engine
3. 添加配置（如果已有其他配置，合并添加）：

```json
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
```

4. Apply & Restart
5. 等待 Docker 完全启动（状态栏显示 "Docker Desktop is running"）

### 2. 验证 Registry 运行

```bash
# 检查 registry 容器
docker ps | grep local-registry

# 如果没运行，启动它
docker start local-registry

# 测试连接
curl http://localhost:5000/v2/_catalog
```

### 3. 标记并推送镜像

```bash
# 标记镜像
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest

# 推送镜像
docker push host.docker.internal:5000/ubuntu-noble:latest

# 验证
curl http://localhost:5000/v2/_catalog
```

### 4. 在 Wukong 中使用

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-local
spec:
  disks:
    - name: system
      size: 30Gi
      storageClassName: docker-desktop
      boot: true
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
```

## 🐛 其他可能的问题

### 问题 1: Registry 容器未运行

**检查**:
```bash
docker ps -a | grep local-registry
```

**解决**:
```bash
docker start local-registry
```

### 问题 2: 端口被占用

**检查**:
```bash
lsof -i :5000
```

**解决**: 使用其他端口或停止占用端口的进程

### 问题 3: 防火墙阻止

Mac 通常不会有这个问题，但如果遇到，检查防火墙设置。

## ✅ 成功标志

推送成功后，你应该看到：

```
The push refers to repository [host.docker.internal:5000/ubuntu-noble]
d02cbf43d6fd: Pushed
310017020499: Pushed
latest: digest: sha256:... size: ...
```

然后验证：

```bash
curl http://localhost:5000/v2/_catalog
```

应该返回：
```json
{"repositories":["ubuntu-noble"]}
```

## 📚 下一步

镜像推送成功后：

1. **创建 Wukong 资源**:
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```

2. **监控 DataVolume 状态**:
   ```bash
   kubectl get datavolume -w
   ```

3. **查看 Wukong 状态**:
   ```bash
   kubectl get wukong ubuntu-noble-local -w
   ```

---

**提示**: 配置 Docker Desktop 后需要重启，确保完全启动后再推送镜像。


# 验证 Docker Desktop 配置

## ✅ 你的配置文件

你的配置看起来是**正确的**：

```json
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": false,
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ],
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "https://mirror.ccs.tencentyun.com"
  ]
}
```

✅ JSON 格式正确  
✅ 包含了所有需要的 `insecure-registries`  
✅ 其他配置也是合理的

## 🔍 验证配置是否生效

### 方法 1: 使用验证脚本（推荐）

```bash
chmod +x scripts/verify-docker-config.sh
./scripts/verify-docker-config.sh
```

脚本会自动检查：
- Docker 是否运行
- 不安全仓库配置是否生效
- Registry 是否运行
- 连接是否正常

### 方法 2: 手动验证

```bash
# 1. 检查配置是否生效
docker info | grep -A 10 "Insecure Registries"

# 应该看到：
# Insecure Registries:
#  localhost:5000
#  host.docker.internal:5000
#  127.0.0.1:5000
```

如果**没有看到**这些地址，说明配置未生效，需要：

1. **确认已点击 "Apply & Restart"**
2. **等待 Docker 完全重启**（状态栏显示 "Docker Desktop is running"）
3. **重新检查**

## 🐛 如果配置正确但仍然失败

### 检查 1: Docker 是否已重启

```bash
# 检查 Docker 运行时间
docker info | grep "Server Version"
```

如果配置后没有重启，配置不会生效。

### 检查 2: Registry 容器状态

```bash
# 检查 registry 是否运行
docker ps | grep local-registry

# 如果没运行，启动它
docker start local-registry

# 验证 registry 可访问
curl http://localhost:5000/v2/_catalog
```

### 检查 3: 网络连接

```bash
# 测试从 Docker 内部访问 registry
docker run --rm curlimages/curl curl http://host.docker.internal:5000/v2/_catalog
```

### 检查 4: 镜像标记

```bash
# 确认镜像已正确标记
docker images | grep ubuntu-noble

# 应该看到：
# host.docker.internal:5000/ubuntu-noble   latest   ...
```

如果没有，重新标记：

```bash
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest
```

## 🔄 完整测试流程

### 1. 验证配置

```bash
docker info | grep -A 10 "Insecure Registries"
```

### 2. 启动 Registry（如果需要）

```bash
docker start local-registry
# 或
docker run -d -p 5000:5000 --name local-registry registry:2
```

### 3. 测试 Registry 连接

```bash
curl http://localhost:5000/v2/_catalog
```

### 4. 标记镜像

```bash
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest
```

### 5. 推送镜像

```bash
docker push host.docker.internal:5000/ubuntu-noble:latest
```

## ⚠️ 常见问题

### 问题 1: 配置显示但推送仍然失败

**可能原因**:
- Docker Desktop 缓存问题
- Registry 容器问题

**解决**:
```bash
# 完全重启 Docker Desktop
# 1. 退出 Docker Desktop
# 2. 重新启动
# 3. 等待完全启动

# 重新创建 registry 容器
docker stop local-registry
docker rm local-registry
docker run -d -p 5000:5000 --name local-registry registry:2
```

### 问题 2: 仍然看到 HTTPS 错误

**检查**:
```bash
# 查看详细的 Docker 配置
docker info

# 确认 insecure-registries 包含所有地址
docker info | grep -A 20 "Insecure Registries"
```

### 问题 3: Registry 连接超时

**可能原因**:
- 端口被占用
- 防火墙阻止

**解决**:
```bash
# 检查端口占用
lsof -i :5000

# 使用其他端口
docker run -d -p 5001:5000 --name local-registry registry:2
# 然后使用 host.docker.internal:5001
```

## ✅ 成功标志

配置正确且生效后：

1. **`docker info` 显示不安全仓库**:
   ```
   Insecure Registries:
    localhost:5000
    host.docker.internal:5000
    127.0.0.1:5000
   ```

2. **推送成功**:
   ```
   The push refers to repository [host.docker.internal:5000/ubuntu-noble]
   d02cbf43d6fd: Pushed
   310017020499: Pushed
   latest: digest: sha256:... size: ...
   ```

3. **Registry 中有镜像**:
   ```bash
   curl http://localhost:5000/v2/_catalog
   # 返回: {"repositories":["ubuntu-noble"]}
   ```

## 📝 下一步

如果配置验证通过，但推送仍然失败，请：

1. **运行验证脚本**:
   ```bash
   ./scripts/verify-docker-config.sh
   ```

2. **查看详细错误信息**:
   ```bash
   docker push host.docker.internal:5000/ubuntu-noble:latest 2>&1 | tee push.log
   ```

3. **检查 Docker 日志**（如果 Docker Desktop 有日志功能）

---

**提示**: 你的配置文件是正确的，问题可能在于配置未生效或 Docker 未重启。先运行验证脚本确认。


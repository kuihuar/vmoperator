# Registry 地址使用说明

## 🤔 问题：推送和拉取使用不同地址？

### 关键理解

- **推送时**（在宿主机 Mac 上）: 可以使用 `localhost:5000`
- **拉取时**（在 Kubernetes Pod 中）: 必须使用 `host.docker.internal:5000`

## 📋 详细说明

### 场景 1: 在宿主机上推送镜像

当你在 **Mac 终端** 执行 `docker push` 时：

```bash
# 方法 1: 使用 localhost（推荐在宿主机上使用）
docker tag novasphere/ubuntu-noble:latest localhost:5000/ubuntu-noble:latest
docker push localhost:5000/ubuntu-noble:latest
# ✅ 可以工作，因为 localhost 在宿主机上指向自己

# 方法 2: 使用 host.docker.internal
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest
docker push host.docker.internal:5000/ubuntu-noble:latest
# ⚠️ 可能工作，取决于 Docker Desktop 配置
```

**在宿主机上的行为**:
- `localhost:5000` → 指向 Mac 自己的 5000 端口 ✅
- `host.docker.internal:5000` → 可能解析，也可能不解析 ⚠️

### 场景 2: 在 Kubernetes Pod 中拉取镜像

当 **CDI Importer Pod** 尝试拉取镜像时：

```yaml
# Wukong 配置
spec:
  disks:
    - name: system
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
      # ↑ 这个地址会被 CDI Importer Pod 使用
```

**在 Pod（容器）中的行为**:
- `localhost:5000` → 指向 Pod 自己 ❌（无法访问宿主机）
- `host.docker.internal:5000` → 指向宿主机 ✅（可以访问）

## ✅ 推荐方案：使用两个地址

### 方案 A: 推送用 localhost，拉取用 host.docker.internal（推荐）

```bash
# 1. 在宿主机上推送（使用 localhost）
docker tag novasphere/ubuntu-noble:latest localhost:5000/ubuntu-noble:latest
docker push localhost:5000/ubuntu-noble:latest

# 2. 再标记一个 host.docker.internal 版本（用于 Kubernetes）
docker tag localhost:5000/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest
docker push host.docker.internal:5000/ubuntu-noble:latest
```

**在 Wukong 中使用**:
```yaml
image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
```

### 方案 B: 统一使用 host.docker.internal

```bash
# 1. 标记为 host.docker.internal
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest

# 2. 推送（在宿主机上）
docker push host.docker.internal:5000/ubuntu-noble:latest
```

**注意**: 如果推送失败，尝试使用 `localhost:5000` 推送，然后再标记。

## 🔍 验证方法

### 在宿主机上验证

```bash
# 检查 registry 是否可访问
curl http://localhost:5000/v2/_catalog
# ✅ 应该返回镜像列表

# 尝试使用 host.docker.internal
curl http://host.docker.internal:5000/v2/_catalog
# ⚠️ 可能工作，也可能不工作
```

### 在容器中验证

```bash
# 从容器内访问 localhost（会失败）
docker run --rm curlimages/curl curl http://localhost:5000/v2/_catalog
# ❌ 无法访问宿主机上的 registry

# 从容器内访问 host.docker.internal（应该成功）
docker run --rm curlimages/curl curl http://host.docker.internal:5000/v2/_catalog
# ✅ 可以访问宿主机上的 registry
```

## 🎯 实际工作流程

### 完整流程

```
1. 在 Mac 上推送镜像
   ↓
   docker push localhost:5000/ubuntu-noble:latest
   ✅ 推送到宿主机上的 registry
   
2. 镜像存储在 registry 中
   ↓
   registry 运行在 Mac 的 5000 端口
   
3. Kubernetes Pod 拉取镜像
   ↓
   Pod 使用: host.docker.internal:5000/ubuntu-noble:latest
   ✅ 通过 host.docker.internal 访问宿主机上的 registry
```

### 关键点

- **Registry 只有一个**: 运行在 Mac 的 5000 端口
- **推送地址**: 在宿主机上可以用 `localhost:5000`
- **拉取地址**: 在容器中必须用 `host.docker.internal:5000`
- **镜像名称**: 可以标记为不同的名称，但指向同一个 registry

## 🔧 最佳实践

### 推荐做法

```bash
# 1. 推送时使用 localhost（在宿主机上）
docker tag novasphere/ubuntu-noble:latest localhost:5000/ubuntu-noble:latest
docker push localhost:5000/ubuntu-noble:latest

# 2. 验证推送成功
curl http://localhost:5000/v2/_catalog

# 3. 在 Wukong 中使用 host.docker.internal（给 Kubernetes 用）
# 注意：镜像已经在 registry 中，只是地址不同
```

**Wukong 配置**:
```yaml
spec:
  disks:
    - name: system
      image: "docker://host.docker.internal:5000/ubuntu-noble:latest"
      # ↑ Kubernetes Pod 会使用这个地址拉取
```

### 为什么这样工作？

1. **Registry 是同一个**: 无论用什么地址推送，都存储在同一个 registry
2. **镜像名称是标签**: `localhost:5000/ubuntu-noble:latest` 和 `host.docker.internal:5000/ubuntu-noble:latest` 在 registry 中可能是同一个镜像（取决于 registry 的实现）
3. **访问路径不同**: 
   - 宿主机 → `localhost:5000` ✅
   - 容器 → `host.docker.internal:5000` ✅

## ⚠️ 注意事项

### 1. Registry 行为

某些 registry 实现可能会：
- 将不同名称视为不同镜像
- 需要分别推送两个名称

**解决**: 如果遇到问题，两个地址都推送：

```bash
# 推送 localhost 版本
docker push localhost:5000/ubuntu-noble:latest

# 推送 host.docker.internal 版本
docker push host.docker.internal:5000/ubuntu-noble:latest
```

### 2. Docker Desktop 配置

确保 `insecure-registries` 包含两个地址：

```json
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
```

### 3. 验证两个地址

```bash
# 验证 localhost
curl http://localhost:5000/v2/_catalog

# 验证 host.docker.internal（在容器中）
docker run --rm curlimages/curl curl http://host.docker.internal:5000/v2/_catalog
```

## 📝 更新推送脚本

可以更新 `scripts/push-to-local-registry.sh` 同时推送两个地址：

```bash
# 推送 localhost 版本（宿主机用）
docker push localhost:5000/ubuntu-noble:latest

# 推送 host.docker.internal 版本（Kubernetes 用）
docker push host.docker.internal:5000/ubuntu-noble:latest
```

## ✅ 总结

| 场景 | 地址 | 说明 |
|------|------|------|
| **宿主机推送** | `localhost:5000` | ✅ 推荐使用 |
| **宿主机推送** | `host.docker.internal:5000` | ⚠️ 可能工作 |
| **容器拉取** | `localhost:5000` | ❌ 无法访问宿主机 |
| **容器拉取** | `host.docker.internal:5000` | ✅ 必须使用 |

**关键**: 
- 推送时可以用 `localhost:5000`（在宿主机上）
- 拉取时必须用 `host.docker.internal:5000`（在容器中）
- 两个地址指向同一个 registry，只是访问路径不同

---

**提示**: 如果推送 `host.docker.internal:5000` 失败，改用 `localhost:5000` 推送，然后在 Wukong 中仍然使用 `host.docker.internal:5000`（因为 Kubernetes Pod 需要这个地址）。


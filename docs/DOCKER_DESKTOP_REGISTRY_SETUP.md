# Docker Desktop 配置本地 Registry 完整指南

## 🔴 错误信息

```
failed to do request: Head "https://host.docker.internal:5000/v2/ubuntu-noble/blobs/...": EOF
```

这个错误表示 Docker 尝试使用 **HTTPS** 连接，但本地 registry 使用 **HTTP**。

## ✅ 解决方案：配置 Docker Desktop

### 步骤 1: 打开 Docker Desktop 设置

1. 点击 Mac 顶部菜单栏的 **Docker 图标** 🐳
2. 选择 **Settings**（或 **Preferences**）

### 步骤 2: 进入 Docker Engine 配置

1. 在左侧菜单中找到 **Docker Engine**
2. 点击进入

### 步骤 3: 编辑 JSON 配置

在右侧的 JSON 编辑器中，找到现有的配置（可能是空的 `{}` 或已有其他配置）。

**如果配置是空的**，替换为：

```json
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
```

**如果已有其他配置**，添加 `insecure-registries` 字段：

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  },
  "experimental": false,
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
```

### 步骤 4: 应用配置

1. 点击右下角的 **"Apply & Restart"** 按钮
2. **等待 Docker 完全重启**（可能需要 30 秒到 1 分钟）
3. 确保状态栏显示 **"Docker Desktop is running"**

### 步骤 5: 验证配置

打开终端，运行：

```bash
# 检查配置是否生效
docker info | grep -A 10 "Insecure Registries"
```

应该看到：

```
Insecure Registries:
 localhost:5000
 host.docker.internal:5000
 127.0.0.1:5000
```

### 步骤 6: 重新推送镜像

```bash
# 确保 registry 运行
docker start local-registry

# 重新推送
docker push host.docker.internal:5000/ubuntu-noble:latest
```

## 📸 配置截图说明

### Docker Desktop Settings 界面

```
┌─────────────────────────────────────┐
│ Docker Desktop Settings             │
├─────────────────────────────────────┤
│ General                             │
│ Resources                            │
│ Docker Engine  ← 点击这里           │
│ Features in development              │
│ ...                                  │
└─────────────────────────────────────┘
```

### Docker Engine 配置界面

```
┌─────────────────────────────────────┐
│ Docker Engine                       │
├─────────────────────────────────────┤
│                                     │
│ {                                   │
│   "insecure-registries": [         │
│     "localhost:5000",              │
│     "host.docker.internal:5000",   │
│     "127.0.0.1:5000"               │
│   ]                                 │
│ }                                   │
│                                     │
│ [Apply & Restart]  ← 点击这里      │
└─────────────────────────────────────┘
```

## 🔍 详细故障排查

### 问题 1: 配置后仍然失败

**检查清单**:

1. **确认 Docker 已完全重启**
   ```bash
   # 检查 Docker 状态
   docker info
   ```

2. **确认配置已保存**
   ```bash
   # 查看配置
   docker info | grep -A 10 "Insecure Registries"
   ```

3. **确认 registry 容器运行**
   ```bash
   docker ps | grep local-registry
   ```

4. **测试 registry 连接**
   ```bash
   curl http://localhost:5000/v2/_catalog
   ```

### 问题 2: 找不到 Docker Engine 设置

**可能的原因**:
- Docker Desktop 版本较旧
- 设置菜单位置不同

**解决**:
1. 更新 Docker Desktop 到最新版本
2. 在 Settings 中查找 "Docker Engine" 或 "Advanced"
3. 如果使用 Docker Desktop for Mac，应该都有这个选项

### 问题 3: JSON 格式错误

**常见错误**:
- 缺少逗号
- 多余的逗号
- 引号不匹配

**正确格式示例**:

```json
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000"
  ]
}
```

**错误格式示例**:

```json
{
  "insecure-registries": [
    "localhost:5000",  ← 最后一个元素后面不能有逗号
    "host.docker.internal:5000",  ← 这里可以有逗号
  ]  ← 但这里不能有逗号
}
```

### 问题 4: 重启后配置丢失

**可能原因**:
- Docker Desktop 配置文件权限问题
- 配置文件被其他工具修改

**解决**:
1. 检查配置文件位置（Mac）:
   ```bash
   ~/.docker/daemon.json
   ```
2. 手动编辑配置文件（如果 Docker Desktop 界面不工作）:
   ```bash
   # 创建或编辑配置文件
   mkdir -p ~/.docker
   cat > ~/.docker/daemon.json <<EOF
   {
     "insecure-registries": [
       "localhost:5000",
       "host.docker.internal:5000",
       "127.0.0.1:5000"
     ]
   }
   EOF
   ```
3. 重启 Docker Desktop

## 🧪 完整测试流程

### 1. 检查 Docker 配置

```bash
docker info | grep -A 10 "Insecure Registries"
```

### 2. 检查 Registry 运行

```bash
docker ps | grep local-registry
# 如果没运行
docker start local-registry
```

### 3. 测试 Registry 连接

```bash
curl http://localhost:5000/v2/_catalog
# 应该返回: {"repositories":[]} 或包含镜像列表
```

### 4. 标记镜像

```bash
docker tag novasphere/ubuntu-noble:latest host.docker.internal:5000/ubuntu-noble:latest
```

### 5. 推送镜像

```bash
docker push host.docker.internal:5000/ubuntu-noble:latest
```

### 6. 验证推送

```bash
curl http://localhost:5000/v2/_catalog
# 应该返回: {"repositories":["ubuntu-noble"]}
```

## 📝 快速参考

### 配置命令（一键配置）

```bash
# 创建配置文件
mkdir -p ~/.docker
cat > ~/.docker/daemon.json <<'EOF'
{
  "insecure-registries": [
    "localhost:5000",
    "host.docker.internal:5000",
    "127.0.0.1:5000"
  ]
}
EOF

# 重启 Docker Desktop（需要手动在界面中重启）
echo "请手动重启 Docker Desktop:"
echo "1. 点击 Docker 图标"
echo "2. 选择 'Restart'"
```

### 验证命令

```bash
# 检查配置
docker info | grep -A 10 "Insecure Registries"

# 检查 registry
docker ps | grep local-registry
curl http://localhost:5000/v2/_catalog

# 推送测试
docker push host.docker.internal:5000/ubuntu-noble:latest
```

## ✅ 成功标志

配置成功后，推送应该显示：

```
The push refers to repository [host.docker.internal:5000/ubuntu-noble]
d02cbf43d6fd: Pushed
310017020499: Pushed
latest: digest: sha256:... size: ...
```

而不是 `https://` 或 `EOF` 错误。

## 🎯 下一步

配置完成后：

1. **重新推送镜像**:
   ```bash
   docker push host.docker.internal:5000/ubuntu-noble:latest
   ```

2. **创建 Wukong 资源**:
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```

3. **监控状态**:
   ```bash
   kubectl get datavolume -w
   kubectl get wukong ubuntu-noble-local -w
   ```

---

**重要提示**: 配置后**必须重启 Docker Desktop**，配置才会生效！


# 镜像拉取地址说明

## crictl pull 的地址解析

当执行 `sudo crictl pull rancher/mirrored-pause:3.6` 时：

1. **镜像名称解析**：
   - `rancher/mirrored-pause:3.6` → `docker.io/rancher/mirrored-pause:3.6`
   - containerd 会自动添加 `docker.io` 前缀（Docker Hub 的默认注册表）

2. **实际请求地址**：
   - `https://registry-1.docker.io/v2/rancher/mirrored-pause/manifests/3.6`
   - 这是 Docker Hub 的官方 API 端点

3. **目标服务器**：
   - IP: `128.242.240.221:443`
   - 这是 Docker Hub 的服务器地址

## 为什么连接超时？

- 网络无法访问 Docker Hub（可能被防火墙阻止或需要代理）
- 已清理镜像源配置，containerd 直接访问 Docker Hub
- Docker Hub 在某些地区访问较慢或不稳定

## 解决方案

### 方案 1: 使用本地镜像（推荐）

如果本地已有镜像，不需要拉取：

```bash
# 检查本地镜像
sudo crictl images | grep pause

# 如果存在，k3s 会直接使用，无需拉取
```

### 方案 2: 配置镜像源

如果需要从网络拉取，可以配置镜像源：

```bash
# 创建镜像源配置
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
  registry-1.docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
EOF

# 重启 k3s
sudo systemctl restart k3s
```

**注意**：如果镜像源返回 403 Forbidden，说明该镜像源不支持该镜像或需要认证。

### 方案 3: 手动导入镜像

如果网络无法访问，可以手动导入镜像：

```bash
# 从其他源下载镜像文件
# 然后使用 ctr 导入
sudo ctr -n k8s.io images import pause-image.tar
```

## 当前情况

根据之前的检查：
- ✅ 本地已有 `rancher/mirrored-pause:3.6` 镜像
- ✅ 镜像在 containerd 中可用
- ❌ 网络无法访问 Docker Hub

**建议**：不需要拉取镜像，直接使用本地镜像即可。k3s 在创建 Pod 时会优先使用本地镜像。

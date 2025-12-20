# 修复 Docker Hub 超时问题

## 问题现象

```
Failed to create pod sandbox: failed to pull image "rancher/mirrored-pause:3.6": 
failed to do request: Head "https://registry-1.docker.io/v2/rancher/mirrored-pause/manifests/3.6": 
dial tcp 199.96.59.61:443: i/o timeout
```

这是网络问题，无法访问 Docker Hub。

## 解决方案

### 方案 1: 配置 k3s 镜像代理（推荐）

k3s 可以通过配置镜像仓库来解决 Docker Hub 访问问题。

#### 步骤 1: 创建镜像仓库配置

```bash
# 创建配置目录
sudo mkdir -p /etc/rancher/k3s

# 创建镜像仓库配置文件
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
      - "https://mirror.azure.cn"
      - "https://reg-mirror.qiniu.com"
  registry-1.docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
      - "https://mirror.azure.cn"
      - "https://reg-mirror.qiniu.com"
EOF
```

#### 步骤 2: 重启 k3s

```bash
sudo systemctl restart k3s

# 等待 k3s 就绪
sleep 10
kubectl get nodes
```

#### 步骤 3: 手动拉取镜像

```bash
# 配置 crictl
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml

# 拉取 pause 镜像
crictl pull rancher/mirrored-pause:3.6

# 或者使用国内镜像源
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6
```

#### 步骤 4: 删除 Pod 重新创建

```bash
# 删除 Pod，让它重新创建
kubectl delete pod -n kubevirt -l app=virt-operator

# 观察重新创建
kubectl get pods -n kubevirt -w
```

### 方案 2: 手动拉取镜像（临时方案）

如果无法配置镜像代理，可以手动拉取镜像：

```bash
# 拉取 pause 镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl pull rancher/mirrored-pause:3.6

# 如果直接拉取失败，尝试使用国内镜像源
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6

# 然后删除 Pod
kubectl delete pod -n kubevirt -l app=virt-operator
```

### 方案 3: 使用代理

如果有代理可用：

```bash
# 配置 k3s 使用代理
sudo mkdir -p /etc/systemd/system/k3s.service.d/
sudo tee /etc/systemd/system/k3s.service.d/http-proxy.conf > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,0.0.0.0,10.0.0.0/8"
EOF

sudo systemctl daemon-reload
sudo systemctl restart k3s
```

### 方案 4: 修改 k3s 配置使用国内镜像源

编辑 k3s 启动参数，使用国内镜像源：

```bash
# 编辑 k3s 服务配置
sudo systemctl edit k3s

# 添加以下内容：
[Service]
Environment="K3S_RESOLV_CONF=/etc/resolv.conf"
ExecStart=
ExecStart=/usr/local/bin/k3s \
    server \
    --system-default-registry=registry.cn-hangzhou.aliyuncs.com

# 保存后重启
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

## 快速修复脚本

```bash
#!/bin/bash

echo "=== 修复 Docker Hub 超时问题 ==="

# 1. 配置镜像仓库
echo "1. 配置 k3s 镜像仓库..."
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.azure.cn"
      - "https://reg-mirror.qiniu.com"
  registry-1.docker.io:
    endpoint:
      - "https://mirror.azure.cn"
      - "https://reg-mirror.qiniu.com"
EOF
echo "✓ 镜像仓库配置已创建"

# 2. 重启 k3s
echo -e "\n2. 重启 k3s..."
sudo systemctl restart k3s
echo "等待 k3s 就绪..."
sleep 15

# 3. 手动拉取镜像
echo -e "\n3. 手动拉取 pause 镜像..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if crictl pull rancher/mirrored-pause:3.6 2>/dev/null; then
    echo "✓ pause 镜像拉取成功"
else
    echo "⚠️  直接拉取失败，尝试使用国内镜像源..."
    crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 || echo "镜像拉取失败，请检查网络"
fi

# 4. 删除 Pod 重新创建
echo -e "\n4. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除，等待重新创建..."

# 5. 观察状态
echo -e "\n5. 观察 Pod 状态（30 秒）..."
timeout 30 kubectl get pods -n kubevirt -w || true

echo -e "\n=== 完成 ==="
echo "如果 Pod 仍然无法启动，请检查："
echo "  1. 网络连接: curl -I https://mirror.azure.cn"
echo "  2. k3s 日志: sudo journalctl -u k3s -n 50"
echo "  3. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
```

## 验证修复

修复后，检查：

```bash
# 1. 检查 Pod 状态
kubectl get pods -n kubevirt

# 2. 检查事件（应该没有超时错误）
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10

# 3. 检查镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl images | grep pause
```

## 国内镜像源列表

推荐的镜像源（按优先级）：

```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"  # 阿里云镜像（推荐）
      - "https://mirror.azure.cn"               # Azure 中国镜像
      - "https://reg-mirror.qiniu.com"          # 七牛云镜像
      - "https://hub-mirror.c.163.com"          # 网易镜像
  registry-1.docker.io:
    endpoint:
      - "https://e0hhb5lk.mirror.aliyuncs.com"
      - "https://mirror.azure.cn"
      - "https://reg-mirror.qiniu.com"
      - "https://hub-mirror.c.163.com"
```

## 总结

主要步骤：
1. **配置 k3s 镜像仓库**（使用国内镜像源）
2. **重启 k3s**（使配置生效）
3. **手动拉取镜像**（确保镜像可用）
4. **删除 Pod 重新创建**（让 k3s 使用新配置）

配置完成后，k3s 会自动使用镜像代理拉取镜像，解决超时问题。


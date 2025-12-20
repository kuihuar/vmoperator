# 网络问题解决方案

## 问题

所有 Docker 镜像源都不可用，无法拉取镜像。

## 解决方案

### 方案 1: 使用代理（如果有）

如果有可用的 HTTP/HTTPS 代理：

```bash
# 配置 k3s 使用代理
sudo mkdir -p /etc/systemd/system/k3s.service.d/
sudo tee /etc/systemd/system/k3s.service.d/http-proxy.conf > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,10.42.0.0/16,10.43.0.0/16"
EOF

sudo systemctl daemon-reload
sudo systemctl restart k3s
```

### 方案 2: 手动下载镜像（离线安装）

在有网络的机器上下载镜像，然后传输到目标机器。

#### 步骤 1: 在有网络的机器上下载

```bash
# 使用 docker 下载镜像
docker pull rancher/mirrored-pause:3.6
docker pull quay.io/kubevirt/virt-operator:v1.2.0

# 导出镜像
docker save rancher/mirrored-pause:3.6 -o pause-3.6.tar
docker save quay.io/kubevirt/virt-operator:v1.2.0 -o virt-operator-v1.2.0.tar
```

#### 步骤 2: 传输到目标机器

```bash
# 使用 scp 传输
scp pause-3.6.tar virt-operator-v1.2.0.tar user@target-machine:/tmp/
```

#### 步骤 3: 在目标机器上导入

```bash
# 使用 crictl 导入（需要先转换为 OCI 格式）
# 或者使用 docker load 然后转换

# 方法 A: 如果目标机器有 docker
docker load -i pause-3.6.tar
docker load -i virt-operator-v1.2.0.tar

# 然后使用 skopeo 转换为 OCI 格式（需要安装 skopeo）
# skopeo copy docker-daemon:rancher/mirrored-pause:3.6 containers-storage:rancher/mirrored-pause:3.6
```

### 方案 3: 使用内网镜像仓库

如果有内网镜像仓库：

```bash
# 配置 k3s 使用内网镜像仓库
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://your-internal-registry:5000"
  registry-1.docker.io:
    endpoint:
      - "https://your-internal-registry:5000"
EOF

sudo systemctl restart k3s
```

### 方案 4: 跳过 pause 镜像检查（高级）

如果系统已有 pause 镜像，可以尝试跳过检查：

```bash
# 检查系统是否有 pause 镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl images | grep pause

# 如果有，可以尝试直接使用
# 但 k3s 可能需要特定名称的镜像
```

### 方案 5: 使用 k3s 离线安装包

如果网络完全受限，考虑使用 k3s 离线安装包：

```bash
# 下载 k3s 离线安装包（包含所有依赖镜像）
# 从 https://github.com/k3s-io/k3s/releases 下载

# 安装离线包
sudo INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh
```

## 临时解决方案

如果急需使用，可以尝试：

### 1. 检查系统是否已有镜像

```bash
# 检查所有镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl images

# 检查是否有可用的 pause 镜像
crictl images | grep -i pause
```

### 2. 使用 k3s 的镜像缓存

k3s 可能已经下载了一些镜像，检查：

```bash
# 检查 k3s 镜像目录
sudo ls -la /var/lib/rancher/k3s/agent/images/

# 如果有镜像文件，k3s 会自动加载
```

### 3. 配置 DNS

如果 DNS 解析有问题：

```bash
# 检查 DNS 配置
cat /etc/resolv.conf

# 配置 k3s 使用特定 DNS
sudo mkdir -p /etc/systemd/system/k3s.service.d/
sudo tee /etc/systemd/system/k3s.service.d/dns.conf > /dev/null <<EOF
[Service]
Environment="K3S_RESOLV_CONF=/etc/resolv.conf"
ExecStart=
ExecStart=/usr/local/bin/k3s server --resolv-conf /etc/resolv.conf
EOF

sudo systemctl daemon-reload
sudo systemctl restart k3s
```

## 推荐方案

根据你的网络环境：

1. **如果有代理/VPN**：使用方案 1（最简单）
2. **如果有内网镜像仓库**：使用方案 3（最稳定）
3. **如果完全离线**：使用方案 2（手动下载）或方案 5（离线安装包）
4. **如果只是 DNS 问题**：使用方案 3 的 DNS 配置

## 验证

配置后验证：

```bash
# 1. 检查 k3s 状态
sudo systemctl status k3s

# 2. 检查 Pods
kubectl get pods -n kubevirt

# 3. 检查事件
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10
```


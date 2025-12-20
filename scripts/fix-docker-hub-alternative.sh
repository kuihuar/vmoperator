#!/bin/bash

# 备用方案：直接使用国内镜像源拉取镜像

echo "=== Docker Hub 超时 - 备用方案 ==="

# 方案 1: 直接使用国内镜像源拉取 pause 镜像
echo -e "\n方案 1: 使用国内镜像源拉取 pause 镜像..."

export CRICTL_CONFIG=~/.config/crictl/crictl.yaml

# 尝试多个镜像源
MIRRORS=(
    "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6"
    "registry.aliyuncs.com/google_containers/pause:3.6"
    "dockerhub.azk8s.cn/google_containers/pause:3.6"
)

SUCCESS=false
for mirror in "${MIRRORS[@]}"; do
    echo "尝试: $mirror"
    if crictl pull "$mirror" 2>/dev/null; then
        echo "✓ 镜像拉取成功: $mirror"
        # 标记为 rancher/mirrored-pause:3.6
        IMAGE_ID=$(crictl images | grep "$mirror" | awk '{print $3}')
        if [ -n "$IMAGE_ID" ]; then
            echo "  镜像 ID: $IMAGE_ID"
            # 注意：crictl 不支持直接 tag，需要重新拉取或使用其他方法
        fi
        SUCCESS=true
        break
    fi
done

if [ "$SUCCESS" = false ]; then
    echo "✗ 所有镜像源都失败"
    echo ""
    echo "方案 2: 配置 k3s 使用代理或 VPN"
    echo "方案 3: 手动下载镜像文件"
fi

# 方案 2: 修改 k3s 配置使用系统默认镜像
echo -e "\n方案 2: 配置 k3s 使用系统默认 pause 镜像..."

# 检查是否有系统 pause 镜像
if crictl images | grep -q "pause"; then
    echo "✓ 系统已有 pause 镜像"
    crictl images | grep pause
else
    echo "⚠️  系统没有 pause 镜像"
fi

# 方案 3: 使用代理配置
echo -e "\n方案 3: 配置代理（如果有）..."
read -p "是否有可用的 HTTP 代理? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "请输入代理地址 (例如: http://proxy.example.com:8080): " PROXY_URL
    if [ -n "$PROXY_URL" ]; then
        echo "配置 k3s 使用代理..."
        sudo mkdir -p /etc/systemd/system/k3s.service.d/
        sudo tee /etc/systemd/system/k3s.service.d/http-proxy.conf > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1,0.0.0.0,10.0.0.0/8"
EOF
        sudo systemctl daemon-reload
        echo "✓ 代理配置已创建，需要重启 k3s: sudo systemctl restart k3s"
    fi
fi

# 方案 4: 手动下载并导入镜像
echo -e "\n方案 4: 手动下载镜像（如果网络允许）..."
echo "如果其他方法都失败，可以："
echo "  1. 在有网络的机器上下载镜像"
echo "  2. 导出为 tar 文件"
echo "  3. 传输到目标机器"
echo "  4. 使用 crictl load 导入"

echo -e "\n=== 建议 ==="
echo "如果镜像源都不可用，推荐："
echo "  1. 配置 VPN 或代理"
echo "  2. 使用内网镜像仓库"
echo "  3. 手动下载镜像文件"


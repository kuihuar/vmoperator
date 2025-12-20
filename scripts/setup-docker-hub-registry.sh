#!/bin/bash

# 配置 k3s 使用 Docker Hub

echo "=== 配置 k3s 使用 Docker Hub ==="

# 1. 测试 Docker Hub 连接
echo -e "\n1. 测试 Docker Hub 连接..."
if curl -s -I --connect-timeout 5 https://hub.docker.com > /dev/null 2>&1; then
    echo "✓ Docker Hub 可访问"
else
    echo "✗ Docker Hub 无法访问，请检查网络"
    exit 1
fi

# 2. 测试 registry-1.docker.io
echo -e "\n2. 测试 Docker Registry..."
if curl -s -I --connect-timeout 5 https://registry-1.docker.io/v2/ > /dev/null 2>&1; then
    echo "✓ Docker Registry 可访问"
else
    echo "⚠️  Docker Registry 可能无法访问，但继续配置"
fi

# 3. 配置 k3s 使用 Docker Hub（移除镜像源配置）
echo -e "\n3. 配置 k3s 使用 Docker Hub..."

# 备份现有配置
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.bak
    echo "✓ 已备份现有配置到 /etc/rancher/k3s/registries.yaml.bak"
fi

# 删除镜像源配置，让 k3s 直接使用 Docker Hub
sudo rm -f /etc/rancher/k3s/registries.yaml
echo "✓ 已删除镜像源配置，k3s 将直接使用 Docker Hub"

# 4. 确保本地镜像已 tag
echo -e "\n4. 确保本地 pause 镜像已 tag..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml

# 检查是否已有 rancher/mirrored-pause:3.6
if crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 本地已有 rancher/mirrored-pause:3.6 镜像"
else
    echo "Tag 本地 pause 镜像..."
    if sudo ctr -n k8s.io images tag \
        registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
        rancher/mirrored-pause:3.6 2>&1; then
        echo "✓ Tag 成功"
    else
        echo "⚠️  Tag 失败，k3s 将尝试从 Docker Hub 拉取"
    fi
fi

# 5. 测试从 Docker Hub 拉取镜像
echo -e "\n5. 测试从 Docker Hub 拉取 pause 镜像..."
if crictl pull rancher/mirrored-pause:3.6 2>&1 | head -5; then
    echo "✓ 成功从 Docker Hub 拉取镜像"
else
    echo "⚠️  拉取失败，但本地已有镜像，应该可以使用"
fi

# 6. 重启 k3s
echo -e "\n6. 重启 k3s（使配置生效）..."
read -p "是否现在重启 k3s? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart k3s
    echo "等待 k3s 就绪..."
    sleep 15
    
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✓ k3s 已就绪"
    else
        echo "⚠️  k3s 可能还在启动中，请稍后检查: kubectl get nodes"
    fi
else
    echo "跳过重启，请稍后手动重启: sudo systemctl restart k3s"
fi

# 7. 删除 Pod 重新创建
echo -e "\n7. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除"

echo -e "\n观察 Pod 状态（30 秒）:"
timeout 30 kubectl get pods -n kubevirt -w 2>/dev/null || kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 成功启动，下一步："
echo "  1. 等待 Operator 就绪: kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s"
echo "  2. 安装 KubeVirt CR: ./scripts/fix-kubevirt-installation.sh (选择 A)"
echo "  3. 安装 CDI: ./scripts/install-cdi.sh"


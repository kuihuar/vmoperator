#!/bin/bash

# 快速修复：配置 k3s 使用 Docker Hub

echo "=== 配置 k3s 使用 Docker Hub ==="

# 1. 删除镜像源配置
echo -e "\n1. 删除镜像源配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.bak
    echo "✓ 已备份: /etc/rancher/k3s/registries.yaml.bak"
fi
sudo rm -f /etc/rancher/k3s/registries.yaml
echo "✓ 已删除镜像源配置，k3s 将直接使用 Docker Hub"

# 2. Tag 本地镜像（备用）
echo -e "\n2. Tag 本地 pause 镜像..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if ! crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    sudo ctr -n k8s.io images tag \
        registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
        rancher/mirrored-pause:3.6 2>&1 | head -3
    echo "✓ Tag 完成"
else
    echo "✓ 本地已有 rancher/mirrored-pause:3.6"
fi

# 3. 测试 Docker Hub 连接
echo -e "\n3. 测试 Docker Hub 连接..."
if curl -s -I --connect-timeout 5 https://registry-1.docker.io/v2/ > /dev/null 2>&1; then
    echo "✓ Docker Registry 可访问"
else
    echo "⚠️  Docker Registry 连接测试失败，但继续..."
fi

# 4. 重启 k3s
echo -e "\n4. 重启 k3s..."
sudo systemctl restart k3s
echo "等待 k3s 就绪..."
sleep 15

if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ k3s 已就绪"
else
    echo "⚠️  k3s 可能还在启动中"
fi

# 5. 删除 Pod
echo -e "\n5. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator
echo "✓ Pod 已删除"

echo -e "\n观察 Pod 状态:"
kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo "如果 Pod 成功启动，检查: kubectl get pods -n kubevirt -w"


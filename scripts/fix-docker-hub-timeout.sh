#!/bin/bash

# 修复 Docker Hub 超时问题

echo "=== 修复 Docker Hub 超时问题 ==="

# 1. 配置镜像仓库
echo -e "\n1. 配置 k3s 镜像仓库..."
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://dockerhub.azk8s.cn"
      - "https://reg-mirror.qiniu.com"
  registry-1.docker.io:
    endpoint:
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://dockerhub.azk8s.cn"
      - "https://reg-mirror.qiniu.com"
EOF
echo "✓ 镜像仓库配置已创建: /etc/rancher/k3s/registries.yaml"

# 2. 重启 k3s
echo -e "\n2. 重启 k3s（使配置生效）..."
read -p "是否现在重启 k3s? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart k3s
    echo "等待 k3s 就绪..."
    sleep 15
    
    # 检查 k3s 状态
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✓ k3s 已就绪"
    else
        echo "⚠️  k3s 可能还在启动中，请稍后检查: kubectl get nodes"
    fi
else
    echo "跳过重启，请稍后手动重启: sudo systemctl restart k3s"
fi

# 3. 手动拉取镜像
echo -e "\n3. 手动拉取 pause 镜像..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml

# 尝试拉取原始镜像
if crictl pull rancher/mirrored-pause:3.6 2>/dev/null; then
    echo "✓ pause 镜像拉取成功 (rancher/mirrored-pause:3.6)"
else
    echo "⚠️  直接拉取失败，尝试使用国内镜像源..."
    # 尝试国内镜像源
    if crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 2>/dev/null; then
        echo "✓ pause 镜像拉取成功 (国内镜像源)"
    else
        echo "⚠️  镜像拉取失败，可能需要："
        echo "   - 检查网络连接"
        echo "   - 等待 k3s 重启完成后再试"
        echo "   - 或手动拉取: crictl pull rancher/mirrored-pause:3.6"
    fi
fi

# 4. 删除 Pod 重新创建
echo -e "\n4. 删除 Pod 重新创建..."
if kubectl get pods -n kubevirt -l app=virt-operator > /dev/null 2>&1; then
    kubectl delete pod -n kubevirt -l app=virt-operator
    echo "✓ Pod 已删除，等待重新创建..."
    echo "  观察状态: kubectl get pods -n kubevirt -w"
else
    echo "⚠️  未找到 Pod，可能已被删除"
fi

# 5. 显示当前状态
echo -e "\n5. 当前 Pod 状态:"
kubectl get pods -n kubevirt 2>/dev/null || echo "命名空间或 Pod 不存在"

echo -e "\n=== 完成 ==="
echo ""
echo "下一步："
echo "  1. 观察 Pod 状态: kubectl get pods -n kubevirt -w"
echo "  2. 如果仍有问题，检查事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
echo "  3. 检查 k3s 日志: sudo journalctl -u k3s -n 50"


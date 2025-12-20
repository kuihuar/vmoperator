#!/bin/bash

# 强制修复镜像源配置

echo "=== 强制修复镜像源配置 ==="

# 1. 检查当前配置
echo -e "\n1. 检查当前配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "当前配置:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "配置文件不存在"
fi

# 2. 检查是否有其他配置文件
echo -e "\n2. 检查其他可能的配置文件..."
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "⚠️  发现 containerd 配置文件，可能包含旧配置"
    sudo grep -i "mirror\|registry" /var/lib/rancher/k3s/agent/etc/containerd/config.toml | head -10
fi

# 3. 完全清理并重新配置
echo -e "\n3. 完全清理并重新配置..."

# 删除所有可能的配置文件
sudo rm -f /etc/rancher/k3s/registries.yaml
echo "✓ 已删除 /etc/rancher/k3s/registries.yaml"

# 检查并清理 containerd 配置中的旧镜像源
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "⚠️  发现 containerd 配置文件，k3s 重启时会重新生成"
    echo "   建议：重启 k3s 让它重新生成配置"
fi

# 4. 创建新的配置文件（只使用阿里云）
echo -e "\n4. 创建新的配置文件（只使用阿里云镜像源）..."
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

echo "✓ 新配置已创建"
cat /etc/rancher/k3s/registries.yaml

# 5. 停止 k3s（确保完全停止）
echo -e "\n5. 停止 k3s..."
sudo systemctl stop k3s
sleep 5

# 6. 清理可能的缓存
echo -e "\n6. 清理可能的缓存..."
# containerd 的配置会在 k3s 启动时重新生成，这里不需要手动清理

# 7. 启动 k3s
echo -e "\n7. 启动 k3s..."
sudo systemctl start k3s
echo "等待 k3s 就绪..."
sleep 20

if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ k3s 已就绪"
else
    echo "⚠️  k3s 可能还在启动中，等待更长时间..."
    sleep 10
    kubectl get nodes || echo "k3s 可能启动失败，请检查: sudo systemctl status k3s"
fi

# 8. 验证配置是否生效
echo -e "\n8. 验证配置是否生效..."
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]; then
    echo "containerd 配置中的镜像源:"
    sudo grep -A 5 "mirrors\|registry" /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -i "aliyun\|azure" || echo "  未找到新镜像源，可能需要检查配置格式"
fi

# 9. 确保本地镜像已 tag
echo -e "\n9. 确保本地镜像已 tag..."
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
if ! crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "Tag 本地 pause 镜像..."
    sudo ctr -n k8s.io images tag \
        registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
        rancher/mirrored-pause:3.6 2>&1 | head -3
fi

# 10. 删除 Pod 重新创建
echo -e "\n10. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator --force --grace-period=0 2>/dev/null || true
sleep 5
kubectl delete pod -n kubevirt -l app=virt-operator 2>/dev/null || true

echo -e "\n观察 Pod 状态:"
kubectl get pods -n kubevirt

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 仍然无法启动，检查："
echo "  1. k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'mirror\|registry\|pause'"
echo "  2. containerd 配置: sudo cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -A 10 mirror"
echo "  3. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"


#!/bin/bash

# 移除镜像源配置，让 k3s 使用本地镜像或直接访问 Docker Hub

echo "=== 移除镜像源配置 ==="

# 1. 检查当前配置
echo -e "\n1. 检查当前配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "当前配置:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "配置文件不存在"
fi

# 2. 备份并删除
echo -e "\n2. 备份并删除配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    BACKUP_FILE="/etc/rancher/k3s/registries.yaml.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp /etc/rancher/k3s/registries.yaml "$BACKUP_FILE"
    echo "✓ 已备份到: $BACKUP_FILE"
    
    sudo rm -f /etc/rancher/k3s/registries.yaml
    echo "✓ 已删除配置文件"
else
    echo "配置文件不存在，无需删除"
fi

# 3. 验证本地镜像
echo -e "\n3. 验证本地 pause 镜像..."
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 本地镜像存在:"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  本地镜像不存在，k3s 将尝试从 Docker Hub 拉取"
    echo "如果网络无法访问 Docker Hub，需要先 tag 本地镜像"
    PAUSE_IMG=$(sudo crictl images | grep pause | head -1 | awk '{print $1":"$2}')
    if [ -n "$PAUSE_IMG" ] && [ "$PAUSE_IMG" != ":" ]; then
        echo "找到其他 pause 镜像: $PAUSE_IMG"
        read -p "是否 tag 为 rancher/mirrored-pause:3.6? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo ctr -n k8s.io images tag "$PAUSE_IMG" rancher/mirrored-pause:3.6
            echo "✓ 已 tag"
        fi
    fi
fi

# 4. 重启 k3s
echo -e "\n4. 重启 k3s..."
sudo systemctl restart k3s
echo "等待 k3s 就绪..."
sleep 20

if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ k3s 已就绪"
else
    echo "⚠️  k3s 可能还在启动中，等待更长时间..."
    sleep 10
    kubectl get nodes || echo "k3s 可能启动失败，请检查: sudo systemctl status k3s"
fi

# 5. 删除 Pod 重新创建
echo -e "\n5. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator --force --grace-period=0 2>/dev/null || true
sleep 5
kubectl delete pod -n kubevirt -l app=virt-operator 2>/dev/null || true

echo "等待 Pod 启动..."
sleep 15

# 6. 检查状态
echo -e "\n6. 检查 Pod 状态..."
kubectl get pods -n kubevirt -l app=virt-operator

echo -e "\n最新事件:"
kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -5

echo -e "\n=== 完成 ==="
echo ""
echo "如果仍然失败，检查："
echo "  1. 镜像是否存在: sudo crictl images | grep pause"
echo "  2. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
echo "  3. k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'pause'"


#!/bin/bash

# 配置 k3s 使用本地 pause 镜像

echo "=== 配置 k3s 使用本地 pause 镜像 ==="

# 1. 检查本地镜像
echo -e "\n1. 检查本地 pause 镜像..."
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 找到本地镜像:"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  未找到 rancher/mirrored-pause:3.6"
    echo "检查是否有其他 pause 镜像..."
    PAUSE_IMG=$(sudo crictl images | grep pause | head -1 | awk '{print $1":"$2}')
    if [ -n "$PAUSE_IMG" ] && [ "$PAUSE_IMG" != ":" ]; then
        echo "找到: $PAUSE_IMG"
        echo "Tag 为 rancher/mirrored-pause:3.6..."
        sudo ctr -n k8s.io images tag "$PAUSE_IMG" rancher/mirrored-pause:3.6
        echo "✓ 已 tag"
    else
        echo "❌ 未找到任何 pause 镜像"
        exit 1
    fi
fi

# 2. 检查当前镜像源配置
echo -e "\n2. 检查当前镜像源配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "当前配置:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "配置文件不存在"
fi

# 3. 方案 A: 移除镜像源配置，让 k3s 使用本地镜像或直接访问 Docker Hub
echo -e "\n3. 方案 A: 移除镜像源配置..."
echo "这将让 k3s 优先使用本地镜像，如果本地没有则尝试从 Docker Hub 拉取"
read -p "是否移除镜像源配置？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 备份
    if [ -f /etc/rancher/k3s/registries.yaml ]; then
        sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.backup.$(date +%Y%m%d-%H%M%S)
        echo "✓ 已备份原配置"
    fi
    
    # 删除配置
    sudo rm -f /etc/rancher/k3s/registries.yaml
    echo "✓ 已删除镜像源配置"
    
    # 重启 k3s
    echo "重启 k3s..."
    sudo systemctl restart k3s
    sleep 20
    
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✓ k3s 已重启"
    else
        echo "⚠️  k3s 可能还在启动中"
    fi
fi

# 4. 方案 B: 配置镜像源为本地优先（如果方案 A 不行）
echo -e "\n4. 方案 B: 配置镜像源为本地优先..."
echo "如果方案 A 不行，可以配置镜像源为本地优先"
echo "但这需要 containerd 支持，k3s 可能不支持"

# 5. 验证镜像是否可用
echo -e "\n5. 验证镜像是否可用..."
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 镜像存在"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  镜像不存在"
fi

# 6. 删除 Pod 重新创建
echo -e "\n6. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator --force --grace-period=0 2>/dev/null || true
sleep 5
kubectl delete pod -n kubevirt -l app=virt-operator 2>/dev/null || true

echo "等待 Pod 启动..."
sleep 15

# 7. 检查 Pod 状态
echo -e "\n7. 检查 Pod 状态..."
kubectl get pods -n kubevirt -l app=virt-operator

echo -e "\n最新事件:"
kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -5

echo -e "\n=== 完成 ==="
echo ""
echo "如果仍然失败，可以尝试："
echo "  1. 检查镜像是否真的存在: sudo crictl images | grep pause"
echo "  2. 检查 containerd 配置: sudo cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -A 10 mirror"
echo "  3. 检查 k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'pause\|image'"


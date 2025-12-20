#!/bin/bash

# 移除所有代理和镜像源配置

echo "=== 移除所有代理和镜像源配置 ==="

# 1. 检查当前代理配置
echo -e "\n1. 检查当前代理配置..."
echo "系统环境变量:"
echo "  HTTP_PROXY: ${HTTP_PROXY:-未设置}"
echo "  HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"

if sudo systemctl is-active k3s > /dev/null 2>&1; then
    echo "k3s 服务环境变量:"
    sudo systemctl show k3s | grep -i "proxy" || echo "  未发现代理配置"
fi

# 2. 检查镜像源配置
echo -e "\n2. 检查镜像源配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "当前镜像源配置:"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "镜像源配置文件不存在"
fi

# 3. 停止 k3s
echo -e "\n3. 停止 k3s..."
sudo systemctl stop k3s
sleep 3

# 4. 备份配置
echo -e "\n4. 备份配置..."
BACKUP_DIR="/tmp/k3s-config-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "备份目录: $BACKUP_DIR"

# 备份 systemd drop-in 配置
DROPIN_DIR="/etc/systemd/system/k3s.service.d"
if [ -d "$DROPIN_DIR" ]; then
    sudo cp -r "$DROPIN_DIR" "$BACKUP_DIR/" 2>/dev/null || true
    echo "✓ 已备份 systemd drop-in 配置"
fi

# 备份镜像源配置
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    sudo cp /etc/rancher/k3s/registries.yaml "$BACKUP_DIR/registries.yaml" 2>/dev/null || true
    echo "✓ 已备份镜像源配置"
fi

# 5. 清理代理配置
echo -e "\n5. 清理代理配置..."

# 清理 systemd drop-in 中的代理配置
if [ -d "$DROPIN_DIR" ]; then
    for file in "$DROPIN_DIR"/*.conf; do
        if [ -f "$file" ]; then
            if sudo grep -qi "proxy\|HTTP_PROXY\|HTTPS_PROXY" "$file"; then
                echo "删除包含代理的配置文件: $file"
                sudo rm -f "$file"
            fi
        fi
    done
fi

# 6. 清理镜像源配置
echo -e "\n6. 清理镜像源配置..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "删除镜像源配置文件..."
    sudo rm -f /etc/rancher/k3s/registries.yaml
    echo "✓ 已删除镜像源配置"
else
    echo "镜像源配置文件不存在，无需删除"
fi

# 7. 重新加载 systemd
echo -e "\n7. 重新加载 systemd..."
sudo systemctl daemon-reload

# 8. 验证配置已清理
echo -e "\n8. 验证配置已清理..."
if [ -d "$DROPIN_DIR" ]; then
    REMAINING=$(ls -A "$DROPIN_DIR" 2>/dev/null | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        echo "✓ systemd drop-in 目录已清空"
        # 如果目录为空，可以删除
        sudo rmdir "$DROPIN_DIR" 2>/dev/null || true
    else
        echo "剩余配置文件:"
        ls -la "$DROPIN_DIR"
    fi
fi

if [ ! -f /etc/rancher/k3s/registries.yaml ]; then
    echo "✓ 镜像源配置已删除"
fi

# 9. 验证本地镜像
echo -e "\n9. 验证本地 pause 镜像..."
if sudo crictl images | grep -q "rancher/mirrored-pause:3.6"; then
    echo "✓ 本地镜像存在:"
    sudo crictl images | grep "rancher/mirrored-pause:3.6"
else
    echo "⚠️  本地镜像不存在，检查是否有其他 pause 镜像..."
    PAUSE_IMG=$(sudo crictl images | grep pause | head -1 | awk '{print $1":"$2}')
    if [ -n "$PAUSE_IMG" ] && [ "$PAUSE_IMG" != ":" ]; then
        echo "找到: $PAUSE_IMG"
        echo "Tag 为 rancher/mirrored-pause:3.6..."
        sudo ctr -n k8s.io images tag "$PAUSE_IMG" rancher/mirrored-pause:3.6
        echo "✓ 已 tag"
    fi
fi

# 10. 启动 k3s
echo -e "\n10. 启动 k3s..."
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

# 11. 验证运行时环境变量
echo -e "\n11. 验证运行时环境变量..."
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    echo "k3s 服务环境变量:"
    if sudo systemctl show k3s | grep -qi "proxy"; then
        echo "⚠️  仍然发现代理环境变量:"
        sudo systemctl show k3s | grep -i "proxy"
    else
        echo "✓ 未发现代理环境变量"
    fi
else
    echo "k3s 服务未运行"
fi

# 12. 删除 Pod 重新创建
echo -e "\n12. 删除 Pod 重新创建..."
kubectl delete pod -n kubevirt -l app=virt-operator --force --grace-period=0 2>/dev/null || true
sleep 5
kubectl delete pod -n kubevirt -l app=virt-operator 2>/dev/null || true

echo "等待 Pod 启动..."
sleep 15

# 13. 检查状态
echo -e "\n13. 检查 Pod 状态..."
kubectl get pods -n kubevirt -l app=virt-operator

echo -e "\n最新事件:"
kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -5

echo -e "\n=== 完成 ==="
echo ""
echo "已清理："
echo "  ✓ k3s systemd 服务中的代理配置"
echo "  ✓ 镜像源配置（阿里云等）"
echo ""
echo "备份位置: $BACKUP_DIR"
echo ""
echo "如果 Pod 仍然无法启动，检查："
echo "  1. 镜像是否存在: sudo crictl images | grep pause"
echo "  2. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
echo "  3. k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'pause\|proxy'"


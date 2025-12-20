#!/bin/bash

# 修复 k3s 代理配置并重启

echo "=== 修复 k3s 代理配置 ==="

# 1. 检查当前代理配置
echo -e "\n1. 检查当前代理配置..."
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    echo "k3s 服务环境变量:"
    sudo systemctl show k3s | grep -i "proxy\|DropInPaths" || echo "  未发现代理配置"
else
    echo "k3s 服务未运行"
fi

# 2. 检查 drop-in 配置文件
echo -e "\n2. 检查 drop-in 配置文件..."
DROPIN_DIR="/etc/systemd/system/k3s.service.d"
if [ -d "$DROPIN_DIR" ]; then
    echo "发现以下配置文件:"
    ls -la "$DROPIN_DIR"
    echo ""
    for file in "$DROPIN_DIR"/*.conf; do
        if [ -f "$file" ]; then
            echo "文件: $file"
            sudo cat "$file"
            echo ""
        fi
    done
fi

# 3. 停止 k3s
echo -e "\n3. 停止 k3s..."
sudo systemctl stop k3s
sleep 3

# 4. 备份并清理代理配置
echo -e "\n4. 备份并清理代理配置..."
BACKUP_DIR="/tmp/k3s-proxy-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "备份目录: $BACKUP_DIR"

if [ -d "$DROPIN_DIR" ]; then
    sudo cp -r "$DROPIN_DIR" "$BACKUP_DIR/" 2>/dev/null || true
    echo "✓ 已备份到: $BACKUP_DIR"
    
    # 删除包含代理的配置文件
    for file in "$DROPIN_DIR"/*.conf; do
        if [ -f "$file" ]; then
            if sudo grep -qi "proxy\|HTTP_PROXY\|HTTPS_PROXY" "$file"; then
                echo "删除包含代理的配置文件: $file"
                sudo rm -f "$file"
            fi
        fi
    done
fi

# 5. 重新加载 systemd
echo -e "\n5. 重新加载 systemd..."
sudo systemctl daemon-reload

# 6. 验证配置已清理
echo -e "\n6. 验证配置已清理..."
if [ -d "$DROPIN_DIR" ]; then
    echo "剩余配置文件:"
    ls -la "$DROPIN_DIR" 2>/dev/null || echo "  目录为空或不存在"
fi

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

# 8. 验证运行时环境变量
echo -e "\n8. 验证运行时环境变量..."
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    echo "k3s 服务环境变量:"
    if sudo systemctl show k3s | grep -qi "proxy"; then
        echo "⚠️  仍然发现代理环境变量:"
        sudo systemctl show k3s | grep -i "proxy"
    else
        echo "✓ 未发现代理环境变量"
    fi
fi

# 9. 检查 Pod 状态
echo -e "\n9. 检查 Pod 状态..."
echo "等待 Pod 启动..."
sleep 10

if kubectl get pods -n kubevirt -l app=virt-operator 2>/dev/null | grep -q virt-operator; then
    echo "virt-operator Pods:"
    kubectl get pods -n kubevirt -l app=virt-operator
    echo ""
    echo "最新事件:"
    kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -5
else
    echo "未找到 virt-operator Pods"
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果 Pod 仍然无法启动，检查："
echo "  1. k3s 日志: sudo journalctl -u k3s -n 100 | grep -i 'pause\|proxy'"
echo "  2. Pod 事件: kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10"
echo "  3. Pod 描述: kubectl describe pod -n kubevirt -l app=virt-operator"


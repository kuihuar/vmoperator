#!/bin/bash

# 移除 k3s 的代理配置

echo "=== 移除 k3s 代理配置 ==="

# 1. 检查当前配置
echo -e "\n1. 检查当前配置..."
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
    
    for file in "$DROPIN_DIR"/*.conf; do
        if [ -f "$file" ]; then
            echo -e "\n检查文件: $file"
            if sudo grep -qi "proxy" "$file"; then
                echo "⚠️  发现代理配置:"
                sudo cat "$file"
            else
                echo "✓ 未发现代理配置"
            fi
        fi
    done
else
    echo "drop-in 目录不存在"
fi

# 3. 备份并清理代理配置
echo -e "\n3. 备份并清理代理配置..."

# 停止 k3s
echo "停止 k3s..."
sudo systemctl stop k3s
sleep 3

# 备份现有配置
BACKUP_DIR="/tmp/k3s-proxy-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "备份目录: $BACKUP_DIR"

if [ -d "$DROPIN_DIR" ]; then
    sudo cp -r "$DROPIN_DIR" "$BACKUP_DIR/" 2>/dev/null || true
    echo "✓ 已备份到: $BACKUP_DIR"
fi

# 清理代理配置
echo -e "\n清理代理配置..."

# 方法 1: 删除包含代理的配置文件
if [ -f "$DROPIN_DIR/http-proxy.conf" ]; then
    echo "删除 $DROPIN_DIR/http-proxy.conf"
    sudo rm -f "$DROPIN_DIR/http-proxy.conf"
fi

# 方法 2: 如果 override.conf 中有代理配置，清理它
if [ -f "$DROPIN_DIR/override.conf" ]; then
    if sudo grep -qi "proxy" "$DROPIN_DIR/override.conf"; then
        echo "清理 $DROPIN_DIR/override.conf 中的代理配置..."
        # 创建一个临时文件，移除代理相关的行
        sudo grep -vi "proxy" "$DROPIN_DIR/override.conf" > /tmp/override.conf.tmp || true
        if [ -s /tmp/override.conf.tmp ]; then
            sudo mv /tmp/override.conf.tmp "$DROPIN_DIR/override.conf"
        else
            # 如果文件为空，删除它
            sudo rm -f "$DROPIN_DIR/override.conf"
        fi
    fi
fi

# 方法 3: 如果还有其他配置文件包含代理，也清理
for file in "$DROPIN_DIR"/*.conf; do
    if [ -f "$file" ] && sudo grep -qi "proxy" "$file"; then
        echo "清理 $file 中的代理配置..."
        sudo grep -vi "proxy" "$file" > /tmp/$(basename "$file").tmp || true
        if [ -s /tmp/$(basename "$file").tmp ]; then
            sudo mv /tmp/$(basename "$file").tmp "$file"
        else
            sudo rm -f "$file"
        fi
    fi
done

# 4. 重新加载 systemd
echo -e "\n4. 重新加载 systemd..."
sudo systemctl daemon-reload

# 5. 验证配置已清理
echo -e "\n5. 验证配置已清理..."
if sudo systemctl show k3s 2>/dev/null | grep -qi "proxy"; then
    echo "⚠️  仍然发现代理配置，请手动检查:"
    sudo systemctl show k3s | grep -i "proxy"
else
    echo "✓ 代理配置已清理"
fi

# 6. 启动 k3s
echo -e "\n6. 启动 k3s..."
sudo systemctl start k3s
echo "等待 k3s 就绪..."
sleep 15

if kubectl get nodes > /dev/null 2>&1; then
    echo "✓ k3s 已就绪"
else
    echo "⚠️  k3s 可能还在启动中，等待更长时间..."
    sleep 10
    kubectl get nodes || echo "k3s 可能启动失败，请检查: sudo systemctl status k3s"
fi

# 7. 验证运行时环境变量
echo -e "\n7. 验证运行时环境变量..."
if sudo systemctl is-active k3s > /dev/null 2>&1; then
    echo "k3s 服务环境变量:"
    if sudo systemctl show k3s | grep -qi "proxy"; then
        echo "⚠️  仍然发现代理环境变量:"
        sudo systemctl show k3s | grep -i "proxy"
        echo ""
        echo "可能需要："
        echo "  1. 检查其他配置文件: sudo systemctl show k3s | grep DropInPaths"
        echo "  2. 手动编辑: sudo systemctl edit k3s"
    else
        echo "✓ 未发现代理环境变量"
    fi
fi

echo -e "\n=== 完成 ==="
echo ""
echo "如果仍然有问题，可以："
echo "  1. 查看备份: ls -la $BACKUP_DIR"
echo "  2. 手动编辑: sudo systemctl edit k3s"
echo "  3. 检查日志: sudo journalctl -u k3s -n 50"


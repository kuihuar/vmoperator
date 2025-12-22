#!/bin/bash

# 彻底删除所有 Multus 配置文件

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "彻底删除所有 Multus 配置文件"
echo_info "=========================================="
echo ""

# 1. 删除 k3s CNI 配置目录中的 Multus 配置
echo_info "1. 删除 k3s CNI 配置目录中的 Multus 配置"
echo ""

K3S_CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"

if [ -f "$K3S_CNI_DIR/00-multus.conf" ]; then
    sudo rm -f "$K3S_CNI_DIR/00-multus.conf"
    echo_info "  ✓ 已删除: $K3S_CNI_DIR/00-multus.conf"
else
    echo_info "  不存在: $K3S_CNI_DIR/00-multus.conf"
fi

if [ -f "$K3S_CNI_DIR/00-multus.conf.disabled" ]; then
    sudo rm -f "$K3S_CNI_DIR/00-multus.conf.disabled"
    echo_info "  ✓ 已删除: $K3S_CNI_DIR/00-multus.conf.disabled"
fi

# 删除 multus.d 目录（但保留备份）
if [ -d "$K3S_CNI_DIR/multus.d" ]; then
    echo_info "  保留 multus.d 目录（可能包含备份）"
    # sudo rm -rf "$K3S_CNI_DIR/multus.d"
fi

# 2. 删除主机 CNI 配置目录中的 Multus 配置
echo ""
echo_info "2. 删除主机 CNI 配置目录中的 Multus 配置"
echo ""

HOST_CNI_DIR="/etc/cni/net.d"

if [ -f "$HOST_CNI_DIR/00-multus.conf" ]; then
    sudo rm -f "$HOST_CNI_DIR/00-multus.conf"
    echo_info "  ✓ 已删除: $HOST_CNI_DIR/00-multus.conf"
else
    echo_info "  不存在: $HOST_CNI_DIR/00-multus.conf"
fi

if [ -d "$HOST_CNI_DIR/multus.d" ]; then
    sudo rm -rf "$HOST_CNI_DIR/multus.d"
    echo_info "  ✓ 已删除: $HOST_CNI_DIR/multus.d"
else
    echo_info "  不存在: $HOST_CNI_DIR/multus.d"
fi

# 3. 查找并删除所有其他位置的 Multus 配置
echo ""
echo_info "3. 查找并删除其他位置的 Multus 配置"
echo ""

# 在 k3s 目录中查找
MULTUS_FILES=$(sudo find /var/lib/rancher/k3s -name "*multus*.conf" -type f 2>/dev/null || echo "")
if [ -n "$MULTUS_FILES" ]; then
    echo "$MULTUS_FILES" | while read file; do
        if [ -n "$file" ]; then
            sudo rm -f "$file"
            echo_info "  ✓ 已删除: $file"
        fi
    done
else
    echo_info "  未找到其他 Multus 配置文件"
fi

# 4. 检查当前 CNI 配置
echo ""
echo_info "4. 检查当前 CNI 配置"
echo ""

echo_info "  k3s CNI 配置目录:"
sudo ls -la "$K3S_CNI_DIR"/*.{conf,conflist} 2>/dev/null | head -5 || echo "  未找到配置文件"

echo ""
echo_info "  主机 CNI 配置目录:"
sudo ls -la "$HOST_CNI_DIR"/*.{conf,conflist} 2>/dev/null | head -5 || echo "  未找到配置文件"

# 5. 检查是否还有 Multus 类型的配置
echo ""
echo_info "5. 检查是否还有 Multus 类型的配置"
echo ""

MULTUS_FOUND=false

# 检查 k3s 目录
for conf in $(sudo ls -1 "$K3S_CNI_DIR"/*.{conf,conflist} 2>/dev/null); do
    CNI_TYPE=$(sudo cat "$conf" | jq -r '.type // .plugins[0].type // ""' 2>/dev/null || echo "")
    if [ "$CNI_TYPE" = "multus" ]; then
        echo_warn "  ⚠️  发现 Multus 配置: $conf"
        MULTUS_FOUND=true
    fi
done

# 检查主机目录
for conf in $(sudo ls -1 "$HOST_CNI_DIR"/*.{conf,conflist} 2>/dev/null); do
    CNI_TYPE=$(sudo cat "$conf" | jq -r '.type // .plugins[0].type // ""' 2>/dev/null || echo "")
    if [ "$CNI_TYPE" = "multus" ]; then
        echo_warn "  ⚠️  发现 Multus 配置: $conf"
        MULTUS_FOUND=true
    fi
done

if [ "$MULTUS_FOUND" = false ]; then
    echo_info "  ✓ 未发现 Multus 配置"
else
    echo_warn "  ⚠️  仍有 Multus 配置存在，需要手动删除"
fi

echo ""
echo_info "=========================================="
echo_info "清理完成"
echo_info "=========================================="
echo ""
echo_warn "⚠️  需要重启 k3s 让配置生效:"
echo "  sudo systemctl restart k3s"
echo ""


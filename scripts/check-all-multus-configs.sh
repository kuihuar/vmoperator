#!/bin/bash

# 检查所有 Multus 配置文件

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查所有 Multus 配置文件"
echo_info "=========================================="
echo ""

# 1. 检查 CNI 配置目录中的所有配置文件
echo_info "1. CNI 配置目录中的所有配置文件"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
echo_info "目录: $CNI_CONF_DIR"
echo ""

for conf_file in $(sudo ls "$CNI_CONF_DIR"/*.conf 2>/dev/null | sort); do
    echo_info "文件: $conf_file"
    echo "  类型: $(sudo cat "$conf_file" | jq -r '.type // "unknown"' 2>/dev/null)"
    
    # 检查是否有 kubeconfig
    KUBECONFIG=$(sudo cat "$conf_file" | jq -r '.kubeconfig // ""' 2>/dev/null)
    if [ -n "$KUBECONFIG" ]; then
        echo "  kubeconfig: $KUBECONFIG"
        
        # 检查文件是否存在
        if [ -f "$KUBECONFIG" ]; then
            echo "    ✓ 文件存在"
        else
            echo "    ✗ 文件不存在"
        fi
    fi
    echo ""
done

# 2. 检查 multus-shim
echo_info "2. 检查 multus-shim 二进制"
echo ""

MULTUS_SHIM_PATHS=(
    "/var/lib/rancher/k3s/data/current/bin/multus-shim"
    "/opt/cni/bin/multus-shim"
)

for path in "${MULTUS_SHIM_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo_info "  ✓ 找到: $path"
        sudo ls -lh "$path"
        
        # 检查文件类型
        echo "  文件类型:"
        file "$path" 2>/dev/null || echo "    无法确定"
        break
    fi
done

# 3. 检查是否有其他 CNI 配置文件
echo ""
echo_info "3. 检查其他可能的 CNI 配置位置"
echo ""

OTHER_CONF_DIRS=(
    "/etc/cni/net.d"
    "/var/lib/cni/net.d"
)

for dir in "${OTHER_CONF_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo_info "  目录: $dir"
        sudo ls -la "$dir" 2>/dev/null | head -10
        echo ""
    fi
done

# 4. 检查 kubelet 日志（最近的 Multus 相关错误）
echo ""
echo_info "4. 检查最近的 kubelet 日志（Multus 相关）"
echo ""

if command -v journalctl > /dev/null 2>&1; then
    echo_info "  最近的 Multus 相关日志:"
    sudo journalctl -u k3s -n 50 --no-pager 2>/dev/null | grep -i "multus\|kubeconfig" | tail -10 || echo "    未找到相关日志"
else
    echo_warn "  journalctl 不可用"
fi

echo ""
echo_info "=========================================="
echo_info "关键发现"
echo_info "=========================================="
echo ""
echo_info "注意：二进制文件名是 multus-shim，不是 multus"
echo_info "这可能影响配置文件的使用方式"
echo ""


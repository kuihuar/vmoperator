#!/bin/bash

# 检查 CNI 插件权限和二进制文件

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 CNI 插件权限和二进制文件"
echo_info "=========================================="
echo ""

# 1. 检查文件权限
KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"

echo_info "1. 检查 kubeconfig 文件权限"
echo ""

if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  文件存在"
    sudo ls -lh "$KUBECONFIG_FILE"
    echo ""
    echo_info "  文件权限（数字）: $(sudo stat -c "%a" "$KUBECONFIG_FILE")"
    echo_info "  文件所有者: $(sudo stat -c "%U:%G" "$KUBECONFIG_FILE")"
    
    # 检查非 root 用户是否能读取
    if sudo -u nobody test -r "$KUBECONFIG_FILE" 2>/dev/null; then
        echo_info "  ✓ 非 root 用户可以读取（但 CNI 插件应该以 root 运行）"
    else
        echo_warn "  ⚠️  非 root 用户无法读取（这正常，因为文件权限可能是 600 或 640）"
    fi
else
    echo_error "  ✗ 文件不存在"
fi

# 2. 检查目录权限
echo ""
echo_info "2. 检查目录权限"
echo ""

K3S_AGENT="/var/lib/rancher/k3s/agent"
CNI_DIR="$K3S_AGENT/etc/cni/net.d"
MULTUS_DIR="$CNI_DIR/multus.d"

for dir in "$K3S_AGENT" "$CNI_DIR" "$MULTUS_DIR"; do
    if [ -d "$dir" ]; then
        PERM=$(sudo stat -c "%a" "$dir")
        OWNER=$(sudo stat -c "%U:%G" "$dir")
        echo_info "  $dir"
        echo_info "    权限: $PERM"
        echo_info "    所有者: $OWNER"
    fi
done

# 3. 检查 Multus 二进制文件位置
echo ""
echo_info "3. 检查 Multus CNI 二进制文件"
echo ""

POSSIBLE_BIN_PATHS=(
    "/var/lib/rancher/k3s/data/current/bin/multus"
    "/var/lib/rancher/k3s/data/cni/bin/multus"
    "/opt/cni/bin/multus"
    "/usr/local/bin/multus"
)

FOUND_BIN=""
for bin_path in "${POSSIBLE_BIN_PATHS[@]}"; do
    if [ -f "$bin_path" ]; then
        echo_info "  ✓ 找到: $bin_path"
        sudo ls -lh "$bin_path"
        FOUND_BIN="$bin_path"
        echo ""
        echo_info "    权限: $(sudo stat -c "%a" "$bin_path")"
        echo_info "    所有者: $(sudo stat -c "%U:%G" "$bin_path")"
        break
    fi
done

if [ -z "$FOUND_BIN" ]; then
    echo_warn "  ⚠️  未找到 Multus 二进制文件"
    echo_info "  检查可能的目录:"
    for dir in "/var/lib/rancher/k3s/data/current/bin" "/var/lib/rancher/k3s/data/cni/bin" "/opt/cni/bin"; do
        if [ -d "$dir" ]; then
            echo_info "    $dir:"
            sudo ls -la "$dir" | grep -i multus || echo_warn "      未找到 multus"
        fi
    done
fi

# 4. 检查 CNI 插件如何运行
echo ""
echo_info "4. CNI 插件运行用户"
echo ""
echo_info "  CNI 插件由 kubelet 调用，通常以 root 运行"
echo_info "  检查 kubelet 进程:"
if pgrep -x kubelet > /dev/null; then
    KUBELET_USER=$(ps -o user= -p $(pgrep -x kubelet) | head -1)
    echo_info "    kubelet 运行用户: $KUBELET_USER"
    if [ "$KUBELET_USER" = "root" ]; then
        echo_info "    ✓ kubelet 以 root 运行，CNI 插件也能以 root 访问文件"
    else
        echo_warn "    ⚠️  kubelet 不是以 root 运行"
    fi
else
    echo_warn "    ⚠️  无法检查 kubelet 进程"
fi

# 5. 验证文件可访问性
echo ""
echo_info "5. 验证文件可访问性"
echo ""

if [ -f "$KUBECONFIG_FILE" ]; then
    # 尝试以 root 身份读取（模拟 CNI 插件）
    if sudo cat "$KUBECONFIG_FILE" > /dev/null 2>&1; then
        echo_info "  ✓ root 用户可以读取文件"
        
        # 检查文件内容是否有效
        if sudo cat "$KUBECONFIG_FILE" | grep -q "apiVersion"; then
            echo_info "  ✓ 文件内容看起来有效（包含 apiVersion）"
        else
            echo_error "  ✗ 文件内容可能无效"
        fi
    else
        echo_error "  ✗ 即使 root 也无法读取文件"
    fi
fi

# 6. 建议
echo ""
echo_info "6. 建议"
echo ""

if [ -f "$KUBECONFIG_FILE" ]; then
    PERM=$(sudo stat -c "%a" "$KUBECONFIG_FILE")
    if [ "$PERM" = "600" ]; then
        echo_info "  文件权限是 600（只有 root 可读写），这对 CNI 插件是合适的"
    elif [ "$PERM" = "644" ]; then
        echo_info "  文件权限是 644（所有用户可读），这对 CNI 插件也是可以的"
    else
        echo_warn "  文件权限是 $PERM，建议检查是否合适"
    fi
fi

echo ""
echo_info "关键点："
echo_info "  - CNI 插件由 kubelet 调用，以 root 运行"
echo_info "  - 即使文件权限是 600，root 也能访问"
echo_info "  - 如果仍无法工作，可能是配置文件路径问题或二进制文件路径问题"
echo ""


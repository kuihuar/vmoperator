#!/bin/bash

# 修复 kubeconfig 权限和证书问题

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
echo_info "修复 kubeconfig 权限"
echo_info "=========================================="
echo ""

# 1. 检查 k3s kubeconfig
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
USER_KUBECONFIG="$HOME/.kube/config"

echo_info "1. 检查 k3s kubeconfig"
echo ""

if [ ! -f "$K3S_KUBECONFIG" ]; then
    echo_error "  ✗ k3s kubeconfig 不存在: $K3S_KUBECONFIG"
    exit 1
fi

echo_info "  ✓ k3s kubeconfig 存在"

# 2. 创建 .kube 目录
echo ""
echo_info "2. 创建 .kube 目录"
echo ""

mkdir -p ~/.kube
echo_info "  ✓ 目录已创建"

# 3. 复制 kubeconfig
echo ""
echo_info "3. 复制 kubeconfig 到用户目录"
echo ""

sudo cp "$K3S_KUBECONFIG" "$USER_KUBECONFIG"
sudo chown $USER:$USER "$USER_KUBECONFIG"
chmod 600 "$USER_KUBECONFIG"

echo_info "  ✓ kubeconfig 已复制到: $USER_KUBECONFIG"
echo_info "  ✓ 权限已设置: 600"

# 4. 检查 server 地址
echo ""
echo_info "4. 检查 server 地址"
echo ""

SERVER=$(grep server "$USER_KUBECONFIG" | awk '{print $2}')
echo_info "  当前 server: $SERVER"

if echo "$SERVER" | grep -q "127.0.0.1\|localhost"; then
    echo_warn "  ⚠️  server 地址是 $SERVER"
    echo_info "  如果需要从远程访问，可以修改为节点 IP"
    echo_info "  当前配置可以正常使用（本地访问）"
fi

# 5. 验证连接
echo ""
echo_info "5. 验证连接"
echo ""

if kubectl get nodes &>/dev/null; then
    echo_info "  ✓ 连接成功"
    kubectl get nodes
else
    echo_error "  ✗ 连接失败"
    echo_info "  尝试使用 sudo kubectl get nodes 验证 k3s 是否正常"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "现在可以使用 kubectl 命令（不需要 sudo）"
echo ""


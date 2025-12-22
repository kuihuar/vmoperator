#!/bin/bash

# 继续 Multus 安装流程

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
echo_info "继续 Multus 安装"
echo_info "=========================================="
echo ""

# 1. 先修复 RBAC（如果权限不完整）
echo_info "1. 修复 RBAC 配置"
echo ""

./scripts/fix-multus-rbac.sh

# 2. 确保 kubeconfig 存在
echo ""
echo_info "2. 检查 kubeconfig"
echo ""

KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo_info "  创建 kubeconfig..."
    sudo ./scripts/create-kubeconfig-official.sh
else
    echo_info "  ✓ kubeconfig 已存在"
fi

# 3. 继续安装 Multus
echo ""
echo_info "3. 继续安装 Multus"
echo ""

# 检查是否已经有部分安装
if kubectl get daemonset -n kube-system kube-multus-ds > /dev/null 2>&1; then
    echo_info "  Multus DaemonSet 已存在，检查状态..."
    kubectl get daemonset -n kube-system kube-multus-ds
    
    echo ""
    read -p "是否重新安装？（会删除现有安装）(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo_info "  删除现有安装..."
        ./scripts/cleanup-multus-installation.sh
        echo ""
        echo_info "  重新安装..."
        sudo ./scripts/install-multus-kubectl-k3s.sh
    else
        echo_info "  使用现有安装"
    fi
else
    echo_info "  执行安装..."
    sudo ./scripts/install-multus-kubectl-k3s.sh
fi

# 4. 验证安装
echo ""
echo_info "4. 验证安装"
echo ""

sleep 5

echo_info "  检查 DaemonSet:"
kubectl get daemonset -n kube-system kube-multus-ds || echo_error "  ✗ DaemonSet 不存在"

echo ""
echo_info "  检查 Pods:"
kubectl get pods -n kube-system -l app=multus

echo ""
echo_info "  等待 Pods 就绪（最多 60 秒）..."
timeout 60 bash -c 'until kubectl get pods -n kube-system -l app=multus -o jsonpath="{.items[0].status.phase}" 2>/dev/null | grep -q Running; do sleep 2; done' && echo_info "  ✓ Pods 已就绪" || echo_warn "  ⚠️  Pods 可能还未就绪，请稍后检查"

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "检查 Pods 状态:"
kubectl get pods -n kube-system -l app=multus

echo ""
echo_info "如果 Pods 有问题，查看日志:"
echo "  kubectl logs -n kube-system -l app=multus"
echo ""


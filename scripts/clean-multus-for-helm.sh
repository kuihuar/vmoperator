#!/bin/bash

# 彻底清理 Multus 资源以便用 Helm 重新安装

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
echo_info "清理 Multus 资源以便 Helm 安装"
echo_info "=========================================="
echo ""

# 1. 卸载 Helm 安装（如果有）
echo_info "1. 卸载现有的 Helm 安装"
echo ""

if helm list -n kube-system | grep -q multus; then
    RELEASE_NAME=$(helm list -n kube-system | grep multus | awk '{print $1}')
    echo_info "  发现 Helm Release: $RELEASE_NAME"
    helm uninstall $RELEASE_NAME -n kube-system --ignore-not-found=true
    sleep 5
else
    echo_info "  ✓ 没有 Helm 安装"
fi

# 2. 删除所有 Multus 相关资源
echo ""
echo_info "2. 删除所有 Multus 相关资源"
echo ""

echo_info "  删除 DaemonSet..."
kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true

echo_info "  删除 Pods..."
kubectl delete pod -n kube-system -l app=multus --ignore-not-found=true --force --grace-period=0
kubectl delete pod -n kube-system -l name=multus --ignore-not-found=true --force --grace-period=0

echo_info "  删除 ServiceAccount..."
kubectl delete serviceaccount -n kube-system multus --ignore-not-found=true
kubectl delete serviceaccount -n kube-system kube-multus-ds --ignore-not-found=true

echo_info "  删除 ClusterRole 和 ClusterRoleBinding..."
kubectl delete clusterrolebinding multus --ignore-not-found=true
kubectl delete clusterrolebinding kube-multus-ds --ignore-not-found=true
kubectl delete clusterrole multus --ignore-not-found=true
kubectl delete clusterrole kube-multus-ds --ignore-not-found=true

echo_info "  删除 ConfigMap..."
kubectl delete configmap -n kube-system multus-config --ignore-not-found=true
kubectl delete configmap -n kube-system kube-multus-ds-config --ignore-not-found=true

echo_info "  删除 Service（如果有）..."
kubectl delete service -n kube-system multus --ignore-not-found=true

echo_info "  删除 Secret（如果有）..."
kubectl delete secret -n kube-system multus-kubeconfig --ignore-not-found=true

# 3. 等待资源完全删除
echo ""
echo_info "3. 等待资源完全删除"
echo ""

sleep 5

# 4. 验证清理
echo ""
echo_info "4. 验证清理结果"
echo ""

REMAINING_PODS=$(kubectl get pods -n kube-system -l app=multus 2>/dev/null | grep -v NAME | wc -l || echo "0")
REMAINING_SA=$(kubectl get serviceaccount -n kube-system | grep -E "multus|kube-multus" | wc -l || echo "0")
REMAINING_DS=$(kubectl get daemonset -n kube-system | grep -E "multus|kube-multus" | wc -l || echo "0")

if [ "$REMAINING_PODS" = "0" ] && [ "$REMAINING_SA" = "0" ] && [ "$REMAINING_DS" = "0" ]; then
    echo_info "  ✓ 所有 Multus 资源已清理"
else
    echo_warn "  ⚠️  仍有资源残留:"
    if [ "$REMAINING_PODS" != "0" ]; then
        echo_warn "    - Pods: $REMAINING_PODS"
        kubectl get pods -n kube-system -l app=multus 2>/dev/null || true
    fi
    if [ "$REMAINING_SA" != "0" ]; then
        echo_warn "    - ServiceAccounts: $REMAINING_SA"
        kubectl get serviceaccount -n kube-system | grep -E "multus|kube-multus" || true
    fi
    if [ "$REMAINING_DS" != "0" ]; then
        echo_warn "    - DaemonSets: $REMAINING_DS"
        kubectl get daemonset -n kube-system | grep -E "multus|kube-multus" || true
    fi
    
    echo ""
    echo_warn "  可能需要手动删除:"
    echo "    kubectl delete serviceaccount -n kube-system <name> --force --grace-period=0"
fi

# 5. 最终检查
echo ""
echo_info "5. 最终检查"
echo ""

# 检查是否有 Finalizers 阻止删除
STUCK_RESOURCES=$(kubectl get all -n kube-system -l app=multus 2>/dev/null | grep -v NAME || echo "")
if [ -n "$STUCK_RESOURCES" ]; then
    echo_warn "  ⚠️  发现可能卡住的资源（可能有 Finalizers）:"
    echo "$STUCK_RESOURCES"
    echo ""
    echo_warn "  如果资源无法删除，可能需要:"
    echo "    kubectl patch <resource-type> -n kube-system <name> -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
fi

echo ""
echo_info "=========================================="
echo_info "清理完成"
echo_info "=========================================="
echo ""
echo_info "现在可以运行 Helm 安装:"
echo "  ./scripts/install-multus-k3s-official.sh"
echo ""


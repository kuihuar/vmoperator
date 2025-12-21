#!/bin/bash

# 卸载当前安装的 Multus

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
echo_info "卸载 Multus"
echo_info "=========================================="
echo ""

# 1. 检查是否使用 Helm 安装
echo_info "1. 检查安装方式"
echo ""

HELM_RELEASE=$(helm list -n kube-system 2>/dev/null | grep -i multus | awk '{print $1}' || echo "")
if [ -n "$HELM_RELEASE" ]; then
    echo_info "  检测到 Helm 安装: $HELM_RELEASE"
    USE_HELM=true
else
    echo_info "  未检测到 Helm 安装，使用 kubectl 方式"
    USE_HELM=false
fi

# 2. 卸载 Multus
echo ""
echo_info "2. 卸载 Multus"
echo ""

if [ "$USE_HELM" = true ]; then
    echo_info "  使用 Helm 卸载..."
    helm uninstall $HELM_RELEASE -n kube-system 2>/dev/null || echo_warn "  Helm 卸载失败，尝试其他方式"
else
    echo_info "  删除 DaemonSet 和 Pod..."
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
    kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 --ignore-not-found=true
    
    echo_info "  删除 CRD..."
    kubectl delete crd networkattachmentdefinitions.k8s.cni.cncf.io --ignore-not-found=true
    
    echo_info "  删除 ServiceAccount、ClusterRole、ClusterRoleBinding..."
    kubectl delete serviceaccount -n kube-system multus --ignore-not-found=true
    kubectl delete clusterrole multus --ignore-not-found=true
    kubectl delete clusterrolebinding multus --ignore-not-found=true
    
    echo_info "  删除 ConfigMap..."
    kubectl delete configmap -n kube-system multus-config --ignore-not-found=true
fi

# 3. 等待清理
echo ""
echo_info "3. 等待资源清理"
sleep 5

# 4. 验证卸载
echo ""
echo_info "4. 验证卸载结果"
echo ""

MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus 2>/dev/null | grep -v NAME | wc -l || echo "0")
if [ "$MULTUS_PODS" = "0" ]; then
    echo_info "  ✓ Multus Pod 已删除"
else
    echo_warn "  ⚠️  仍有 $MULTUS_PODS 个 Multus Pod 存在"
    kubectl get pods -n kube-system -l app=multus
fi

MULTUS_DS=$(kubectl get daemonset -n kube-system kube-multus-ds 2>/dev/null | grep -v NAME | wc -l || echo "0")
if [ "$MULTUS_DS" = "0" ]; then
    echo_info "  ✓ Multus DaemonSet 已删除"
else
    echo_warn "  ⚠️  Multus DaemonSet 仍存在"
fi

echo ""
echo_info "=========================================="
echo_info "卸载完成"
echo_info "=========================================="
echo ""
echo_info "可以继续使用 Helm 安装 Multus"
echo "  ./scripts/install-multus-helm.sh"
echo ""


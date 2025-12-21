#!/bin/bash

# 清理旧 Multus 并用 Helm 安装

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
echo_info "清理并重新安装 Multus (Helm)"
echo_info "=========================================="
echo ""

# 1. 删除旧的 Multus
echo_info "1. 删除旧的 Multus 安装"
echo ""

# 删除 DaemonSet
kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true

# 删除 Pod
kubectl delete pod -n kube-system -l app=multus --ignore-not-found=true --force --grace-period=0

# 删除其他资源
kubectl delete serviceaccount -n kube-system kube-multus-ds --ignore-not-found=true
kubectl delete clusterrolebinding multus --ignore-not-found=true
kubectl delete clusterrole multus --ignore-not-found=true
kubectl delete configmap -n kube-system multus-config --ignore-not-found=true

# 删除 Helm 安装的（如果有）
if helm list -n kube-system | grep -q multus; then
    RELEASE_NAME=$(helm list -n kube-system | grep multus | awk '{print $1}')
    echo_info "  卸载 Helm Release: $RELEASE_NAME"
    helm uninstall $RELEASE_NAME -n kube-system --ignore-not-found=true
fi

echo_info "  ✓ 清理完成"
sleep 5

# 2. 添加 Helm Repo
echo ""
echo_info "2. 配置 Helm Repository"
echo ""

helm repo add k8snetworkplumbingwg https://k8snetworkplumbingwg.github.io/helm-charts/ 2>/dev/null || echo_warn "  Repository 已存在"
helm repo update

echo_info "  ✓ Helm Repository 已配置"

# 3. 检查 values 文件
echo ""
echo_info "3. 检查 values 配置文件"
echo ""

VALUES_FILE="config/multus-values.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    echo_error "  ✗ Values 文件不存在: $VALUES_FILE"
    exit 1
fi

echo_info "  ✓ Values 文件: $VALUES_FILE"

# 4. 安装 Multus
echo ""
echo_info "4. 使用 Helm 安装 Multus"
echo ""

RELEASE_NAME="multus"
NAMESPACE="kube-system"

echo_info "  安装命令:"
echo "    helm install $RELEASE_NAME k8snetworkplumbingwg/multus \\"
echo "      --namespace $NAMESPACE \\"
echo "      --create-namespace \\"
echo "      --values $VALUES_FILE"
echo ""

read -p "是否继续? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_warn "  已取消"
    exit 0
fi

helm install $RELEASE_NAME k8snetworkplumbingwg/multus \
    --namespace $NAMESPACE \
    --create-namespace \
    --values $VALUES_FILE \
    --wait \
    --timeout 10m

if [ $? -eq 0 ]; then
    echo_info "  ✓ Multus 安装成功"
else
    echo_error "  ✗ Multus 安装失败"
    echo_warn "  查看详细信息:"
    echo "    helm list -n $NAMESPACE"
    echo "    kubectl get pods -n $NAMESPACE -l app=multus"
    exit 1
fi

# 5. 验证安装
echo ""
echo_info "5. 验证安装"
echo ""

sleep 10

echo_info "  Pod 状态:"
kubectl get pods -n $NAMESPACE -l app=multus

echo ""
echo_info "  DaemonSet 状态:"
kubectl get daemonset -n $NAMESPACE -l app=multus

echo ""
echo_info "  CRD:"
kubectl get crd | grep networkattachment || echo_warn "  CRD 未创建"

echo ""
MULTUS_POD=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod 日志 ($MULTUS_POD):"
    kubectl logs -n $NAMESPACE $MULTUS_POD --tail=20 2>&1 | head -15
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""


#!/bin/bash

# 使用 k3s 官方推荐的方式安装 Multus
# 参考: https://docs.k3s.io/networking/multus-ipams

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "使用 k3s 官方推荐方式安装 Multus"
echo_info "参考: https://docs.k3s.io/networking/multus-ipams"
echo_info "=========================================="
echo ""

# 检查 Helm
if ! command -v helm &> /dev/null; then
    echo_error "  ✗ Helm 未安装"
    exit 1
fi

echo_info "  Helm 版本: $(helm version --short)"

# 1. 清理旧安装
echo ""
echo_info "1. 清理旧的 Multus 安装"
echo ""

# 检查是否有清理脚本
if [ -f "scripts/clean-multus-for-helm.sh" ]; then
    echo_info "  使用清理脚本彻底清理..."
    ./scripts/clean-multus-for-helm.sh
else
    echo_info "  手动清理资源..."
    
    # 卸载旧的 Helm 安装
    if helm list -n kube-system | grep -q multus; then
        RELEASE_NAME=$(helm list -n kube-system | grep multus | awk '{print $1}')
        echo_info "  卸载旧的 Helm Release: $RELEASE_NAME"
        helm uninstall $RELEASE_NAME -n kube-system --ignore-not-found=true
    fi
    
    # 删除所有相关资源
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
    kubectl delete pod -n kube-system -l app=multus --ignore-not-found=true --force --grace-period=0
    kubectl delete serviceaccount -n kube-system multus --ignore-not-found=true
    kubectl delete serviceaccount -n kube-system kube-multus-ds --ignore-not-found=true
    kubectl delete clusterrolebinding multus --ignore-not-found=true
    kubectl delete clusterrolebinding kube-multus-ds --ignore-not-found=true
    kubectl delete clusterrole multus --ignore-not-found=true
    kubectl delete clusterrole kube-multus-ds --ignore-not-found=true
    kubectl delete configmap -n kube-system multus-config --ignore-not-found=true
    
    sleep 5
    echo_info "  ✓ 清理完成"
fi

# 2. 添加 Helm Repo
echo ""
echo_info "2. 添加 RKE2 Helm Repository"
echo ""

helm repo add rke2-charts https://rke2-charts.rancher.io 2>/dev/null || echo_warn "  Repository 可能已存在"
helm repo update

echo_info "  ✓ Helm Repository 已配置"

# 3. 检查 values 文件
echo ""
echo_info "3. 检查配置文件"
echo ""

VALUES_FILE="config/multus-values-k3s.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    echo_error "  ✗ Values 文件不存在: $VALUES_FILE"
    exit 1
fi

echo_info "  ✓ Values 文件: $VALUES_FILE"
echo_info "  配置文件内容预览:"
cat "$VALUES_FILE" | head -20
echo ""

# 4. 安装 Multus
echo ""
echo_info "4. 使用 Helm 安装 Multus (rke2-multus)"
echo ""

RELEASE_NAME="multus"
NAMESPACE="kube-system"

echo_info "  安装命令:"
echo "    helm install $RELEASE_NAME rke2-charts/rke2-multus \\"
echo "      --namespace $NAMESPACE \\"
echo "      --create-namespace \\"
echo "      --values $VALUES_FILE"
echo ""

read -p "是否继续安装? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_warn "  已取消"
    exit 0
fi

helm install $RELEASE_NAME rke2-charts/rke2-multus \
    --namespace $NAMESPACE \
    --create-namespace \
    --values $VALUES_FILE \
    --wait \
    --timeout 10m

if [ $? -eq 0 ]; then
    echo_info "  ✓ Multus 安装成功"
else
    echo_error "  ✗ Multus 安装失败"
    exit 1
fi

# 5. 验证安装
echo ""
echo_info "5. 验证安装"
echo ""

sleep 10

echo_info "  Pod 状态:"
kubectl get pods -n $NAMESPACE -l app=multus || kubectl get pods -n $NAMESPACE | grep multus

echo ""
echo_info "  DaemonSet 状态:"
kubectl get daemonset -n $NAMESPACE -l app=multus || kubectl get daemonset -n $NAMESPACE | grep multus

echo ""
echo_info "  CRD:"
kubectl get crd | grep networkattachment || echo_warn "  CRD 未找到"

echo ""
MULTUS_POD=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
             kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.metadata.labels.app=="multus")].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod 日志 ($MULTUS_POD):"
    kubectl logs -n $NAMESPACE $MULTUS_POD --tail=20 2>&1 | head -15
    
    echo ""
    echo_info "  检查 Pod 内的 CNI 配置:"
    kubectl exec -n $NAMESPACE $MULTUS_POD -- ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/ 2>&1 | head -10 || true
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "参考文档:"
echo "  - k3s Multus 文档: https://docs.k3s.io/networking/multus-ipams"
echo "  - Multus Thick Plugin: https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/thick-plugin.md"
echo ""
echo_info "如果 Pod 状态异常，请检查："
echo "  1. Pod 日志: kubectl logs -n $NAMESPACE -l app=multus"
echo "  2. Pod 详情: kubectl describe pod -n $NAMESPACE -l app=multus"
echo "  3. Values 配置: cat $VALUES_FILE"
echo ""


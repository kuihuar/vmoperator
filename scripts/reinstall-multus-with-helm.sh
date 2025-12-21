#!/bin/bash

# 删除当前 Multus 并使用 Helm 重新安装

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
echo_info "使用 Helm 重新安装 Multus"
echo_info "=========================================="
echo ""

# 1. 检查 Helm
echo_info "1. 检查 Helm 是否安装"
if ! command -v helm &> /dev/null; then
    echo_error "  ✗ Helm 未安装"
    echo_info "  安装 Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi
echo_info "  ✓ Helm 已安装: $(helm version --short)"

# 2. 添加 Helm Repo
echo ""
echo_info "2. 添加 Multus Helm Repository"
echo ""

helm repo add k8snetworkplumbingwg https://k8snetworkplumbingwg.github.io/helm-charts/ 2>/dev/null || echo_warn "  Repository 可能已存在"
helm repo update

echo_info "  ✓ Helm Repository 已配置"

# 3. 删除当前安装的 Multus
echo ""
echo_info "3. 删除当前安装的 Multus"
echo ""

# 检查是否有通过 YAML 安装的 Multus
if kubectl get daemonset -n kube-system kube-multus-ds &>/dev/null; then
    echo_info "  发现 DaemonSet: kube-multus-ds"
    echo_warn "  删除当前 Multus 安装..."
    
    # 删除 DaemonSet
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
    
    # 删除 Pod
    kubectl delete pod -n kube-system -l app=multus --ignore-not-found=true
    
    # 删除 ServiceAccount
    kubectl delete serviceaccount -n kube-system kube-multus-ds --ignore-not-found=true
    
    # 删除 ClusterRole 和 ClusterRoleBinding
    kubectl delete clusterrolebinding multus --ignore-not-found=true
    kubectl delete clusterrole multus --ignore-not-found=true
    
    # 删除 ConfigMap（如果有）
    kubectl delete configmap -n kube-system multus-config --ignore-not-found=true
    
    # 等待删除完成
    sleep 5
    echo_info "  ✓ 旧安装已删除"
else
    echo_info "  ✓ 未发现旧的 Multus 安装"
fi

# 检查是否有 Helm 安装的
if helm list -n kube-system | grep -q multus; then
    echo_warn "  发现 Helm 安装的 Multus，先卸载..."
    RELEASE_NAME=$(helm list -n kube-system | grep multus | awk '{print $1}')
    helm uninstall $RELEASE_NAME -n kube-system || true
    sleep 5
fi

# 4. 检查 values 文件
echo ""
echo_info "4. 检查 values 配置文件"
echo ""

VALUES_FILE="config/multus-values.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    echo_error "  ✗ Values 文件不存在: $VALUES_FILE"
    exit 1
fi

echo_info "  ✓ Values 文件存在: $VALUES_FILE"
echo_info "  检查配置..."

# 检查必要的配置
if grep -q "cni_conf:" "$VALUES_FILE"; then
    echo_info "  ✓ 找到 cni_conf 配置"
else
    echo_warn "  ⚠️  未找到 cni_conf 配置，将使用默认值"
fi

# 5. 安装 Multus
echo ""
echo_info "5. 使用 Helm 安装 Multus"
echo ""

RELEASE_NAME="multus"
NAMESPACE="kube-system"

read -p "是否继续安装? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_warn "  已取消"
    exit 0
fi

echo_info "  安装 Multus..."
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
    exit 1
fi

# 6. 验证安装
echo ""
echo_info "6. 验证安装"
echo ""

sleep 10

echo_info "  检查 Pod 状态:"
kubectl get pods -n $NAMESPACE -l app=multus

echo ""
echo_info "  检查 DaemonSet:"
kubectl get daemonset -n $NAMESPACE -l app=multus

echo ""
echo_info "  检查 CRD:"
kubectl get crd | grep networkattachment

echo ""
echo_info "  查看 Pod 日志:"
MULTUS_POD=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    kubectl logs -n $NAMESPACE $MULTUS_POD --tail=20 2>&1 | head -15 || echo_warn "  无法获取日志"
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 状态不是 Running，请检查："
echo "  1. Pod 日志: kubectl logs -n $NAMESPACE -l app=multus"
echo "  2. Pod 详情: kubectl describe pod -n $NAMESPACE -l app=multus"
echo "  3. Values 配置: cat $VALUES_FILE"
echo ""


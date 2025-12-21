#!/bin/bash

# 使用 Helm 安装 Multus CNI

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
echo_info "使用 Helm 安装 Multus CNI"
echo_info "=========================================="
echo ""

# 1. 检查 Helm
echo_info "1. 检查 Helm"
echo ""

if ! command -v helm &> /dev/null; then
    echo_error "  ✗ Helm 未安装"
    echo_info "  安装 Helm:"
    echo "    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

HELM_VERSION=$(helm version --short)
echo_info "  ✓ Helm 已安装: $HELM_VERSION"

# 2. 添加 Helm 仓库
echo ""
echo_info "2. 添加 Multus Helm 仓库"
echo ""

REPO_NAME="multus"
REPO_URL="https://k8snetworkplumbingwg.github.io/helm-charts"

if helm repo list | grep -q "$REPO_NAME"; then
    echo_info "  ✓ 仓库已存在，更新..."
    helm repo update $REPO_NAME
else
    echo_info "  添加仓库..."
    helm repo add $REPO_NAME $REPO_URL
    helm repo update $REPO_NAME
    echo_info "  ✓ 仓库已添加"
fi

# 3. 检查并卸载旧版本
echo ""
echo_info "3. 检查现有安装"
echo ""

OLD_RELEASE=$(helm list -n kube-system 2>/dev/null | grep -i multus | awk '{print $1}' || echo "")
if [ -n "$OLD_RELEASE" ]; then
    echo_warn "  检测到现有安装: $OLD_RELEASE"
    read -p "是否卸载旧版本? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo_info "  卸载旧版本..."
        helm uninstall $OLD_RELEASE -n kube-system || true
        sleep 5
    fi
fi

# 4. 准备 values 文件
echo ""
echo_info "4. 准备配置"
echo ""

VALUES_FILE="config/multus-values.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    echo_error "  ✗ Values 文件不存在: $VALUES_FILE"
    exit 1
fi

echo_info "  ✓ 使用配置文件: $VALUES_FILE"

# 显示关键配置
echo ""
echo_info "  关键配置预览:"
echo "    CNI 配置目录: $(grep -A 1 "confDir:" $VALUES_FILE | grep -v "^#" | tail -1 | awk '{print $2}')"
echo "    主机挂载路径: $(grep -A 1 "hostPath:" $VALUES_FILE | grep "/var/lib/rancher/k3s" | head -1 | awk '{print $2}')"

# 5. 安装 Multus
echo ""
echo_info "5. 安装 Multus"
echo ""

RELEASE_NAME="multus"
NAMESPACE="kube-system"

echo_info "  执行安装..."
helm install $RELEASE_NAME $REPO_NAME/multus \
  --namespace $NAMESPACE \
  --create-namespace \
  --values $VALUES_FILE \
  --wait --timeout 5m

if [ $? -eq 0 ]; then
    echo_info "  ✓ Multus 安装成功"
else
    echo_error "  ✗ 安装失败"
    exit 1
fi

# 6. 验证安装
echo ""
echo_info "6. 验证安装"
echo ""

sleep 10

echo_info "  检查 DaemonSet:"
kubectl get daemonset -n $NAMESPACE | grep multus || echo_warn "  未找到 DaemonSet"

echo ""
echo_info "  检查 Pods:"
kubectl get pods -n $NAMESPACE -l app=multus

echo ""
echo_info "  检查 CRD:"
kubectl get crd | grep network-attachment || echo_warn "  未找到 CRD"

# 7. 检查 Pod 状态和日志
echo ""
echo_info "7. 检查 Pod 状态"
echo ""

MULTUS_PODS=$(kubectl get pods -n $NAMESPACE -l app=multus -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_PODS" ]; then
    for pod in $MULTUS_PODS; do
        STATUS=$(kubectl get pod -n $NAMESPACE $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo_info "  Pod: $pod - 状态: $STATUS"
        
        if [ "$STATUS" = "Running" ]; then
            echo_info "    ✓ Pod 运行正常"
            echo_info "    查看日志:"
            kubectl logs -n $NAMESPACE $pod --tail=10 2>&1 | head -5 || echo_warn "      无法获取日志"
        else
            echo_warn "    ⚠️  Pod 状态异常"
            echo_info "    查看日志:"
            kubectl logs -n $NAMESPACE $pod --tail=20 2>&1 | head -10 || echo_warn "      无法获取日志"
        fi
    done
else
    echo_warn "  ⚠️  未找到 Multus Pods"
fi

# 8. 验证配置文件
echo ""
echo_info "8. 验证配置文件"
echo ""

if [ -n "$MULTUS_PODS" ]; then
    POD=$(echo $MULTUS_PODS | awk '{print $1}')
    echo_info "  检查 Pod 内配置文件:"
    
    if kubectl exec -n $NAMESPACE $POD -- test -f /etc/cni/net.d/multus.d/daemon-config.json 2>/dev/null; then
        echo_info "    ✓ daemon-config.json 存在"
    else
        echo_warn "    ✗ daemon-config.json 不存在"
    fi
    
    if kubectl exec -n $NAMESPACE $POD -- test -f /etc/cni/net.d/00-multus.conf 2>/dev/null; then
        echo_info "    ✓ 00-multus.conf 存在"
    else
        echo_warn "    ✗ 00-multus.conf 不存在"
    fi
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "后续步骤:"
echo "  1. 检查所有 Pod 状态: kubectl get pods -n kube-system -l app=multus"
echo "  2. 查看日志: kubectl logs -n kube-system -l app=multus --tail=50"
echo "  3. 验证 CRD: kubectl get crd networkattachmentdefinitions.k8s.cni.cncf.io"
echo ""
echo_info "如果遇到问题，可以："
echo "  - 查看 Helm 状态: helm status multus -n kube-system"
echo "  - 卸载重新安装: helm uninstall multus -n kube-system"
echo ""


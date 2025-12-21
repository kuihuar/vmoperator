#!/bin/bash

# 修复 Multus kubeconfig 文件缺失问题

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
echo_info "修复 Multus kubeconfig 文件缺失"
echo_info "=========================================="
echo ""

# 检查路径
CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
KUBECONFIG_PATH="$CNI_CONF_DIR/multus.d/multus.kubeconfig"

echo_info "检查 Multus kubeconfig 文件: $KUBECONFIG_PATH"
echo ""

if [ -f "$KUBECONFIG_PATH" ]; then
    echo_info "  ✓ kubeconfig 文件已存在"
    sudo ls -la "$KUBECONFIG_PATH"
    exit 0
fi

echo_warn "  ✗ kubeconfig 文件不存在"

# 检查 Multus Pod
echo ""
echo_info "检查 Multus Pod 状态"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MULTUS_POD" ]; then
    echo_error "  ✗ 未找到 Multus Pod"
    echo_warn "  请先安装 Multus: ./scripts/install-multus-kubectl-k3s.sh"
    exit 1
fi

echo_info "  Multus Pod: $MULTUS_POD"
MULTUS_STATUS=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
echo_info "  状态: $MULTUS_STATUS"

if [ "$MULTUS_STATUS" != "Running" ]; then
    echo_warn "  ⚠️  Multus Pod 未运行，可能无法自动创建 kubeconfig"
    echo_info "  查看日志:"
    kubectl logs -n kube-system $MULTUS_POD --tail=20 2>&1 | head -15
fi

# 手动创建 kubeconfig
echo ""
echo_info "手动创建 Multus kubeconfig 文件"
echo ""

# 获取 Kubernetes API Server 地址
API_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")
if [ -z "$API_SERVER" ]; then
    # 尝试从集群中获取
    API_SERVER=$(kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print $NF}' | sed 's|https://||' || echo "kubernetes.default.svc:443")
fi

echo_info "  API Server: $API_SERVER"

# 获取 ServiceAccount token（使用 Multus ServiceAccount）
SA_NAME=$(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null || echo "kube-multus-ds")
echo_info "  ServiceAccount: $SA_NAME"

# 检查 ServiceAccount 是否存在
if ! kubectl get serviceaccount -n kube-system $SA_NAME &>/dev/null; then
    echo_warn "  ⚠️  ServiceAccount 不存在，使用默认的"
    SA_NAME="default"
fi

# 获取 Token
SECRET_NAME=$(kubectl get serviceaccount -n kube-system $SA_NAME -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")

if [ -z "$SECRET_NAME" ]; then
    echo_warn "  ⚠️  未找到 ServiceAccount Secret，尝试创建 Token"
    
    # 对于 k3s，使用 node 的 kubeconfig
    echo_info "  使用 k3s node kubeconfig..."
    
    # 创建目录
    sudo mkdir -p "$CNI_CONF_DIR/multus.d"
    
    # 复制 k3s kubeconfig
    K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if [ -f "$K3S_KUBECONFIG" ]; then
        echo_info "  从 k3s kubeconfig 创建 Multus kubeconfig..."
        
        # 读取 k3s kubeconfig 并修改 server 地址为内部地址
        sudo cp "$K3S_KUBECONFIG" "$KUBECONFIG_PATH.tmp"
        
        # 修改 server 地址为集群内部地址
        sudo sed -i "s|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g" "$KUBECONFIG_PATH.tmp"
        
        sudo mv "$KUBECONFIG_PATH.tmp" "$KUBECONFIG_PATH"
        sudo chmod 644 "$KUBECONFIG_PATH"
        
        echo_info "  ✓ kubeconfig 已创建"
    else
        echo_error "  ✗ 无法找到 k3s kubeconfig"
        exit 1
    fi
else
    echo_info "  从 ServiceAccount Secret 创建 kubeconfig..."
    
    TOKEN=$(kubectl get secret -n kube-system $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    CA_CERT=$(kubectl get secret -n kube-system $SECRET_NAME -o jsonpath='{.data.ca\.crt}' 2>/dev/null || echo "")
    
    if [ -z "$TOKEN" ] || [ -z "$CA_CERT" ]; then
        echo_warn "  ⚠️  无法从 Secret 获取 token，使用 k3s kubeconfig"
        sudo mkdir -p "$CNI_CONF_DIR/multus.d"
        sudo cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_PATH"
        sudo sed -i "s|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g" "$KUBECONFIG_PATH"
        sudo chmod 644 "$KUBECONFIG_PATH"
    else
        # 创建 kubeconfig
        sudo mkdir -p "$CNI_CONF_DIR/multus.d"
        
        sudo tee "$KUBECONFIG_PATH" > /dev/null <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT}
    server: https://kubernetes.default.svc:443
  name: cluster
contexts:
- context:
    cluster: cluster
    user: multus
  name: multus-context
current-context: multus-context
users:
- name: multus
  user:
    token: ${TOKEN}
EOF
        
        sudo chmod 644 "$KUBECONFIG_PATH"
        echo_info "  ✓ kubeconfig 已创建"
    fi
fi

# 验证文件
echo ""
echo_info "验证 kubeconfig 文件"
echo ""

if [ -f "$KUBECONFIG_PATH" ]; then
    echo_info "  ✓ 文件存在: $KUBECONFIG_PATH"
    sudo ls -la "$KUBECONFIG_PATH"
    
    # 验证内容
    if sudo grep -q "server:" "$KUBECONFIG_PATH" && sudo grep -q "kubernetes" "$KUBECONFIG_PATH"; then
        echo_info "  ✓ kubeconfig 内容看起来正确"
    else
        echo_warn "  ⚠️  kubeconfig 内容可能不正确"
    fi
else
    echo_error "  ✗ 文件创建失败"
    exit 1
fi

# 重启受影响的 Pod
echo ""
echo_info "重启受影响的 Pod（如果需要）"
echo ""

echo_info "  受影响的 Pod 会在此文件创建后自动恢复"
echo_info "  如果需要立即恢复，可以删除并重新创建 Pod:"
echo "    kubectl delete pod -n rook-ceph ceph-csi-controller-manager-5dc6b7cf95-znbq6"

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""


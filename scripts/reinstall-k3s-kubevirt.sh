#!/bin/bash

# 重新安装 k3s 和 KubeVirt（不安装 Multus）

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
echo_info "重新安装 k3s 和 KubeVirt"
echo_info "=========================================="
echo ""
echo_info "安装顺序："
echo "  1. k3s"
echo "  2. CDI"
echo "  3. KubeVirt"
echo "  4. Ceph (可选)"
echo ""
echo_warn "⚠️  注意：本次安装不包含 Multus"
echo ""

# ==========================================
# 步骤 1: 安装 k3s
# ==========================================
echo ""
echo_info "1. 安装 k3s"
echo ""

if command -v k3s &>/dev/null; then
    echo_warn "  k3s 已安装，跳过"
    K3S_VERSION=$(k3s --version | head -1)
    echo_info "  当前版本: $K3S_VERSION"
else
    echo_info "  下载并安装 k3s..."
    curl -sfL https://get.k3s.io | sh -
    echo_info "  ✓ k3s 已安装"
fi

# 等待 k3s 启动
echo_info "  等待 k3s 启动..."
sleep 10

# 检查状态
if sudo systemctl is-active --quiet k3s; then
    echo_info "  ✓ k3s 运行中"
else
    echo_error "  ✗ k3s 未运行"
    sudo systemctl status k3s --no-pager | head -10
    exit 1
fi

# 配置 kubeconfig
echo_info "  配置 kubeconfig..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# 验证
kubectl get nodes
echo_info "  ✓ k3s 安装完成"

# ==========================================
# 步骤 2: 安装 CDI
# ==========================================
echo ""
echo_info "2. 安装 CDI"
echo ""

if kubectl get namespace cdi &>/dev/null; then
    echo_warn "  CDI 命名空间已存在，跳过安装"
else
    echo_info "  设置 CDI 版本..."
    export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)
    echo_info "  版本: $CDI_VERSION"
    
    echo_info "  安装 CDI Operator..."
    kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml
    
    echo_info "  等待 Operator 就绪..."
    kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s || {
        echo_warn "  Operator 启动超时，继续..."
    }
    
    echo_info "  安装 CDI CR..."
    kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml
    
    echo_info "  等待 CDI 就绪..."
    kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s || {
        echo_warn "  CDI 启动超时，继续..."
    }
    
    echo_info "  ✓ CDI 安装完成"
fi

# ==========================================
# 步骤 3: 安装 KubeVirt
# ==========================================
echo ""
echo_info "3. 安装 KubeVirt"
echo ""

if kubectl get namespace kubevirt &>/dev/null && kubectl get kubevirt -n kubevirt kubevirt &>/dev/null; then
    echo_warn "  KubeVirt 已安装，跳过"
else
    echo_info "  设置 KubeVirt 版本..."
    export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)
    echo_info "  版本: $KUBEVIRT_VERSION"
    
    echo_info "  安装 KubeVirt Operator..."
    kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
    
    echo_info "  等待 Operator 就绪..."
    kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s || {
        echo_warn "  Operator 启动超时，继续..."
    }
    
    echo_info "  安装 KubeVirt CR..."
    kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
    
    echo_info "  等待 KubeVirt 就绪..."
    kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s || {
        echo_warn "  KubeVirt 启动超时，继续..."
    }
    
    # 配置 KubeVirt（k3s 环境）
    echo_info "  配置 KubeVirt（启用软件模拟）..."
    kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}' || true
    
    # 添加节点 label
    echo_info "  添加节点 label..."
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl label node $NODE_NAME kubevirt.io/schedulable=true --overwrite || true
    
    echo_info "  ✓ KubeVirt 安装完成"
fi

# ==========================================
# 步骤 4: 验证安装
# ==========================================
echo ""
echo_info "4. 验证安装"
echo ""

echo_info "  节点状态:"
kubectl get nodes

echo ""
echo_info "  KubeVirt Pods:"
kubectl get pods -n kubevirt

echo ""
echo_info "  CDI Pods:"
kubectl get pods -n cdi

echo ""

# ==========================================
# 步骤 5: 询问是否安装 Ceph
# ==========================================
echo ""
echo_info "5. 安装 Ceph (可选)"
echo ""

read -p "是否现在安装 Ceph？(y/n，默认y): " INSTALL_CEPH
INSTALL_CEPH=${INSTALL_CEPH:-y}

if [[ $INSTALL_CEPH =~ ^[Yy]$ ]]; then
    echo_info "  开始安装 Ceph..."
    if [ -f "scripts/install-ceph-rook.sh" ]; then
        sudo ./scripts/install-ceph-rook.sh
    else
        echo_warn "  安装脚本不存在，请手动安装"
    fi
else
    echo_info "  跳过 Ceph 安装"
    echo_info "  稍后可以运行: sudo ./scripts/install-ceph-rook.sh"
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "验证命令:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n kubevirt"
echo "  kubectl get pods -n cdi"
echo "  kubectl get pods -n rook-ceph"
echo ""


#!/bin/bash

# 安装 KubeVirt（包含 CDI 前置依赖）

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
echo_info "安装 KubeVirt（包含 CDI）"
echo_info "=========================================="
echo ""

# 检查 k3s
if ! kubectl get nodes &>/dev/null; then
    echo_error "无法连接到 k3s 集群"
    echo_info "请先安装 k3s: sudo ./scripts/install-k3s-only.sh"
    exit 1
fi

# ==========================================
# 步骤 1: 安装 CDI（KubeVirt 的前置依赖）
# ==========================================
echo ""
echo_info "步骤 1: 安装 CDI (Containerized Data Importer)"
echo ""

if kubectl get namespace cdi &>/dev/null && kubectl get cdi -n cdi cdi &>/dev/null; then
    echo_warn "  CDI 已安装，跳过"
else
    echo_info "  设置 CDI 版本..."
    export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)
    
    # 如果获取失败，使用固定版本
    if [ -z "$CDI_VERSION" ] || [ "$CDI_VERSION" = "null" ]; then
        export CDI_VERSION=v1.62.0
        echo_warn "  使用固定版本: $CDI_VERSION"
    else
        echo_info "  版本: $CDI_VERSION"
    fi
    
    echo_info "  安装 CDI Operator..."
    if kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml 2>&1; then
        echo_info "  ✓ CDI Operator YAML 已应用"
    else
        echo_error "  ✗ CDI Operator 安装失败"
        exit 1
    fi
    
    echo_info "  等待 CDI Operator 就绪（最多 5 分钟）..."
    if kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s 2>&1; then
        echo_info "  ✓ CDI Operator 已就绪"
    else
        echo_warn "  ⚠️  CDI Operator 启动超时，继续安装 CDI CR..."
        kubectl get pods -n cdi
    fi
    
    echo_info "  安装 CDI CR..."
    if kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml 2>&1; then
        echo_info "  ✓ CDI CR 已应用"
    else
        echo_error "  ✗ CDI CR 安装失败"
        exit 1
    fi
    
    echo_info "  等待 CDI 就绪（最多 5 分钟）..."
    if kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s 2>&1; then
        echo_info "  ✓ CDI 已就绪"
    else
        echo_warn "  ⚠️  CDI 启动超时，检查状态..."
        kubectl get cdi -n cdi
        kubectl get pods -n cdi
    fi
fi

# ==========================================
# 步骤 2: 安装 KubeVirt
# ==========================================
echo ""
echo_info "步骤 2: 安装 KubeVirt"
echo ""

if kubectl get namespace kubevirt &>/dev/null && kubectl get kubevirt -n kubevirt kubevirt &>/dev/null; then
    echo_warn "  KubeVirt 已安装，跳过"
else
    echo_info "  设置 KubeVirt 版本..."
    export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)
    
    # 如果获取失败，使用固定版本
    if [ -z "$KUBEVIRT_VERSION" ] || [ "$KUBEVIRT_VERSION" = "null" ]; then
        export KUBEVIRT_VERSION=v1.2.0
        echo_warn "  使用固定版本: $KUBEVIRT_VERSION"
    else
        echo_info "  版本: $KUBEVIRT_VERSION"
    fi
    
    echo_info "  安装 KubeVirt Operator..."
    if kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml 2>&1; then
        echo_info "  ✓ KubeVirt Operator YAML 已应用"
    else
        echo_error "  ✗ KubeVirt Operator 安装失败"
        exit 1
    fi
    
    echo_info "  等待 KubeVirt Operator 就绪（最多 5 分钟）..."
    if kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s 2>&1; then
        echo_info "  ✓ KubeVirt Operator 已就绪"
    else
        echo_warn "  ⚠️  KubeVirt Operator 启动超时，继续安装 KubeVirt CR..."
        kubectl get pods -n kubevirt
    fi
    
    echo_info "  安装 KubeVirt CR..."
    if kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml 2>&1; then
        echo_info "  ✓ KubeVirt CR 已应用"
    else
        echo_error "  ✗ KubeVirt CR 安装失败"
        exit 1
    fi
    
    echo_info "  等待 KubeVirt 就绪（最多 10 分钟）..."
    if kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s 2>&1; then
        echo_info "  ✓ KubeVirt 已就绪"
    else
        echo_warn "  ⚠️  KubeVirt 启动超时，检查状态..."
        kubectl get kubevirt -n kubevirt
        kubectl get pods -n kubevirt
    fi
fi

# ==========================================
# 步骤 3: 配置 KubeVirt（k3s 环境）
# ==========================================
echo ""
echo_info "步骤 3: 配置 KubeVirt（k3s 环境）"
echo ""

# 启用软件模拟（k3s 环境通常需要）
echo_info "  启用软件模拟（如果硬件不支持 KVM）..."
if kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}' 2>&1; then
    echo_info "  ✓ 软件模拟已启用"
else
    echo_warn "  ⚠️  配置失败（可能已经配置）"
fi

# 添加节点 label
echo_info "  添加节点 label..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NODE_NAME" ]; then
    if kubectl label node $NODE_NAME kubevirt.io/schedulable=true --overwrite 2>&1; then
        echo_info "  ✓ 节点 label 已添加: $NODE_NAME"
    else
        echo_warn "  ⚠️  添加 label 失败"
    fi
else
    echo_warn "  ⚠️  无法获取节点名称"
fi

# ==========================================
# 步骤 4: 验证安装
# ==========================================
echo ""
echo_info "步骤 4: 验证安装"
echo ""

echo_info "  CDI 状态:"
kubectl get cdi -n cdi 2>/dev/null || echo "  CDI 未安装"
kubectl get pods -n cdi 2>/dev/null | head -5 || echo "  无 CDI Pods"

echo ""
echo_info "  KubeVirt 状态:"
kubectl get kubevirt -n kubevirt 2>/dev/null || echo "  KubeVirt 未安装"
kubectl get pods -n kubevirt 2>/dev/null | head -10 || echo "  无 KubeVirt Pods"

echo ""
echo_info "  节点 label:"
kubectl get nodes --show-labels | grep kubevirt || echo "  未找到 kubevirt label"

echo ""
echo_info "=========================================="
echo_info "KubeVirt 安装完成"
echo_info "=========================================="
echo ""
echo_info "验证命令:"
echo "  kubectl get pods -n kubevirt"
echo "  kubectl get pods -n cdi"
echo "  kubectl get kubevirt -n kubevirt"
echo ""
echo_info "下一步:"
echo "  安装 Ceph: sudo ./scripts/install-ceph-rook.sh"
echo ""

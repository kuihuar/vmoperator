#!/bin/bash

# 检查 KubeVirt 节点调度配置

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 KubeVirt 节点调度配置"
echo_info "=========================================="
echo ""

# 1. 检查节点信息
echo_info "1. 检查节点信息"
echo ""

NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo_info "  节点名称: $NODE_NAME"
echo ""

# 2. 检查节点 Labels
echo_info "2. 检查节点 Labels"
echo ""

kubectl get node "$NODE_NAME" --show-labels | grep -E "NAME|kubevirt|node-role"
echo ""

# 3. 检查 KubeVirt 相关 Labels
echo_info "3. 检查 KubeVirt 相关 Labels"
echo ""

KUBEVIRT_LABEL=$(kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels.kubevirt\.io/schedulable}' 2>/dev/null || echo "")
if [ -n "$KUBEVIRT_LABEL" ]; then
    echo_info "  ✓ kubevirt.io/schedulable: $KUBEVIRT_LABEL"
else
    echo_warn "  ⚠️  未找到 kubevirt.io/schedulable label"
fi

NODE_ROLE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' 2>/dev/null || echo "")
if [ -n "$NODE_ROLE" ]; then
    echo_info "  ✓ node-role.kubernetes.io/control-plane: $NODE_ROLE"
else
    echo_warn "  ⚠️  未找到 control-plane label"
fi

echo ""

# 4. 检查节点 Taints
echo_info "4. 检查节点 Taints"
echo ""

TAINTS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints}' 2>/dev/null || echo "[]")
if [ "$TAINTS" != "[]" ] && [ -n "$TAINTS" ]; then
    echo_warn "  ⚠️  节点有 Taints:"
    kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' | tr ' ' '\n' | while read taint; do
        echo "    - $taint"
    done
else
    echo_info "  ✓ 节点没有 Taints（可以调度）"
fi

echo ""

# 5. 检查 KubeVirt 配置
echo_info "5. 检查 KubeVirt 配置"
echo ""

KUBEVIRT_CR=$(kubectl get kubevirt kubevirt -n kubevirt -o yaml 2>/dev/null || echo "")
if [ -n "$KUBEVIRT_CR" ]; then
    echo_info "  ✓ KubeVirt CR 存在"
    
    # 检查是否有节点选择器配置
    NODE_SELECTOR=$(echo "$KUBEVIRT_CR" | grep -A 5 "nodeSelector" || echo "")
    if [ -n "$NODE_SELECTOR" ]; then
        echo "  节点选择器配置:"
        echo "$NODE_SELECTOR" | head -5
    fi
else
    echo_warn "  ⚠️  未找到 KubeVirt CR"
fi

echo ""

# 6. 建议
echo_info "=========================================="
echo_info "建议"
echo_info "=========================================="
echo ""

if [ -z "$KUBEVIRT_LABEL" ]; then
    echo_info "需要添加 kubevirt.io/schedulable label:"
    echo "  kubectl label node $NODE_NAME kubevirt.io/schedulable=true"
    echo ""
fi

if [ "$TAINTS" != "[]" ] && [ -n "$TAINTS" ]; then
    echo_warn "节点有 Taints，VM 可能需要配置 tolerations"
    echo ""
fi

echo_info "单节点环境通常不需要特殊配置，但建议："
echo "  1. 确保节点没有阻止调度的 Taints"
echo "  2. 添加 kubevirt.io/schedulable=true label（如果 KubeVirt 需要）"
echo "  3. 检查 KubeVirt 的节点选择器配置"


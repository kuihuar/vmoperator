#!/bin/bash

# 配置 KubeVirt 单节点调度

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
echo_info "配置 KubeVirt 单节点调度"
echo_info "=========================================="
echo ""

# 1. 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo_info "节点名称: $NODE_NAME"
echo ""

# 2. 添加 kubevirt.io/schedulable label
echo_info "1. 添加 kubevirt.io/schedulable label"
echo ""

CURRENT_LABEL=$(kubectl get node "$NODE_NAME" -o jsonpath='{.metadata.labels.kubevirt\.io/schedulable}' 2>/dev/null || echo "")

if [ "$CURRENT_LABEL" = "true" ]; then
    echo_info "  ✓ Label 已存在: kubevirt.io/schedulable=true"
else
    echo_info "  添加 label..."
    kubectl label node "$NODE_NAME" kubevirt.io/schedulable=true --overwrite
    echo_info "  ✓ Label 已添加"
fi

echo ""

# 3. 检查节点 Taints
echo_info "2. 检查节点 Taints"
echo ""

TAINTS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints}' 2>/dev/null || echo "[]")

if [ "$TAINTS" != "[]" ] && [ -n "$TAINTS" ]; then
    echo_warn "  ⚠️  节点有 Taints:"
    kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' | tr ' ' '\n' | while read taint; do
        echo "    - $taint"
    done
    echo ""
    echo_warn "  注意: 如果 VM 无法调度，可能需要配置 tolerations"
else
    echo_info "  ✓ 节点没有 Taints（可以正常调度）"
fi

echo ""

# 4. 验证配置
echo_info "3. 验证配置"
echo ""

kubectl get node "$NODE_NAME" --show-labels | grep -E "NAME|kubevirt"
echo ""

echo_info "=========================================="
echo_info "配置完成"
echo_info "=========================================="
echo ""

echo_info "现在可以创建 VM 了。如果仍然无法调度，检查："
echo "  1. KubeVirt 是否正常运行: kubectl get pods -n kubevirt"
echo "  2. 节点资源是否充足: kubectl describe node $NODE_NAME"
echo "  3. VM 配置中的 nodeSelector 和 tolerations"


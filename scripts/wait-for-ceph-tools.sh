#!/bin/bash

# 等待 Ceph Tools Pod 完全就绪

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

MAX_WAIT=${1:-300}  # 默认等待 5 分钟

echo ""
echo_info "等待 rook-ceph-tools Pod 完全就绪"
echo ""

# 检查 Pod 是否存在
if ! kubectl get pod rook-ceph-tools -n rook-ceph &>/dev/null; then
    echo_error "Tools Pod 不存在"
    exit 1
fi

echo_info "检查 Pod 状态..."
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    POD_PHASE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    CONTAINER_READY=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    CONTAINER_STATE=$(kubectl get pod rook-ceph-tools -n rook-ceph -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "")
    
    if [ "$POD_PHASE" = "Running" ] && [ "$CONTAINER_READY" = "true" ]; then
        echo_info "  ✓ Pod 已就绪"
        
        # 测试容器是否可以执行命令
        echo_info "  测试容器连接..."
        if kubectl exec -n rook-ceph rook-ceph-tools -- echo "test" &>/dev/null; then
            echo_info "  ✓ 容器可以执行命令"
            exit 0
        else
            echo_warn "  ⚠️  容器无法执行命令，继续等待..."
        fi
    else
        echo "  等待中... ($WAITED/$MAX_WAIT 秒) - Pod: $POD_PHASE, Container: $CONTAINER_READY"
    fi
    
    sleep 5
    WAITED=$((WAITED + 5))
done

echo_error "等待超时（$MAX_WAIT 秒）"
echo_info "当前 Pod 状态:"
kubectl get pod rook-ceph-tools -n rook-ceph
echo ""
echo_info "Pod 事件:"
kubectl describe pod rook-ceph-tools -n rook-ceph | grep -A 20 "Events:" || echo "无事件"

exit 1


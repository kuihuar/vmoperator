#!/bin/bash

# 快速检查 Ceph CSI Plugin 日志

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "检查 Ceph CSI Plugin 日志"
echo ""

# 获取 CSI RBD Plugin Pod
POD_NAME=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo_error "未找到 CSI RBD Plugin Pod"
    exit 1
fi

echo_info "Pod: $POD_NAME"
echo ""

# 检查 csi-rbdplugin 容器日志
echo_info "csi-rbdplugin 容器日志:"
echo "----------------------------------------"
kubectl logs "$POD_NAME" -n rook-ceph -c csi-rbdplugin --tail=100 2>&1
echo "----------------------------------------"
echo ""

# 检查 Pod 状态
echo_info "Pod 状态:"
kubectl get pod "$POD_NAME" -n rook-ceph
echo ""

# 检查 Pod 事件
echo_info "Pod 事件:"
kubectl describe pod "$POD_NAME" -n rook-ceph | grep -A 30 "Events:" || echo "无事件"


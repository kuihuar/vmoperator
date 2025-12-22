#!/bin/bash

# 检查 Ceph 完整状态

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 Ceph 完整状态"
echo_info "=========================================="
echo ""

# 1. 检查 CephCluster
echo_info "1. CephCluster 状态"
kubectl get cephcluster -n rook-ceph
echo ""

# 2. 检查所有 Pods
echo_info "2. 所有 Rook-Ceph Pods"
kubectl get pods -n rook-ceph
echo ""

# 3. 检查 CSI 相关资源
echo_info "3. CSI 相关资源"
echo "  DaemonSets:"
kubectl get daemonset -n rook-ceph | grep csi || echo "  无 CSI DaemonSet"
echo ""
echo "  Deployments:"
kubectl get deployment -n rook-ceph | grep csi || echo "  无 CSI Deployment"
echo ""
echo "  Pods:"
kubectl get pods -n rook-ceph | grep csi || echo "  无 CSI Pods"
echo ""

# 4. 检查 Mon Pods
echo_info "4. Mon Pods 状态"
MON_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-mon -o name 2>/dev/null || echo "")
if [ -z "$MON_PODS" ]; then
    echo_warn "  ⚠️  未找到 Mon Pods"
else
    echo "$MON_PODS" | while read pod; do
        echo "  $pod:"
        kubectl get "$pod" -n rook-ceph -o wide
        echo "  日志（最后 10 行）:"
        kubectl logs "$pod" -n rook-ceph --tail=10 2>&1 | head -10 || echo "  无法获取日志"
        echo ""
    done
fi

# 5. 检查 OSD Pods
echo_info "5. OSD Pods 状态"
OSD_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-osd -o name 2>/dev/null || echo "")
if [ -z "$OSD_PODS" ]; then
    echo_warn "  ⚠️  未找到 OSD Pods"
else
    echo "$OSD_PODS" | while read pod; do
        echo "  $pod:"
        kubectl get "$pod" -n rook-ceph -o wide
        echo ""
    done
fi

# 6. 检查 CSI Pods 详细状态
echo_info "6. CSI Pods 详细状态"
CSI_PODS=$(kubectl get pods -n rook-ceph -o name | grep csi || echo "")
if [ -z "$CSI_PODS" ]; then
    echo_warn "  ⚠️  未找到 CSI Pods"
else
    echo "$CSI_PODS" | while read pod; do
        echo "  $pod:"
        kubectl get "$pod" -n rook-ceph -o wide
        echo "  事件:"
        kubectl describe "$pod" -n rook-ceph | grep -A 10 "Events:" || echo "  无事件"
        echo ""
    done
fi

# 7. 检查 Rook Operator
echo_info "7. Rook Operator 状态"
OPERATOR_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-operator -o name 2>/dev/null | head -1)
if [ -z "$OPERATOR_POD" ]; then
    echo_error "  ✗ 未找到 Rook Operator Pod"
else
    echo "  $OPERATOR_POD:"
    kubectl get "$OPERATOR_POD" -n rook-ceph -o wide
    echo ""
    echo "  最新日志（最后 20 行）:"
    kubectl logs "$OPERATOR_POD" -n rook-ceph --tail=20 2>&1 | tail -20
fi

echo ""
echo_info "=========================================="
echo_info "检查完成"
echo_info "=========================================="


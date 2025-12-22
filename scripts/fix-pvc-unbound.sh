#!/bin/bash

# 修复 PVC 未绑定问题

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
echo_info "修复 PVC 未绑定问题"
echo_info "=========================================="
echo ""

# 1. 先运行诊断
echo_info "1. 运行诊断..."
echo ""

./scripts/diagnose-pvc-unbound.sh "$@"

echo ""

# 2. 检查并等待 Ceph 集群就绪
echo_info "2. 检查 Ceph 集群就绪状态"
echo ""

CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

if [ "$CEPH_PHASE" != "Ready" ]; then
    echo_warn "  ⚠️  Ceph 集群未就绪: $CEPH_PHASE"
    echo_info "  等待 Ceph 集群就绪（最多 5 分钟）..."
    
    for i in {1..60}; do
        CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$CEPH_PHASE" = "Ready" ]; then
            echo_info "  ✓ Ceph 集群已就绪"
            break
        fi
        echo "  等待中... ($i/60)"
        sleep 5
    done
    
    if [ "$CEPH_PHASE" != "Ready" ]; then
        echo_warn "  ⚠️  Ceph 集群仍未就绪，但继续检查其他问题"
    fi
else
    echo_info "  ✓ Ceph 集群已就绪"
fi

echo ""

# 3. 检查并创建 StorageClass（如果不存在）
echo_info "3. 检查 StorageClass"
echo ""

if ! kubectl get storageclass rook-ceph-block &>/dev/null; then
    echo_warn "  ⚠️  StorageClass 不存在，创建中..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
    
    echo_info "  ✓ StorageClass 已创建"
else
    echo_info "  ✓ StorageClass 已存在"
fi

echo ""

# 4. 检查 CSI Provisioner
echo_info "4. 检查 CSI Provisioner"
echo ""

PROV_PODS=$(kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner | grep Running | wc -l || echo "0")

if [ "$PROV_PODS" -eq "0" ]; then
    echo_warn "  ⚠️  没有运行中的 CSI Provisioner Pod"
    echo_info "  检查 Provisioner Pod 状态:"
    kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner
    echo ""
    echo_warn "  如果 Pod 未运行，可能需要："
    echo "    1. 检查 CSI Driver 安装"
    echo "    2. 检查 Ceph 集群状态"
    echo "    3. 查看 Pod 日志和事件"
else
    echo_info "  ✓ 有 $PROV_PODS 个 CSI Provisioner Pod 正在运行"
fi

echo ""

# 5. 检查并删除卡住的 PVC（可选）
if [ -n "$1" ]; then
    PVC_NAME="$1"
    PVC_NAMESPACE="${2:-default}"
    
    echo_info "5. 检查 PVC: $PVC_NAME"
    echo ""
    
    PVC_PHASE=$(kubectl get pvc "$PVC_NAME" -n "$PVC_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [ "$PVC_PHASE" = "Pending" ]; then
        echo_warn "  ⚠️  PVC 处于 Pending 状态"
        echo ""
        echo_info "  查看 PVC 事件:"
        kubectl describe pvc "$PVC_NAME" -n "$PVC_NAMESPACE" | grep -A 10 "Events:"
        echo ""
        
        read -p "是否删除并重新创建 PVC? (y/n，默认n): " RECREATE
        RECREATE=${RECREATE:-n}
        
        if [ "$RECREATE" = "y" ]; then
            echo_info "  删除 PVC..."
            kubectl delete pvc "$PVC_NAME" -n "$PVC_NAMESPACE"
            echo_info "  ✓ PVC 已删除，请重新创建"
        fi
    else
        echo_info "  PVC 状态: $PVC_PHASE"
    fi
fi

echo ""

# 6. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "如果问题仍然存在，请检查:"
echo "  1. Ceph 集群是否完全就绪: kubectl get cephcluster -n rook-ceph"
echo "  2. OSD Pods 是否运行: kubectl get pods -n rook-ceph -l app=rook-ceph-osd"
echo "  3. CSI Provisioner 日志: kubectl logs -n rook-ceph <provisioner-pod> -c csi-rbdplugin-provisioner"
echo "  4. PVC 事件: kubectl describe pvc <pvc-name>"
echo ""


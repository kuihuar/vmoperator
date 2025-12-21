#!/bin/bash

# 清理 Rook 以便重新安装

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
echo_info "清理 Rook 以便重新安装"
echo_info "=========================================="
echo ""

# 1. 卸载 Helm Release
echo_info "1. 卸载 Helm Release"
echo ""

if command -v helm &> /dev/null; then
    HELM_RELEASE=$(helm list -n rook-ceph 2>/dev/null | grep rook-ceph | awk '{print $1}' || echo "")
    
    if [ -n "$HELM_RELEASE" ]; then
        echo_info "  发现 Helm Release: $HELM_RELEASE"
        helm uninstall $HELM_RELEASE -n rook-ceph --ignore-not-found=true
        echo_info "  ✓ Helm Release 已卸载"
    else
        echo_info "  未找到 Helm Release"
    fi
else
    echo_warn "  Helm 未安装，跳过 Helm 卸载"
fi

# 2. 删除 CephCluster
echo ""
echo_info "2. 删除 CephCluster"
echo ""

kubectl delete cephcluster rook-ceph -n rook-ceph --ignore-not-found=true --wait=false

# 3. 删除所有 Rook Pods
echo ""
echo_info "3. 删除所有 Rook Pods"
echo ""

kubectl delete pods -n rook-ceph --all --force --grace-period=0 --ignore-not-found=true

# 4. 删除所有 Rook 资源
echo ""
echo_info "4. 删除所有 Rook 资源"
echo ""

kubectl delete deployment -n rook-ceph --all --ignore-not-found=true
kubectl delete daemonset -n rook-ceph --all --ignore-not-found=true
kubectl delete statefulset -n rook-ceph --all --ignore-not-found=true
kubectl delete job -n rook-ceph --all --ignore-not-found=true --force --grace-period=0
kubectl delete service -n rook-ceph --all --ignore-not-found=true
kubectl delete configmap -n rook-ceph --all --ignore-not-found=true
kubectl delete secret -n rook-ceph --all --ignore-not-found=true
kubectl delete pvc -n rook-ceph --all --ignore-not-found=true

# 5. 删除 StorageClass
echo ""
echo_info "5. 删除 StorageClass"
echo ""

kubectl delete storageclass rook-ceph-block rook-cephfs --ignore-not-found=true

# 6. 等待清理
echo ""
echo_info "6. 等待资源清理"
echo ""

sleep 10

# 7. 删除命名空间（可选）
echo ""
read -p "是否删除 rook-ceph 命名空间？(y/n) " DELETE_NS
if [[ $DELETE_NS =~ ^[Yy]$ ]]; then
    echo_info "  删除命名空间..."
    kubectl delete namespace rook-ceph --ignore-not-found=true --wait=true --timeout=2m 2>/dev/null || {
        echo_warn "  命名空间删除可能需要更多时间，强制删除..."
        kubectl delete namespace rook-ceph --ignore-not-found=true --grace-period=0 --force
    }
    echo_info "  ✓ 命名空间已删除"
else
    echo_info "  保留命名空间"
fi

# 8. 清理 CRDs（可选）
echo ""
read -p "是否删除 Rook CRDs？(y/n) " DELETE_CRDS
if [[ $DELETE_CRDS =~ ^[Yy]$ ]]; then
    echo_info "  删除 Rook CRDs..."
    kubectl get crd | grep rook | awk '{print $1}' | xargs kubectl delete crd --ignore-not-found=true
    echo_info "  ✓ CRDs 已删除"
else
    echo_info "  保留 CRDs（建议保留以便重新安装）"
fi

# 9. 清理节点数据（可选）
echo ""
echo_warn "如果要完全清理，需要在节点上删除数据目录："
echo "  sudo rm -rf /var/lib/rook"
echo ""

echo_info "=========================================="
echo_info "清理完成"
echo_info "=========================================="
echo ""
echo_info "现在可以重新安装:"
echo "  ./scripts/install-ceph-rook.sh"
echo ""


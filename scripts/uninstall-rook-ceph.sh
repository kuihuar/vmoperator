#!/bin/bash

# 完整卸载和清理 Rook Ceph

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_warn "=========================================="
echo_warn "卸载和清理 Rook Ceph"
echo_warn "=========================================="
echo ""
echo_warn "此操作将删除所有 Rook Ceph 资源，包括："
echo "  - 所有 PVC/PV"
echo "  - StorageClass"
echo "  - Ceph 集群"
echo "  - Rook Operator"
echo "  - 命名空间"
echo "  - CRD（可选）"
echo ""
read -p "确认要继续吗？(yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo_info "已取消"
    exit 0
fi

echo ""

# 1. 删除所有使用 rook-ceph-block StorageClass 的 PVC
echo_info "步骤 1: 删除所有使用 rook-ceph-block 的 PVC"
echo ""

PVC_LIST=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName == "rook-ceph-block") | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$PVC_LIST" ]; then
    echo_warn "  找到以下 PVC，将被删除："
    echo "$PVC_LIST" | while read ns name; do
        if [ -n "$ns" ] && [ -n "$name" ]; then
            echo "    - $ns/$name"
        fi
    done
    echo ""
    
    echo "$PVC_LIST" | while read ns name; do
        if [ -n "$ns" ] && [ -n "$name" ]; then
            echo_info "  删除 PVC: $ns/$name"
            kubectl delete pvc "$name" -n "$ns" --ignore-not-found=true 2>/dev/null || true
        fi
    done
    
    echo_info "  等待 PVC 删除（30秒）..."
    sleep 30
else
    echo_info "  未找到使用 rook-ceph-block 的 PVC"
fi

echo ""

# 2. 删除所有 PV
echo_info "步骤 2: 删除所有 PV"
echo ""

PV_LIST=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName == "rook-ceph-block") | .metadata.name' 2>/dev/null || echo "")

if [ -n "$PV_LIST" ]; then
    echo_warn "  找到以下 PV，将被删除："
    echo "$PV_LIST" | while read pv; do
        if [ -n "$pv" ]; then
            echo "    - $pv"
        fi
    done
    echo ""
    
    echo "$PV_LIST" | while read pv; do
        if [ -n "$pv" ]; then
            echo_info "  删除 PV: $pv"
            kubectl delete pv "$pv" --ignore-not-found=true 2>/dev/null || true
        fi
    done
else
    echo_info "  未找到 rook-ceph-block 的 PV"
fi

echo ""

# 3. 删除 StorageClass
echo_info "步骤 3: 删除 StorageClass"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    echo_info "  删除 StorageClass: rook-ceph-block"
    kubectl delete storageclass rook-ceph-block --ignore-not-found=true
else
    echo_info "  StorageClass 不存在"
fi

echo ""

# 4. 删除 CephBlockPool
echo_info "步骤 4: 删除 CephBlockPool"
echo ""

CBP_LIST=$(kubectl get cephblockpool -n rook-ceph -o name 2>/dev/null || echo "")

if [ -n "$CBP_LIST" ]; then
    echo "$CBP_LIST" | while read cbp; do
        if [ -n "$cbp" ]; then
            echo_info "  删除 $cbp"
            kubectl delete "$cbp" -n rook-ceph --ignore-not-found=true 2>/dev/null || true
        fi
    done
else
    echo_info "  未找到 CephBlockPool"
fi

echo ""

# 5. 删除 CephCluster
echo_info "步骤 5: 删除 CephCluster"
echo ""

CC_LIST=$(kubectl get cephcluster -n rook-ceph -o name 2>/dev/null || echo "")

if [ -n "$CC_LIST" ]; then
    echo "$CC_LIST" | while read cc; do
        if [ -n "$cc" ]; then
            echo_info "  删除 $cc"
            kubectl delete "$cc" -n rook-ceph --ignore-not-found=true 2>/dev/null || true
        fi
    done
    
    echo_info "  等待 CephCluster 删除（60秒）..."
    sleep 60
else
    echo_info "  未找到 CephCluster"
fi

echo ""

# 6. 删除 Rook Operator
echo_info "步骤 6: 删除 Rook Operator"
echo ""

if kubectl get deployment rook-ceph-operator -n rook-ceph &>/dev/null; then
    echo_info "  删除 Rook Operator Deployment"
    kubectl delete deployment rook-ceph-operator -n rook-ceph --ignore-not-found=true
else
    echo_info "  Rook Operator Deployment 不存在"
fi

# 删除 Rook Operator ConfigMap
if kubectl get configmap rook-ceph-operator-config -n rook-ceph &>/dev/null; then
    echo_info "  删除 Rook Operator ConfigMap"
    kubectl delete configmap rook-ceph-operator-config -n rook-ceph --ignore-not-found=true
fi

echo ""

# 7. 删除 rook-ceph 命名空间中的所有资源
echo_info "步骤 7: 清理 rook-ceph 命名空间"
echo ""

if kubectl get namespace rook-ceph &>/dev/null; then
    echo_info "  删除 rook-ceph 命名空间中的所有资源..."
    
    # 删除所有 Pod
    kubectl delete pods --all -n rook-ceph --ignore-not-found=true 2>/dev/null || true
    
    # 删除所有 Service
    kubectl delete svc --all -n rook-ceph --ignore-not-found=true 2>/dev/null || true
    
    # 删除所有 Secret
    kubectl delete secret --all -n rook-ceph --ignore-not-found=true 2>/dev/null || true
    
    # 删除所有 ConfigMap
    kubectl delete configmap --all -n rook-ceph --ignore-not-found=true 2>/dev/null || true
    
    echo_info "  等待资源清理（30秒）..."
    sleep 30
else
    echo_info "  rook-ceph 命名空间不存在"
fi

echo ""

# 8. 删除命名空间
echo_info "步骤 8: 删除 rook-ceph 命名空间"
echo ""

if kubectl get namespace rook-ceph &>/dev/null; then
    echo_info "  删除命名空间: rook-ceph"
    kubectl delete namespace rook-ceph --ignore-not-found=true
    
    echo_info "  等待命名空间删除（30秒）..."
    sleep 30
else
    echo_info "  命名空间不存在"
fi

echo ""

# 9. 可选：删除 CRD
echo_warn "步骤 9: 是否删除 Rook Ceph CRD？"
echo_warn "  删除 CRD 会删除所有相关的自定义资源定义"
echo ""
read -p "删除 CRD？(yes/no，默认 no): " DELETE_CRD
DELETE_CRD=${DELETE_CRD:-no}

if [ "$DELETE_CRD" = "yes" ]; then
    echo_info "  删除 Rook Ceph CRD..."
    
    CRD_LIST=$(kubectl get crd | grep -E "rook\.io|ceph\.rook\.io" | awk '{print $1}' || echo "")
    
    if [ -n "$CRD_LIST" ]; then
        echo "$CRD_LIST" | while read crd; do
            if [ -n "$crd" ]; then
                echo_info "    删除 CRD: $crd"
                kubectl delete crd "$crd" --ignore-not-found=true 2>/dev/null || true
            fi
        done
    else
        echo_info "    未找到 Rook CRD"
    fi
else
    echo_info "  跳过 CRD 删除"
fi

echo ""

# 10. 清理主机上的数据（可选）
echo_warn "步骤 10: 清理主机数据（需要手动执行）"
echo ""
echo_warn "  以下目录可能包含 Rook Ceph 数据，需要手动清理："
echo "    - /var/lib/rook"
echo "    - /var/lib/ceph"
echo ""
echo_info "  如果需要完全清理，请手动删除这些目录："
echo "    sudo rm -rf /var/lib/rook"
echo "    sudo rm -rf /var/lib/ceph"
echo ""

# 11. 总结
echo_info "=========================================="
echo_info "清理完成"
echo_info "=========================================="
echo ""

echo_info "已删除的资源："
echo "  ✓ PVC/PV"
echo "  ✓ StorageClass"
echo "  ✓ CephCluster"
echo "  ✓ CephBlockPool"
echo "  ✓ Rook Operator"
echo "  ✓ rook-ceph 命名空间"
if [ "$DELETE_CRD" = "yes" ]; then
    echo "  ✓ CRD"
fi

echo ""
echo_warn "注意："
echo "  - 主机上的数据目录需要手动清理"
echo "  - 如果使用了特定设备（如 /dev/sdb），需要手动清理设备"
echo ""


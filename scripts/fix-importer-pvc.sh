#!/bin/bash

# 修复 importer-prime Pod 的 PVC 未绑定问题

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
echo_info "修复 importer-prime Pod PVC 问题"
echo_info "=========================================="
echo ""

# 1. 先运行诊断
echo_info "1. 运行诊断..."
echo ""

if [ -n "$1" ]; then
    ./scripts/diagnose-importer-pvc.sh "$1"
else
    ./scripts/diagnose-importer-pvc.sh
fi

echo ""

# 2. 检查并修复 CSI Secret
echo_info "2. 检查 CSI Secret 配置"
echo ""

if [ -f "./scripts/fix-ceph-csi-secret.sh" ]; then
    echo_info "  运行 CSI Secret 修复脚本..."
    ./scripts/fix-ceph-csi-secret.sh
else
    echo_warn "  ⚠️  修复脚本不存在，跳过"
fi

echo ""

# 3. 检查 Ceph Pool
echo_info "3. 检查 Ceph Pool"
echo ""

if [ -f "./scripts/create-ceph-pool.sh" ]; then
    echo_info "  检查 replicapool 是否存在..."
    
    # 检查 pool 是否存在
    if kubectl exec -n rook-ceph rook-ceph-tools -- ceph osd pool ls 2>/dev/null | grep -q "replicapool"; then
        echo_info "  ✓ replicapool 已存在"
    else
        echo_warn "  ⚠️  replicapool 不存在，创建中..."
        ./scripts/create-ceph-pool.sh
    fi
else
    echo_warn "  ⚠️  创建 pool 脚本不存在，跳过"
fi

echo ""

# 4. 检查 Ceph 集群状态
echo_info "4. 检查 Ceph 集群状态"
echo ""

CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

if [ "$CEPH_PHASE" = "Ready" ]; then
    echo_info "  ✓ Ceph 集群已就绪"
else
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
        echo_warn "  ⚠️  Ceph 集群仍未就绪，但继续..."
    fi
fi

echo ""

# 5. 检查 PVC 状态并提供建议
echo_info "5. 检查相关 PVC 状态"
echo ""

if [ -n "$1" ]; then
    POD_NAME="$1"
    
    # 获取 Pod 命名空间
    POD_NAMESPACE=$(kubectl get pod "$POD_NAME" -o jsonpath='{.metadata.namespace}' 2>/dev/null || echo "default")
    
    # 获取 PVC 名称
    PVC_NAME=$(kubectl get pod "$POD_NAME" -n "$POD_NAMESPACE" -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null | head -1)
    
    if [ -n "$PVC_NAME" ]; then
        echo_info "  找到 PVC: $PVC_NAME"
        echo ""
        
        PVC_PHASE=$(kubectl get pvc "$PVC_NAME" -n "$POD_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        echo_info "  PVC 状态: $PVC_PHASE"
        echo ""
        
        if [ "$PVC_PHASE" = "Pending" ]; then
            echo_warn "  ⚠️  PVC 仍处于 Pending 状态"
            echo ""
            echo_info "  查看 PVC 详细信息:"
            kubectl describe pvc "$PVC_NAME" -n "$POD_NAMESPACE" | grep -A 30 "Events:"
            echo ""
            
            echo_info "  如果 PVC 持续处于 Pending 状态，可能的原因："
            echo "    1. CSI Provisioner 无法连接到 Ceph 集群"
            echo "    2. StorageClass 配置错误"
            echo "    3. Ceph Pool 不存在或不可用"
            echo "    4. 存储空间不足"
            echo ""
            echo_info "  建议检查："
            echo "    - kubectl logs -n rook-ceph <csi-provisioner-pod> -c csi-rbdplugin-provisioner"
            echo "    - kubectl describe storageclass rook-ceph-block"
            echo "    - kubectl exec -n rook-ceph rook-ceph-tools -- ceph df"
        elif [ "$PVC_PHASE" = "Bound" ]; then
            echo_info "  ✓ PVC 已绑定"
        fi
    else
        echo_warn "  ⚠️  无法找到 Pod 使用的 PVC"
    fi
fi

echo ""

# 6. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "下一步："
echo "  1. 等待 PVC 绑定（通常需要几分钟）"
echo "  2. 检查 Pod 状态: kubectl get pod $POD_NAME"
echo "  3. 如果问题仍然存在，运行诊断脚本: ./scripts/diagnose-importer-pvc.sh $POD_NAME"
echo ""


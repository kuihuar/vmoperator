#!/bin/bash

# 诊断 importer-prime Pod 的 PVC 未绑定问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

POD_NAME="${1:-importer-prime-3522e238-81dd-430f-b9a0-41756b131f4f}"

echo ""
echo_info "=========================================="
echo_info "诊断 importer-prime Pod PVC 问题"
echo_info "=========================================="
echo ""

# 1. 检查 Pod 状态
echo_info "1. 检查 Pod 状态"
echo ""

POD_INFO=$(kubectl get pod "$POD_NAME" -o json 2>/dev/null || echo "")

if [ -z "$POD_INFO" ]; then
    echo_error "  ✗ Pod 不存在: $POD_NAME"
    echo ""
    echo_info "  查找所有 importer Pod:"
    kubectl get pods -A | grep importer-prime || echo "  未找到 importer Pod"
    exit 1
fi

POD_NAMESPACE=$(echo "$POD_INFO" | jq -r '.metadata.namespace' 2>/dev/null || echo "default")
echo_info "  Pod: $POD_NAME"
echo_info "  Namespace: $POD_NAMESPACE"
echo ""

kubectl get pod "$POD_NAME" -n "$POD_NAMESPACE" -o wide
echo ""

# 2. 检查 Pod 使用的 PVC
echo_info "2. 检查 Pod 使用的 PVC"
echo ""

PVC_NAME=$(echo "$POD_INFO" | jq -r '.spec.volumes[] | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName' 2>/dev/null | head -1)

if [ -z "$PVC_NAME" ]; then
    echo_warn "  ⚠️  无法从 Pod 定义中提取 PVC 名称"
    echo_info "  检查 Pod 详细信息:"
    kubectl describe pod "$POD_NAME" -n "$POD_NAMESPACE" | grep -A 10 "Volumes:"
else
    echo_info "  PVC 名称: $PVC_NAME"
    echo ""
    
    # 检查 PVC 状态
    echo_info "  3. 检查 PVC 状态"
    echo ""
    
    kubectl get pvc "$PVC_NAME" -n "$POD_NAMESPACE" -o wide
    echo ""
    
    echo_info "  PVC 详细信息:"
    kubectl describe pvc "$PVC_NAME" -n "$POD_NAMESPACE"
    echo ""
fi

# 3. 检查相关的 DataVolume（如果存在）
echo_info "4. 检查相关的 DataVolume"
echo ""

# importer Pod 名称格式通常是 importer-<dv-name>-<uuid>
DV_NAME=$(echo "$POD_NAME" | sed -E 's/^importer-prime-([^-]+)-.*/\1/' || echo "")

if [ -n "$DV_NAME" ]; then
    echo_info "  可能的 DataVolume 名称: $DV_NAME"
    echo ""
    
    if kubectl get datavolume "$DV_NAME" -n "$POD_NAMESPACE" &>/dev/null; then
        echo_info "  ✓ DataVolume 存在"
        echo ""
        kubectl get datavolume "$DV_NAME" -n "$POD_NAMESPACE" -o yaml | grep -A 20 "status:"
    else
        echo_warn "  ⚠️  DataVolume 不存在"
        echo_info "  查找所有 DataVolume:"
        kubectl get datavolume -n "$POD_NAMESPACE" || echo "  未找到 DataVolume"
    fi
else
    echo_info "  查找所有 DataVolume:"
    kubectl get datavolume -n "$POD_NAMESPACE" || echo "  未找到 DataVolume"
fi

echo ""

# 4. 检查 StorageClass
echo_info "5. 检查 StorageClass"
echo ""

if [ -n "$PVC_NAME" ]; then
    STORAGE_CLASS=$(kubectl get pvc "$PVC_NAME" -n "$POD_NAMESPACE" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    
    if [ -n "$STORAGE_CLASS" ]; then
        echo_info "  StorageClass: $STORAGE_CLASS"
        echo ""
        
        if kubectl get storageclass "$STORAGE_CLASS" &>/dev/null; then
            echo_info "  ✓ StorageClass 存在"
            echo ""
            kubectl describe storageclass "$STORAGE_CLASS" | head -30
        else
            echo_error "  ✗ StorageClass 不存在: $STORAGE_CLASS"
        fi
    else
        echo_warn "  ⚠️  PVC 未指定 StorageClass"
    fi
fi

echo ""

# 5. 检查 Ceph 集群状态
echo_info "6. 检查 Ceph 集群状态"
echo ""

if kubectl get cephcluster rook-ceph -n rook-ceph &>/dev/null; then
    CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    CEPH_HEALTH=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "")
    
    echo_info "  Ceph 集群状态: $CEPH_PHASE"
    echo_info "  Ceph 健康状态: $CEPH_HEALTH"
    
    if [ "$CEPH_PHASE" != "Ready" ]; then
        echo_warn "  ⚠️  Ceph 集群未就绪，这可能导致 PVC 无法绑定"
    fi
else
    echo_error "  ✗ Ceph 集群未找到"
fi

echo ""

# 6. 检查 CSI Provisioner
echo_info "7. 检查 CSI Provisioner"
echo ""

CSI_PROV_PODS=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner 2>/dev/null || echo "")

if [ -z "$CSI_PROV_PODS" ]; then
    echo_error "  ✗ 未找到 CSI RBD Plugin Provisioner"
else
    echo "$CSI_PROV_PODS"
    echo ""
    
    RUNNING_PROV=$(echo "$CSI_PROV_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_PROV" -gt 0 ]; then
        echo_info "  ✓ 有 $RUNNING_PROV 个 Provisioner Pod 正在运行"
        
        # 检查最新的日志
        PROV_POD=$(echo "$CSI_PROV_PODS" | grep Running | head -1 | awk '{print $1}')
        if [ -n "$PROV_POD" ]; then
            echo ""
            echo_info "  CSI Provisioner 最近日志:"
            kubectl logs "$PROV_POD" -n rook-ceph -c csi-rbdplugin-provisioner --tail=20 2>&1 | head -20 || echo "  无法获取日志"
        fi
    else
        echo_warn "  ⚠️  没有运行中的 Provisioner Pod"
    fi
fi

echo ""

# 7. 检查 PVC 事件
echo_info "8. 检查 PVC 事件"
echo ""

if [ -n "$PVC_NAME" ]; then
    echo_info "  PVC 事件:"
    kubectl describe pvc "$PVC_NAME" -n "$POD_NAMESPACE" | grep -A 20 "Events:" || echo "  无事件"
fi

echo ""

# 8. 总结
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

echo_info "常见问题和解决方案:"
echo ""
echo "1. CSI Secret 缺失或配置错误:"
echo "   运行: ./scripts/fix-ceph-csi-secret.sh"
echo ""
echo "2. StorageClass 配置错误:"
echo "   检查: kubectl describe storageclass <storageclass-name>"
echo ""
echo "3. Ceph 集群未就绪:"
echo "   检查: kubectl get cephcluster -n rook-ceph"
echo ""
echo "4. CSI Provisioner 未运行:"
echo "   检查: kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner"
echo ""
echo "5. Ceph Pool 不存在:"
echo "   运行: ./scripts/create-ceph-pool.sh"
echo ""


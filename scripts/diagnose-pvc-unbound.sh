#!/bin/bash

# 诊断 PVC 未绑定问题

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
echo_info "诊断 PVC 未绑定问题"
echo_info "=========================================="
echo ""

# 1. 检查所有 PVC 状态
echo_info "1. 检查所有 PVC 状态"
echo ""

PVC_LIST=$(kubectl get pvc --all-namespaces 2>/dev/null || echo "")

if [ -z "$PVC_LIST" ]; then
    echo_warn "  ⚠️  未找到任何 PVC"
else
    echo "$PVC_LIST"
    echo ""
    
    # 检查未绑定的 PVC
    UNBOUND_PVC=$(echo "$PVC_LIST" | grep -v "Bound" | grep -v "NAME" || echo "")
    if [ -n "$UNBOUND_PVC" ]; then
        echo_warn "  ⚠️  发现未绑定的 PVC:"
        echo "$UNBOUND_PVC"
    fi
fi

echo ""

# 2. 检查特定 PVC（如果提供了名称）
if [ -n "$1" ]; then
    PVC_NAME="$1"
    PVC_NAMESPACE="${2:-default}"
    
    echo_info "2. 检查 PVC: $PVC_NAME (namespace: $PVC_NAMESPACE)"
    echo ""
    
    kubectl get pvc "$PVC_NAME" -n "$PVC_NAMESPACE" -o wide
    echo ""
    
    echo_info "  PVC 详细信息:"
    kubectl describe pvc "$PVC_NAME" -n "$PVC_NAMESPACE" | grep -A 20 "Events:"
    echo ""
    
    # 检查 StorageClass
    STORAGE_CLASS=$(kubectl get pvc "$PVC_NAME" -n "$PVC_NAMESPACE" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    if [ -n "$STORAGE_CLASS" ]; then
        echo_info "  StorageClass: $STORAGE_CLASS"
        echo ""
        
        # 检查 StorageClass 是否存在
        if kubectl get storageclass "$STORAGE_CLASS" &>/dev/null; then
            echo_info "  ✓ StorageClass 存在"
            echo ""
            echo_info "  StorageClass 详情:"
            kubectl describe storageclass "$STORAGE_CLASS"
        else
            echo_error "  ✗ StorageClass 不存在: $STORAGE_CLASS"
        fi
    fi
fi

echo ""

# 3. 检查 Ceph 集群状态
echo_info "3. 检查 Ceph 集群状态"
echo ""

CEPH_CLUSTER=$(kubectl get cephcluster rook-ceph -n rook-ceph 2>/dev/null || echo "")

if [ -z "$CEPH_CLUSTER" ]; then
    echo_error "  ✗ Ceph 集群未找到"
else
    echo_info "  ✓ Ceph 集群存在"
    CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    CEPH_HEALTH=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "")
    
    echo "    状态: $CEPH_PHASE"
    echo "    健康: $CEPH_HEALTH"
    
    if [ "$CEPH_PHASE" != "Ready" ]; then
        echo_warn "  ⚠️  Ceph 集群未就绪，这可能导致 PVC 无法绑定"
    fi
fi

echo ""

# 4. 检查 OSD Pods
echo_info "4. 检查 OSD Pods"
echo ""

OSD_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-osd 2>/dev/null || echo "")

if [ -z "$OSD_PODS" ]; then
    echo_error "  ✗ 未找到 OSD Pods"
    echo_warn "    这会导致 PVC 无法绑定"
else
    echo "$OSD_PODS"
    echo ""
    
    # 检查是否有 Running 的 OSD
    RUNNING_OSD=$(echo "$OSD_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_OSD" -gt 0 ]; then
        echo_info "  ✓ 有 $RUNNING_OSD 个 OSD Pod 正在运行"
    else
        echo_warn "  ⚠️  没有运行中的 OSD Pod"
    fi
fi

echo ""

# 5. 检查 CSI Driver
echo_info "5. 检查 CSI Driver"
echo ""

# 检查 CSI Provisioner
CSI_PROVISIONER=$(kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner || echo "")

if [ -z "$CSI_PROVISIONER" ]; then
    echo_error "  ✗ 未找到 CSI RBD Plugin Provisioner"
    echo_warn "    这会导致 PVC 无法创建 PV"
else
    echo_info "  CSI Provisioner Pods:"
    echo "$CSI_PROVISIONER"
    echo ""
    
    # 检查是否有 Running 的
    RUNNING_PROV=$(echo "$CSI_PROVISIONER" | grep -c "Running" || echo "0")
    if [ "$RUNNING_PROV" -gt 0 ]; then
        echo_info "  ✓ 有 $RUNNING_PROV 个 Provisioner Pod 正在运行"
    else
        echo_warn "  ⚠️  没有运行中的 Provisioner Pod"
        echo ""
        echo_info "  检查 Provisioner Pod 日志:"
        PROV_POD=$(echo "$CSI_PROVISIONER" | head -2 | tail -1 | awk '{print $1}')
        if [ -n "$PROV_POD" ]; then
            kubectl logs "$PROV_POD" -n rook-ceph -c csi-rbdplugin-provisioner --tail=20 2>&1 | head -20 || echo "  无法获取日志"
        fi
    fi
fi

echo ""

# 6. 检查 StorageClass
echo_info "6. 检查 StorageClass"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    echo_info "  ✓ rook-ceph-block StorageClass 存在"
    echo ""
    echo_info "  StorageClass 配置:"
    kubectl get storageclass rook-ceph-block -o yaml | grep -A 10 "provisioner\|parameters"
else
    echo_error "  ✗ rook-ceph-block StorageClass 不存在"
    echo_warn "    需要创建 StorageClass"
fi

echo ""

# 7. 检查 PV
echo_info "7. 检查 PV"
echo ""

PV_LIST=$(kubectl get pv 2>/dev/null || echo "")

if [ -z "$PV_LIST" ]; then
    echo_warn "  ⚠️  未找到任何 PV"
else
    echo "$PV_LIST" | head -10
fi

echo ""

# 8. 总结和建议
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

echo_info "常见原因和解决方案:"
echo ""
echo "1. Ceph 集群未就绪:"
echo "   解决: 等待 Ceph 集群变为 Ready 状态"
echo "   检查: kubectl get cephcluster -n rook-ceph"
echo ""
echo "2. OSD Pod 未运行:"
echo "   解决: 检查 OSD Pod 状态和日志"
echo "   检查: kubectl get pods -n rook-ceph -l app=rook-ceph-osd"
echo ""
echo "3. CSI Driver 未运行:"
echo "   解决: 检查 CSI Provisioner Pod 状态"
echo "   检查: kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner"
echo ""
echo "4. StorageClass 配置错误:"
echo "   解决: 检查 StorageClass 的 provisioner 和 parameters"
echo "   检查: kubectl describe storageclass rook-ceph-block"
echo ""
echo "5. 存储空间不足:"
echo "   解决: 检查 Ceph 集群可用空间"
echo "   检查: kubectl exec -n rook-ceph rook-ceph-tools -- ceph df"
echo ""


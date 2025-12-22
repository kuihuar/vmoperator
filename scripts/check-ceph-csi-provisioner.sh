#!/bin/bash

# 检查 Ceph CSI Provisioner 状态

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
echo_info "检查 Ceph CSI Provisioner 状态"
echo_info "=========================================="
echo ""

# 1. 检查 CSI Provisioner Pods
echo_info "1. 检查 CSI RBD Plugin Provisioner Pods"
echo ""

PROV_PODS=$(kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner || echo "")

if [ -z "$PROV_PODS" ]; then
    echo_error "  ✗ 未找到 CSI Provisioner Pods"
    echo_warn "    这会导致 PVC 无法创建 PV"
else
    echo "$PROV_PODS"
    echo ""
    
    # 检查每个 Pod 的状态
    echo "$PROV_PODS" | grep -v "NAME" | while read line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        
        if [ "$STATUS" = "Running" ]; then
            echo_info "  ✓ $POD_NAME: Running"
        else
            echo_warn "  ⚠️  $POD_NAME: $STATUS"
            
            # 查看 Pod 事件
            echo "    事件:"
            kubectl describe pod "$POD_NAME" -n rook-ceph | grep -A 5 "Events:" | head -10 || echo "    无事件"
            
            # 查看日志（如果是 CrashLoopBackOff）
            if echo "$STATUS" | grep -q "CrashLoopBackOff\|Error"; then
                echo "    日志（最后 20 行）:"
                kubectl logs "$POD_NAME" -n rook-ceph -c csi-rbdplugin-provisioner --tail=20 2>&1 | head -20 || echo "    无法获取日志"
            fi
            echo ""
        fi
    done
fi

echo ""

# 2. 检查 CSI Driver
echo_info "2. 检查 CSI Driver"
echo ""

if kubectl get csidriver rook-ceph.rbd.csi.ceph.com &>/dev/null; then
    echo_info "  ✓ CSI Driver 存在"
    kubectl get csidriver rook-ceph.rbd.csi.ceph.com
else
    echo_error "  ✗ CSI Driver 不存在"
    echo_warn "    这会导致 PVC 无法创建 PV"
fi

echo ""

# 3. 检查 Ceph 集群状态
echo_info "3. 检查 Ceph 集群状态"
echo ""

CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
CEPH_HEALTH=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "")

if [ -z "$CEPH_PHASE" ]; then
    echo_error "  ✗ Ceph 集群未找到"
else
    echo "  状态: $CEPH_PHASE"
    echo "  健康: $CEPH_HEALTH"
    
    if [ "$CEPH_PHASE" != "Ready" ]; then
        echo_warn "  ⚠️  Ceph 集群未就绪，这会导致 PVC 无法绑定"
    fi
fi

echo ""

# 4. 检查 OSD Pods
echo_info "4. 检查 OSD Pods"
echo ""

OSD_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-osd 2>/dev/null || echo "")

if [ -z "$OSD_PODS" ]; then
    echo_error "  ✗ 未找到 OSD Pods"
    echo_warn "    没有 OSD，PVC 无法创建存储"
else
    echo "$OSD_PODS"
    echo ""
    
    RUNNING_OSD=$(echo "$OSD_PODS" | grep -c "Running" || echo "0")
    if [ "$RUNNING_OSD" -gt 0 ]; then
        echo_info "  ✓ 有 $RUNNING_OSD 个 OSD Pod 正在运行"
    else
        echo_warn "  ⚠️  没有运行中的 OSD Pod"
    fi
fi

echo ""

# 5. 检查 PVC 事件
echo_info "5. 检查 PVC 事件"
echo ""

PVC_LIST=$(kubectl get pvc | grep -v "NAME" | awk '{print $1}' || echo "")

if [ -n "$PVC_LIST" ]; then
    echo "$PVC_LIST" | while read pvc; do
        if [ -n "$pvc" ]; then
            echo_info "  PVC: $pvc"
            echo "    事件:"
            kubectl describe pvc "$pvc" | grep -A 10 "Events:" | head -15 || echo "    无事件"
            echo ""
        fi
    done
fi

echo ""

# 6. 检查 StorageClass
echo_info "6. 检查 StorageClass 配置"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    echo_info "  ✓ StorageClass 存在"
    echo ""
    echo_info "  StorageClass 配置:"
    kubectl get storageclass rook-ceph-block -o yaml | grep -A 15 "provisioner\|parameters"
else
    echo_error "  ✗ StorageClass 不存在"
fi

echo ""

# 7. 总结
echo_info "=========================================="
echo_info "总结"
echo_info "=========================================="
echo ""

echo_info "如果 PVC 未绑定，通常是因为："
echo "  1. Ceph 集群未就绪（状态不是 Ready）"
echo "  2. OSD Pods 未运行"
echo "  3. CSI Provisioner Pods 未运行"
echo "  4. CSI Driver 未注册"
echo ""
echo_info "检查顺序："
echo "  1. 先确保 Ceph 集群 Ready"
echo "  2. 确保 OSD Pods Running"
echo "  3. 确保 CSI Provisioner Running"
echo "  4. 检查 PVC 事件查看具体错误"


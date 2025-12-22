#!/bin/bash

# 诊断 Ceph CSI 驱动问题

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
echo_info "诊断 Ceph CSI 驱动问题"
echo_info "=========================================="
echo ""

# 1. 检查 CSI Pods 状态
echo_info "1. 检查 CSI Pods 状态"
echo ""

CSI_PODS=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin 2>/dev/null | grep -v NAME || true)

if [ -z "$CSI_PODS" ]; then
    echo_error "  ✗ 未找到 CSI RBD Plugin Pods"
else
    echo "$CSI_PODS"
    echo ""
    
    # 获取第一个 Pod 名称
    POD_NAME=$(echo "$CSI_PODS" | head -2 | tail -1 | awk '{print $1}')
    
    if [ -n "$POD_NAME" ]; then
        echo_info "  检查 Pod: $POD_NAME"
        echo ""
        
        # 检查 Pod 详细状态
        echo_info "  Pod 状态详情:"
        kubectl get pod "$POD_NAME" -n rook-ceph -o wide
        echo ""
        
        # 检查 csi-rbdplugin 容器日志
        echo_info "  csi-rbdplugin 容器日志（最后 50 行）:"
        if kubectl logs "$POD_NAME" -n rook-ceph -c csi-rbdplugin --tail=50 2>&1 | head -20; then
            echo ""
        else
            echo_warn "  ⚠️  无法获取 csi-rbdplugin 容器日志"
            echo ""
        fi
        
        # 检查 driver-registrar 容器日志
        echo_info "  driver-registrar 容器日志（最后 20 行）:"
        kubectl logs "$POD_NAME" -n rook-ceph -c driver-registrar --tail=20 2>&1 | head -20
        echo ""
        
        # 检查 Pod 事件
        echo_info "  Pod 事件:"
        kubectl describe pod "$POD_NAME" -n rook-ceph | grep -A 20 "Events:" || echo "  无事件"
        echo ""
    fi
fi

# 2. 检查 Ceph 集群状态
echo_info "2. 检查 Ceph 集群状态"
echo ""

CEPH_CLUSTER=$(kubectl get cephcluster -n rook-ceph 2>/dev/null | grep -v NAME || true)

if [ -z "$CEPH_CLUSTER" ]; then
    echo_error "  ✗ 未找到 CephCluster"
else
    echo "$CEPH_CLUSTER"
    echo ""
    
    # 检查 CephCluster 状态
    echo_info "  CephCluster 详细状态:"
    kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status}' 2>/dev/null | jq '.' 2>/dev/null || kubectl get cephcluster rook-ceph -n rook-ceph -o yaml | grep -A 30 "status:" || echo "  无法获取状态"
    echo ""
fi

# 3. 检查 Ceph OSD 状态
echo_info "3. 检查 Ceph OSD Pods"
echo ""

OSD_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-osd 2>/dev/null | grep -v NAME || true)

if [ -z "$OSD_PODS" ]; then
    echo_warn "  ⚠️  未找到 OSD Pods（可能还在创建中）"
else
    echo "$OSD_PODS"
    echo ""
    
    # 检查第一个 OSD Pod 的状态
    OSD_POD=$(echo "$OSD_PODS" | head -2 | tail -1 | awk '{print $1}')
    if [ -n "$OSD_POD" ]; then
        echo_info "  检查 OSD Pod: $OSD_POD"
        kubectl get pod "$OSD_POD" -n rook-ceph -o wide
        echo ""
        
        # 检查 OSD Pod 日志（如果有错误）
        if kubectl get pod "$OSD_POD" -n rook-ceph | grep -q "Error\|CrashLoopBackOff"; then
            echo_warn "  ⚠️  OSD Pod 有错误，查看日志:"
            kubectl logs "$OSD_POD" -n rook-ceph --tail=30 2>&1 | head -30
            echo ""
        fi
    fi
fi

# 4. 检查 CSI 配置
echo_info "4. 检查 CSI 配置"
echo ""

# 检查 StorageClass
echo_info "  StorageClass:"
kubectl get storageclass | grep rook || echo_warn "  ⚠️  未找到 rook StorageClass"
echo ""

# 检查 CSI Driver
echo_info "  CSI Driver:"
kubectl get csidriver 2>/dev/null | grep rook || echo_warn "  ⚠️  未找到 rook CSI Driver"
echo ""

# 5. 检查 Ceph 集群健康状态（如果可用）
echo_info "5. 检查 Ceph 集群健康状态"
echo ""

# 尝试通过 rook-ceph-tools Pod 检查
TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools 2>/dev/null | grep -v NAME | head -1 | awk '{print $1}')

if [ -n "$TOOLS_POD" ]; then
    echo_info "  使用 rook-ceph-tools Pod 检查集群状态:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph status 2>/dev/null || echo_warn "  ⚠️  无法执行 ceph status"
    echo ""
else
    echo_warn "  ⚠️  未找到 rook-ceph-tools Pod，无法检查集群健康状态"
    echo_info "    可以创建 tools Pod: kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/toolbox.yaml"
    echo ""
fi

# 6. 总结和建议
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

echo_info "常见问题和解决方案:"
echo ""
echo "1. CSI Plugin 无法启动:"
echo "   - 检查 Ceph 集群是否就绪: kubectl get cephcluster -n rook-ceph"
echo "   - 检查 OSD Pods 是否运行: kubectl get pods -n rook-ceph -l app=rook-ceph-osd"
echo "   - 检查 CSI 配置 Secret: kubectl get secret -n rook-ceph | grep csi"
echo ""
echo "2. driver-registrar 无法连接:"
echo "   - 通常是 csi-rbdplugin 容器未启动"
echo "   - 检查 csi-rbdplugin 容器日志: kubectl logs <pod> -n rook-ceph -c csi-rbdplugin"
echo "   - 检查 Ceph 集群是否健康"
echo ""
echo "3. Ceph 集群未就绪:"
echo "   - 等待 OSD Pods 启动（可能需要几分钟）"
echo "   - 检查设备/目录是否正确配置"
echo "   - 查看 Rook Operator 日志: kubectl logs -n rook-ceph -l app=rook-ceph-operator"
echo ""


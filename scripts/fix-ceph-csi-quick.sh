#!/bin/bash

# 快速修复 Ceph CSI RBD 模块问题

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
echo_info "快速修复 Ceph CSI RBD 模块问题"
echo_info "=========================================="
echo ""

# 1. 检查主机 rbd 模块
echo_info "1. 检查主机 rbd 内核模块"
echo ""

KERNEL_VERSION=$(uname -r)
echo_info "  内核版本: $KERNEL_VERSION"

# 检查模块文件是否存在
if [ -f "/lib/modules/$KERNEL_VERSION/kernel/drivers/block/rbd.ko" ] || \
   [ -f "/lib/modules/$KERNEL_VERSION/kernel/drivers/block/rbd.ko.xz" ] || \
   [ -f "/lib/modules/$KERNEL_VERSION/kernel/drivers/block/rbd.ko.gz" ]; then
    echo_info "  ✓ rbd 模块文件存在"
    
    # 尝试加载
    if sudo modprobe rbd 2>/dev/null; then
        echo_info "  ✓ rbd 模块可以加载"
        lsmod | grep "^rbd " || true
    else
        echo_warn "  ⚠️  rbd 模块无法加载（可能是架构不匹配）"
    fi
else
    echo_warn "  ⚠️  rbd 模块文件不存在"
    echo_warn "     路径: /lib/modules/$KERNEL_VERSION/kernel/drivers/block/"
fi

echo ""

# 2. 检查架构
echo_info "2. 检查系统架构"
echo ""

ARCH=$(uname -m)
echo_info "  主机架构: $ARCH"

# 检查容器架构
CSI_POD=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CSI_POD" ]; then
    CONTAINER_ARCH=$(kubectl get pod "$CSI_POD" -n rook-ceph -o jsonpath='{.spec.containers[?(@.name=="csi-rbdplugin")].image}' 2>/dev/null | grep -oE '(amd64|arm64|arm)' || echo "未知")
    echo_info "  容器架构: $CONTAINER_ARCH"
    
    if [ "$ARCH" != "x86_64" ] && [ "$CONTAINER_ARCH" = "amd64" ]; then
        echo_warn "  ⚠️  架构可能不匹配（主机: $ARCH, 容器: $CONTAINER_ARCH）"
    fi
fi

echo ""

# 3. 解决方案：删除并重新创建 CSI DaemonSet
echo_info "3. 尝试修复：删除 CSI DaemonSet 让 Rook 重新创建"
echo ""

CSI_DS=$(kubectl get daemonset -n rook-ceph -l app=csi-rbdplugin -o name 2>/dev/null | head -1)

if [ -z "$CSI_DS" ]; then
    echo_error "  ✗ 未找到 CSI DaemonSet"
    exit 1
fi

echo_info "  找到 DaemonSet: $CSI_DS"
echo ""

read -p "是否删除 CSI DaemonSet 让 Rook 重新创建? (y/n，默认y): " DELETE_DS
DELETE_DS=${DELETE_DS:-y}

if [ "$DELETE_DS" != "y" ]; then
    echo_info "  已取消"
    exit 0
fi

echo_info "  删除 CSI DaemonSet..."
kubectl delete "$CSI_DS" -n rook-ceph

echo_info "  等待 Rook Operator 重新创建（30秒）..."
sleep 30

# 检查是否重新创建
NEW_DS=$(kubectl get daemonset -n rook-ceph -l app=csi-rbdplugin -o name 2>/dev/null | head -1)

if [ -n "$NEW_DS" ]; then
    echo_info "  ✓ DaemonSet 已重新创建: $NEW_DS"
    echo ""
    echo_info "  等待 Pod 启动（60秒）..."
    sleep 60
    
    # 检查 Pod 状态
    echo_info "  检查 Pod 状态:"
    kubectl get pods -n rook-ceph -l app=csi-rbdplugin
    echo ""
    
    # 检查日志
    NEW_POD=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$NEW_POD" ]; then
        echo_info "  检查新 Pod 日志:"
        kubectl logs "$NEW_POD" -n rook-ceph -c csi-rbdplugin --tail=20 2>&1 | head -20 || echo_warn "  无法获取日志（Pod 可能还在启动）"
    fi
else
    echo_warn "  ⚠️  DaemonSet 未重新创建，请检查 Rook Operator 日志"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "如果问题仍然存在，可能的原因："
echo "  1. 内核模块架构不匹配（容器是 amd64，主机是其他架构）"
echo "  2. 内核版本太新或太旧，模块不兼容"
echo "  3. 需要配置 CSI 使用用户空间 RBD（不需要内核模块）"
echo ""
echo_info "下一步："
echo "  1. 等待几分钟，观察 Pod 是否恢复正常"
echo "  2. 如果仍然失败，检查 Rook Operator 日志:"
echo "     kubectl logs -n rook-ceph -l app=rook-ceph-operator --tail=50"
echo "  3. 考虑使用 CephFS 而不是 RBD（如果不需要块存储）"


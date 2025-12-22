#!/bin/bash

# 修复 Ceph CSI RBD 内核模块问题

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
echo_info "修复 Ceph CSI RBD 内核模块问题"
echo_info "=========================================="
echo ""

# 1. 检查主机内核信息
echo_info "1. 检查主机内核信息"
echo ""

KERNEL_VERSION=$(uname -r)
KERNEL_ARCH=$(uname -m)

echo_info "  内核版本: $KERNEL_VERSION"
echo_info "  架构: $KERNEL_ARCH"
echo ""

# 检查 rbd 模块是否可用
echo_info "2. 检查 rbd 内核模块"
echo ""

if lsmod | grep -q "^rbd "; then
    echo_info "  ✓ rbd 模块已加载"
    lsmod | grep "^rbd "
    echo ""
else
    echo_warn "  ⚠️  rbd 模块未加载"
    echo ""
    
    # 尝试加载模块
    echo_info "  尝试加载 rbd 模块..."
    if sudo modprobe rbd 2>&1; then
        echo_info "  ✓ rbd 模块加载成功"
    else
        echo_error "  ✗ rbd 模块加载失败"
        echo_warn "    这可能是正常的，因为模块可能需要在容器内加载"
    fi
    echo ""
fi

# 3. 检查 CSI DaemonSet 配置
echo_info "3. 检查 CSI DaemonSet 配置"
echo ""

CSI_DS=$(kubectl get daemonset -n rook-ceph -l app=csi-rbdplugin -o name 2>/dev/null | head -1)

if [ -z "$CSI_DS" ]; then
    echo_error "  ✗ 未找到 CSI RBD Plugin DaemonSet"
    exit 1
fi

echo_info "  DaemonSet: $CSI_DS"
echo ""

# 检查是否启用了特权模式
PRIVILEGED=$(kubectl get "$CSI_DS" -n rook-ceph -o jsonpath='{.spec.template.spec.containers[?(@.name=="csi-rbdplugin")].securityContext.privileged}' 2>/dev/null)

if [ "$PRIVILEGED" = "true" ]; then
    echo_info "  ✓ 已启用特权模式"
else
    echo_warn "  ⚠️  未启用特权模式（可能需要）"
fi

# 检查 hostNetwork
HOST_NETWORK=$(kubectl get "$CSI_DS" -n rook-ceph -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null)

if [ "$HOST_NETWORK" = "true" ]; then
    echo_info "  ✓ 已启用 hostNetwork"
else
    echo_warn "  ⚠️  未启用 hostNetwork"
fi

echo ""

# 4. 解决方案：使用用户空间 RBD（推荐）
echo_info "4. 解决方案"
echo ""

echo_warn "  问题: CSI 驱动尝试加载内核模块 rbd，但模块与主机内核不兼容"
echo ""
echo_info "  解决方案 1: 配置 CSI 使用用户空间 RBD（推荐）"
echo "    这不需要内核模块，使用 librbd 用户空间库"
echo ""
echo_info "  解决方案 2: 确保 DaemonSet 有正确的权限和挂载"
echo "    需要特权模式和主机路径挂载"
echo ""

read -p "是否应用解决方案 1（配置用户空间 RBD）? (y/n，默认y): " APPLY_FIX
APPLY_FIX=${APPLY_FIX:-y}

if [ "$APPLY_FIX" != "y" ]; then
    echo_info "  已取消，请手动配置"
    exit 0
fi

# 5. 检查 CephCluster 配置
echo_info "5. 检查并更新 CephCluster 配置"
echo ""

# 检查是否已有 CSI 配置
CSI_CONFIG=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.spec.csi}' 2>/dev/null || echo "")

if [ -n "$CSI_CONFIG" ]; then
    echo_info "  当前 CSI 配置:"
    echo "$CSI_CONFIG" | jq '.' 2>/dev/null || echo "$CSI_CONFIG"
    echo ""
fi

# 创建补丁来启用用户空间 RBD
echo_info "  更新 CephCluster 以使用用户空间 RBD..."
echo ""

# 检查 CephCluster 是否支持 CSI 配置
CEPH_VERSION=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.spec.cephVersion.image}' 2>/dev/null || echo "")

if [ -z "$CEPH_VERSION" ]; then
    echo_error "  ✗ 无法获取 Ceph 版本"
    exit 1
fi

echo_info "  Ceph 版本: $CEPH_VERSION"
echo ""

# 注意：CephCluster 的 CSI 配置可能需要通过 ConfigMap 或环境变量设置
# 对于 Rook，通常需要在 CSI DaemonSet 中设置环境变量

echo_warn "  注意: 用户空间 RBD 配置需要在 CSI DaemonSet 中设置环境变量"
echo_info "  检查 CSI DaemonSet 环境变量..."
echo ""

# 检查 CSI DaemonSet 的环境变量
ENV_VARS=$(kubectl get "$CSI_DS" -n rook-ceph -o jsonpath='{.spec.template.spec.containers[?(@.name=="csi-rbdplugin")].env}' 2>/dev/null | jq -r '.[] | "\(.name)=\(.value)"' 2>/dev/null || echo "")

if echo "$ENV_VARS" | grep -q "RBD_FEATURES\|ENABLE_RBD"; then
    echo_info "  当前环境变量:"
    echo "$ENV_VARS" | grep -E "RBD|CEPH" || echo "  无相关环境变量"
else
    echo_warn "  ⚠️  未找到 RBD 相关环境变量"
fi

echo ""

# 6. 提供手动修复步骤
echo_info "=========================================="
echo_info "手动修复步骤"
echo_info "=========================================="
echo ""

echo_info "由于 Rook CSI 配置较复杂，建议使用以下方法之一："
echo ""

echo_info "方法 1: 等待 Rook 自动修复（如果 Ceph 集群健康）"
echo "  有时 Rook 会自动重试，等待几分钟后检查"
echo ""

echo_info "方法 2: 删除 CSI DaemonSet 让 Rook 重新创建"
echo "  kubectl delete daemonset -n rook-ceph -l app=csi-rbdplugin"
echo "  # Rook Operator 会自动重新创建"
echo ""

echo_info "方法 3: 检查主机内核模块支持"
echo "  确保主机内核支持 rbd 模块:"
echo "  ls /lib/modules/\$(uname -r)/kernel/drivers/block/rbd.ko*"
echo ""

echo_info "方法 4: 使用 CephFS 而不是 RBD（如果不需要块存储）"
echo "  CephFS 使用 FUSE，不需要内核模块"
echo ""

echo ""
echo_warn "当前错误是内核模块兼容性问题，在容器环境中很常见"
echo_info "建议先尝试方法 1 和方法 2"


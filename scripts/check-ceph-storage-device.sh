#!/bin/bash

# 检查 Ceph 数据存储设备

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
echo_info "检查 Ceph 数据存储设备"
echo_info "=========================================="
echo ""

# 1. 检查 CephCluster 配置
echo_info "1. 检查 CephCluster 存储配置"
echo ""

CEPH_CLUSTER=$(kubectl get cephcluster rook-ceph -n rook-ceph -o yaml 2>/dev/null)

if [ -z "$CEPH_CLUSTER" ]; then
    echo_error "  ✗ 未找到 CephCluster"
    exit 1
fi

echo_info "  存储配置:"
echo "$CEPH_CLUSTER" | grep -A 20 "storage:" | head -20
echo ""

# 检查是否配置了设备
HAS_DEVICES=$(echo "$CEPH_CLUSTER" | grep -q "devices:" && echo "yes" || echo "no")
HAS_DIRECTORIES=$(echo "$CEPH_CLUSTER" | grep -q "directories:" && echo "yes" || echo "no")
USE_ALL_DEVICES=$(echo "$CEPH_CLUSTER" | grep -A 5 "storage:" | grep -q "useAllDevices: true" && echo "yes" || echo "no")

if [ "$HAS_DEVICES" = "yes" ]; then
    echo_info "  ✓ 配置了指定设备"
    echo "$CEPH_CLUSTER" | grep -A 10 "devices:" | head -10
elif [ "$USE_ALL_DEVICES" = "yes" ]; then
    echo_warn "  ⚠️  配置为使用所有设备（useAllDevices: true）"
elif [ "$HAS_DIRECTORIES" = "yes" ]; then
    echo_warn "  ⚠️  配置为使用目录存储（不是块设备）"
    echo "$CEPH_CLUSTER" | grep -A 10 "directories:" | head -10
else
    echo_warn "  ⚠️  未找到明确的存储配置"
fi

echo ""

# 2. 检查 OSD Pods 使用的设备
echo_info "2. 检查 OSD Pods 使用的设备"
echo ""

OSD_PODS=$(kubectl get pods -n rook-ceph -l app=rook-ceph-osd -o name 2>/dev/null)

if [ -z "$OSD_PODS" ]; then
    echo_warn "  ⚠️  未找到 OSD Pods"
else
    echo "$OSD_PODS" | while read pod; do
        POD_NAME=$(echo "$pod" | cut -d'/' -f2)
        echo_info "  Pod: $POD_NAME"
        
        # 检查 Pod 的 volumeMounts
        echo "    挂载的设备:"
        kubectl get "$pod" -n rook-ceph -o jsonpath='{.spec.containers[*].volumeMounts[*].mountPath}' 2>/dev/null | tr ' ' '\n' | grep -E "dev|block" || echo "    无设备挂载"
        
        # 检查 Pod 的 volumes
        echo "    使用的设备路径:"
        kubectl get "$pod" -n rook-ceph -o jsonpath='{.spec.volumes[*].hostPath.path}' 2>/dev/null | tr ' ' '\n' | grep -E "/dev|/block" || echo "    无设备路径"
        
        echo ""
    done
fi

# 3. 检查主机上的设备使用情况
echo_info "3. 检查主机设备使用情况"
echo ""

# 检查 /dev/sdb 是否存在
if [ -b "/dev/sdb" ]; then
    echo_info "  ✓ /dev/sdb 存在"
    
    # 检查设备信息
    echo "    设备信息:"
    sudo fdisk -l /dev/sdb 2>/dev/null | head -10 || echo "    无法读取设备信息"
    echo ""
    
    # 检查设备是否被挂载
    MOUNTED=$(mount | grep sdb || echo "")
    if [ -n "$MOUNTED" ]; then
        echo_warn "  ⚠️  /dev/sdb 已被挂载:"
        echo "$MOUNTED"
    else
        echo_info "  ✓ /dev/sdb 未被挂载（可以被 Ceph 使用）"
    fi
    echo ""
    
    # 检查设备是否被使用
    IN_USE=$(sudo lsof /dev/sdb 2>/dev/null || echo "")
    if [ -n "$IN_USE" ]; then
        echo_warn "  ⚠️  /dev/sdb 正在被使用:"
        echo "$IN_USE" | head -5
    else
        echo_info "  ✓ /dev/sdb 未被其他进程使用"
    fi
    echo ""
    
    # 检查设备是否有文件系统
    HAS_FS=$(sudo blkid /dev/sdb 2>/dev/null || echo "")
    if [ -n "$HAS_FS" ]; then
        echo_warn "  ⚠️  /dev/sdb 已有文件系统:"
        echo "$HAS_FS"
        echo_warn "    注意: Ceph 需要使用未格式化的裸设备"
    else
        echo_info "  ✓ /dev/sdb 是裸设备（无文件系统，适合 Ceph）"
    fi
    echo ""
else
    echo_warn "  ⚠️  /dev/sdb 不存在"
    echo ""
fi

# 4. 检查 OSD 实际使用的设备（通过 Pod 内部）
echo_info "4. 检查 OSD 实际使用的设备（通过 Pod）"
echo ""

if [ -n "$OSD_PODS" ]; then
    FIRST_POD=$(echo "$OSD_PODS" | head -1 | cut -d'/' -f2)
    
    if [ -n "$FIRST_POD" ]; then
        echo_info "  检查 Pod: $FIRST_POD"
        
        # 尝试在 Pod 内检查设备
        echo "    尝试在 Pod 内列出设备:"
        kubectl exec "$FIRST_POD" -n rook-ceph -- lsblk 2>/dev/null | head -20 || echo_warn "    无法在 Pod 内检查设备"
        echo ""
        
        # 检查 OSD 数据目录
        echo "    检查 OSD 数据目录:"
        kubectl exec "$FIRST_POD" -n rook-ceph -- df -h /var/lib/ceph 2>/dev/null | head -5 || echo_warn "    无法检查数据目录"
        echo ""
    fi
fi

# 5. 检查 Ceph OSD 状态（如果可用）
echo_info "5. 检查 Ceph OSD 状态"
echo ""

TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1)

if [ -n "$TOOLS_POD" ]; then
    echo_info "  使用 rook-ceph-tools 检查 OSD:"
    kubectl exec "$TOOLS_POD" -n rook-ceph -- ceph osd tree 2>/dev/null || echo_warn "  无法执行 ceph osd tree"
    echo ""
    
    echo_info "  检查 OSD 详细信息:"
    kubectl exec "$TOOLS_POD" -n rook-ceph -- ceph osd df tree 2>/dev/null || echo_warn "  无法执行 ceph osd df tree"
    echo ""
else
    echo_warn "  ⚠️  未找到 rook-ceph-tools Pod"
    echo_info "    可以创建 tools Pod 来检查:"
    echo "    kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/toolbox.yaml"
    echo ""
fi

# 6. 检查数据目录（如果使用目录存储）
echo_info "6. 检查数据目录（如果使用目录存储）"
echo ""

DATA_DIR="/var/lib/rook"
if [ -d "$DATA_DIR" ]; then
    echo_info "  数据目录: $DATA_DIR"
    echo "    大小:"
    sudo du -sh "$DATA_DIR" 2>/dev/null || echo "    无法检查大小"
    echo "    使用情况:"
    df -h "$DATA_DIR" 2>/dev/null | tail -1 || echo "    无法检查使用情况"
    echo ""
    
    # 检查是否在数据盘上
    MOUNT_POINT=$(df "$DATA_DIR" 2>/dev/null | tail -1 | awk '{print $1}')
    if echo "$MOUNT_POINT" | grep -q "sdb"; then
        echo_info "  ✓ 数据目录在 /dev/sdb 上"
    else
        echo_warn "  ⚠️  数据目录不在 /dev/sdb 上，挂载点: $MOUNT_POINT"
    fi
    echo ""
else
    echo_warn "  ⚠️  数据目录不存在: $DATA_DIR"
    echo ""
fi

# 7. 总结
echo_info "=========================================="
echo_info "总结"
echo_info "=========================================="
echo ""

echo_info "要确认 Ceph 是否使用 /dev/sdb:"
echo "  1. 检查 CephCluster 配置中是否指定了 /dev/sdb"
echo "  2. 检查 OSD Pods 的 volumeMounts 是否包含 /dev/sdb"
echo "  3. 检查主机上 /dev/sdb 是否被 Ceph 使用（通过 lsblk 或 lsof）"
echo "  4. 使用 rook-ceph-tools 检查 OSD 详细信息"
echo ""

echo_info "如果 Ceph 没有使用 /dev/sdb，可能需要："
echo "  1. 检查 CephCluster 配置是否正确"
echo "  2. 确保 /dev/sdb 是未格式化的裸设备"
echo "  3. 重新创建 CephCluster 或更新配置"


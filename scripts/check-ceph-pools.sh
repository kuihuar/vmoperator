#!/bin/bash

# 检查 Ceph 存储池

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
echo_info "检查 Ceph 存储池"
echo_info "=========================================="
echo ""

# 1. 检查 tools Pod
echo_info "1. 检查 rook-ceph-tools Pod"
echo ""

TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1)

if [ -z "$TOOLS_POD" ]; then
    echo_warn "  ⚠️  Tools Pod 不存在"
    echo_info "    创建 Tools Pod: kubectl apply -f <tools-pod-yaml>"
    echo_info "    或运行: ./scripts/create-ceph-pool.sh"
    exit 1
fi

echo_info "  ✓ Tools Pod 存在: $TOOLS_POD"
echo ""

# 2. 列出所有存储池
echo_info "2. 列出所有存储池"
echo ""

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null || echo "")

if [ -z "$POOLS" ]; then
    echo_error "  ✗ 无法获取存储池列表"
    echo_warn "    可能 Ceph 集群未就绪"
    exit 1
fi

echo "$POOLS"
echo ""

# 3. 检查 replicapool
echo_info "3. 检查 replicapool 存储池"
echo ""

if echo "$POOLS" | grep -q "^replicapool$"; then
    echo_info "  ✓ replicapool 存在"
    echo ""
    
    # 显示存储池详细信息
    echo_info "  存储池详细信息:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool get replicapool all 2>/dev/null | head -30 || echo_warn "  无法获取详细信息"
else
    echo_error "  ✗ replicapool 不存在"
    echo ""
    echo_warn "  这是问题的根源！需要创建 replicapool 存储池"
    echo ""
    echo_info "  解决方案:"
    echo "    运行: ./scripts/create-ceph-pool.sh replicapool"
fi

echo ""

# 4. 检查存储池的应用程序
echo_info "4. 检查存储池应用程序"
echo ""

if echo "$POOLS" | grep -q "^replicapool$"; then
    APP_INFO=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application get replicapool 2>/dev/null || echo "")
    
    if echo "$APP_INFO" | grep -q "rbd"; then
        echo_info "  ✓ replicapool 已启用 rbd 应用程序"
    else
        echo_warn "  ⚠️  replicapool 未启用 rbd 应用程序"
        echo_info "    启用: kubectl exec -n rook-ceph $TOOLS_POD -- ceph osd pool application enable replicapool rbd"
    fi
fi

echo ""

# 5. 检查 StorageClass 配置
echo_info "5. 检查 StorageClass 配置"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    STORAGE_CLASS_POOL=$(kubectl get storageclass rook-ceph-block -o jsonpath='{.parameters.pool}' 2>/dev/null || echo "")
    
    echo_info "  StorageClass 配置的存储池: $STORAGE_CLASS_POOL"
    
    if [ "$STORAGE_CLASS_POOL" = "replicapool" ]; then
        if echo "$POOLS" | grep -q "^replicapool$"; then
            echo_info "  ✓ StorageClass 配置正确，存储池存在"
        else
            echo_error "  ✗ StorageClass 配置的存储池不存在"
            echo_warn "    需要创建存储池: ./scripts/create-ceph-pool.sh replicapool"
        fi
    else
        echo_warn "  ⚠️  StorageClass 使用不同的存储池: $STORAGE_CLASS_POOL"
        if echo "$POOLS" | grep -q "^${STORAGE_CLASS_POOL}$"; then
            echo_info "  ✓ 该存储池存在"
        else
            echo_error "  ✗ 该存储池不存在"
            echo_warn "    需要创建存储池: ./scripts/create-ceph-pool.sh $STORAGE_CLASS_POOL"
        fi
    fi
else
    echo_error "  ✗ StorageClass 不存在"
fi

echo ""
echo_info "=========================================="
echo_info "检查完成"
echo_info "=========================================="


#!/bin/bash

# 完整修复 Ceph 存储池问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

POOL_NAME="${1:-replicapool}"

echo ""
echo_info "=========================================="
echo_info "完整修复 Ceph 存储池问题"
echo_info "=========================================="
echo ""

# 1. 检查 Ceph 集群状态
echo_info "1. 检查 Ceph 集群状态"
echo ""

if ! kubectl get cephcluster rook-ceph -n rook-ceph &>/dev/null; then
    echo_error "  ✗ Ceph 集群不存在"
    echo_warn "    请先安装 Ceph 集群"
    exit 1
fi

CEPH_PHASE=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
CEPH_HEALTH=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "")

echo_info "  Ceph 集群状态: $CEPH_PHASE"
echo_info "  Ceph 健康状态: $CEPH_HEALTH"
echo ""

if [ "$CEPH_PHASE" != "Ready" ]; then
    echo_warn "  ⚠️  Ceph 集群未就绪，等待中（最多 5 分钟）..."
    
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
        echo_error "  ✗ Ceph 集群仍未就绪: $CEPH_PHASE"
        echo_warn "    继续尝试修复，但可能失败"
    fi
fi

# 2. 检查并修复 Tools Pod
echo_info "2. 检查 rook-ceph-tools Pod"
echo ""

TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -z "$TOOLS_POD" ]; then
    echo_warn "  ⚠️  Tools Pod 不存在，创建中..."
    ./scripts/fix-ceph-tools-pod.sh
    TOOLS_POD="rook-ceph-tools"
else
    echo_info "  ✓ Tools Pod 存在: $TOOLS_POD"
    
    # 检查 Pod 状态
    POD_PHASE=$(kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    CONTAINER_READY=$(kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    if [ "$POD_PHASE" != "Running" ] || [ "$CONTAINER_READY" != "true" ]; then
        echo_warn "  ⚠️  Tools Pod 未就绪，修复中..."
        ./scripts/fix-ceph-tools-pod.sh
        TOOLS_POD="rook-ceph-tools"
        
        # 等待 Pod 就绪
        echo_info "  等待 Tools Pod 就绪（60秒）..."
        for i in {1..12}; do
            POD_PHASE=$(kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            CONTAINER_READY=$(kubectl get pod "$TOOLS_POD" -n rook-ceph -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
            
            if [ "$POD_PHASE" = "Running" ] && [ "$CONTAINER_READY" = "true" ]; then
                echo_info "  ✓ Tools Pod 已就绪"
                break
            fi
            echo "  等待中... ($i/12)"
            sleep 5
        done
    fi
fi

echo ""

# 3. 测试 Ceph 连接
echo_info "3. 测试 Ceph 连接"
echo ""

if ! kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph status &>/dev/null; then
    echo_error "  ✗ 无法连接到 Ceph 集群"
    echo ""
    echo_info "  尝试修复连接问题..."
    echo ""
    
    # 运行连接修复脚本
    if [ -f "./scripts/fix-ceph-tools-connection.sh" ]; then
        ./scripts/fix-ceph-tools-connection.sh
        
        # 重新检查连接
        TOOLS_POD="rook-ceph-tools"
        if ! kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph status &>/dev/null; then
            echo_error "  ✗ 修复后仍无法连接"
            echo ""
            echo_info "  请手动检查:"
            echo "    1. 运行诊断: ./scripts/diagnose-ceph-connection-issue.sh"
            echo "    2. 检查 Mon Pods: kubectl get pods -n rook-ceph -l app=rook-ceph-mon"
            echo "    3. 检查 Ceph 集群: kubectl get cephcluster -n rook-ceph"
            exit 1
        fi
    else
        echo_warn "  ⚠️  修复脚本不存在，请手动修复"
        exit 1
    fi
fi

echo_info "  ✓ Ceph 连接正常"
echo ""

# 4. 检查存储池是否存在
echo_info "4. 检查存储池 $POOL_NAME"
echo ""

POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null || echo "")

if echo "$POOLS" | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池 $POOL_NAME 已存在"
    echo ""
    
    # 检查存储池详细信息
    echo_info "  存储池详细信息:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool get "$POOL_NAME" all 2>/dev/null | head -20 || echo_warn "  无法获取详细信息"
    echo ""
    
    # 检查存储池应用程序
    echo_info "  检查存储池应用程序:"
    APP_INFO=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application get "$POOL_NAME" 2>/dev/null || echo "")
    
    if echo "$APP_INFO" | grep -q "rbd"; then
        echo_info "  ✓ 存储池已启用 rbd 应用程序"
    else
        echo_warn "  ⚠️  存储池未启用 rbd 应用程序，启用中..."
        kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application enable "$POOL_NAME" rbd 2>/dev/null || {
            echo_error "  ✗ 启用 rbd 应用程序失败"
            exit 1
        }
        echo_info "  ✓ rbd 应用程序已启用"
    fi
    
    # 检查存储池是否初始化
    echo_info "  检查存储池初始化状态:"
    POOL_INFO=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool get "$POOL_NAME" application_metadata 2>/dev/null || echo "")
    
    if [ -z "$POOL_INFO" ] || ! echo "$POOL_INFO" | grep -q "rbd"; then
        echo_warn "  ⚠️  存储池可能未初始化，初始化中..."
        kubectl exec -n rook-ceph "$TOOLS_POD" -- rbd pool init "$POOL_NAME" 2>/dev/null || {
            echo_warn "  ⚠️  初始化失败，可能已经初始化"
        }
        echo_info "  ✓ 存储池已初始化"
    fi
    
else
    echo_warn "  ⚠️  存储池 $POOL_NAME 不存在，创建中..."
    echo ""
    
    # 创建存储池
    echo_info "  创建存储池: ceph osd pool create $POOL_NAME 32 32"
    POOL_CREATE_OUTPUT=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool create "$POOL_NAME" 32 32 2>&1)
    POOL_CREATE_EXIT=$?
    
    if [ $POOL_CREATE_EXIT -ne 0 ]; then
        if echo "$POOL_CREATE_OUTPUT" | grep -q "already exists\|EEXIST"; then
            echo_info "  ✓ 存储池已存在（之前创建）"
        else
            echo_error "  ✗ 存储池创建失败"
            echo ""
            echo_info "  错误输出:"
            echo "$POOL_CREATE_OUTPUT"
            exit 1
        fi
    else
        echo_info "  ✓ 存储池创建成功"
    fi
    
    echo ""
    
    # 初始化存储池
    echo_info "  初始化存储池为 RBD 存储池:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- rbd pool init "$POOL_NAME" 2>/dev/null || {
        echo_warn "  ⚠️  初始化失败，可能已经初始化"
    }
    echo_info "  ✓ 存储池已初始化"
    
    echo ""
    
    # 启用 rbd 应用程序
    echo_info "  启用 rbd 应用程序:"
    kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application enable "$POOL_NAME" rbd 2>/dev/null || {
        echo_warn "  ⚠️  启用失败，可能已经启用"
    }
    echo_info "  ✓ rbd 应用程序已启用"
fi

echo ""

# 5. 验证存储池
echo_info "5. 验证存储池配置"
echo ""

# 验证存储池存在
if kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null | grep -q "^${POOL_NAME}$"; then
    echo_info "  ✓ 存储池存在"
else
    echo_error "  ✗ 存储池不存在"
    exit 1
fi

# 验证应用程序已启用
APP_INFO=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool application get "$POOL_NAME" 2>/dev/null || echo "")
if echo "$APP_INFO" | grep -q "rbd"; then
    echo_info "  ✓ rbd 应用程序已启用"
else
    echo_error "  ✗ rbd 应用程序未启用"
    exit 1
fi

# 显示存储池统计信息
echo_info "  存储池统计信息:"
kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph df detail 2>/dev/null | grep "$POOL_NAME" || echo_warn "  无法获取统计信息"

echo ""

# 6. 检查 StorageClass 配置
echo_info "6. 检查 StorageClass 配置"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    STORAGE_CLASS_POOL=$(kubectl get storageclass rook-ceph-block -o jsonpath='{.parameters.pool}' 2>/dev/null || echo "")
    
    echo_info "  StorageClass 配置的存储池: $STORAGE_CLASS_POOL"
    
    if [ "$STORAGE_CLASS_POOL" = "$POOL_NAME" ]; then
        echo_info "  ✓ StorageClass 配置正确"
    else
        echo_warn "  ⚠️  StorageClass 使用不同的存储池: $STORAGE_CLASS_POOL"
        echo_warn "    如果 PVC 无法绑定，可能需要修改 StorageClass 或创建对应的存储池"
    fi
else
    echo_error "  ✗ StorageClass 不存在"
    echo_warn "    需要创建 StorageClass: ./scripts/fix-ceph-csi-secret.sh"
fi

echo ""

# 7. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "存储池 $POOL_NAME 已就绪"
echo ""
echo_info "下一步:"
echo "  1. 检查 PVC 状态: kubectl get pvc -A"
echo "  2. 如果 PVC 仍为 Pending，检查:"
echo "     - kubectl describe pvc <pvc-name>"
echo "     - kubectl logs -n rook-ceph <csi-provisioner-pod> -c csi-rbdplugin-provisioner"
echo "  3. 验证存储池: ./scripts/check-ceph-pools.sh"
echo ""


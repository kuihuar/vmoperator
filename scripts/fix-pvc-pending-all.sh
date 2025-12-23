#!/bin/bash

# 一键修复 PVC Pending 问题

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
echo_info "一键修复 PVC Pending 问题"
echo_info "=========================================="
echo ""

# 1. 运行完整诊断
echo_info "步骤 1: 运行完整诊断"
echo ""

if [ -f "./scripts/diagnose-pvc-pending-complete.sh" ]; then
    ./scripts/diagnose-pvc-pending-complete.sh
else
    echo_warn "  ⚠️  诊断脚本不存在，跳过"
fi

echo ""
echo "按 Enter 继续修复，或 Ctrl+C 取消..."
read

# 2. 修复 CSI Secret
echo_info "步骤 2: 修复 CSI Secret 配置"
echo ""

if [ -f "./scripts/fix-ceph-csi-secret.sh" ]; then
    ./scripts/fix-ceph-csi-secret.sh
else
    echo_error "  ✗ 修复脚本不存在: fix-ceph-csi-secret.sh"
    exit 1
fi

echo ""

# 3. 检查并创建存储池
echo_info "步骤 3: 检查 Ceph 存储池"
echo ""

# 获取 StorageClass 配置的 pool
SC_POOL=$(kubectl get storageclass rook-ceph-block -o jsonpath='{.parameters.pool}' 2>/dev/null || echo "replicapool")

if [ -z "$SC_POOL" ]; then
    SC_POOL="replicapool"
fi

echo_info "  StorageClass 配置的存储池: $SC_POOL"
echo ""

# 检查存储池是否存在
TOOLS_POD=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")

if [ -n "$TOOLS_POD" ]; then
    POOLS=$(kubectl exec -n rook-ceph "$TOOLS_POD" -- ceph osd pool ls 2>/dev/null || echo "")
    
    if echo "$POOLS" | grep -q "^${SC_POOL}$"; then
        echo_info "  ✓ 存储池 $SC_POOL 已存在"
    else
        echo_warn "  ⚠️  存储池 $SC_POOL 不存在，创建中..."
        if [ -f "./scripts/fix-ceph-pool-complete.sh" ]; then
            ./scripts/fix-ceph-pool-complete.sh "$SC_POOL"
        elif [ -f "./scripts/create-ceph-pool.sh" ]; then
            ./scripts/create-ceph-pool.sh "$SC_POOL"
        else
            echo_error "  ✗ 存储池创建脚本不存在"
        fi
    fi
else
    echo_warn "  ⚠️  Tools Pod 不存在，无法检查存储池"
    echo_info "  尝试修复 Tools Pod..."
    if [ -f "./scripts/fix-ceph-tools-connection.sh" ]; then
        ./scripts/fix-ceph-tools-connection.sh
        sleep 10
    fi
fi

echo ""

# 4. 验证 CSI Provisioner
echo_info "步骤 4: 检查 CSI Provisioner Pods"
echo ""

CSI_PROV_PODS=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner 2>/dev/null || echo "")

if [ -z "$CSI_PROV_PODS" ]; then
    echo_error "  ✗ 未找到 CSI Provisioner Pods"
    echo_warn "    这可能是 Rook Operator 的问题"
else
    RUNNING_PROV=$(echo "$CSI_PROV_PODS" | grep -c "Running" || echo "0")
    
    if [ "$RUNNING_PROV" -eq 0 ]; then
        echo_warn "  ⚠️  没有运行中的 CSI Provisioner Pod"
        echo_info "  检查失败的 Pod:"
        kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner
        echo ""
        echo_info "  建议等待 Rook Operator 重新创建 Pod，或检查 Rook Operator 状态"
    else
        echo_info "  ✓ 有 $RUNNING_PROV 个 CSI Provisioner Pod 正在运行"
    fi
fi

echo ""

# 5. 等待并检查 PVC 状态
echo_info "步骤 5: 等待 PVC 绑定（最多 2 分钟）"
echo ""

for i in {1..24}; do
    PENDING_COUNT=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -c "Pending" || echo "0")
    BOUND_COUNT=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -c "Bound" || echo "0")
    
    if [ "$PENDING_COUNT" -eq 0 ] && [ "$BOUND_COUNT" -gt 0 ]; then
        echo_info "  ✓ 所有 PVC 已绑定"
        break
    fi
    
    if [ $i -eq 1 ]; then
        echo_info "  当前状态: $PENDING_COUNT 个 Pending, $BOUND_COUNT 个 Bound"
    fi
    
    echo "  等待中... ($i/24)"
    sleep 5
done

echo ""
echo_info "  PVC 最终状态:"
kubectl get pvc --all-namespaces 2>/dev/null || echo "  无法获取 PVC 状态"

echo ""

# 6. 如果仍然有问题，显示详细错误
PENDING_COUNT=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -c "Pending" || echo "0")

if [ "$PENDING_COUNT" -gt 0 ]; then
    echo_warn "  ⚠️  仍有 $PENDING_COUNT 个 PVC 处于 Pending 状态"
    echo ""
    echo_info "  检查 PVC 事件:"
    PENDING_PVC=$(kubectl get pvc --all-namespaces 2>/dev/null | grep "Pending" | head -1)
    if [ -n "$PENDING_PVC" ]; then
        PVC_NS=$(echo "$PENDING_PVC" | awk '{print $1}')
        PVC_NAME=$(echo "$PENDING_PVC" | awk '{print $2}')
        echo_info "  检查 PVC: $PVC_NAME (namespace: $PVC_NS)"
        kubectl describe pvc "$PVC_NAME" -n "$PVC_NS" | grep -A 20 "Events:" || echo "  无事件"
    fi
    echo ""
    echo_info "  检查 CSI Provisioner 日志:"
    PROV_POD=$(kubectl get pods -n rook-ceph -l app=csi-rbdplugin-provisioner -o name 2>/dev/null | head -1 | sed 's|pod/||' || echo "")
    if [ -n "$PROV_POD" ]; then
        kubectl logs "$PROV_POD" -n rook-ceph -c csi-rbdplugin-provisioner --tail=50 2>&1 | grep -i "error\|fail" || echo "  未找到明显错误"
    fi
fi

echo ""

# 7. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "下一步:"
echo "  1. 检查 PVC 状态: kubectl get pvc --all-namespaces"
echo "  2. 如果仍有问题，运行诊断: ./scripts/diagnose-pvc-pending-complete.sh"
echo "  3. 检查 CSI Provisioner 日志: kubectl logs -n rook-ceph <provisioner-pod> -c csi-rbdplugin-provisioner"
echo ""


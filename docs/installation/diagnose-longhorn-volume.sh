#!/bin/bash

# 诊断 Longhorn 卷未就绪问题
# 用法: ./diagnose-longhorn-volume.sh [PVC_NAME]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

PVC_NAME="${1:-}"

if [ -z "${PVC_NAME}" ]; then
    echo_error "请提供 PVC 名称"
    echo "用法: $0 <PVC_NAME>"
    echo ""
    echo "示例:"
    echo "  $0 pvc-aacfb25f-8086-4b83-8696-b929e6de4b7a"
    echo "  $0 wukong"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "诊断 Longhorn 卷: ${PVC_NAME}"
echo_info "=========================================="
echo ""

# 1. 检查 PVC 状态
echo_info "1. 检查 PVC 状态..."
echo "----------------------------------------"
if kubectl get pvc "${PVC_NAME}" -A &>/dev/null; then
    kubectl get pvc "${PVC_NAME}" -A -o wide
    echo ""
    echo_info "PVC 详细信息:"
    kubectl describe pvc "${PVC_NAME}" -A | grep -A 20 "Status:\|Events:" || true
else
    echo_error "PVC ${PVC_NAME} 不存在"
    echo_info "查找所有 PVC:"
    kubectl get pvc -A
    exit 1
fi
echo ""

# 2. 获取 PV 名称
PV_NAME=$(kubectl get pvc "${PVC_NAME}" -A -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
if [ -z "${PV_NAME}" ]; then
    echo_warn "PVC 还没有绑定到 PV"
    echo_info "检查 PVC 事件:"
    kubectl get events -A --field-selector involvedObject.name="${PVC_NAME}" --sort-by='.lastTimestamp' | tail -10
    exit 1
fi

echo_info "2. 关联的 PV: ${PV_NAME}"
echo "----------------------------------------"
kubectl get pv "${PV_NAME}" -o wide
echo ""
kubectl describe pv "${PV_NAME}" | grep -A 20 "Status:\|Source:\|Events:" || true
echo ""

# 3. 获取 Longhorn Volume 名称（通常是 PV 名称）
VOLUME_NAME="${PV_NAME}"
echo_info "3. 检查 Longhorn Volume: ${VOLUME_NAME}"
echo "----------------------------------------"

# 检查 Longhorn Volume CRD
if kubectl get volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system &>/dev/null; then
    echo_info "Volume 状态:"
    kubectl get volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system -o wide
    echo ""
    echo_info "Volume 详细信息:"
    kubectl describe volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system | grep -A 30 "Status:\|State:\|Robustness:\|Conditions:" || true
    echo ""
    
    # 获取 Volume 状态
    VOLUME_STATE=$(kubectl get volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
    VOLUME_ROBUSTNESS=$(kubectl get volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system -o jsonpath='{.status.robustness}' 2>/dev/null || echo "unknown")
    
    echo_info "Volume 状态摘要:"
    echo "  State: ${VOLUME_STATE}"
    echo "  Robustness: ${VOLUME_ROBUSTNESS}"
    echo ""
    
    if [ "${VOLUME_STATE}" != "attached" ] && [ "${VOLUME_STATE}" != "attaching" ]; then
        echo_warn "⚠️  Volume 状态不是 'attached' 或 'attaching'"
        echo_info "尝试附加 Volume..."
        kubectl patch volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system --type='merge' -p '{"spec":{"nodeID":"'$(hostname)'"}}' 2>/dev/null || true
    fi
else
    echo_error "Longhorn Volume ${VOLUME_NAME} 不存在"
    echo_info "查找所有 Longhorn Volumes:"
    kubectl get volumes.longhorn.io -n longhorn-system | head -10
    exit 1
fi

# 4. 检查 Engine
echo_info "4. 检查 Engine..."
echo "----------------------------------------"
ENGINE_NAME=$(kubectl get volumes.longhorn.io "${VOLUME_NAME}" -n longhorn-system -o jsonpath='{.status.currentImage}' 2>/dev/null || echo "")
if [ -n "${ENGINE_NAME}" ]; then
    ENGINE_POD=$(kubectl get pods -n longhorn-system -l longhorn.io/engine="${VOLUME_NAME}" -o name 2>/dev/null | head -1 || echo "")
    if [ -n "${ENGINE_POD}" ]; then
        echo_info "Engine Pod: ${ENGINE_POD}"
        kubectl get "${ENGINE_POD}" -n longhorn-system -o wide
        echo ""
        echo_info "Engine Pod 状态:"
        kubectl describe "${ENGINE_POD}" -n longhorn-system | grep -A 20 "Status:\|State:\|Events:" || true
        echo ""
        echo_info "Engine Pod 日志（最后 20 行）:"
        kubectl logs "${ENGINE_POD}" -n longhorn-system --tail=20 || true
    else
        echo_warn "未找到 Engine Pod"
    fi
else
    echo_warn "未找到 Engine 信息"
fi
echo ""

# 5. 检查 Replicas
echo_info "5. 检查 Replicas..."
echo "----------------------------------------"
REPLICAS=$(kubectl get replicas.longhorn.io -n longhorn-system -l longhorn.io/volume="${VOLUME_NAME}" 2>/dev/null || echo "")
if [ -n "${REPLICAS}" ]; then
    echo_info "Replicas:"
    kubectl get replicas.longhorn.io -n longhorn-system -l longhorn.io/volume="${VOLUME_NAME}" -o wide
    echo ""
    echo_info "Replica 详细信息:"
    kubectl get replicas.longhorn.io -n longhorn-system -l longhorn.io/volume="${VOLUME_NAME}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.currentState}{"\t"}{.status.instanceStatus}{"\n"}{end}' || true
else
    echo_warn "未找到 Replicas"
fi
echo ""

# 6. 检查 Longhorn Manager
echo_info "6. 检查 Longhorn Manager..."
echo "----------------------------------------"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name 2>/dev/null | head -1 || echo "")
if [ -n "${MANAGER_POD}" ]; then
    echo_info "Manager Pod: ${MANAGER_POD}"
    kubectl get "${MANAGER_POD}" -n longhorn-system -o wide
    echo ""
    echo_info "Manager 日志中关于 ${VOLUME_NAME} 的信息（最后 30 行）:"
    kubectl logs "${MANAGER_POD}" -n longhorn-system --tail=100 | grep -i "${VOLUME_NAME}" | tail -30 || echo "  未找到相关日志"
else
    echo_error "未找到 Longhorn Manager Pod"
fi
echo ""

# 7. 检查节点状态
echo_info "7. 检查 Longhorn 节点状态..."
echo "----------------------------------------"
kubectl get nodes.longhorn.io -n longhorn-system -o wide || true
echo ""

# 8. 总结和建议
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [ "${VOLUME_STATE}" = "attached" ] && [ "${VOLUME_ROBUSTNESS}" = "healthy" ]; then
    echo_info "✓ Volume 状态正常"
    echo_info "如果 Pod 仍然无法附加，请检查："
    echo "  1. Pod 是否在正确的节点上"
    echo "  2. 节点是否有足够的资源"
    echo "  3. Longhorn CSI Driver 是否正常工作"
elif [ "${VOLUME_STATE}" = "detached" ]; then
    echo_warn "⚠️  Volume 处于 detached 状态"
    echo_info "建议操作："
    echo "  1. 检查 Longhorn Manager 日志"
    echo "  2. 检查节点状态"
    echo "  3. 尝试手动附加 Volume:"
    echo "     kubectl patch volumes.longhorn.io ${VOLUME_NAME} -n longhorn-system --type='merge' -p '{\"spec\":{\"nodeID\":\"'$(hostname)'\"}}'"
elif [ "${VOLUME_ROBUSTNESS}" != "healthy" ]; then
    echo_error "✗ Volume 健康状态异常: ${VOLUME_ROBUSTNESS}"
    echo_info "建议操作："
    echo "  1. 检查 Replica 状态"
    echo "  2. 检查节点磁盘空间"
    echo "  3. 查看 Longhorn Manager 日志"
else
    echo_warn "⚠️  Volume 状态: ${VOLUME_STATE}, 健康状态: ${VOLUME_ROBUSTNESS}"
    echo_info "请根据上述详细信息进行排查"
fi

echo ""


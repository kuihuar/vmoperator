#!/bin/bash

# 诊断 Longhorn Pod 问题
# 检查 longhorn-manager 和 longhorn-driver-deployer 的状态

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
echo_section() { echo -e "${CYAN}=== $1 ===${NC}"; }

echo ""
echo_section "诊断 Longhorn Pod 问题"
echo ""

# ==========================================
# 1. 检查所有 Longhorn Pod 状态
# ==========================================
echo_section "1. Longhorn Pod 状态概览"
echo "----------------------------------------"
kubectl get pods -n longhorn-system
echo ""

# ==========================================
# 2. 检查 longhorn-manager Pod
# ==========================================
echo_section "2. longhorn-manager Pod 详情"
echo "----------------------------------------"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${MANAGER_POD}" ]; then
    echo_error "未找到 longhorn-manager Pod"
else
    echo_info "Manager Pod: ${MANAGER_POD}"
    echo ""
    
    # Pod 状态
    echo_info "Pod 状态:"
    kubectl get pod "${MANAGER_POD}" -n longhorn-system -o wide
    echo ""
    
    # Pod 详细信息
    echo_info "Pod 详细信息:"
    kubectl describe pod "${MANAGER_POD}" -n longhorn-system | \
        grep -A 30 "Status:\|State:\|Events:" | head -50
    echo ""
    
    # 容器状态
    echo_info "容器状态:"
    kubectl get pod "${MANAGER_POD}" -n longhorn-system -o jsonpath='{.status.containerStatuses[*]}' | \
        jq -r '.' 2>/dev/null || kubectl get pod "${MANAGER_POD}" -n longhorn-system -o jsonpath='{.status.containerStatuses[*].name}{"\t"}{.status.containerStatuses[*].state}' && echo ""
    echo ""
    
    # 日志（最后 50 行）
    echo_info "Manager 日志（最后 50 行）:"
    kubectl logs "${MANAGER_POD}" -n longhorn-system --tail=50 2>&1 | tail -50 || \
        echo_warn "无法获取日志"
    echo ""
    
    # 检查是否有 Engine Image 相关错误
    ENGINE_IMAGE_ERROR=$(kubectl logs "${MANAGER_POD}" -n longhorn-system 2>&1 | \
        grep -i "engine.*version\|incompatible\|ei-db6c2b6f" | head -5 || echo "")
    if [ -n "${ENGINE_IMAGE_ERROR}" ]; then
        echo_warn "发现 Engine Image 相关错误:"
        echo "${ENGINE_IMAGE_ERROR}"
        echo ""
    fi
fi
echo ""

# ==========================================
# 3. 检查 longhorn-driver-deployer Pod
# ==========================================
echo_section "3. longhorn-driver-deployer Pod 详情"
echo "----------------------------------------"
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${DEPLOYER_POD}" ]; then
    echo_error "未找到 longhorn-driver-deployer Pod"
else
    echo_info "Driver Deployer Pod: ${DEPLOYER_POD}"
    echo ""
    
    # Pod 状态
    echo_info "Pod 状态:"
    kubectl get pod "${DEPLOYER_POD}" -n longhorn-system -o wide
    echo ""
    
    # Pod 详细信息
    echo_info "Pod 详细信息:"
    kubectl describe pod "${DEPLOYER_POD}" -n longhorn-system | \
        grep -A 30 "Status:\|State:\|Events:" | head -50
    echo ""
    
    # 检查 Init 容器
    echo_info "Init 容器状态:"
    kubectl get pod "${DEPLOYER_POD}" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[*]}' | \
        jq -r '.' 2>/dev/null || kubectl get pod "${DEPLOYER_POD}" -n longhorn-system -o jsonpath='{.status.initContainerStatuses[*].name}{"\t"}{.status.initContainerStatuses[*].state}' && echo ""
    echo ""
    
    # Init 容器日志
    INIT_CONTAINER=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
        -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null || echo "")
    if [ -n "${INIT_CONTAINER}" ]; then
        echo_info "Init 容器日志 (${INIT_CONTAINER}):"
        kubectl logs "${DEPLOYER_POD}" -n longhorn-system -c "${INIT_CONTAINER}" --tail=50 2>&1 || \
            echo_warn "无法获取 Init 容器日志"
        echo ""
    fi
    
    # 主容器日志
    echo_info "主容器日志（最后 50 行）:"
    kubectl logs "${DEPLOYER_POD}" -n longhorn-system --tail=50 2>&1 | tail -50 || \
        echo_warn "无法获取日志"
    echo ""
fi
echo ""

# ==========================================
# 4. 检查 Engine Image
# ==========================================
echo_section "4. Engine Image 状态"
echo "----------------------------------------"
ENGINE_IMAGES=$(kubectl get engineimages.longhorn.io -n longhorn-system 2>/dev/null || echo "")
if [ -z "${ENGINE_IMAGES}" ]; then
    echo_warn "未找到 Engine Image"
else
    kubectl get engineimages.longhorn.io -n longhorn-system
    echo ""
    
    # 检查问题 Engine Image
    if kubectl get engineimages.longhorn.io ei-db6c2b6f -n longhorn-system &>/dev/null; then
        echo_warn "发现问题 Engine Image: ei-db6c2b6f"
        kubectl get engineimages.longhorn.io ei-db6c2b6f -n longhorn-system -o yaml | \
            grep -A 10 "spec:\|status:" | head -20
    fi
fi
echo ""

# ==========================================
# 5. 检查 Longhorn Settings
# ==========================================
echo_section "5. Longhorn Settings"
echo "----------------------------------------"
SETTINGS=$(kubectl get settings.longhorn.io -n longhorn-system 2>/dev/null | head -5 || echo "")
if [ -n "${SETTINGS}" ]; then
    echo "Settings:"
    echo "${SETTINGS}"
else
    echo_warn "未找到 Settings"
fi
echo ""

# ==========================================
# 6. 总结和建议
# ==========================================
echo_section "诊断总结"
echo "----------------------------------------"

# 检查是否有 Engine Image 版本错误
if kubectl logs -n longhorn-system -l app=longhorn-manager 2>&1 | grep -q "incompatible Engine.*version"; then
    echo_error "确认问题：Engine Image 版本不兼容"
    echo ""
    echo_info "修复步骤："
    echo "  1. 运行修复脚本："
    echo "     ./docs/installation/fix-engine-image-version.sh"
    echo ""
    echo "  2. 或手动删除旧的 Engine Image："
    echo "     kubectl delete engineimages.longhorn.io ei-db6c2b6f -n longhorn-system"
    echo "     kubectl delete pods -n longhorn-system -l app=longhorn-manager"
    echo ""
fi

# 检查 driver-deployer 问题
if [ -n "${DEPLOYER_POD}" ]; then
    DEPLOYER_PHASE=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
    if [ "${DEPLOYER_PHASE}" = "Error" ] || [ "${DEPLOYER_PHASE}" = "CrashLoopBackOff" ]; then
        echo_warn "longhorn-driver-deployer 处于异常状态"
        echo ""
        echo_info "可能原因："
        echo "  - longhorn-manager 未就绪，导致 driver-deployer 无法启动"
        echo "  - Init 容器等待 longhorn-manager 超时"
        echo ""
        echo_info "建议："
        echo "  1. 先修复 longhorn-manager 问题"
        echo "  2. 修复后，driver-deployer 应该能自动恢复"
        echo ""
    fi
fi

echo_info "已完成的检查:"
echo "  ✓ longhorn-manager Pod 状态和日志"
echo "  ✓ longhorn-driver-deployer Pod 状态和日志"
echo "  ✓ Engine Image 状态"
echo "  ✓ Longhorn Settings"
echo ""


#!/bin/bash

# 检查 longhorn-driver-deployer CrashLoopBackOff 问题

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 longhorn-driver-deployer CrashLoopBackOff 问题"
echo_info "=========================================="
echo ""

# 1. 检查所有 Longhorn Pod 状态
echo_info "1. Longhorn Pod 状态概览"
echo "----------------------------------------"
kubectl get pods -n longhorn-system
echo ""

# 2. 检查 longhorn-manager 状态
echo_info "2. 检查 longhorn-manager 状态"
echo "----------------------------------------"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${MANAGER_POD}" ]; then
    echo_error "未找到 longhorn-manager Pod"
else
    MANAGER_STATUS=$(kubectl get pod "${MANAGER_POD}" -n longhorn-system \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
    MANAGER_READY=$(kubectl get pod "${MANAGER_POD}" -n longhorn-system \
        -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")].ready}' 2>/dev/null || echo "false")
    
    echo "Manager Pod: ${MANAGER_POD}"
    echo "Status: ${MANAGER_STATUS}"
    echo "Ready: ${MANAGER_READY}"
    
    if [ "${MANAGER_READY}" != "true" ]; then
        echo_warn "  ⚠️  Manager 未就绪，这可能是 driver-deployer 失败的原因"
        echo ""
        echo "Manager 容器状态:"
        kubectl get pod "${MANAGER_POD}" -n longhorn-system -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")].state}' 2>/dev/null | jq -r '.' || \
            kubectl get pod "${MANAGER_POD}" -n longhorn-system -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")]}' && echo ""
    else
        echo_info "  ✓ Manager 已就绪"
    fi
fi
echo ""

# 3. 检查 driver-deployer Pod
echo_info "3. 检查 longhorn-driver-deployer Pod 详情"
echo "----------------------------------------"
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${DEPLOYER_POD}" ]; then
    echo_error "未找到 longhorn-driver-deployer Pod"
    exit 1
fi

echo "Pod: ${DEPLOYER_POD}"
kubectl get pod "${DEPLOYER_POD}" -n longhorn-system -o wide
echo ""

# 4. 检查 Pod 详细信息
echo_info "4. Pod 详细信息"
echo "----------------------------------------"
kubectl describe pod "${DEPLOYER_POD}" -n longhorn-system | \
    grep -A 30 "Status:\|State:\|Events:" | head -50
echo ""

# 5. 检查 Init 容器
echo_info "5. Init 容器状态和日志"
echo "----------------------------------------"
INIT_CONTAINER=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
    -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null || echo "")

if [ -n "${INIT_CONTAINER}" ]; then
    echo "Init 容器名称: ${INIT_CONTAINER}"
    echo ""
    echo "Init 容器状态:"
    kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
        -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null | jq -r '.' || \
        kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
        -o jsonpath='{.status.initContainerStatuses[0]}' && echo ""
    echo ""
    echo "Init 容器日志（最后 30 行）:"
    kubectl logs "${DEPLOYER_POD}" -n longhorn-system -c "${INIT_CONTAINER}" --tail=30 2>&1 || \
        echo_warn "无法获取 Init 容器日志"
else
    echo_warn "未找到 Init 容器"
fi
echo ""

# 6. 检查主容器日志
echo_info "6. 主容器日志（最后 30 行）"
echo "----------------------------------------"
kubectl logs "${DEPLOYER_POD}" -n longhorn-system --tail=30 2>&1 | tail -30 || \
    echo_warn "无法获取主容器日志"
echo ""

# 7. 检查主容器状态
echo_info "7. 主容器状态"
echo "----------------------------------------"
CONTAINER_STATE=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
    -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "")
if [ -n "${CONTAINER_STATE}" ]; then
    echo "${CONTAINER_STATE}" | jq -r '.' 2>/dev/null || echo "${CONTAINER_STATE}"
    
    # 检查退出码
    EXIT_CODE=$(echo "${CONTAINER_STATE}" | jq -r '.terminated.exitCode // .waiting.reason // "N/A"' 2>/dev/null || echo "N/A")
    if [ "${EXIT_CODE}" != "N/A" ] && [ "${EXIT_CODE}" != "null" ]; then
        echo ""
        echo "退出码/原因: ${EXIT_CODE}"
    fi
fi
echo ""

# 8. 检查 Manager 是否可访问
echo_info "8. 检查 longhorn-manager 服务是否可访问"
echo "----------------------------------------"
if kubectl get svc longhorn-backend -n longhorn-system &>/dev/null; then
    echo "Service 存在: longhorn-backend"
    kubectl get svc longhorn-backend -n longhorn-system
    echo ""
    
    # 尝试从集群内访问
    echo "尝试访问 Manager API:"
    kubectl run test-manager-access --rm -i --restart=Never --image=curlimages/curl:latest \
        -- curl -s -m 5 http://longhorn-backend.longhorn-system.svc:9500/v1 2>&1 | head -10 || \
        echo_warn "无法访问 Manager API"
else
    echo_warn "Service longhorn-backend 不存在"
fi
echo ""

# 9. 检查 Engine Image
echo_info "9. 检查 Engine Image 状态"
echo "----------------------------------------"
ENGINE_IMAGES=$(kubectl get engineimages.longhorn.io -n longhorn-system 2>/dev/null || echo "")
if [ -z "${ENGINE_IMAGES}" ]; then
    echo_warn "未找到 Engine Image"
else
    kubectl get engineimages.longhorn.io -n longhorn-system
    echo ""
    
    # 检查是否有问题 Engine Image
    PROBLEM_EI=$(kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.controllerAPIVersion < 4) | .metadata.name' 2>/dev/null || echo "")
    if [ -n "${PROBLEM_EI}" ]; then
        echo_warn "发现问题 Engine Image（controller API version < 4）:"
        echo "${PROBLEM_EI}"
    fi
fi
echo ""

# 10. 总结
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

# 分析可能的原因
REASONS=()

if [ "${MANAGER_READY}" != "true" ]; then
    REASONS+=("longhorn-manager 未就绪")
fi

if [ -n "${PROBLEM_EI}" ]; then
    REASONS+=("存在版本不兼容的 Engine Image")
fi

INIT_FAILED=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
    -o jsonpath='{.status.initContainerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "")
if [ -n "${INIT_FAILED}" ] && [ "${INIT_FAILED}" != "0" ]; then
    REASONS+=("Init 容器失败（退出码: ${INIT_FAILED}）")
fi

CONTAINER_FAILED=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
    -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "")
if [ -n "${CONTAINER_FAILED}" ] && [ "${CONTAINER_FAILED}" != "0" ]; then
    REASONS+=("主容器失败（退出码: ${CONTAINER_FAILED}）")
fi

if [ ${#REASONS[@]} -gt 0 ]; then
    echo_error "可能的原因:"
    for reason in "${REASONS[@]}"; do
        echo "  - ${reason}"
    done
else
    echo_warn "未发现明显问题，请查看上面的日志获取详细信息"
fi

echo ""
echo_info "建议的修复步骤:"
echo "  1. 如果 Manager 未就绪，先修复 Manager 问题"
echo "  2. 如果存在 Engine Image 问题，删除旧的 Engine Image"
echo "  3. 删除 driver-deployer Pod，让它重新创建"
echo "  4. 检查日志中的具体错误信息"
echo ""


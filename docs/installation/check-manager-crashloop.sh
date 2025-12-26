#!/bin/bash

# 检查 longhorn-manager CrashLoopBackOff 问题（1/2 状态）

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

MANAGER_POD="${1:-}"

if [ -z "${MANAGER_POD}" ]; then
    MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "${MANAGER_POD}" ]; then
    echo_error "未找到 longhorn-manager Pod"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "检查 longhorn-manager CrashLoopBackOff (1/2)"
echo_info "=========================================="
echo ""
echo_info "Pod: ${MANAGER_POD}"
echo ""

# 1. 检查 Pod 状态（1/2 表示有 2 个容器，只有 1 个就绪）
echo_info "1. Pod 容器状态"
echo "----------------------------------------"
kubectl get pod "${MANAGER_POD}" -n longhorn-system -o wide
echo ""

# 2. 检查所有容器状态
echo_info "2. 所有容器详细状态"
echo "----------------------------------------"
CONTAINERS=$(kubectl get pod "${MANAGER_POD}" -n longhorn-system \
    -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")

if [ -n "${CONTAINERS}" ]; then
    for container in ${CONTAINERS}; do
        echo "容器: ${container}"
        CONTAINER_STATUS=$(kubectl get pod "${MANAGER_POD}" -n longhorn-system \
            -o jsonpath="{.status.containerStatuses[?(@.name==\"${container}\")]}" 2>/dev/null || echo "")
        
        if [ -n "${CONTAINER_STATUS}" ]; then
            READY=$(echo "${CONTAINER_STATUS}" | jq -r '.ready' 2>/dev/null || echo "unknown")
            RESTARTS=$(echo "${CONTAINER_STATUS}" | jq -r '.restartCount' 2>/dev/null || echo "0")
            STATE=$(echo "${CONTAINER_STATUS}" | jq -r '.state | keys[0]' 2>/dev/null || echo "unknown")
            
            echo "  Ready: ${READY}"
            echo "  Restarts: ${RESTARTS}"
            echo "  State: ${STATE}"
            
            # 检查状态详情
            if [ "${STATE}" = "waiting" ]; then
                REASON=$(echo "${CONTAINER_STATUS}" | jq -r '.state.waiting.reason' 2>/dev/null || echo "")
                echo "  Waiting Reason: ${REASON}"
            elif [ "${STATE}" = "terminated" ]; then
                EXIT_CODE=$(echo "${CONTAINER_STATUS}" | jq -r '.state.terminated.exitCode' 2>/dev/null || echo "")
                REASON=$(echo "${CONTAINER_STATUS}" | jq -r '.state.terminated.reason' 2>/dev/null || echo "")
                echo "  Exit Code: ${EXIT_CODE}"
                echo "  Reason: ${REASON}"
            fi
            
            if [ "${READY}" != "true" ]; then
                echo_warn "  ⚠️  容器未就绪"
            fi
        fi
        echo ""
    done
fi

# 3. 检查每个容器的日志
echo_info "3. 容器日志检查"
echo "----------------------------------------"
for container in ${CONTAINERS}; do
    echo "容器: ${container}"
    echo "  日志（最后 30 行）:"
    kubectl logs "${MANAGER_POD}" -n longhorn-system -c "${container}" --tail=30 2>&1 | tail -30 || \
        echo_warn "    无法获取日志"
    echo ""
done

# 4. 检查 Pod 事件
echo_info "4. Pod 事件"
echo "----------------------------------------"
kubectl get events -n longhorn-system --field-selector involvedObject.name="${MANAGER_POD}" \
    --sort-by='.lastTimestamp' -o wide 2>/dev/null | tail -15 || echo "无事件"
echo ""

# 5. 检查是否有 Engine Image 错误
echo_info "5. 检查 Engine Image 相关错误"
echo "----------------------------------------"
ENGINE_ERROR=$(kubectl logs "${MANAGER_POD}" -n longhorn-system -c longhorn-manager 2>&1 | \
    grep -iE "incompatible Engine|controller API version.*below required|ei-[0-9a-f]+" | head -5 || echo "")

if [ -n "${ENGINE_ERROR}" ]; then
    echo_error "发现 Engine Image 版本错误:"
    echo "${ENGINE_ERROR}"
    echo ""
    OLD_EI=$(echo "${ENGINE_ERROR}" | grep -oE "ei-[0-9a-f]+" | head -1)
    if [ -n "${OLD_EI}" ]; then
        echo_info "问题 Engine Image: ${OLD_EI}"
    fi
else
    echo_info "未发现 Engine Image 版本错误"
fi
echo ""

# 6. 检查其他错误
echo_info "6. 检查其他错误"
echo "----------------------------------------"
OTHER_ERRORS=$(kubectl logs "${MANAGER_POD}" -n longhorn-system -c longhorn-manager 2>&1 | \
    grep -iE "error|fatal|panic|failed" | tail -10 || echo "")

if [ -n "${OTHER_ERRORS}" ]; then
    echo_warn "发现其他错误:"
    echo "${OTHER_ERRORS}"
fi
echo ""

# 7. 检查 Pod 详细信息
echo_info "7. Pod 详细信息（关键部分）"
echo "----------------------------------------"
kubectl describe pod "${MANAGER_POD}" -n longhorn-system | \
    grep -A 20 "Status:\|State:\|Events:" | head -40
echo ""

# 8. 总结
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [ -n "${ENGINE_ERROR}" ]; then
    echo_error "确认问题：Engine Image 版本不兼容"
    echo ""
    echo_info "修复方法："
    if [ -n "${OLD_EI}" ]; then
        echo "  1. 删除旧的 Engine Image:"
        echo "     kubectl patch engineimages.longhorn.io ${OLD_EI} -n longhorn-system --type='json' -p='[{\"op\": \"remove\", \"path\": \"/metadata/finalizers\"}]'"
        echo "     kubectl delete engineimages.longhorn.io ${OLD_EI} -n longhorn-system"
        echo ""
        echo "  2. 重启 Manager:"
        echo "     kubectl delete pods -n longhorn-system -l app=longhorn-manager"
    else
        echo "  运行修复脚本:"
        echo "    ./docs/installation/fix-engine-image-quick.sh"
    fi
else
    echo_warn "未发现 Engine Image 错误"
    echo ""
    echo_info "请检查："
    echo "  1. 上面的容器日志中的错误信息"
    echo "  2. 哪个容器在 CrashLoopBackOff（可能是 sidecar 容器）"
    echo "  3. Pod 事件中的详细信息"
fi
echo ""


#!/bin/bash

# 检查 longhorn-manager BackOff 问题

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
echo_info "检查 longhorn-manager BackOff 问题"
echo_info "=========================================="
echo ""
echo_info "Pod: ${MANAGER_POD}"
echo ""

# 1. 解释 BackOff 的含义
echo_info "1. BackOff 警告的含义"
echo "----------------------------------------"
echo "BackOff 表示："
echo "  - 容器启动失败后，Kubernetes 会尝试重启"
echo "  - 如果连续失败，Kubernetes 会逐渐增加重启间隔（指数退避）"
echo "  - 这是 Kubernetes 的保护机制，避免频繁重启消耗资源"
echo "  - 需要查看容器日志和退出原因来定位问题"
echo ""

# 2. 检查 Pod 详细状态
echo_info "2. Pod 详细状态"
echo "----------------------------------------"
kubectl describe pod "${MANAGER_POD}" -n longhorn-system | \
    grep -A 30 "Status:\|State:\|Events:" | head -60
echo ""

# 3. 检查容器状态
echo_info "3. 容器状态详情"
echo "----------------------------------------"
CONTAINER_STATUS=$(kubectl get pod "${MANAGER_POD}" -n longhorn-system \
    -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")]}' 2>/dev/null || echo "")

if [ -n "${CONTAINER_STATUS}" ]; then
    echo "${CONTAINER_STATUS}" | jq -r '.' 2>/dev/null || echo "${CONTAINER_STATUS}"
    echo ""
    
    # 提取退出码和原因
    EXIT_CODE=$(echo "${CONTAINER_STATUS}" | jq -r '.state.terminated.exitCode // .lastState.terminated.exitCode // "N/A"' 2>/dev/null || echo "N/A")
    REASON=$(echo "${CONTAINER_STATUS}" | jq -r '.state.terminated.reason // .lastState.terminated.reason // .state.waiting.reason // "N/A"' 2>/dev/null || echo "N/A")
    
    if [ "${EXIT_CODE}" != "N/A" ] && [ "${EXIT_CODE}" != "null" ]; then
        echo "退出码: ${EXIT_CODE}"
    fi
    if [ "${REASON}" != "N/A" ] && [ "${REASON}" != "null" ]; then
        echo "原因: ${REASON}"
    fi
fi
echo ""

# 4. 检查容器日志（最后 50 行）
echo_info "4. 容器日志（最后 50 行）"
echo "----------------------------------------"
kubectl logs "${MANAGER_POD}" -n longhorn-system -c longhorn-manager --tail=50 2>&1 | tail -50 || \
    kubectl logs "${MANAGER_POD}" -n longhorn-system --tail=50 2>&1 | tail -50 || \
    echo_warn "无法获取日志"
echo ""

# 5. 检查是否有 Engine Image 错误
echo_info "5. 检查 Engine Image 相关错误"
echo "----------------------------------------"
ENGINE_ERROR=$(kubectl logs "${MANAGER_POD}" -n longhorn-system -c longhorn-manager 2>&1 | \
    grep -iE "incompatible Engine|controller API version|ei-[0-9a-f]+" | head -5 || echo "")

if [ -n "${ENGINE_ERROR}" ]; then
    echo_error "发现 Engine Image 版本错误:"
    echo "${ENGINE_ERROR}"
    echo ""
    echo_info "这是导致 Manager 启动失败的原因"
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
else
    echo_info "未发现其他明显错误"
fi
echo ""

# 7. 检查重启次数
echo_info "7. 重启统计"
echo "----------------------------------------"
RESTART_COUNT=$(kubectl get pod "${MANAGER_POD}" -n longhorn-system \
    -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")].restartCount}' 2>/dev/null || echo "0")
echo "重启次数: ${RESTART_COUNT}"
echo ""

# 8. 总结和建议
echo_info "=========================================="
echo_info "问题分析"
echo_info "=========================================="
echo ""

if [ -n "${ENGINE_ERROR}" ]; then
    echo_error "确认问题：Engine Image 版本不兼容"
    echo ""
    echo_info "修复方法："
    echo "  1. 删除旧的 Engine Image:"
    echo "     ./docs/installation/fix-engine-image-quick.sh"
    echo ""
    echo "  2. 或手动删除:"
    OLD_EI=$(echo "${ENGINE_ERROR}" | grep -oE "ei-[0-9a-f]+" | head -1)
    if [ -n "${OLD_EI}" ]; then
        echo "     kubectl patch engineimages.longhorn.io ${OLD_EI} -n longhorn-system --type='json' -p='[{\"op\": \"remove\", \"path\": \"/metadata/finalizers\"}]'"
        echo "     kubectl delete engineimages.longhorn.io ${OLD_EI} -n longhorn-system"
    fi
    echo ""
    echo "  3. 重启 Manager:"
    echo "     kubectl delete pods -n longhorn-system -l app=longhorn-manager"
else
    echo_warn "未发现 Engine Image 错误，可能是其他原因"
    echo ""
    echo_info "请检查："
    echo "  1. 上面的容器日志中的错误信息"
    echo "  2. Pod 事件中的详细信息"
    echo "  3. 节点资源是否充足（CPU、内存、磁盘）"
    echo "  4. 数据盘路径是否正确配置"
fi
echo ""


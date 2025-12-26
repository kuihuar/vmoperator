#!/bin/bash

# 检查 longhorn-manager CrashLoopBackOff 问题
# 诊断 Engine Image 版本不兼容等问题

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 longhorn-manager CrashLoopBackOff 问题"
echo_info "=========================================="
echo ""

# 1. 检查 Manager Pod 状态
echo_info "1. 检查 longhorn-manager Pod 状态"
echo "----------------------------------------"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${MANAGER_POD}" ]; then
    echo_error "未找到 longhorn-manager Pod"
    exit 1
fi

echo "Pod: ${MANAGER_POD}"
kubectl get pod "${MANAGER_POD}" -n longhorn-system
echo ""

# 2. 检查 Manager Pod 日志（查找错误）
echo_info "2. 检查 longhorn-manager 日志（最后 50 行）"
echo "----------------------------------------"
MANAGER_LOGS=$(kubectl logs "${MANAGER_POD}" -n longhorn-system --tail=50 2>&1)
echo "${MANAGER_LOGS}"
echo ""

# 3. 检查是否是 Engine Image 版本问题
echo_info "3. 检查 Engine Image 版本问题"
echo "----------------------------------------"
ENGINE_IMAGE_ERROR=$(echo "${MANAGER_LOGS}" | \
    grep -iE "incompatible Engine|controller API version.*below required|ei-[0-9a-f]+" || echo "")

if [ -n "${ENGINE_IMAGE_ERROR}" ]; then
    echo_error "✗ 确认问题：Engine Image 版本不兼容"
    echo ""
    echo "错误信息："
    echo "${ENGINE_IMAGE_ERROR}"
    echo ""
    
    # 提取 Engine Image 名称
    OLD_ENGINE_IMAGE=$(echo "${ENGINE_IMAGE_ERROR}" | grep -oE "ei-[0-9a-f]+" | head -1 || echo "")
    if [ -n "${OLD_ENGINE_IMAGE}" ]; then
        echo_info "问题 Engine Image: ${OLD_ENGINE_IMAGE}"
        
        # 检查该 Engine Image 是否存在
        if kubectl get engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system &>/dev/null; then
            echo_warn "  Engine Image 仍然存在"
            kubectl get engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system -o yaml | \
                grep -A 5 "spec:\|status:" | head -10
        else
            echo_info "  Engine Image 不存在（可能已被删除）"
        fi
    fi
else
    echo_info "✓ 未发现 Engine Image 版本错误"
fi
echo ""

# 4. 检查所有 Engine Image
echo_info "4. 检查所有 Engine Image"
echo "----------------------------------------"
ENGINE_IMAGES=$(kubectl get engineimages.longhorn.io -n longhorn-system 2>/dev/null || echo "")
if [ -z "${ENGINE_IMAGES}" ]; then
    echo_warn "未找到 Engine Image"
else
    kubectl get engineimages.longhorn.io -n longhorn-system
    echo ""
    
    # 检查每个 Engine Image 的状态
    kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.name)\t\(.status.state // "unknown")\t\(.spec.image // "unknown")"' 2>/dev/null | \
        while IFS=$'\t' read -r name state image; do
            if [ -z "${name}" ]; then
                continue
            fi
            echo "  ${name}: state=${state}, image=${image}"
        done
fi
echo ""

# 5. 检查 Pod 事件
echo_info "5. 检查 Pod 事件"
echo "----------------------------------------"
kubectl get events -n longhorn-system --field-selector involvedObject.name="${MANAGER_POD}" \
    --sort-by='.lastTimestamp' -o wide 2>/dev/null | tail -10 || echo "无事件"
echo ""

# 6. 检查容器状态
echo_info "6. 检查容器状态"
echo "----------------------------------------"
kubectl get pod "${MANAGER_POD}" -n longhorn-system -o jsonpath='{.status.containerStatuses[*]}' | \
    jq -r '.' 2>/dev/null || kubectl get pod "${MANAGER_POD}" -n longhorn-system -o jsonpath='{.status.containerStatuses[*].name}{"\t"}{.status.containerStatuses[*].state}' && echo ""
echo ""

# 7. 检查 driver-deployer 状态
echo_info "7. 检查 longhorn-driver-deployer 状态"
echo "----------------------------------------"
DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${DEPLOYER_POD}" ]; then
    echo "Pod: ${DEPLOYER_POD}"
    kubectl get pod "${DEPLOYER_POD}" -n longhorn-system
    echo ""
    
    # 检查 Init 容器状态
    INIT_STATUS=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
        -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null || echo "")
    if [ -n "${INIT_STATUS}" ]; then
        echo "Init 容器状态:"
        echo "${INIT_STATUS}" | jq -r '.' 2>/dev/null || echo "${INIT_STATUS}"
    fi
    
    # Init 容器日志
    INIT_CONTAINER=$(kubectl get pod "${DEPLOYER_POD}" -n longhorn-system \
        -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null || echo "")
    if [ -n "${INIT_CONTAINER}" ]; then
        echo ""
        echo "Init 容器日志（最后 20 行）:"
        kubectl logs "${DEPLOYER_POD}" -n longhorn-system -c "${INIT_CONTAINER}" --tail=20 2>&1 || echo "无法获取日志"
    fi
else
    echo_warn "未找到 longhorn-driver-deployer Pod"
fi
echo ""

# 8. 总结
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [ -n "${ENGINE_IMAGE_ERROR}" ]; then
    echo_error "确认问题：Engine Image 版本不兼容"
    echo ""
    echo_info "问题原因："
    echo "  - 旧的 Engine Image 版本过低（controller API version < 4）"
    echo "  - Longhorn v1.8.1 要求 Engine Image controller API version >= 4"
    echo ""
    echo_info "修复方法："
    if [ -n "${OLD_ENGINE_IMAGE}" ]; then
        echo "  1. 删除旧的 Engine Image:"
        echo "     kubectl delete engineimages.longhorn.io ${OLD_ENGINE_IMAGE} -n longhorn-system"
        echo ""
        echo "  2. 如果有 finalizers，先清理："
        echo "     kubectl patch engineimages.longhorn.io ${OLD_ENGINE_IMAGE} -n longhorn-system --type='json' -p='[{\"op\": \"remove\", \"path\": \"/metadata/finalizers\"}]'"
        echo "     kubectl delete engineimages.longhorn.io ${OLD_ENGINE_IMAGE} -n longhorn-system"
        echo ""
        echo "  3. 重启 Manager:"
        echo "     kubectl delete pods -n longhorn-system -l app=longhorn-manager"
    else
        echo "  1. 检查所有 Engine Image:"
        echo "     kubectl get engineimages.longhorn.io -n longhorn-system"
        echo ""
        echo "  2. 删除所有旧的 Engine Image（版本 < 4 的）"
        echo ""
        echo "  3. 重启 Manager:"
        echo "     kubectl delete pods -n longhorn-system -l app=longhorn-manager"
    fi
else
    echo_warn "未发现 Engine Image 版本问题"
    echo ""
    echo_info "可能的原因："
    echo "  - 其他配置问题"
    echo "  - 资源不足"
    echo "  - 网络问题"
    echo ""
    echo_info "请检查 Manager 日志中的其他错误信息"
fi
echo ""


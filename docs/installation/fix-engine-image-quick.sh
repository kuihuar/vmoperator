#!/bin/bash

# 快速修复 Engine Image 版本问题（带超时和强制清理）

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

ENGINE_IMAGE_NAME="${1:-ei-db6c2b6f}"

echo ""
echo_info "修复 Engine Image 版本问题: ${ENGINE_IMAGE_NAME}"
echo ""

# 1. 检查 Engine Image 是否存在
if ! kubectl get engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system &>/dev/null; then
    echo_warn "Engine Image ${ENGINE_IMAGE_NAME} 不存在，可能已被删除"
    echo_info "检查所有 Engine Image:"
    kubectl get engineimages.longhorn.io -n longhorn-system
    exit 0
fi

# 2. 检查是否有 Volume 使用该 Engine Image
echo_info "1. 检查是否有 Volume 使用该 Engine Image..."
VOLUMES_USING_ENGINE=$(kubectl get volumes.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r ".items[] | select(.status.currentImage == \"${ENGINE_IMAGE_NAME}\") | .metadata.name" 2>/dev/null || echo "")

if [ -n "${VOLUMES_USING_ENGINE}" ]; then
    echo_warn "发现使用该 Engine Image 的 Volume:"
    echo "${VOLUMES_USING_ENGINE}"
    echo_warn "删除 Engine Image 可能导致这些 Volume 无法使用"
    read -p "是否继续？(y/n，默认n): " CONTINUE
    CONTINUE=${CONTINUE:-n}
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        echo_info "已取消"
        exit 0
    fi
else
    echo_info "  ✓ 没有 Volume 使用该 Engine Image"
fi

# 3. 检查 finalizers
echo ""
echo_info "2. 检查并清理 finalizers..."
FINALIZERS=$(kubectl get engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system \
    -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")

if [ -n "${FINALIZERS}" ]; then
    echo_warn "  发现 finalizers: ${FINALIZERS}"
    echo_info "  清理 finalizers..."
    
    # 使用 timeout 避免卡住
    timeout 10 kubectl patch engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system \
        --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1
    
    if [ $? -eq 0 ]; then
        echo_info "  ✓ finalizers 已清理"
    else
        echo_warn "  ⚠️  清理 finalizers 可能失败或超时，继续尝试删除"
    fi
    
    sleep 2
else
    echo_info "  ✓ 没有 finalizers"
fi

# 4. 删除 Engine Image（带超时）
echo ""
echo_info "3. 删除 Engine Image（带 10 秒超时）..."
timeout 10 kubectl delete engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system 2>&1

DELETE_RESULT=$?
if [ ${DELETE_RESULT} -eq 0 ]; then
    echo_info "  ✓ Engine Image 已删除"
elif [ ${DELETE_RESULT} -eq 124 ]; then
    echo_warn "  ⚠️  删除超时（可能卡住），尝试强制删除..."
    
    # 再次清理 finalizers 并强制删除
    kubectl patch engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system \
        --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value": []}]' 2>/dev/null || true
    
    sleep 2
    
    # 再次尝试删除
    timeout 5 kubectl delete engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system --grace-period=0 2>&1 || true
else
    echo_warn "  ⚠️  删除失败，错误代码: ${DELETE_RESULT}"
fi

# 5. 验证删除结果
echo ""
echo_info "4. 验证删除结果..."
sleep 2
if kubectl get engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system &>/dev/null; then
    echo_warn "  ⚠️  Engine Image 仍然存在"
    echo_info "  当前状态:"
    kubectl get engineimages.longhorn.io "${ENGINE_IMAGE_NAME}" -n longhorn-system -o yaml | grep -A 5 "metadata:\|status:" | head -10
    echo ""
    echo_warn "  可能需要手动处理，或等待一段时间后重试"
else
    echo_info "  ✓ Engine Image 已成功删除"
fi

# 6. 重启 Manager
echo ""
echo_info "5. 重启 longhorn-manager..."
kubectl delete pods -n longhorn-system -l app=longhorn-manager --timeout=10s 2>&1 || true

echo ""
echo_info "6. 等待 Manager 重启（10 秒）..."
sleep 10

# 7. 检查状态
echo ""
echo_info "7. 检查 Pod 状态:"
kubectl get pods -n longhorn-system -l app=longhorn-manager

echo ""
echo_info "修复完成！"
echo ""
echo_info "如果 Manager 仍然无法启动，请检查日志:"
echo "  kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
echo ""


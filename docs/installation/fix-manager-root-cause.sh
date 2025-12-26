#!/bin/bash

# 修复 longhorn-manager CrashLoopBackOff 的根本原因
# 不是简单重启，而是找到并修复根本问题

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "诊断并修复 longhorn-manager CrashLoopBackOff 根本原因"
echo_info "=========================================="
echo ""

# 1. 获取 Manager Pod
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${MANAGER_POD}" ]; then
    echo_error "未找到 longhorn-manager Pod"
    exit 1
fi

echo_info "Manager Pod: ${MANAGER_POD}"
echo ""

# 2. 查看日志找到根本原因
echo_info "1. 查看 Manager 日志（查找失败原因）"
echo "----------------------------------------"
MANAGER_LOGS=$(kubectl logs "${MANAGER_POD}" -n longhorn-system -c longhorn-manager --tail=100 2>&1)

# 检查 Engine Image 错误
ENGINE_ERROR=$(echo "${MANAGER_LOGS}" | \
    grep -iE "incompatible Engine|controller API version.*below required|ei-[0-9a-f]+" | head -3 || echo "")

if [ -n "${ENGINE_ERROR}" ]; then
    echo_error "✗ 发现根本原因：Engine Image 版本不兼容"
    echo ""
    echo "错误信息："
    echo "${ENGINE_ERROR}"
    echo ""
    
    # 提取 Engine Image 名称
    OLD_ENGINE_IMAGE=$(echo "${ENGINE_ERROR}" | grep -oE "ei-[0-9a-f]+" | head -1 || echo "")
    
    if [ -n "${OLD_ENGINE_IMAGE}" ]; then
        echo_info "问题 Engine Image: ${OLD_ENGINE_IMAGE}"
        echo ""
        echo_info "2. 修复：删除旧的 Engine Image"
        echo "----------------------------------------"
        
        # 检查是否存在
        if kubectl get engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system &>/dev/null; then
            echo_info "  删除 Engine Image: ${OLD_ENGINE_IMAGE}"
            
            # 清理 finalizers（带超时）
            echo_info "    清理 finalizers..."
            timeout 10 kubectl patch engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system \
                --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1 || true
            
            sleep 2
            
            # 删除（带超时）
            echo_info "    删除 Engine Image..."
            timeout 10 kubectl delete engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system 2>&1
            
            if [ $? -eq 0 ]; then
                echo_info "    ✓ Engine Image 已删除"
            else
                echo_warn "    ⚠️  删除可能超时或失败，尝试强制删除..."
                # 强制清理 finalizers
                kubectl patch engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system \
                    --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value": []}]' 2>&1 || true
                sleep 2
                kubectl delete engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system --grace-period=0 --force 2>&1 || true
            fi
            
            # 验证删除
            sleep 3
            if kubectl get engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system &>/dev/null; then
                echo_warn "    ⚠️  Engine Image 仍然存在，可能需要手动处理"
            else
                echo_info "    ✓ Engine Image 已成功删除"
            fi
            
            echo ""
            echo_info "3. 等待 Manager 自动恢复（不再需要手动重启）"
            echo "----------------------------------------"
            echo_info "  删除 Engine Image 后，Manager 应该能自动恢复"
            echo_info "  等待 30 秒后检查状态..."
            sleep 30
            
            # 检查 Manager 状态
            NEW_MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager \
                -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            
            if [ -n "${NEW_MANAGER_POD}" ]; then
                MANAGER_READY=$(kubectl get pod "${NEW_MANAGER_POD}" -n longhorn-system \
                    -o jsonpath='{.status.containerStatuses[?(@.name=="longhorn-manager")].ready}' 2>/dev/null || echo "false")
                
                if [ "${MANAGER_READY}" = "true" ]; then
                    echo_info "  ✓ Manager 已自动恢复并运行正常"
                else
                    echo_warn "  ⚠️  Manager 仍在恢复中，请稍等..."
                    echo_info "  当前状态:"
                    kubectl get pods -n longhorn-system -l app=longhorn-manager
                fi
            fi
        else
            echo_warn "  Engine Image ${OLD_ENGINE_IMAGE} 不存在（可能已被删除）"
            echo_info "  检查是否还有其他问题..."
        fi
    else
        echo_warn "  无法从错误信息中提取 Engine Image 名称"
        echo_info "  请手动检查并删除所有旧的 Engine Image:"
        echo "    kubectl get engineimages.longhorn.io -n longhorn-system"
    fi
else
    # 检查其他错误
    echo_info "未发现 Engine Image 版本错误，检查其他原因..."
    echo ""
    
    # 查找其他错误
    FATAL_ERROR=$(echo "${MANAGER_LOGS}" | grep -i "fatal\|panic" | head -3 || echo "")
    if [ -n "${FATAL_ERROR}" ]; then
        echo_error "发现致命错误:"
        echo "${FATAL_ERROR}"
    fi
    
    # 显示最后几行日志
    echo ""
    echo_info "最后 20 行日志:"
    echo "${MANAGER_LOGS}" | tail -20
    echo ""
    
    echo_warn "未发现 Engine Image 错误，可能是其他原因"
    echo_info "请检查上面的日志获取详细信息"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "当前 Manager 状态:"
kubectl get pods -n longhorn-system -l app=longhorn-manager
echo ""
echo_info "如果 Manager 仍未恢复，请检查日志:"
echo "  kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
echo ""


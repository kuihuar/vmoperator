#!/bin/bash

# Longhorn 诊断脚本 - 检查 Pod 状态和问题

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
echo_info "Longhorn 诊断工具"
echo_info "=========================================="
echo ""

# 1. 检查命名空间
echo_info "1. 检查命名空间..."
if kubectl get ns longhorn-system &>/dev/null; then
    echo_info "  ✓ longhorn-system 命名空间存在"
else
    echo_error "  ✗ longhorn-system 命名空间不存在"
    exit 1
fi

# 2. 检查 Pod 状态
echo ""
echo_info "2. 检查 Pod 状态..."
kubectl get pods -n longhorn-system

echo ""
echo_warn "详细状态分析："

# 检查 manager Pod
MANAGER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name 2>/dev/null | head -1)
if [ -n "${MANAGER_PODS}" ]; then
    MANAGER_POD_NAME=$(echo ${MANAGER_PODS} | cut -d'/' -f2)
    echo ""
    echo_info "3. 检查 longhorn-manager Pod: ${MANAGER_POD_NAME}"
    
    MANAGER_STATUS=$(kubectl get pod ${MANAGER_POD_NAME} -n longhorn-system -o jsonpath='{.status.phase}' 2>/dev/null)
    MANAGER_RESTARTS=$(kubectl get pod ${MANAGER_POD_NAME} -n longhorn-system -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    
    echo_info "  状态: ${MANAGER_STATUS}"
    echo_info "  重启次数: ${MANAGER_RESTARTS}"
    
    if [ "${MANAGER_STATUS}" != "Running" ] || [ "${MANAGER_RESTARTS}" -gt 0 ]; then
        echo_warn "  ⚠️  Manager Pod 有问题"
        echo_info "  查看详细状态："
        kubectl describe pod ${MANAGER_POD_NAME} -n longhorn-system | tail -20
        
        echo ""
        echo_info "  查看日志（最后 30 行）："
        kubectl logs ${MANAGER_POD_NAME} -n longhorn-system --tail=30 2>&1 | tail -30
    fi
fi

# 检查 driver-deployer Pod
DRIVER_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o name 2>/dev/null | head -1)
if [ -n "${DRIVER_PODS}" ]; then
    DRIVER_POD_NAME=$(echo ${DRIVER_PODS} | cut -d'/' -f2)
    echo ""
    echo_info "4. 检查 longhorn-driver-deployer Pod: ${DRIVER_POD_NAME}"
    
    DRIVER_STATUS=$(kubectl get pod ${DRIVER_POD_NAME} -n longhorn-system -o jsonpath='{.status.phase}' 2>/dev/null)
    INIT_STATUS=$(kubectl get pod ${DRIVER_POD_NAME} -n longhorn-system -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null)
    
    echo_info "  状态: ${DRIVER_STATUS}"
    echo_info "  Init 容器状态: ${INIT_STATUS}"
    
    if echo "${DRIVER_STATUS}" | grep -q "Init\|Pending"; then
        echo_warn "  ⚠️  Driver-deployer Pod 卡在 Init 阶段"
        echo_info "  查看 Init 容器日志："
        kubectl logs ${DRIVER_POD_NAME} -n longhorn-system -c wait-longhorn-manager --tail=20 2>&1 || echo "无法获取日志"
        
        echo ""
        echo_info "  查看详细状态："
        kubectl describe pod ${DRIVER_POD_NAME} -n longhorn-system | grep -A 10 "Events:" || true
    fi
fi

# 5. 检查 DaemonSet 配置
echo ""
echo_info "5. 检查 DaemonSet 配置..."
if kubectl get daemonset longhorn-manager -n longhorn-system &>/dev/null; then
    echo_info "  检查是否有 readinessProbe（应该没有）："
    if kubectl get daemonset longhorn-manager -n longhorn-system -o yaml | grep -q "readinessProbe"; then
        echo_error "  ✗ 发现 readinessProbe，这可能导致问题"
        echo_warn "  建议删除 readinessProbe"
    else
        echo_info "  ✓ 没有 readinessProbe（正确）"
    fi
fi

# 6. 检查 Service 和 Endpoints
echo ""
echo_info "6. 检查 Service 和 Endpoints..."
kubectl get svc -n longhorn-system | grep -E "NAME|longhorn-backend|longhorn-conversion-webhook"

BACKEND_ENDPOINTS=$(kubectl get endpoints longhorn-backend -n longhorn-system -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
if [ -n "${BACKEND_ENDPOINTS}" ]; then
    echo_info "  ✓ longhorn-backend 有 Endpoints: ${BACKEND_ENDPOINTS}"
else
    echo_warn "  ⚠️  longhorn-backend 没有 Endpoints（Manager 可能未就绪）"
fi

# 7. 总结和建议
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [ -n "${MANAGER_PODS}" ]; then
    if [ "${MANAGER_STATUS}" != "Running" ] || [ "${MANAGER_RESTARTS}" -gt 0 ]; then
        echo_warn "问题：longhorn-manager 未正常运行"
        echo_info "建议操作："
        echo "  1. 查看完整日志: kubectl logs ${MANAGER_POD_NAME} -n longhorn-system"
        echo "  2. 如果一直 CrashLoop，可能需要："
        echo "     - 检查数据盘路径是否正确"
        echo "     - 检查节点资源是否充足"
        echo "     - 重新安装（使用修改后的 YAML）"
    fi
fi

if [ -n "${DRIVER_PODS}" ]; then
    if echo "${DRIVER_STATUS}" | grep -q "Init\|Pending"; then
        echo_warn "问题：longhorn-driver-deployer 卡在 Init 阶段"
        echo_info "建议操作："
        echo "  1. 等待最多 5 分钟（init 容器有超时机制）"
        echo "  2. 如果超过 5 分钟还在 Init，检查 manager 是否就绪"
        echo "  3. 可以手动删除 Pod 让它重新创建: kubectl delete pod ${DRIVER_POD_NAME} -n longhorn-system"
    fi
fi

echo ""
echo_info "如果需要重新安装，执行："
echo "  ./docs/installation/install-longhorn.sh"


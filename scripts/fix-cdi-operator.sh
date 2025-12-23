#!/bin/bash

# 修复 CDI Operator 问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

POD_NAME="cdi-operator-5449578fbf-v4ql6"

echo ""
echo_info "=========================================="
echo_info "诊断和修复 CDI Operator"
echo_info "=========================================="
echo ""

# 1. 获取 Pod 详细信息
echo_info "1. 检查 Pod 详细信息"
echo ""

kubectl get pod "$POD_NAME" -n cdi -o wide
echo ""

# 2. 检查 Pod 事件
echo_info "2. 检查 Pod 事件（关键信息）"
echo ""

EVENTS=$(kubectl describe pod "$POD_NAME" -n cdi 2>/dev/null | grep -A 30 "Events:" || echo "")

if [ -n "$EVENTS" ]; then
    echo "$EVENTS"
    echo ""
    
    # 提取关键错误
    ERROR_EVENTS=$(echo "$EVENTS" | grep -i "error\|fail\|warning" || echo "")
    if [ -n "$ERROR_EVENTS" ]; then
        echo_warn "  发现错误事件:"
        echo "$ERROR_EVENTS"
        echo ""
    fi
else
    echo_warn "  无法获取事件"
fi

# 3. 检查容器状态
echo_info "3. 检查容器状态"
echo ""

CONTAINER_STATE=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "")
CONTAINER_READY=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
RESTART_COUNT=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

echo_info "  容器状态: $CONTAINER_STATE"
echo_info "  容器就绪: $CONTAINER_READY"
echo_info "  重启次数: $RESTART_COUNT"
echo ""

# 检查等待原因
WAITING_REASON=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
if [ -n "$WAITING_REASON" ]; then
    echo_warn "  等待原因: $WAITING_REASON"
    WAITING_MSG=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].state.waiting.message}' 2>/dev/null || echo "")
    if [ -n "$WAITING_MSG" ]; then
        echo_warn "  等待消息: $WAITING_MSG"
    fi
fi

# 检查终止原因
TERMINATED_REASON=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null || echo "")
if [ -n "$TERMINATED_REASON" ]; then
    echo_warn "  终止原因: $TERMINATED_REASON"
    TERMINATED_EXIT_CODE=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "")
    if [ -n "$TERMINATED_EXIT_CODE" ]; then
        echo_warn "  退出码: $TERMINATED_EXIT_CODE"
    fi
fi

echo ""

# 4. 获取完整日志（查找错误）
echo_info "4. 获取完整日志（查找错误）"
echo ""

FULL_LOGS=$(kubectl logs "$POD_NAME" -n cdi --tail=200 2>&1 || echo "")

if [ -n "$FULL_LOGS" ]; then
    # 查找错误
    ERROR_LINES=$(echo "$FULL_LOGS" | grep -i "error\|fail\|panic\|fatal" || echo "")
    
    if [ -n "$ERROR_LINES" ]; then
        echo_error "  发现错误日志:"
        echo "$ERROR_LINES" | head -30
        echo ""
    else
        echo_info "  未在日志中发现明显错误"
        echo ""
        echo_info "  最后 50 行日志:"
        echo "$FULL_LOGS" | tail -50
        echo ""
    fi
else
    echo_warn "  无法获取日志"
fi

# 5. 检查资源限制
echo_info "5. 检查资源限制和请求"
echo ""

RESOURCE_REQUESTS=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.spec.containers[0].resources.requests}' 2>/dev/null || echo "")
RESOURCE_LIMITS=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.spec.containers[0].resources.limits}' 2>/dev/null || echo "")

if [ -n "$RESOURCE_REQUESTS" ]; then
    echo_info "  资源请求: $RESOURCE_REQUESTS"
fi
if [ -n "$RESOURCE_LIMITS" ]; then
    echo_info "  资源限制: $RESOURCE_LIMITS"
fi

# 检查节点资源
NODE_NAME=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
if [ -z "$NODE_NAME" ]; then
    NODE_NAME=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.status.hostIP}' 2>/dev/null || echo "")
fi

if [ -n "$NODE_NAME" ]; then
    echo_info "  节点: $NODE_NAME"
    
    # 检查节点压力
    DISK_PRESSURE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="DiskPressure")].status}' 2>/dev/null || echo "")
    MEMORY_PRESSURE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}' 2>/dev/null || echo "")
    
    if [ "$DISK_PRESSURE" = "True" ]; then
        echo_warn "  ⚠️  节点磁盘压力: True"
    fi
    if [ "$MEMORY_PRESSURE" = "True" ]; then
        echo_warn "  ⚠️  节点内存压力: True"
    fi
fi

echo ""

# 6. 检查依赖资源
echo_info "6. 检查依赖资源"
echo ""

# 检查 ServiceAccount
SA_NAME=$(kubectl get pod "$POD_NAME" -n cdi -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null || echo "")
if [ -n "$SA_NAME" ]; then
    if kubectl get serviceaccount "$SA_NAME" -n cdi &>/dev/null; then
        echo_info "  ✓ ServiceAccount 存在: $SA_NAME"
    else
        echo_error "  ✗ ServiceAccount 不存在: $SA_NAME"
    fi
fi

# 检查 ConfigMap
CM_LIST=$(kubectl get configmap -n cdi 2>/dev/null | wc -l || echo "0")
echo_info "  ConfigMap 数量: $CM_LIST"

# 检查 Secret
SECRET_LIST=$(kubectl get secret -n cdi 2>/dev/null | wc -l || echo "0")
echo_info "  Secret 数量: $SECRET_LIST"

echo ""

# 7. 总结和建议
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

# 根据错误类型提供建议
if [ -n "$TERMINATED_REASON" ]; then
    if [ "$TERMINATED_REASON" = "Error" ]; then
        echo_error "  问题: 容器异常退出"
        echo_info "  可能原因:"
        echo "    1. 应用程序错误（检查日志中的 panic/fatal）"
        echo "    2. 配置错误（检查 ConfigMap/Secret）"
        echo "    3. 权限问题（检查 RBAC）"
    elif [ "$TERMINATED_REASON" = "OOMKilled" ]; then
        echo_error "  问题: 内存不足被杀死"
        echo_info "  解决: 增加内存限制或减少资源使用"
    fi
fi

if [ -n "$WAITING_REASON" ]; then
    if [ "$WAITING_REASON" = "ImagePullBackOff" ] || [ "$WAITING_REASON" = "ErrImagePull" ]; then
        echo_error "  问题: 镜像拉取失败"
        echo_info "  解决: 检查镜像仓库连接或镜像名称"
    elif [ "$WAITING_REASON" = "CrashLoopBackOff" ]; then
        echo_error "  问题: 容器反复崩溃"
        echo_info "  解决: 查看日志找出崩溃原因"
    fi
fi

echo ""
echo_info "  建议操作:"
echo "    1. 如果日志显示配置错误，检查 CDI 配置"
echo "    2. 如果日志显示权限错误，检查 RBAC"
echo "    3. 如果资源不足，增加资源限制"
echo "    4. 如果问题持续，尝试删除 Pod 让其重新创建:"
echo "       kubectl delete pod $POD_NAME -n cdi"
echo ""


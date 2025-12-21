#!/bin/bash

# 诊断 longhorn-manager 启动失败的根本原因
# 不再查找独立的 admission-webhook 组件

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
echo_info "=========================================="
echo_info "诊断 longhorn-manager 启动失败的根本原因"
echo_info "=========================================="
echo ""

# 1. 获取 Manager Pod
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$MANAGER_POD" ]; then
    echo_error "未找到 longhorn-manager Pod"
    exit 1
fi

echo_info "Manager Pod: $MANAGER_POD"

# 2. 查看完整日志
echo ""
echo_info "1. 查看 Manager Pod 完整日志（最后 100 行）"
echo "=========================================="
kubectl logs -n longhorn-system $MANAGER_POD --tail=100 2>&1 | tail -50
echo "=========================================="

# 3. 提取关键错误
echo ""
echo_info "2. 提取关键错误信息"
ERROR_LOG=$(kubectl logs -n longhorn-system $MANAGER_POD --tail=200 2>&1 || echo "")

echo ""
echo_info "检查常见错误模式："

# 检查 DNS 错误
if echo "$ERROR_LOG" | grep -qi "dns\|resolve.*failed\|unable to resolve"; then
    echo_error "✗ 检测到 DNS 解析问题"
    echo "  错误信息："
    echo "$ERROR_LOG" | grep -i "dns\|resolve.*failed\|unable to resolve" | tail -5
    echo ""
    echo_warn "修复建议："
    echo "  sudo ./scripts/fix-k3s-dns-for-longhorn.sh"
    DNS_ISSUE=true
else
    echo_info "✓ 未检测到 DNS 问题"
    DNS_ISSUE=false
fi

# 检查 open-iscsi 错误
if echo "$ERROR_LOG" | grep -qi "iscsi\|iscsiadm.*not found\|open-iscsi"; then
    echo_error "✗ 检测到 open-iscsi 问题"
    echo "  错误信息："
    echo "$ERROR_LOG" | grep -i "iscsi\|iscsiadm.*not found\|open-iscsi" | tail -5
    echo ""
    echo_warn "修复建议："
    echo "  # 在节点上执行"
    echo "  sudo apt-get install -y open-iscsi"
    echo "  sudo systemctl enable iscsid && sudo systemctl start iscsid"
    echo "  kubectl delete pod -n longhorn-system $MANAGER_POD"
    ISCSI_ISSUE=true
else
    echo_info "✓ 未检测到 open-iscsi 问题"
    ISCSI_ISSUE=false
fi

# 检查 webhook 超时错误
if echo "$ERROR_LOG" | grep -qi "webhook.*not accessible\|timed out.*webhook\|admission.*webhook.*not accessible"; then
    echo_error "✗ 检测到 Webhook 超时问题（循环依赖）"
    echo "  错误信息："
    echo "$ERROR_LOG" | grep -i "webhook.*not accessible\|timed out.*webhook\|admission.*webhook.*not accessible" | tail -5
    echo ""
    echo_warn "这是循环依赖问题："
    echo "  - Manager 启动时需要访问 webhook 服务"
    echo "  - 但 webhook 服务需要 Manager 运行才能工作"
    echo ""
    echo_warn "可能的解决方案："
    echo "  1. 检查是否有配置可以增加超时时间"
    echo "  2. 检查是否有配置可以禁用 webhook 检查"
    echo "  3. 先修复其他启动问题，让 Manager 能成功启动一次"
    WEBHOOK_ISSUE=true
else
    echo_info "✓ 未检测到 webhook 超时问题"
    WEBHOOK_ISSUE=false
fi

# 检查资源不足
if echo "$ERROR_LOG" | grep -qi "out of.*memory\|OOM\|resource.*not.*available"; then
    echo_error "✗ 检测到资源不足问题"
    echo "  错误信息："
    echo "$ERROR_LOG" | grep -i "out of.*memory\|OOM\|resource.*not.*available" | tail -5
    echo ""
    echo_warn "修复建议："
    echo "  - 增加节点资源"
    echo "  - 或减少其他工作负载"
    RESOURCE_ISSUE=true
else
    echo_info "✓ 未检测到资源不足问题"
    RESOURCE_ISSUE=false
fi

# 检查其他致命错误
FATAL_ERRORS=$(echo "$ERROR_LOG" | grep -i "fatal\|panic\|error starting" | tail -5)
if [ -n "$FATAL_ERRORS" ]; then
    echo_error "✗ 检测到其他致命错误"
    echo "  错误信息："
    echo "$FATAL_ERRORS"
    OTHER_ISSUE=true
else
    echo_info "✓ 未检测到其他致命错误"
    OTHER_ISSUE=false
fi

# 4. 检查 Pod 详情
echo ""
echo_info "3. 检查 Pod 状态详情"
kubectl get pod -n longhorn-system $MANAGER_POD -o yaml | grep -A 20 "containerStatuses:" | head -30

# 5. 检查容器状态
echo ""
echo_info "4. 检查各个容器状态"
kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{range .status.containerStatuses[*]}{.name}{": "}{.state}{"\n"}{end}' || echo "无法获取容器状态"

# 6. 检查事件
echo ""
echo_info "5. 查看 Pod 事件"
kubectl describe pod -n longhorn-system $MANAGER_POD | grep -A 30 "Events:" | head -35

# 7. 检查节点资源
echo ""
echo_info "6. 检查节点资源"
NODE_NAME=$(kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{.spec.nodeName}')
if [ -n "$NODE_NAME" ]; then
    echo_info "节点: $NODE_NAME"
    kubectl describe node $NODE_NAME | grep -A 10 "Allocated resources:" || echo "无法获取资源信息"
fi

# 8. 总结和建议
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="

echo ""
if [ "$DNS_ISSUE" = true ]; then
    echo_error "主要问题：DNS 解析失败"
    echo ""
    echo_info "立即修复："
    echo "  sudo ./scripts/fix-k3s-dns-for-longhorn.sh"
elif [ "$ISCSI_ISSUE" = true ]; then
    echo_error "主要问题：缺少 open-iscsi"
    echo ""
    echo_info "立即修复："
    echo "  # SSH 到节点: $NODE_NAME"
    echo "  sudo apt-get install -y open-iscsi"
    echo "  sudo systemctl enable iscsid && sudo systemctl start iscsid"
    echo "  kubectl delete pod -n longhorn-system $MANAGER_POD"
elif [ "$WEBHOOK_ISSUE" = true ]; then
    echo_error "主要问题：Webhook 循环依赖"
    echo ""
    echo_warn "这是已知的启动顺序问题。需要："
    echo "  1. 先修复其他问题（DNS、open-iscsi 等）"
    echo "  2. 确保 Manager 能成功启动"
    echo "  3. Manager 成功启动后，webhook 会自动可用"
    echo ""
    echo_info "检查是否有其他阻止 Manager 启动的问题..."
elif [ "$RESOURCE_ISSUE" = true ]; then
    echo_error "主要问题：资源不足"
    echo ""
    echo_info "需要增加节点资源或减少其他工作负载"
else
    echo_warn "未识别出明确的错误模式，请查看上面的日志和事件"
fi

echo ""
echo_info "查看完整日志的命令："
echo "  kubectl logs -n longhorn-system $MANAGER_POD --tail=200"


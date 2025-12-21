#!/bin/bash

# 修复 longhorn-manager CrashLoopBackOff 问题

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
echo_info "修复 longhorn-manager CrashLoopBackOff"
echo_info "=========================================="
echo ""

# 1. 获取 Manager Pod
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$MANAGER_POD" ]; then
    echo_error "未找到 longhorn-manager Pod"
    exit 1
fi

echo_info "Manager Pod: $MANAGER_POD"

# 2. 查看日志
echo ""
echo_info "1. 查看 Manager Pod 日志（最后 50 行）"
echo "---"
kubectl logs -n longhorn-system $MANAGER_POD --tail=50 2>&1 | tail -30
echo "---"

# 3. 查看 Pod 详情
echo ""
echo_info "2. 查看 Pod 详情和事件"
kubectl describe pod -n longhorn-system $MANAGER_POD | grep -A 20 "Events:" | head -25

# 4. 检查常见错误
echo ""
echo_info "3. 检查常见错误原因"

# 4.1 检查是否是 DNS 问题
if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "dns\|resolve\|unable to resolve"; then
    echo_error "检测到 DNS 解析问题"
    echo_info "建议运行: sudo ./scripts/fix-k3s-dns-for-longhorn.sh"
fi

# 4.2 检查是否是 webhook 问题
if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "webhook\|admission.*not accessible"; then
    echo_error "检测到 Webhook 连接问题"
    echo_info "这是循环依赖：Manager 需要 webhook，但 webhook 需要 Manager"
    echo_info "需要等待 Manager 先启动成功"
fi

# 4.3 检查是否是 open-iscsi 问题
if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "iscsi\|iscsiadm"; then
    echo_error "检测到 open-iscsi 问题"
    echo_info "需要在节点上安装 open-iscsi"
    echo_info "Ubuntu/Debian: sudo apt-get install -y open-iscsi && sudo systemctl enable iscsid && sudo systemctl start iscsid"
fi

# 5. 检查 Endpoints
echo ""
echo_info "4. 检查 admission-webhook Endpoints"
ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
if [ -z "$ENDPOINTS" ]; then
    echo_error "✗ Endpoints 为空"
    echo_info "原因：Manager Pod 虽然匹配选择器，但状态不是 Ready"
else
    echo_info "✓ Endpoints: $ENDPOINTS"
fi

# 6. 检查 Manager 容器状态
echo ""
echo_info "5. 检查容器状态"
kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{range .status.containerStatuses[*]}{.name}{": "}{.state}{"\n"}{end}'

# 7. 提供修复建议
echo ""
echo_info "=========================================="
echo_info "修复建议"
echo_info "=========================================="

echo ""
echo_warn "根据日志错误选择修复方案："
echo ""
echo "1. 如果是 DNS 问题："
echo "   sudo ./scripts/fix-k3s-dns-for-longhorn.sh"
echo ""
echo "2. 如果是 open-iscsi 问题："
echo "   # 在节点上执行"
echo "   sudo apt-get install -y open-iscsi"
echo "   sudo systemctl enable iscsid && sudo systemctl start iscsid"
echo "   kubectl delete pod -n longhorn-system $MANAGER_POD"
echo ""
echo "3. 如果是 webhook 循环依赖问题："
echo "   # 需要先让 Manager 启动成功（修复其他问题）"
echo "   # 然后等待 webhook 就绪"
echo ""
echo "4. 如果所有方法都失败："
echo "   # 重新安装 Longhorn"
echo "   ./scripts/fix-longhorn-admission-webhook-missing.sh"


#!/bin/bash

# 诊断 longhorn-manager 重启问题
# 重点检查 admission webhook 相关的问题

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

echo_step() {
    echo -e "${BLUE}[步骤]${NC} $1"
}

echo ""
echo_info "=========================================="
echo_info "Longhorn Manager 重启问题诊断工具"
echo_info "=========================================="
echo ""

# 1. 检查 longhorn-manager Pod 状态
echo_step "1. 检查 longhorn-manager Pod 状态"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$MANAGER_POD" ]; then
    echo_error "未找到 longhorn-manager Pod"
    echo "检查所有 Pods:"
    kubectl get pods -n longhorn-system
    exit 1
fi

echo_info "找到 Manager Pod: $MANAGER_POD"
kubectl get pod -n longhorn-system $MANAGER_POD

# 2. 查看最新日志
echo ""
echo_step "2. 查看 longhorn-manager 最新日志（最后 50 行）"
echo "---"
kubectl logs -n longhorn-system $MANAGER_POD --tail=50 2>&1 | tail -30
echo "---"

# 3. 检查 admission-webhook 相关资源
echo ""
echo_step "3. 检查 admission-webhook 相关资源"

# 3.1 检查 Service
echo_info "3.1 检查 longhorn-admission-webhook Service"
kubectl get svc -n longhorn-system longhorn-admission-webhook 2>&1 || echo_warn "Service 不存在"

# 3.2 检查 Endpoints
echo ""
echo_info "3.2 检查 longhorn-admission-webhook Endpoints"
ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
if [ -z "$ENDPOINTS" ]; then
    echo_error "✗ Endpoints 为空（这是问题所在！）"
else
    echo_info "✓ Endpoints: $ENDPOINTS"
fi

# 3.3 检查 Pods
echo ""
echo_info "3.3 检查 admission-webhook Pods"
WEBHOOK_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-admission-webhook -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "$WEBHOOK_PODS" ]; then
    echo_error "✗ 未找到 admission-webhook Pods"
    echo "这可能是根本原因！"
else
    echo_info "✓ 找到 Pods: $WEBHOOK_PODS"
    for pod in $WEBHOOK_PODS; do
        echo ""
        echo "Pod: $pod"
        kubectl get pod -n longhorn-system $pod
        echo ""
        echo "Pod 状态详情:"
        kubectl describe pod -n longhorn-system $pod | grep -A 10 "Status:\|Events:" | head -15
    done
fi

# 3.4 检查 DaemonSet/Deployment
echo ""
echo_info "3.4 检查 admission-webhook DaemonSet/Deployment"
kubectl get daemonset,deployment -n longhorn-system | grep admission-webhook || echo_warn "未找到 DaemonSet/Deployment"

# 4. 检查 Manager Pod 详情
echo ""
echo_step "4. 检查 longhorn-manager Pod 详情"
echo_info "查看 Pod 事件:"
kubectl describe pod -n longhorn-system $MANAGER_POD | grep -A 20 "Events:" | head -25

# 5. 检查网络连接
echo ""
echo_step "5. 测试网络连接"

if [ -n "$WEBHOOK_PODS" ]; then
    WEBHOOK_POD=$(echo $WEBHOOK_PODS | awk '{print $1}')
    echo_info "测试从 Manager Pod 到 Webhook Service 的连接..."
    echo "---"
    kubectl exec -n longhorn-system $MANAGER_POD -- wget -qO- --timeout=5 "https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/healthz" 2>&1 || echo_warn "连接失败"
    echo "---"
fi

# 6. 检查 DNS 解析
echo ""
echo_step "6. 检查 DNS 解析"
echo_info "测试 DNS 解析 longhorn-admission-webhook.longhorn-system.svc"
echo "---"
kubectl exec -n longhorn-system $MANAGER_POD -- nslookup longhorn-admission-webhook.longhorn-system.svc 2>&1 || echo_warn "DNS 解析失败"
echo "---"

# 7. 检查相关事件
echo ""
echo_step "7. 检查最近的事件"
echo_info "longhorn-system 命名空间的最近事件:"
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | tail -20

# 8. 总结和推荐操作
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="

if [ -z "$WEBHOOK_PODS" ]; then
    echo_error "问题：admission-webhook Pod 不存在"
    echo ""
    echo_warn "推荐操作："
    echo "1. 检查 DaemonSet/Deployment 是否存在"
    echo "2. 如果不存在，可能是 Longhorn 安装不完整"
    echo "3. 考虑重新安装 Longhorn"
    echo ""
    echo "命令："
    echo "  kubectl get daemonset,deployment -n longhorn-system"
    echo "  kubectl get all -n longhorn-system | grep admission"
elif [ -z "$ENDPOINTS" ]; then
    echo_error "问题：admission-webhook Service 没有 Endpoints"
    echo ""
    echo_warn "推荐操作："
    echo "1. 检查 Webhook Pod 是否正在运行"
    echo "2. 如果 Pod 未运行，查看 Pod 日志和事件"
    echo "3. 如果 Pod 有问题，删除 Pod 让其重建"
    echo ""
    echo "命令："
    for pod in $WEBHOOK_PODS; do
        echo "  kubectl logs -n longhorn-system $pod"
        echo "  kubectl describe pod -n longhorn-system $pod"
    done
else
    echo_warn "Webhook 资源存在但 Manager 仍无法连接"
    echo "可能是："
    echo "1. Webhook Pod 刚启动，还未就绪"
    echo "2. 网络策略阻止连接"
    echo "3. 证书/TLS 问题"
fi

echo ""
echo_info "更多诊断信息："
echo "  查看 Manager 完整日志: kubectl logs -n longhorn-system $MANAGER_POD --tail=100"
echo "  查看所有 Longhorn Pods: kubectl get pods -n longhorn-system"


#!/bin/bash

# 检查 admission-webhook 是否集成在 longhorn-manager 中

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
echo_info "检查 admission-webhook 的实现方式"
echo ""

# 1. 检查当前集群中的资源
echo_info "1. 检查集群中的资源"

if kubectl get namespace longhorn-system &> /dev/null; then
    echo_info "Service:"
    kubectl get svc -n longhorn-system longhorn-admission-webhook 2>/dev/null && echo "  ✓ Service 存在" || echo "  ✗ Service 不存在"
    
    echo ""
    echo_info "Endpoints:"
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -n "$ENDPOINTS" ]; then
        echo "  ✓ Endpoints: $ENDPOINTS"
        # 检查 Endpoints 指向哪个 Pod
        ENDPOINT_POD=$(kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[0].addresses[0].targetRef.name}' 2>/dev/null || echo "")
        if [ -n "$ENDPOINT_POD" ]; then
            echo "  → 指向 Pod: $ENDPOINT_POD"
            kubectl get pod -n longhorn-system $ENDPOINT_POD
        fi
    else
        echo "  ✗ Endpoints 为空"
    fi
    
    echo ""
    echo_info "检查 longhorn-manager Pod 是否监听 9502 端口:"
    MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$MANAGER_POD" ]; then
        echo "  Manager Pod: $MANAGER_POD"
        # 检查 Pod 中是否有 9502 端口
        kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{.spec.containers[*].ports[*]}' | grep -q "9502" && echo "  ✓ Manager Pod 监听 9502 端口" || echo "  ✗ Manager Pod 未监听 9502 端口"
        
        # 检查 Manager Pod 的端口定义
        echo ""
        echo_info "Manager Pod 端口配置:"
        kubectl get pod -n longhorn-system $MANAGER_POD -o json | jq -r '.spec.containers[].ports[]? | "  端口: \(.containerPort)/\(.protocol)"' 2>/dev/null || kubectl describe pod -n longhorn-system $MANAGER_POD | grep -A 5 "Ports:"
    fi
else
    echo_warn "longhorn-system 命名空间不存在"
fi

# 2. 检查 Helm Chart 中的定义
echo ""
echo_info "2. 检查 Helm Chart 中的定义"

LONGHORN_VERSION="${1:-1.10.1}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
helm repo update

echo_info "获取 Chart 清单..."
helm template longhorn longhorn/longhorn \
  --version "$LONGHORN_VERSION" \
  --namespace longhorn-system \
  > "$TEMP_DIR/manifest.yaml"

# 检查 Service 定义指向哪里
echo ""
echo_info "检查 admission-webhook Service 的选择器:"
WEBHOOK_SERVICE=$(grep -A 30 "kind: Service" "$TEMP_DIR/manifest.yaml" | grep -A 30 "longhorn-admission-webhook")
if [ -n "$WEBHOOK_SERVICE" ]; then
    echo "$WEBHOOK_SERVICE" | grep -A 10 "selector:" | head -15
    SELECTOR=$(echo "$WEBHOOK_SERVICE" | grep -A 10 "selector:" | grep -E "app:|component:" | head -5)
    echo_info "选择器: $SELECTOR"
    
    # 根据选择器查找对应的 Pod
    if [ -n "$SELECTOR" ]; then
        echo ""
        echo_info "根据选择器查找 Pod..."
        SELECTOR_APP=$(echo "$SELECTOR" | grep "app:" | sed 's/.*app: *\(.*\)/\1/' | head -1)
        SELECTOR_COMPONENT=$(echo "$SELECTOR" | grep "component:" | sed 's/.*component: *\(.*\)/\1/' | head -1)
        
        if [ -n "$SELECTOR_APP" ]; then
            echo "  选择器 app: $SELECTOR_APP"
            if kubectl get pods -n longhorn-system -l app="$SELECTOR_APP" &> /dev/null; then
                kubectl get pods -n longhorn-system -l app="$SELECTOR_APP"
            fi
        fi
        if [ -n "$SELECTOR_COMPONENT" ]; then
            echo "  选择器 component: $SELECTOR_COMPONENT"
            if kubectl get pods -n longhorn-system -l component="$SELECTOR_COMPONENT" &> /dev/null; then
                kubectl get pods -n longhorn-system -l component="$SELECTOR_COMPONENT"
            fi
        fi
    fi
else
    echo_warn "未找到 Service 定义"
fi

# 3. 检查是否有独立的 Deployment/DaemonSet
echo ""
echo_info "3. 检查是否有独立的 Deployment/DaemonSet"
grep -B 5 -A 50 "kind: Deployment" "$TEMP_DIR/manifest.yaml" | grep -B 5 -A 50 "admission.*webhook\|webhook.*admission" | head -60 || echo_warn "未找到独立的 Deployment"

grep -B 5 -A 50 "kind: DaemonSet" "$TEMP_DIR/manifest.yaml" | grep -B 5 -A 50 "admission.*webhook\|webhook.*admission" | head -60 || echo_warn "未找到独立的 DaemonSet"

# 4. 检查 ValidatingWebhookConfiguration
echo ""
echo_info "4. 检查 ValidatingWebhookConfiguration/MutatingWebhookConfiguration"
WEBHOOK_CONFIG=$(grep -A 100 "kind: ValidatingWebhookConfiguration\|kind: MutatingWebhookConfiguration" "$TEMP_DIR/manifest.yaml" | grep -i "longhorn\|admission" | head -20)
if [ -n "$WEBHOOK_CONFIG" ]; then
    echo_info "找到 Webhook Configuration:"
    echo "$WEBHOOK_CONFIG" | head -20
else
    echo_warn "未找到 Webhook Configuration"
fi

# 5. 总结
echo ""
echo_info "=========================================="
echo_info "总结"
echo_info "=========================================="

if kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[0].addresses[0].targetRef.name}' 2>/dev/null | grep -q "longhorn-manager"; then
    echo_info "✓ admission-webhook 可能集成在 longhorn-manager 中"
    echo ""
    echo_warn "如果 Manager 无法访问 webhook，可能是："
    echo "  1. Manager Pod 本身有问题"
    echo "  2. 端口 9502 未正确暴露"
    echo "  3. 网络策略阻止连接"
else
    echo_warn "admission-webhook 可能是独立组件，但 Pod 不存在"
    echo ""
    echo_info "需要检查："
    echo "  1. Deployment/DaemonSet 是否创建"
    echo "  2. Pod 是否被调度"
    echo "  3. 是否有错误阻止 Pod 启动"
fi


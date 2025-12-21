#!/bin/bash

# 检查并修复 admission-webhook 选择器问题

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
echo_info "检查和修复 admission-webhook 选择器问题"
echo_info "=========================================="
echo ""

# 1. 检查 Service 选择器
echo_info "1. 检查 Service 选择器"
SELECTOR=$(kubectl get svc -n longhorn-system longhorn-admission-webhook -o jsonpath='{.spec.selector}' 2>/dev/null || echo "")
echo "选择器: $SELECTOR"

# 2. 查找匹配该选择器的 Pods
echo ""
echo_info "2. 查找匹配该选择器的 Pods"
# 解析选择器
SELECTOR_KEYS=$(echo "$SELECTOR" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")
if [ -n "$SELECTOR_KEYS" ]; then
    echo "搜索标签: $SELECTOR_KEYS"
    # 构建 kubectl label 查询
    LABEL_QUERY=""
    for label in $SELECTOR_KEYS; do
        if [ -z "$LABEL_QUERY" ]; then
            LABEL_QUERY="$label"
        else
            LABEL_QUERY="$LABEL_QUERY,$label"
        fi
    done
    echo_info "查询: -l $LABEL_QUERY"
    kubectl get pods -n longhorn-system -l "$LABEL_QUERY" || echo_warn "未找到匹配的 Pods"
else
    echo_warn "无法解析选择器"
fi

# 3. 检查 Helm Chart 中是否有 Deployment/DaemonSet 定义
echo ""
echo_info "3. 检查 Helm Chart 中的定义"
LONGHORN_VERSION="${1:-1.10.1}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
helm repo update

helm template longhorn longhorn/longhorn \
  --version "$LONGHORN_VERSION" \
  --namespace longhorn-system \
  > "$TEMP_DIR/manifest.yaml"

# 搜索带有该标签的 Deployment/DaemonSet
echo_info "搜索包含该选择器标签的资源..."
grep -B 10 -A 50 "longhorn.io/admission-webhook.*longhorn-admission-webhook" "$TEMP_DIR/manifest.yaml" | grep -E "kind:|name:|app:|longhorn.io/admission-webhook" | head -20

# 4. 检查是否有 Deployment/DaemonSet 应该创建这个 Pod
echo ""
echo_info "4. 检查集群中是否有相关的 Deployment/DaemonSet"
kubectl get deployment,daemonset -n longhorn-system -o yaml | grep -A 20 "longhorn.io/admission-webhook" || echo_warn "未找到相关的 Deployment/DaemonSet"

# 5. 检查 Manager Pod 的标签
echo ""
echo_info "5. 检查 Manager Pod 的标签"
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MANAGER_POD" ]; then
    echo "Manager Pod 标签:"
    kubectl get pod -n longhorn-system $MANAGER_POD --show-labels
    echo ""
    MANAGER_LABELS=$(kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "")
    if echo "$MANAGER_LABELS" | grep -q "longhorn.io/admission-webhook"; then
        echo_info "✓ Manager Pod 有 admission-webhook 标签"
    else
        echo_warn "✗ Manager Pod 没有 admission-webhook 标签"
        echo ""
        echo_info "检查是否需要添加标签..."
    fi
fi

# 6. 检查是否有 Deployment 应该管理这个 Pod
echo ""
echo_info "6. 搜索所有 Deployment/DaemonSet"
ALL_DEPLOYMENTS=$(kubectl get deployment,daemonset -n longhorn-system -o jsonpath='{range .items[*]}{.kind}{" "}{.metadata.name}{"\n"}{end}')
echo "$ALL_DEPLOYMENTS"

# 搜索是否有 admission-webhook 相关的
ADMISSION_DEPLOYMENT=$(echo "$ALL_DEPLOYMENTS" | grep -i "admission\|webhook" || echo "")
if [ -n "$ADMISSION_DEPLOYMENT" ]; then
    echo ""
    echo_info "找到可能的 Deployment/DaemonSet:"
    echo "$ADMISSION_DEPLOYMENT"
    for item in $ADMISSION_DEPLOYMENT; do
        KIND=$(echo $item | awk '{print $1}')
        NAME=$(echo $item | awk '{print $2}')
        if [ -n "$NAME" ]; then
            echo ""
            echo "检查 $KIND: $NAME"
            kubectl get $KIND -n longhorn-system $NAME -o yaml | grep -A 10 "selector:" | head -15
        fi
    done
else
    echo_warn "未找到 admission-webhook 相关的 Deployment/DaemonSet"
fi

# 7. 总结和建议
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="

if [ -z "$ADMISSION_DEPLOYMENT" ]; then
    echo_error "问题：没有找到创建 admission-webhook Pod 的 Deployment/DaemonSet"
    echo ""
    echo_warn "可能的原因："
    echo "  1. Helm Chart 安装不完整"
    echo "  2. 在 v1.10.1 中 admission-webhook 应该由某个组件管理，但该组件未创建"
    echo "  3. 可能是 Manager 的一部分，但配置不正确"
    echo ""
    echo_info "建议："
    echo "  1. 检查 Helm Chart 是否应该创建独立的 Deployment"
    echo "  2. 或者检查是否应该修改 Manager 的标签以匹配 Service 选择器"
    echo "  3. 如果确认是集成在 Manager 中，可能需要修改 Service 选择器"
fi


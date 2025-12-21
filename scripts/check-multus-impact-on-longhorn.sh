#!/bin/bash

# 检查 Multus 是否影响 Longhorn Manager 启动

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
echo_info "检查 Multus 是否影响 Longhorn Manager"
echo_info "=========================================="
echo ""

# 1. 检查 Multus 安装位置和方式
echo_info "1. 检查 Multus 安装情况"
echo ""

MULTUS_DS=$(kubectl get daemonset -n kube-system -l app=multus -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_DS" ]; then
    echo_info "Multus DaemonSet: $MULTUS_DS"
    kubectl get $MULTUS_DS -n kube-system
else
    echo_warn "未找到 Multus DaemonSet"
fi

echo ""
MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus -o name 2>/dev/null || echo "")
if [ -n "$MULTUS_PODS" ]; then
    echo_info "Multus Pods:"
    for pod in $MULTUS_PODS; do
        kubectl get $pod -n kube-system
    done
else
    echo_warn "未找到 Multus Pods"
fi

# 2. 检查 Multus Pod 状态
echo ""
echo_info "2. 检查 Multus Pod 状态和日志"
echo ""

if [ -n "$MULTUS_PODS" ]; then
    for pod in $MULTUS_PODS; do
        POD_NAME=$(echo $pod | cut -d'/' -f2)
        echo_info "检查 Pod: $POD_NAME"
        STATUS=$(kubectl get pod -n kube-system $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "  状态: $STATUS"
        
        if [ "$STATUS" != "Running" ]; then
            echo_warn "  ⚠️  Multus Pod 未正常运行，可能影响网络"
            echo "  查看日志: kubectl logs -n kube-system $POD_NAME --tail=30"
        fi
        
        # 检查是否有错误日志
        ERRORS=$(kubectl logs -n kube-system $POD_NAME --tail=50 2>&1 | grep -i "error\|fail" | head -5 || echo "")
        if [ -n "$ERRORS" ]; then
            echo_warn "  ⚠️  发现错误日志:"
            echo "$ERRORS" | sed 's/^/    /'
        fi
    done
else
    echo_warn "无法检查 Multus Pod 状态"
fi

# 3. 检查 Multus 是否影响网络连接
echo ""
echo_info "3. 检查 Multus 网络配置"
echo ""

# 检查 CNI 配置
echo_info "检查 CNI 配置（在节点上执行）:"
echo "  sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/"
echo "  sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf 2>/dev/null || echo '未找到 Multus 配置'"

# 检查 Multus 是否配置了默认网络
MULTUS_CONF=$(kubectl get pod -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MULTUS_CONF" ]; then
    echo ""
    echo_info "检查 Multus Pod 中的 CNI 配置:"
    echo "  kubectl exec -n kube-system $MULTUS_CONF -- ls -la /host/etc/cni/net.d/ 2>/dev/null || echo '无法访问配置目录'"
fi

# 4. 检查 Longhorn Manager Pod 的网络配置
echo ""
echo_info "4. 检查 Longhorn Manager Pod 的网络配置"
echo ""

MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MANAGER_POD" ]; then
    echo_info "Manager Pod: $MANAGER_POD"
    
    # 检查 Pod 的 annotations（看是否使用了 Multus 网络）
    MULTUS_ANN=$(kubectl get pod -n longhorn-system $MANAGER_POD -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks}' 2>/dev/null || echo "")
    if [ -n "$MULTUS_ANN" ]; then
        echo_warn "  ⚠️  Manager Pod 使用了 Multus 网络，这可能影响连接"
        echo "  Multus 注解: $MULTUS_ANN"
    else
        echo_info "  ✓ Manager Pod 使用默认网络（未使用 Multus）"
    fi
    
    # 检查 Pod 的网络接口
    echo ""
    echo_info "检查 Manager Pod 的网络接口:"
    echo "  kubectl exec -n longhorn-system $MANAGER_POD -- ip addr show 2>/dev/null || echo '无法访问 Pod'"
    
    # 检查 Pod 能否连接到 Service
    echo ""
    echo_info "测试 Manager Pod 能否连接到 admission-webhook Service:"
    echo "  kubectl exec -n longhorn-system $MANAGER_POD -- curl -k -s -o /dev/null -w '%{http_code}' https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/healthz 2>&1 || echo '连接失败'"
else
    echo_warn "未找到 Longhorn Manager Pod"
fi

# 5. 检查 Service 和 Endpoints
echo ""
echo_info "5. 检查 admission-webhook Service 和 Endpoints"
echo ""

WEBHOOK_SVC=$(kubectl get svc -n longhorn-system longhorn-admission-webhook -o name 2>/dev/null || echo "")
if [ -n "$WEBHOOK_SVC" ]; then
    echo_info "Service 存在: $WEBHOOK_SVC"
    kubectl get $WEBHOOK_SVC -n longhorn-system
    
    echo ""
    ENDPOINTS=$(kubectl get endpoints -n longhorn-system longhorn-admission-webhook -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -z "$ENDPOINTS" ]; then
        echo_error "  ✗ Endpoints 为空，Service 无法路由到 Pod"
        echo_warn "  这可能是因为："
        echo "    1. Manager Pod 未正常运行"
        echo "    2. Service 选择器不匹配 Pod 标签"
        echo "    3. 网络问题（包括 Multus 配置问题）"
    else
        echo_info "  ✓ Endpoints: $ENDPOINTS"
    fi
else
    echo_warn "未找到 admission-webhook Service"
fi

# 6. 诊断结论
echo ""
echo_info "=========================================="
echo_info "诊断结论"
echo_info "=========================================="
echo ""

if [ -z "$MULTUS_PODS" ] || [ "$STATUS" != "Running" ]; then
    echo_warn "Multus 可能有问题，但通常不会直接影响 Longhorn Manager"
    echo "  - Multus 主要用于多网络接口，不影响默认 Pod 网络"
    echo "  - 除非 Manager Pod 配置了 Multus 网络，否则 Multus 不应该影响它"
else
    echo_info "Multus 运行正常"
fi

echo ""
echo_warn "可能影响 Longhorn Manager 的因素："
echo "  1. ❌ webhook 循环依赖（已确认）"
echo "  2. ❓ DNS 解析问题（k3s systemd-resolved）"
echo "  3. ❓ 网络连接问题（Multus 配置错误可能导致）"
echo "  4. ❓ Service/Endpoints 选择器不匹配"
echo ""

echo_info "建议的排查顺序："
echo "  1. 先修复 webhook 循环依赖问题（可能需要降级 Longhorn）"
echo "  2. 检查 DNS 是否已修复（运行: ./scripts/fix-k3s-dns-for-longhorn.sh）"
echo "  3. 如果 Manager Pod 使用了 Multus 网络，检查 Multus 配置"
echo "  4. 验证 Service 选择器是否匹配 Manager Pod 标签"
echo ""

# 7. 提供快速诊断命令
echo_info "快速诊断命令："
echo ""
echo "# 检查 Multus Pod 状态"
echo "kubectl get pods -n kube-system -l app=multus"
echo ""
echo "# 查看 Multus 日志"
echo "kubectl logs -n kube-system -l app=multus --tail=50"
echo ""
echo "# 检查 Manager Pod 是否使用 Multus"
echo "kubectl get pod -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks}'"
echo ""
echo "# 测试 Manager Pod 网络连接"
if [ -n "$MANAGER_POD" ]; then
    echo "kubectl exec -n longhorn-system $MANAGER_POD -- nslookup longhorn-admission-webhook.longhorn-system.svc"
fi
echo ""


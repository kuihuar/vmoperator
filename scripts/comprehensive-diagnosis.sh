#!/bin/bash

# 综合诊断脚本 - 找出所有问题的根本原因

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
echo_info "综合诊断 - 找出所有问题的根本原因"
echo_info "=========================================="
echo ""

# 1. 检查 Multus Pod 崩溃原因
echo_info "=========================================="
echo_info "1. 诊断 Multus Pod 崩溃"
echo_info "=========================================="
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "Multus Pod: $MULTUS_POD"
    kubectl get pod -n kube-system $MULTUS_POD
    
    echo ""
    echo_info "查看崩溃前的日志:"
    kubectl logs -n kube-system $MULTUS_POD --tail=50 2>&1 | head -30
    
    echo ""
    echo_info "查看 Pod 事件:"
    kubectl describe pod -n kube-system $MULTUS_POD 2>&1 | grep -A 20 "Events:" | head -25
    
    echo ""
    echo_warn "检查常见问题:"
    
    # 检查是否是 CNI 路径问题
    if kubectl logs -n kube-system $MULTUS_POD 2>&1 | grep -qi "failed to find.*CNI\|could not find.*plugin\|/etc/cni/net.d"; then
        echo_error "  ✗ 可能是 CNI 路径配置问题（k3s 特定问题）"
        echo_info "    解决方案: 运行 ./scripts/fix-multus-k3s.sh"
    fi
else
    echo_warn "未找到 Multus Pod"
fi

# 2. 检查 Longhorn Manager 重启原因
echo ""
echo_info "=========================================="
echo_info "2. 诊断 Longhorn Manager 重启"
echo_info "=========================================="
echo ""

MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MANAGER_POD" ]; then
    echo_info "Manager Pod: $MANAGER_POD"
    kubectl get pod -n longhorn-system $MANAGER_POD
    
    echo ""
    echo_info "查看最近的错误日志:"
    kubectl logs -n longhorn-system $MANAGER_POD --tail=50 2>&1 | grep -i "error\|fatal\|panic\|crash" | head -20 || kubectl logs -n longhorn-system $MANAGER_POD --tail=30
    
    echo ""
    echo_info "查看 Pod 事件:"
    kubectl describe pod -n longhorn-system $MANAGER_POD 2>&1 | grep -A 20 "Events:" | head -25
    
    echo ""
    echo_warn "检查常见问题:"
    
    # 检查 webhook 问题
    if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "webhook.*not accessible\|admission.*timeout\|endpoint.*unavailable"; then
        echo_error "  ✗ Webhook 连接问题"
    fi
    
    # 检查 DNS 问题
    if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "dns.*error\|resolve.*failed\|nameserver.*timeout"; then
        echo_error "  ✗ DNS 解析问题（k3s systemd-resolved）"
        echo_info "    解决方案: 运行 ./scripts/fix-k3s-dns-for-longhorn.sh"
    fi
    
    # 检查 iscsi 问题
    if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "iscsi.*not found\|iscsiadm.*error"; then
        echo_error "  ✗ open-iscsi 未安装"
        echo_info "    解决方案: sudo apt-get install -y open-iscsi && sudo systemctl enable iscsid && sudo systemctl start iscsid"
    fi
else
    echo_warn "未找到 Longhorn Manager Pod"
fi

# 3. 检查 longhorn-driver-deployer Init 问题
echo ""
echo_info "=========================================="
echo_info "3. 诊断 longhorn-driver-deployer Init 问题"
echo_info "=========================================="
echo ""

DEPLOYER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$DEPLOYER_POD" ]; then
    echo_info "Driver Deployer Pod: $DEPLOYER_POD"
    kubectl get pod -n longhorn-system $DEPLOYER_POD
    
    echo ""
    echo_info "查看 Init Container 日志:"
    INIT_CONTAINERS=$(kubectl get pod -n longhorn-system $DEPLOYER_POD -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || echo "")
    if [ -n "$INIT_CONTAINERS" ]; then
        for init in $INIT_CONTAINERS; do
            echo_info "  Init Container: $init"
            kubectl logs -n longhorn-system $DEPLOYER_POD -c $init --tail=30 2>&1 | head -20 || echo "    无日志或已完成"
            echo ""
        done
    else
        echo_warn "  未找到 Init Containers"
    fi
    
    echo_info "查看 Pod 事件:"
    kubectl describe pod -n longhorn-system $DEPLOYER_POD 2>&1 | grep -A 20 "Events:" | head -25
    
    echo ""
    echo_warn "检查常见问题:"
    
    # 检查是否是等待 longhorn-backend 就绪
    if kubectl logs -n longhorn-system $DEPLOYER_POD -c wait-longhorn-backend 2>&1 | grep -qi "waiting\|not ready\|timeout"; then
        echo_error "  ✗ 等待 longhorn-backend 就绪超时"
        echo_info "    原因: longhorn-manager 未正常运行，导致 backend 未就绪"
    fi
    
    # 检查网络问题
    if kubectl describe pod -n longhorn-system $DEPLOYER_POD 2>&1 | grep -qi "network.*unavailable\|failed to pull\|image pull"; then
        echo_error "  ✗ 网络或镜像拉取问题"
    fi
else
    echo_warn "未找到 longhorn-driver-deployer Pod"
fi

# 4. 检查系统资源
echo ""
echo_info "=========================================="
echo_info "4. 检查系统资源"
echo_info "=========================================="
echo ""

echo_info "节点资源:"
kubectl top nodes 2>/dev/null || echo_warn "无法获取节点资源（需要 metrics-server）"

echo ""
echo_info "检查节点状态:"
kubectl get nodes -o wide

# 5. 检查网络连接
echo ""
echo_info "=========================================="
echo_info "5. 检查网络连接（如果 Manager Pod 存在）"
echo_info "=========================================="
echo ""

if [ -n "$MANAGER_POD" ]; then
    echo_info "测试 DNS 解析:"
    kubectl exec -n longhorn-system $MANAGER_POD -- nslookup kubernetes.default 2>&1 | head -10 || echo_error "  ✗ DNS 解析失败"
    
    echo ""
    echo_info "测试 Service 连接:"
    kubectl exec -n longhorn-system $MANAGER_POD -- curl -k -s -o /dev/null -w "HTTP Code: %{http_code}\n" https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/healthz 2>&1 || echo_error "  ✗ Service 连接失败"
fi

# 6. 总结和建议
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

echo_warn "发现的问题："
echo ""
echo "1. Multus Pod 崩溃:"
if [ -n "$MULTUS_POD" ]; then
    if kubectl logs -n kube-system $MULTUS_POD 2>&1 | grep -qi "failed to find.*CNI"; then
        echo "   - 原因: CNI 路径配置错误（k3s 特定问题）"
        echo "   - 修复: ./scripts/fix-multus-k3s.sh"
    else
        echo "   - 查看上方日志确定原因"
    fi
else
    echo "   - 未找到 Pod"
fi

echo ""
echo "2. Longhorn Manager 重启:"
if [ -n "$MANAGER_POD" ]; then
    ISSUES=""
    if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "dns\|resolve"; then
        ISSUES="${ISSUES}DNS问题 "
    fi
    if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "webhook"; then
        ISSUES="${ISSUES}Webhook问题 "
    fi
    if kubectl logs -n longhorn-system $MANAGER_POD 2>&1 | grep -qi "iscsi"; then
        ISSUES="${ISSUES}iscsi问题 "
    fi
    if [ -z "$ISSUES" ]; then
        echo "   - 查看上方日志确定原因"
    else
        echo "   - 可能原因: $ISSUES"
    fi
else
    echo "   - 未找到 Pod"
fi

echo ""
echo "3. Driver Deployer Init 卡住:"
if [ -n "$DEPLOYER_POD" ]; then
    echo "   - 原因: 通常是因为 longhorn-manager 未正常运行"
    echo "   - 修复: 先修复 Manager 问题，然后删除 Deployer Pod 让它重新创建"
else
    echo "   - 未找到 Pod"
fi

echo ""
echo_info "建议的修复顺序："
echo "  1. 修复 DNS 问题（如果是 k3s systemd-resolved）"
echo "     ./scripts/fix-k3s-dns-for-longhorn.sh"
echo ""
echo "  2. 修复 Multus CNI 路径问题"
echo "     ./scripts/fix-multus-k3s.sh"
echo ""
echo "  3. 安装 open-iscsi（如果缺失）"
echo "     sudo apt-get install -y open-iscsi"
echo "     sudo systemctl enable iscsid && sudo systemctl start iscsid"
echo ""
echo "  4. 重启相关 Pod"
echo "     kubectl delete pod -n kube-system $MULTUS_POD"
echo "     kubectl delete pod -n longhorn-system -l app=longhorn-manager"
echo "     kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer"
echo ""


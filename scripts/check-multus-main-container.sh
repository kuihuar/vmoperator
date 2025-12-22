#!/bin/bash

# 检查 Multus 主容器失败原因

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "检查 Multus 主容器失败原因"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MULTUS_POD" ]; then
    echo_error "未找到 Multus Pod"
    exit 1
fi

echo_info "Pod: $MULTUS_POD"
echo ""

# 1. 查看 Pod 状态
echo_info "1. Pod 状态"
echo ""
kubectl get pod -n kube-system $MULTUS_POD -o wide
echo ""

# 2. 查看主容器日志
echo_info "2. 主容器日志 (kube-multus)"
echo ""
kubectl logs -n kube-system $MULTUS_POD -c kube-multus --tail=50 2>&1 || echo_warn "无法获取日志或容器未启动"
echo ""

# 3. 查看所有容器状态
echo_info "3. 所有容器状态"
echo ""
kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state}{"\n"}{end}'
echo ""

# 4. 查看 Pod 事件
echo_info "4. Pod 事件"
echo ""
kubectl describe pod -n kube-system $MULTUS_POD | grep -A 30 "Events:" || echo_warn "无法获取事件"
echo ""

# 5. 检查配置文件和 kubeconfig
echo_info "5. 检查配置文件"
echo ""

MULTUS_CONF="/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf"
if [ -f "$MULTUS_CONF" ]; then
    echo_info "  ✓ 配置文件存在"
    KUBECONFIG_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // ""' 2>/dev/null || echo "")
    echo_info "  kubeconfig 路径: $KUBECONFIG_PATH"
    
    if [ -n "$KUBECONFIG_PATH" ]; then
        if [ -f "$KUBECONFIG_PATH" ]; then
            echo_info "  ✓ kubeconfig 文件存在"
        else
            echo_error "  ✗ kubeconfig 文件不存在: $KUBECONFIG_PATH"
        fi
    fi
else
    echo_error "  ✗ 配置文件不存在"
fi

echo ""


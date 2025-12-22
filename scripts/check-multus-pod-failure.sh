#!/bin/bash

# 检查 Multus Pod 失败原因

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "检查 Multus Pod 失败原因"
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

# 2. 查看 init 容器日志
echo_info "2. init 容器日志 (install-multus-binary)"
echo ""
kubectl logs -n kube-system $MULTUS_POD -c install-multus-binary --tail=50 || echo_warn "无法获取日志"
echo ""

# 3. 查看主容器日志（如果有）
echo_info "3. 主容器状态"
echo ""
kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.containerStatuses[*].name}' 2>/dev/null || echo_warn "主容器未启动"
echo ""

# 4. 查看 Pod 事件
echo_info "4. Pod 事件"
echo ""
kubectl describe pod -n kube-system $MULTUS_POD | grep -A 20 "Events:" || echo_warn "无法获取事件"
echo ""

# 5. 检查挂载点
echo_info "5. 检查 DaemonSet 挂载配置"
echo ""
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="install-multus-binary")]}' | jq '.volumeMounts' 2>/dev/null || echo_warn "无法获取挂载配置"
echo ""

# 6. 检查挂载的主机路径是否存在
echo_info "6. 检查主机路径"
echo ""

CNI_BIN_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cnibin")].hostPath.path}' 2>/dev/null || echo "")
if [ -n "$CNI_BIN_PATH" ]; then
    echo_info "  CNI 二进制目录: $CNI_BIN_PATH"
    if [ -d "$CNI_BIN_PATH" ]; then
        echo_info "  ✓ 目录存在"
        sudo ls -la "$CNI_BIN_PATH" | head -5
    else
        echo_error "  ✗ 目录不存在"
    fi
fi

echo ""


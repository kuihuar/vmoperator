#!/bin/bash

# 检查 Multus 是否真的已安装

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 Multus 安装状态"
echo_info "=========================================="
echo ""

# 1. 检查 DaemonSet
echo_info "1. 检查 Multus DaemonSet"
echo ""

if kubectl get daemonset -n kube-system kube-multus-ds > /dev/null 2>&1; then
    echo_info "  ✓ DaemonSet 存在"
    kubectl get daemonset -n kube-system kube-multus-ds
    echo ""
    
    # 检查期望的 Pod 数量
    DESIRED=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    READY=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    echo_info "  期望 Pods: $DESIRED, 就绪 Pods: $READY"
    
    if [ "$DESIRED" = "$READY" ] && [ "$READY" != "0" ]; then
        echo_info "  ✓ 所有 Pods 已就绪"
    else
        echo_warn "  ⚠️  Pods 未全部就绪"
    fi
else
    echo_error "  ✗ DaemonSet 不存在（未安装）"
fi

# 2. 检查 Pods
echo ""
echo_info "2. 检查 Multus Pods"
echo ""

PODS=$(kubectl get pods -n kube-system -l app=multus 2>/dev/null || echo "")
if [ -n "$PODS" ]; then
    echo_info "  Pods:"
    kubectl get pods -n kube-system -l app=multus
    echo ""
    
    # 检查 Pod 状态
    RUNNING=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$RUNNING" ]; then
        echo_info "  ✓ 有 Running 状态的 Pod"
    else
        echo_warn "  ⚠️  没有 Running 状态的 Pod"
        echo_info "  查看 Pod 状态:"
        kubectl get pods -n kube-system -l app=multus -o wide
    fi
else
    echo_error "  ✗ 没有找到 Multus Pods（未安装或未启动）"
fi

# 3. 检查配置文件
echo ""
echo_info "3. 检查 Multus 配置文件"
echo ""

MULTUS_CONF="/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf"
if [ -f "$MULTUS_CONF" ]; then
    echo_info "  ✓ 配置文件存在: $MULTUS_CONF"
    sudo ls -lh "$MULTUS_CONF"
else
    echo_warn "  ⚠️  配置文件不存在"
fi

# 4. 检查 kubeconfig
echo ""
echo_info "4. 检查 kubeconfig"
echo ""

KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  ✓ kubeconfig 文件存在: $KUBECONFIG_FILE"
    sudo ls -lh "$KUBECONFIG_FILE"
else
    echo_warn "  ⚠️  kubeconfig 文件不存在"
fi

# 5. 检查二进制文件
echo ""
echo_info "5. 检查 Multus 二进制文件"
echo ""

MULTUS_BIN="/var/lib/rancher/k3s/data/current/bin/multus-shim"
if [ -f "$MULTUS_BIN" ]; then
    echo_info "  ✓ 二进制文件存在: $MULTUS_BIN"
else
    echo_warn "  ⚠️  二进制文件不存在"
fi

# 6. 总结
echo ""
echo_info "=========================================="
echo_info "安装状态总结"
echo_info "=========================================="
echo ""

DS_EXISTS=$(kubectl get daemonset -n kube-system kube-multus-ds -o name 2>/dev/null || echo "")
PODS_EXIST=$(kubectl get pods -n kube-system -l app=multus -o name 2>/dev/null | head -1 || echo "")
CONF_EXISTS=$([ -f "$MULTUS_CONF" ] && echo "yes" || echo "no")

if [ -n "$DS_EXISTS" ] && [ -n "$PODS_EXIST" ] && [ "$CONF_EXISTS" = "yes" ]; then
    echo_info "✓ Multus 已安装"
    echo_info "  - DaemonSet: 存在"
    echo_info "  - Pods: 存在"
    echo_info "  - 配置文件: 存在"
    echo ""
    echo_info "关于警告："
    echo_warn "  '无法访问 CRD' 的警告是正常的"
    echo_info "  因为验证命令需要 list 权限，但 Multus 实际只需要 get/update"
    echo_info "  只要 Pods 运行正常，Multus 就可以正常工作"
elif [ -n "$DS_EXISTS" ]; then
    echo_warn "⚠️  Multus 部分安装"
    echo_info "  - DaemonSet: 存在"
    if [ -z "$PODS_EXIST" ]; then
        echo_warn "  - Pods: 不存在（可能正在创建中）"
    fi
    if [ "$CONF_EXISTS" = "no" ]; then
        echo_warn "  - 配置文件: 不存在"
    fi
else
    echo_error "✗ Multus 未安装"
fi

echo ""


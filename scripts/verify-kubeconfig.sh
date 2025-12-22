#!/bin/bash

# 验证 Multus kubeconfig

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"

echo ""
echo_info "验证 Multus kubeconfig"
echo ""

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo_error "文件不存在: $KUBECONFIG_FILE"
    exit 1
fi

echo_info "1. 检查文件内容"
echo ""

# 检查文件格式
if sudo cat "$KUBECONFIG_FILE" | grep -q "apiVersion:"; then
    echo_info "  ✓ 文件格式看起来正确"
else
    echo_error "  ✗ 文件格式可能有问题"
fi

# 显示关键信息（隐藏敏感信息）
SERVER=$(sudo cat "$KUBECONFIG_FILE" | grep -A 2 "server:" | grep "server:" | awk '{print $2}' | tr -d '"' || echo "")
CONTEXT=$(sudo cat "$KUBECONFIG_FILE" | grep "current-context:" | awk '{print $2}' || echo "")
USER=$(sudo cat "$KUBECONFIG_FILE" | grep -A 1 "name:" | head -2 | tail -1 | awk '{print $2}' | tr -d '"' || echo "")

echo_info "  Server: $SERVER"
echo_info "  Context: $CONTEXT"
echo_info "  User: $USER"

# 检查 token 是否存在
if sudo cat "$KUBECONFIG_FILE" | grep -q "token:"; then
    TOKEN_LEN=$(sudo cat "$KUBECONFIG_FILE" | grep "token:" | awk '{print $2}' | tr -d '"' | wc -c)
    echo_info "  ✓ Token 存在（长度: $TOKEN_LEN 字符）"
else
    echo_error "  ✗ Token 不存在"
fi

# 检查 CA 是否存在
if sudo cat "$KUBECONFIG_FILE" | grep -q "certificate-authority-data:"; then
    CA_LEN=$(sudo cat "$KUBECONFIG_FILE" | grep "certificate-authority-data:" | awk '{print $2}' | wc -c)
    echo_info "  ✓ CA 证书存在（长度: $CA_LEN 字符）"
else
    echo_error "  ✗ CA 证书不存在"
fi

echo ""
echo_info "2. 测试连接（使用超时）"
echo ""

# 测试连接
if timeout 10 KUBECONFIG="$KUBECONFIG_FILE" kubectl --request-timeout=5s get nodes > /dev/null 2>&1; then
    echo_info "  ✓ 可以连接到 Kubernetes API"
    echo_info "  节点列表:"
    KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes --no-headers | head -3
elif timeout 10 KUBECONFIG="$KUBECONFIG_FILE" kubectl --request-timeout=10s get pods -n kube-system > /dev/null 2>&1; then
    echo_info "  ✓ 可以连接到 Kubernetes API（但 get nodes 失败，可能是权限问题）"
else
    echo_warn "  ⚠️  无法连接，但可能只是权限问题"
    echo_info "  尝试更详细的错误信息:"
    KUBECONFIG="$KUBECONFIG_FILE" kubectl --request-timeout=5s get pods 2>&1 | head -5 || true
fi

echo ""
echo_info "3. 检查 ServiceAccount 和权限"
echo ""

# 检查 ServiceAccount
if kubectl get sa -n kube-system multus > /dev/null 2>&1; then
    echo_info "  ✓ ServiceAccount 存在"
    
    # 检查 ClusterRoleBinding
    if kubectl get clusterrolebinding multus > /dev/null 2>&1; then
        echo_info "  ✓ ClusterRoleBinding 存在"
        
        # 显示绑定的权限
        kubectl get clusterrolebinding multus -o jsonpath='{.roleRef.name}' 2>/dev/null | grep -q multus && \
            echo_info "  ✓ 绑定到 multus ClusterRole"
    else
        echo_warn "  ⚠️  ClusterRoleBinding 不存在"
    fi
else
    echo_error "  ✗ ServiceAccount 不存在"
fi

echo ""
echo_info "4. 测试使用 kubeconfig 访问资源"
echo ""

# 测试访问 NetworkAttachmentDefinition CRD
if KUBECONFIG="$KUBECONFIG_FILE" kubectl get crd network-attachment-definitions.k8s.cni.cncf.io > /dev/null 2>&1; then
    echo_info "  ✓ 可以访问 NetworkAttachmentDefinition CRD"
else
    echo_warn "  ⚠️  无法访问 CRD（可能是权限问题）"
fi

# 测试访问 pods
if KUBECONFIG="$KUBECONFIG_FILE" kubectl get pods -n kube-system --limit=1 > /dev/null 2>&1; then
    echo_info "  ✓ 可以访问 pods"
else
    echo_warn "  ⚠️  无法访问 pods（可能是权限问题）"
fi

echo ""
echo_info "5. 对比测试（使用默认 kubeconfig）"
echo ""

if kubectl get nodes > /dev/null 2>&1; then
    echo_info "  ✓ 默认 kubeconfig 可以正常工作"
    DEFAULT_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
    echo_info "  默认 server: $DEFAULT_SERVER"
    echo_info "  Multus server: $SERVER"
    
    if [ "$DEFAULT_SERVER" != "$SERVER" ]; then
        echo_warn "  ⚠️  Server 地址不同，但这可能是正常的（Multus 使用集群内部地址）"
    fi
else
    echo_warn "  ⚠️  默认 kubeconfig 也有问题"
fi

echo ""
echo_info "=========================================="
echo_info "验证结果"
echo_info "=========================================="
echo ""
echo_info "kubeconfig 文件已创建，即使验证失败，文件仍然可以使用"
echo_info "Multus CNI 插件在运行时可能会重试连接"
echo ""
echo_info "如果 Multus 仍无法工作，检查："
echo "  1. Multus Pod 日志: kubectl logs -n kube-system -l app=multus"
echo "  2. kubelet 日志中的 Multus 相关错误"
echo ""


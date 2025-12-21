#!/bin/bash

# 检查 Multus 相关文件和目录的权限

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 Multus 权限配置"
echo_info "=========================================="
echo ""

# 1. 检查 k3s 目录权限
echo_info "1. 检查 k3s 目录权限"
echo ""

K3S_BASE="/var/lib/rancher/k3s"
K3S_AGENT="$K3S_BASE/agent"
CNI_DIR="$K3S_AGENT/etc/cni/net.d"
KUBECONFIG_FILE="$CNI_DIR/multus.d/multus.kubeconfig"

echo "k3s 基础目录:"
sudo ls -ld "$K3S_BASE"
echo ""
echo "agent 目录:"
sudo ls -ld "$K3S_AGENT"
echo ""
echo "CNI 配置目录:"
sudo ls -ld "$CNI_DIR" 2>/dev/null || echo_error "  ✗ 目录不存在"
echo ""
echo "kubeconfig 文件:"
sudo ls -l "$KUBECONFIG_FILE" 2>/dev/null || echo_error "  ✗ 文件不存在"

# 2. 检查 Multus DaemonSet 的运行用户
echo ""
echo_info "2. 检查 Multus DaemonSet 运行用户"
echo ""

DS_SECURITY=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.securityContext}' 2>/dev/null || echo "")
CONTAINER_SECURITY=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext}' 2>/dev/null || echo "")
RUN_AS_USER=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsUser}' 2>/dev/null || echo "")
RUN_AS_GROUP=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsGroup}' 2>/dev/null || echo "")

echo "DaemonSet 安全上下文:"
echo "$DS_SECURITY" | jq '.' 2>/dev/null || echo "未配置"
echo ""
echo "容器安全上下文:"
echo "$CONTAINER_SECURITY" | jq '.' 2>/dev/null || echo "未配置"
echo ""
echo "运行用户 ID: ${RUN_AS_USER:-未配置（默认可能为 root 或 65534）}"
echo "运行组 ID: ${RUN_AS_GROUP:-未配置}"

# 3. 检查 Pod 内的实际权限
echo ""
echo_info "3. 检查 Pod 内的实际权限"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo "Multus Pod: $MULTUS_POD"
    echo ""
    echo "Pod 内用户:"
    kubectl exec -n kube-system $MULTUS_POD -- id 2>/dev/null || echo_error "无法获取用户信息"
    echo ""
    echo "检查挂载点权限:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -ld /host/etc/cni/net.d 2>/dev/null || echo_error "无法访问挂载点"
    echo ""
    echo "检查 kubeconfig 文件权限:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -l /host/etc/cni/net.d/multus.d/multus.kubeconfig 2>/dev/null || echo_error "无法访问文件"
    echo ""
    echo "尝试读取文件:"
    kubectl exec -n kube-system $MULTUS_POD -- cat /host/etc/cni/net.d/multus.d/multus.kubeconfig > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo_info "  ✓ Pod 可以读取文件"
    else
        echo_error "  ✗ Pod 无法读取文件（可能是权限问题）"
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

# 4. 权限分析
echo ""
echo_info "4. 权限分析"
echo ""

AGENT_PERM=$(stat -c "%a" "$K3S_AGENT" 2>/dev/null || echo "")
if [ "$AGENT_PERM" = "700" ]; then
    echo_warn "  ⚠️  agent 目录权限为 700 (drwx------)"
    echo_warn "     只有 root 用户可以访问"
    echo_warn "     如果 Pod 不是以 root 运行，可能无法访问"
elif [ "$AGENT_PERM" = "755" ] || [ "$AGENT_PERM" = "750" ]; then
    echo_info "  ✓ agent 目录权限为 $AGENT_PERM，应该可以访问"
else
    echo_warn "  ⚠️  agent 目录权限为 $AGENT_PERM，请检查"
fi

if [ -f "$KUBECONFIG_FILE" ]; then
    FILE_PERM=$(stat -c "%a" "$KUBECONFIG_FILE" 2>/dev/null || echo "")
    if [ "$FILE_PERM" = "600" ] || [ "$FILE_PERM" = "640" ]; then
        echo_warn "  ⚠️  kubeconfig 文件权限为 $FILE_PERM"
        if [ "$FILE_PERM" = "600" ]; then
            echo_warn "     只有 root 用户可以读写"
        fi
    elif [ "$FILE_PERM" = "644" ] || [ "$FILE_PERM" = "664" ]; then
        echo_info "  ✓ kubeconfig 文件权限为 $FILE_PERM，应该可以读取"
    fi
fi

echo ""
echo_info "=========================================="
echo_info "建议"
echo_info "=========================================="
echo ""

if [ "$AGENT_PERM" = "700" ]; then
    echo_info "agent 目录权限为 700，建议："
    echo "  1. 确保 Multus Pod 以 root 运行（uid=0）"
    echo "  2. 或者修改目录权限（不推荐，可能影响 k3s 安全）"
    echo "  3. 或者将文件放在可访问的目录（如 /etc/cni/net.d）"
fi

if [ -f "$KUBECONFIG_FILE" ]; then
    FILE_PERM=$(stat -c "%a" "$KUBECONFIG_FILE" 2>/dev/null || echo "")
    if [ "$FILE_PERM" = "600" ]; then
        echo_info "kubeconfig 文件权限为 600，建议修改为 644："
        echo "  sudo chmod 644 $KUBECONFIG_FILE"
    fi
fi

echo ""


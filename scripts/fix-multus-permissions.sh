#!/bin/bash

# 修复 Multus 权限问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复 Multus 权限问题"
echo_info "=========================================="
echo ""

# 1. 检查当前权限
echo_info "1. 检查当前权限配置"
echo ""

K3S_AGENT="/var/lib/rancher/k3s/agent"
CNI_DIR="$K3S_AGENT/etc/cni/net.d"
KUBECONFIG_FILE="$CNI_DIR/multus.d/multus.kubeconfig"

AGENT_PERM=$(stat -c "%a" "$K3S_AGENT" 2>/dev/null || echo "")
echo_info "  agent 目录权限: $AGENT_PERM"

if [ "$AGENT_PERM" = "700" ]; then
    echo_warn "  ⚠️  目录权限为 700，只有 root 可以访问"
fi

# 2. 检查 Multus DaemonSet 运行用户
echo ""
echo_info "2. 检查 Multus DaemonSet 运行用户"
echo ""

RUN_AS_USER=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsUser}' 2>/dev/null || echo "")
RUN_AS_GROUP=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsGroup}' 2>/dev/null || echo "")

echo_info "  当前运行用户: ${RUN_AS_USER:-未配置（可能使用默认值）}"
echo_info "  当前运行组: ${RUN_AS_GROUP:-未配置}"

if [ -z "$RUN_AS_USER" ] || [ "$RUN_AS_USER" != "0" ]; then
    echo_warn "  ⚠️  Pod 不是以 root 运行，无法访问 700 权限的目录"
    echo_info "  需要修复..."
    NEED_FIX=true
else
    echo_info "  ✓ Pod 以 root 运行"
    NEED_FIX=false
fi

# 3. 修复 DaemonSet 配置
echo ""
if [ "$NEED_FIX" = true ]; then
    echo_info "3. 修复 DaemonSet 配置（设置为 root 运行）"
    echo ""
    
    # 检查是否已有 securityContext
    CURRENT_SC=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].securityContext}' 2>/dev/null || echo "{}")
    
    if [ "$CURRENT_SC" = "{}" ] || [ -z "$CURRENT_SC" ]; then
        # 没有 securityContext，添加
        echo_info "  添加 securityContext..."
        kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/securityContext",
            "value": {
              "runAsUser": 0,
              "runAsGroup": 0
            }
          }
        ]'
    else
        # 已有 securityContext，更新
        echo_info "  更新 securityContext..."
        kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/securityContext/runAsUser",
            "value": 0
          },
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/securityContext/runAsGroup",
            "value": 0
          }
        ]' 2>/dev/null || kubectl patch daemonset -n kube-system kube-multus-ds --type json -p '[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/securityContext/runAsUser",
            "value": 0
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/securityContext/runAsGroup",
            "value": 0
          }
        ]'
    fi
    
    echo_info "  ✓ DaemonSet 已更新"
else
    echo_info "3. DaemonSet 配置正确，无需修复"
fi

# 4. 修复文件权限
echo ""
echo_info "4. 检查并修复文件权限"
echo ""

if [ -f "$KUBECONFIG_FILE" ]; then
    FILE_PERM=$(stat -c "%a" "$KUBECONFIG_FILE" 2>/dev/null || echo "")
    echo_info "  当前文件权限: $FILE_PERM"
    
    if [ "$FILE_PERM" != "644" ]; then
        echo_info "  修改文件权限为 644..."
        sudo chmod 644 "$KUBECONFIG_FILE"
        echo_info "  ✓ 文件权限已更新"
    else
        echo_info "  ✓ 文件权限正确"
    fi
else
    echo_warn "  ⚠️  kubeconfig 文件不存在: $KUBECONFIG_FILE"
    echo_info "  创建文件..."
    sudo mkdir -p "$(dirname "$KUBECONFIG_FILE")"
    K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if [ -f "$K3S_KUBECONFIG" ]; then
        sudo cp "$K3S_KUBECONFIG" "$KUBECONFIG_FILE"
        sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$KUBECONFIG_FILE"
        sudo chmod 644 "$KUBECONFIG_FILE"
        echo_info "  ✓ 文件已创建"
    else
        echo_error "  ✗ 未找到 k3s kubeconfig"
    fi
fi

# 5. 重启 Pod
echo ""
echo_info "5. 重启 Multus Pod"
echo ""

MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_PODS" ]; then
    for pod in $MULTUS_PODS; do
        echo_info "  删除 Pod: $pod"
        kubectl delete pod -n kube-system $pod --force --grace-period=0 2>/dev/null || true
    done
    echo_info "  ✓ Pod 已删除，等待重新创建..."
    sleep 5
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

# 6. 验证修复
echo ""
echo_info "6. 验证修复"
echo ""

sleep 5
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  检查 Pod 运行用户:"
    kubectl exec -n kube-system $MULTUS_POD -- id 2>/dev/null | grep -q "uid=0" && echo_info "  ✓ 以 root 运行" || echo_error "  ✗ 不是 root"
    
    echo_info "  检查文件访问:"
    if kubectl exec -n kube-system $MULTUS_POD -- test -f /host/etc/cni/net.d/multus.d/multus.kubeconfig 2>/dev/null; then
        echo_info "  ✓ 可以访问文件"
    else
        echo_error "  ✗ 无法访问文件"
    fi
    
    echo_info "  检查 Pod 状态:"
    kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}' | grep -q "Running" && echo_info "  ✓ Pod 运行中" || echo_warn "  ⚠️  Pod 状态异常"
else
    echo_warn "  ⚠️  Pod 尚未启动，请稍后检查"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 仍有问题，检查日志:"
echo "  kubectl logs -n kube-system -l app=multus --tail=50"
echo ""


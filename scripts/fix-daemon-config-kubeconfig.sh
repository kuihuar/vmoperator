#!/bin/bash

# 修复 daemon-config.json 中的 kubeconfig 路径

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
echo_info "修复 daemon-config.json kubeconfig 路径"
echo_info "=========================================="
echo ""

DAEMON_CONFIG="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json"
HOST_KUBECONFIG="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
POD_KUBECONFIG="/host/etc/cni/net.d/multus.d/multus.kubeconfig"

# 1. 检查文件是否存在
echo_info "1. 检查主机文件"
echo ""

if [ ! -f "$HOST_KUBECONFIG" ]; then
    echo_error "  ✗ 主机文件不存在: $HOST_KUBECONFIG"
    echo_info "  创建文件..."
    
    sudo mkdir -p "$(dirname "$HOST_KUBECONFIG")"
    K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if [ -f "$K3S_KUBECONFIG" ]; then
        sudo cp "$K3S_KUBECONFIG" "$HOST_KUBECONFIG"
        sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$HOST_KUBECONFIG"
        sudo chmod 644 "$HOST_KUBECONFIG"
        echo_info "  ✓ 文件已创建"
    else
        echo_error "  ✗ 未找到 k3s kubeconfig"
        exit 1
    fi
else
    echo_info "  ✓ 主机文件存在: $HOST_KUBECONFIG"
    sudo ls -lh "$HOST_KUBECONFIG"
fi

# 2. 检查 DaemonSet 挂载
echo ""
echo_info "2. 检查 DaemonSet 挂载配置"
echo ""

DS_HOST_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

echo_info "  主机路径: $DS_HOST_PATH"
echo_info "  Pod 内挂载点: $DS_MOUNT_PATH"

# 3. 检查 daemon-config.json
echo ""
echo_info "3. 检查 daemon-config.json"
echo ""

if [ ! -f "$DAEMON_CONFIG" ]; then
    echo_error "  ✗ 配置文件不存在"
    exit 1
fi

CURRENT_PATH=$(sudo cat "$DAEMON_CONFIG" | jq -r '.kubeconfig // ""')
echo_info "  当前配置的路径: $CURRENT_PATH"

if [ "$CURRENT_PATH" != "$POD_KUBECONFIG" ]; then
    echo_warn "  ⚠️  路径不匹配，更新配置..."
    sudo cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cat "$DAEMON_CONFIG" | jq ".kubeconfig = \"$POD_KUBECONFIG\"" | sudo tee "${DAEMON_CONFIG}.tmp" > /dev/null
    sudo mv "${DAEMON_CONFIG}.tmp" "$DAEMON_CONFIG"
    sudo chmod 644 "$DAEMON_CONFIG"
    echo_info "  ✓ 已更新为: $POD_KUBECONFIG"
else
    echo_info "  ✓ 路径正确"
fi

# 4. 验证 Pod 内访问
echo ""
echo_info "4. 验证 Pod 内访问"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Multus Pod: $MULTUS_POD"
    
    # 尝试访问文件
    if kubectl exec -n kube-system $MULTUS_POD -- sh -c "test -f $POD_KUBECONFIG" 2>/dev/null; then
        echo_info "  ✓ Pod 内可以访问文件"
    else
        echo_warn "  ⚠️  Pod 内暂时无法访问"
        echo_info "  重启 Multus Pod..."
        kubectl delete pod -n kube-system $MULTUS_POD --force --grace-period=0 2>/dev/null || true
        sleep 5
        
        # 再次检查
        MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$MULTUS_POD" ]; then
            sleep 5
            if kubectl exec -n kube-system $MULTUS_POD -- sh -c "test -f $POD_KUBECONFIG" 2>/dev/null; then
                echo_info "  ✓ Pod 重启后可以访问"
            else
                echo_error "  ✗ Pod 重启后仍无法访问"
                echo_info "  可能原因："
                echo "    1. 挂载配置不正确"
                echo "    2. 文件权限问题"
                echo "    3. 目录权限问题（agent 目录是 700）"
            fi
        fi
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 内仍无法访问，检查："
echo "  1. DaemonSet 挂载配置是否正确"
echo "  2. 文件权限（应该是 644）"
echo "  3. 目录权限（可能需要放宽 agent 目录权限，但不推荐）"
echo ""


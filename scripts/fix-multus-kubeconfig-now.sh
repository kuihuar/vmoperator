#!/bin/bash

# 立即修复 Multus kubeconfig 文件缺失问题

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
echo_info "立即修复 Multus kubeconfig 文件缺失"
echo_info "=========================================="
echo ""

# 根据错误信息，Multus 在 Pod 内查找的路径是：/host/etc/cni/net.d/multus.d/multus.kubeconfig
# 这意味着 DaemonSet 挂载点是 /host/etc/cni/net.d
# 主机路径应该是 /var/lib/rancher/k3s/agent/etc/cni/net.d

HOST_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

echo_info "1. 检查文件是否存在"
echo ""

if [ -f "$HOST_PATH" ]; then
    echo_info "  ✓ 文件已存在: $HOST_PATH"
    sudo ls -lh "$HOST_PATH"
else
    echo_warn "  ✗ 文件不存在: $HOST_PATH"
    echo_info "  创建文件..."
    
    # 创建目录
    sudo mkdir -p "$(dirname "$HOST_PATH")"
    
    if [ ! -f "$K3S_KUBECONFIG" ]; then
        echo_error "  ✗ k3s kubeconfig 不存在: $K3S_KUBECONFIG"
        exit 1
    fi
    
    # 复制并修改
    sudo cp "$K3S_KUBECONFIG" "$HOST_PATH"
    sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$HOST_PATH"
    sudo chmod 644 "$HOST_PATH"
    
    echo_info "  ✓ 文件已创建"
    sudo ls -lh "$HOST_PATH"
fi

echo ""
echo_info "2. 检查 Multus 配置文件中的路径"
echo ""

MULTUS_CONF="/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf"
if [ -f "$MULTUS_CONF" ]; then
    CURRENT_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // ""')
    echo_info "  配置文件中指定的路径: ${CURRENT_PATH:-未配置}"
    
    EXPECTED_PATH="/host/etc/cni/net.d/multus.d/multus.kubeconfig"
    if [ "$CURRENT_PATH" != "$EXPECTED_PATH" ]; then
        echo_warn "  ⚠️  路径不匹配，修复配置..."
        sudo cp "$MULTUS_CONF" "${MULTUS_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
        sudo cat "$MULTUS_CONF" | jq ".kubeconfig = \"$EXPECTED_PATH\"" | sudo tee "$MULTUS_CONF" > /dev/null
        echo_info "  ✓ 已更新为: $EXPECTED_PATH"
    else
        echo_info "  ✓ 路径正确"
    fi
else
    echo_warn "  ⚠️  配置文件不存在: $MULTUS_CONF"
fi

echo ""
echo_info "3. 检查 DaemonSet 挂载配置"
echo ""

DS_HOST_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

echo_info "  DaemonSet 挂载:"
echo_info "    主机路径: $DS_HOST_PATH"
echo_info "    Pod 内挂载点: $DS_MOUNT_PATH"

if [ "$DS_MOUNT_PATH" = "/host/etc/cni/net.d" ] && [ "$DS_HOST_PATH" = "/var/lib/rancher/k3s/agent/etc/cni/net.d" ]; then
    echo_info "  ✓ 挂载配置正确"
else
    echo_warn "  ⚠️  挂载配置可能不正确"
fi

echo ""
echo_info "4. 验证 Pod 内访问"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Multus Pod: $MULTUS_POD"
    
    if kubectl exec -n kube-system $MULTUS_POD -- test -f /host/etc/cni/net.d/multus.d/multus.kubeconfig 2>/dev/null; then
        echo_info "  ✓ Pod 内可以访问文件"
    else
        echo_warn "  ⚠️  Pod 内暂时无法访问（可能需要重启 Pod）"
        echo_info "  重启 Multus Pod..."
        kubectl delete pod -n kube-system $MULTUS_POD --force --grace-period=0 2>/dev/null || true
        sleep 3
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

echo ""
echo_info "5. 验证修复"
echo ""

if [ -f "$HOST_PATH" ]; then
    echo_info "  ✓ 主机文件存在: $HOST_PATH"
    echo_info "    权限: $(stat -c "%a" "$HOST_PATH" 2>/dev/null || echo "未知")"
    echo_info "    大小: $(stat -c "%s" "$HOST_PATH" 2>/dev/null || echo "未知") bytes"
else
    echo_error "  ✗ 主机文件不存在"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "文件位置:"
echo "  主机: $HOST_PATH"
echo "  Pod 内: /host/etc/cni/net.d/multus.d/multus.kubeconfig"
echo ""
echo_info "如果 Ceph Pod 仍无法创建，等待几秒后重试，或重启受影响的 Pod:"
echo "  kubectl delete pods -n rook-ceph --all --force --grace-period=0"
echo ""

#!/bin/bash

# 清理错误文件并只在正确位置创建 kubeconfig

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
echo_info "清理并修复 Multus kubeconfig"
echo_info "=========================================="
echo ""

# 1. 读取配置确定路径
echo_info "1. 确定 Multus 使用的 kubeconfig 路径"
echo ""

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_DIR/00-multus.conf"

if [ ! -f "$MULTUS_CONF" ]; then
    echo_error "  ✗ Multus 配置文件不存在: $MULTUS_CONF"
    exit 1
fi

KUBECONFIG_POD_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // ""')
if [ -z "$KUBECONFIG_POD_PATH" ]; then
    echo_error "  ✗ 配置文件中未找到 kubeconfig 路径"
    exit 1
fi

echo_info "  配置文件中指定的路径（Pod 内）: $KUBECONFIG_POD_PATH"

# 2. 检查 DaemonSet 挂载
DS_HOST_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

if [ -z "$DS_HOST_PATH" ] || [ -z "$DS_MOUNT_PATH" ]; then
    echo_error "  ✗ 无法获取 DaemonSet 挂载配置"
    exit 1
fi

echo_info "  DaemonSet 挂载:"
echo_info "    主机路径: $DS_HOST_PATH"
echo_info "    Pod 内挂载点: $DS_MOUNT_PATH"

# 3. 计算主机上的实际路径
RELATIVE_PATH="${KUBECONFIG_POD_PATH#${DS_MOUNT_PATH}/}"
CORRECT_HOST_PATH="$DS_HOST_PATH/$RELATIVE_PATH"

echo ""
echo_info "2. 计算正确的主机路径"
echo_info "  ✓ 正确的主机路径: $CORRECT_HOST_PATH"
echo ""

# 4. 清理错误创建的文件
echo_info "3. 清理错误创建的文件"
echo ""

WRONG_PATHS=(
    "/host/etc/cni/net.d/multus.d/multus.kubeconfig"
    "/etc/cni/net.d/multus.d/multus.kubeconfig"
)

for wrong_path in "${WRONG_PATHS[@]}"; do
    if [ -f "$wrong_path" ] && [ "$wrong_path" != "$CORRECT_HOST_PATH" ]; then
        echo_warn "  删除错误位置的文件: $wrong_path"
        sudo rm -f "$wrong_path"
        echo_info "  ✓ 已删除"
    fi
done

# 5. 在正确位置创建文件
echo ""
echo_info "4. 在正确位置创建/验证文件"
echo ""

if [ -f "$CORRECT_HOST_PATH" ]; then
    echo_info "  ✓ 文件已存在: $CORRECT_HOST_PATH"
    sudo ls -lh "$CORRECT_HOST_PATH"
else
    echo_info "  创建文件: $CORRECT_HOST_PATH"
    sudo mkdir -p "$(dirname "$CORRECT_HOST_PATH")"
    
    K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if [ -f "$K3S_KUBECONFIG" ]; then
        sudo cp "$K3S_KUBECONFIG" "$CORRECT_HOST_PATH"
        sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$CORRECT_HOST_PATH"
        sudo chmod 644 "$CORRECT_HOST_PATH"
        echo_info "  ✓ 文件已创建"
        sudo ls -lh "$CORRECT_HOST_PATH"
    else
        echo_error "  ✗ 未找到 k3s kubeconfig: $K3S_KUBECONFIG"
        exit 1
    fi
fi

# 6. 验证
echo ""
echo_info "5. 验证"
echo ""

echo_info "  配置文件中: $KUBECONFIG_POD_PATH"
echo_info "  主机路径: $CORRECT_HOST_PATH"
echo_info "  DaemonSet 挂载: $DS_HOST_PATH -> $DS_MOUNT_PATH"
echo ""

# 检查 Pod 内访问
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  检查 Pod 内访问..."
    if kubectl exec -n kube-system $MULTUS_POD -- test -f "$KUBECONFIG_POD_PATH" 2>/dev/null; then
        echo_info "  ✓ Pod 内可以访问文件"
    else
        echo_warn "  ⚠️  Pod 内暂时无法访问（可能需要重启 Pod）"
    fi
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""
echo_info "Multus kubeconfig 文件位置:"
echo "  主机: $CORRECT_HOST_PATH"
echo "  Pod 内: $KUBECONFIG_POD_PATH"
echo ""
echo_info "如果 Pod 仍无法访问，重启 Multus Pod:"
echo "  kubectl delete pod -n kube-system -l app=multus --force --grace-period=0"
echo ""


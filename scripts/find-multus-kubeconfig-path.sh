#!/bin/bash

# 查找 Multus 实际使用的 kubeconfig 路径

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "查找 Multus 实际使用的 kubeconfig 路径"
echo_info "=========================================="
echo ""

# 1. 检查 Multus 配置文件（daemon-config.json）
echo_info "1. 检查 Multus 配置文件中的 kubeconfig 路径"
echo ""

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
DAEMON_CONFIG="$CNI_DIR/multus.d/daemon-config.json"

if [ -f "$DAEMON_CONFIG" ]; then
    echo_info "  配置文件: $DAEMON_CONFIG"
    echo ""
    echo "  内容:"
    sudo cat "$DAEMON_CONFIG" | jq -r '.kubeconfig // "未配置"'
    echo ""
    KUBECONFIG_IN_CONFIG=$(sudo cat "$DAEMON_CONFIG" | jq -r '.kubeconfig // ""')
    echo_info "  配置中指定的路径（Pod 内路径）: $KUBECONFIG_IN_CONFIG"
else
    echo_error "  ✗ 配置文件不存在: $DAEMON_CONFIG"
    exit 1
fi

# 2. 检查 DaemonSet 挂载配置
echo ""
echo_info "2. 检查 Multus DaemonSet 挂载配置"
echo ""

DS_HOST_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

echo_info "  DaemonSet 挂载:"
echo_info "    主机路径: $DS_HOST_PATH"
echo_info "    Pod 内挂载点: $DS_MOUNT_PATH"

# 3. 计算主机上的实际路径
echo ""
echo_info "3. 计算主机上的实际路径"
echo ""

if [ -n "$KUBECONFIG_IN_CONFIG" ] && [ -n "$DS_HOST_PATH" ] && [ -n "$DS_MOUNT_PATH" ]; then
    # 去掉开头的 /etc/cni/net.d，替换为主机路径
    RELATIVE_PATH="${KUBECONFIG_IN_CONFIG#${DS_MOUNT_PATH}/}"
    HOST_FILE_PATH="$DS_HOST_PATH/$RELATIVE_PATH"
    
    echo_info "  配置路径（Pod 内）: $KUBECONFIG_IN_CONFIG"
    echo_info "  挂载点（Pod 内）: $DS_MOUNT_PATH"
    echo_info "  主机挂载点: $DS_HOST_PATH"
    echo_info "  相对路径: $RELATIVE_PATH"
    echo ""
    echo_info "  ✓ 主机上的实际路径应该是: $HOST_FILE_PATH"
    
    # 检查文件是否存在
    if [ -f "$HOST_FILE_PATH" ]; then
        echo_info "  ✓ 文件存在"
        sudo ls -lh "$HOST_FILE_PATH"
    else
        echo_error "  ✗ 文件不存在"
        echo_warn "  需要创建: $HOST_FILE_PATH"
    fi
else
    echo_error "  ✗ 无法计算路径（缺少必要信息）"
fi

# 4. 检查所有可能的文件位置
echo ""
echo_info "4. 检查所有可能的 kubeconfig 文件位置"
echo ""

POSSIBLE_PATHS=(
    "$CNI_DIR/multus.d/multus.kubeconfig"
    "/host/etc/cni/net.d/multus.d/multus.kubeconfig"
    "/etc/cni/net.d/multus.d/multus.kubeconfig"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo_info "  ✓ 存在: $path"
        sudo ls -lh "$path"
    else
        echo_warn "  ✗ 不存在: $path"
    fi
done

# 5. 检查 Pod 内实际看到的路径
echo ""
echo_info "5. 检查 Pod 内实际看到的路径"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Multus Pod: $MULTUS_POD"
    
    if [ -n "$KUBECONFIG_IN_CONFIG" ]; then
        echo_info "  检查 Pod 内路径: $KUBECONFIG_IN_CONFIG"
        if kubectl exec -n kube-system $MULTUS_POD -- test -f "$KUBECONFIG_IN_CONFIG" 2>/dev/null; then
            echo_info "  ✓ Pod 内可以访问文件"
            kubectl exec -n kube-system $MULTUS_POD -- ls -lh "$KUBECONFIG_IN_CONFIG"
        else
            echo_error "  ✗ Pod 内无法访问文件"
        fi
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

echo ""
echo_info "=========================================="
echo_info "结论"
echo_info "=========================================="
echo ""
if [ -n "$HOST_FILE_PATH" ]; then
    echo_info "Multus 使用的 kubeconfig 文件路径:"
    echo "  配置文件中: $KUBECONFIG_IN_CONFIG (Pod 内路径)"
    echo "  主机路径: $HOST_FILE_PATH"
    echo ""
    if [ -f "$HOST_FILE_PATH" ]; then
        echo_info "✓ 文件存在，路径正确"
    else
        echo_error "✗ 文件不存在，需要创建: $HOST_FILE_PATH"
    fi
else
    echo_error "无法确定路径"
fi
echo ""


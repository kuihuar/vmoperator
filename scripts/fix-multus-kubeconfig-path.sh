#!/bin/bash

# 修复 Multus kubeconfig 路径配置

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
echo_info "修复 Multus kubeconfig 路径"
echo_info "=========================================="
echo ""

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_DIR/00-multus.conf"
DAEMON_CONFIG="$CNI_DIR/multus.d/daemon-config.json"

# 1. 检查 DaemonSet 挂载
DS_HOST_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")
DS_MOUNT_PATH=$(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")

if [ -z "$DS_HOST_PATH" ] || [ -z "$DS_MOUNT_PATH" ]; then
    echo_error "  ✗ 无法获取 DaemonSet 挂载配置"
    exit 1
fi

echo_info "DaemonSet 挂载配置:"
echo_info "  主机路径: $DS_HOST_PATH"
echo_info "  Pod 内挂载点: $DS_MOUNT_PATH"
echo ""

# 2. 确定正确的 Pod 内路径
# 由于挂载到 /host/etc/cni/net.d，所以 Pod 内路径应该是 /host/etc/cni/net.d/multus.d/multus.kubeconfig
CORRECT_POD_PATH="$DS_MOUNT_PATH/multus.d/multus.kubeconfig"

echo_info "正确的 Pod 内路径: $CORRECT_POD_PATH"
echo ""

# 3. 检查并修复 00-multus.conf
if [ -f "$MULTUS_CONF" ]; then
    echo_info "1. 检查 00-multus.conf"
    CURRENT_PATH=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // ""')
    echo_info "  当前配置的路径: ${CURRENT_PATH:-未配置}"
    
    if [ "$CURRENT_PATH" != "$CORRECT_POD_PATH" ]; then
        echo_warn "  ⚠️  路径不匹配，需要修复"
        echo_info "  修复配置文件..."
        
        # 备份
        sudo cp "$MULTUS_CONF" "${MULTUS_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
        
        # 更新路径
        sudo cat "$MULTUS_CONF" | jq ".kubeconfig = \"$CORRECT_POD_PATH\"" | sudo tee "$MULTUS_CONF" > /dev/null
        sudo chmod 644 "$MULTUS_CONF"
        
        echo_info "  ✓ 已更新为: $CORRECT_POD_PATH"
    else
        echo_info "  ✓ 路径正确"
    fi
else
    echo_error "  ✗ 配置文件不存在: $MULTUS_CONF"
fi

echo ""

# 4. 检查并修复 daemon-config.json（如果使用 Thick Plugin）
if [ -f "$DAEMON_CONFIG" ]; then
    echo_info "2. 检查 daemon-config.json"
    CURRENT_DAEMON_PATH=$(sudo cat "$DAEMON_CONFIG" | jq -r '.kubeconfig // ""')
    echo_info "  当前配置的路径: ${CURRENT_DAEMON_PATH:-未配置}"
    
    if [ -z "$CURRENT_DAEMON_PATH" ]; then
        echo_warn "  ⚠️  未配置 kubeconfig，添加配置..."
        
        # 备份
        sudo cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
        
        # 添加 kubeconfig 路径
        sudo cat "$DAEMON_CONFIG" | jq ".kubeconfig = \"$CORRECT_POD_PATH\"" | sudo tee "$DAEMON_CONFIG" > /dev/null
        sudo chmod 644 "$DAEMON_CONFIG"
        
        echo_info "  ✓ 已添加 kubeconfig 路径: $CORRECT_POD_PATH"
    elif [ "$CURRENT_DAEMON_PATH" != "$CORRECT_POD_PATH" ]; then
        echo_warn "  ⚠️  路径不匹配，需要修复"
        echo_info "  修复配置文件..."
        
        # 备份
        sudo cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
        
        # 更新路径
        sudo cat "$DAEMON_CONFIG" | jq ".kubeconfig = \"$CORRECT_POD_PATH\"" | sudo tee "$DAEMON_CONFIG" > /dev/null
        sudo chmod 644 "$DAEMON_CONFIG"
        
        echo_info "  ✓ 已更新为: $CORRECT_POD_PATH"
    else
        echo_info "  ✓ 路径正确"
    fi
fi

echo ""

# 5. 验证文件存在
echo_info "3. 验证文件存在"
echo ""

HOST_FILE_PATH="$DS_HOST_PATH/multus.d/multus.kubeconfig"
if [ -f "$HOST_FILE_PATH" ]; then
    echo_info "  ✓ 主机文件存在: $HOST_FILE_PATH"
    sudo ls -lh "$HOST_FILE_PATH"
else
    echo_error "  ✗ 主机文件不存在: $HOST_FILE_PATH"
    echo_info "  创建文件..."
    
    sudo mkdir -p "$(dirname "$HOST_FILE_PATH")"
    K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if [ -f "$K3S_KUBECONFIG" ]; then
        sudo cp "$K3S_KUBECONFIG" "$HOST_FILE_PATH"
        sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' "$HOST_FILE_PATH"
        sudo chmod 644 "$HOST_FILE_PATH"
        echo_info "  ✓ 文件已创建"
    else
        echo_error "  ✗ 未找到 k3s kubeconfig"
        exit 1
    fi
fi

echo ""

# 6. 验证 Pod 内访问
echo_info "4. 验证 Pod 内访问"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Multus Pod: $MULTUS_POD"
    
    if kubectl exec -n kube-system $MULTUS_POD -- test -f "$CORRECT_POD_PATH" 2>/dev/null; then
        echo_info "  ✓ Pod 内可以访问文件"
        kubectl exec -n kube-system $MULTUS_POD -- ls -lh "$CORRECT_POD_PATH"
    else
        echo_warn "  ⚠️  Pod 内暂时无法访问（需要重启 Pod）"
    fi
else
    echo_warn "  ⚠️  未找到 Multus Pod"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "配置摘要:"
echo "  主机路径: $HOST_FILE_PATH"
echo "  Pod 内路径: $CORRECT_POD_PATH"
echo "  配置文件已更新"
echo ""
echo_info "如果 Pod 仍无法访问，重启 Multus Pod:"
echo "  kubectl delete pod -n kube-system -l app=multus --force --grace-period=0"
echo ""


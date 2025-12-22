#!/bin/bash

# 最终修复 Multus - 一次性解决所有问题

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
echo_info "最终修复 Multus - 一次性解决"
echo_info "=========================================="
echo ""

# 1. 获取最新错误
echo_info "1. 获取最新错误信息"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod: $MULTUS_POD"
    echo_info "  最新日志:"
    kubectl logs -n kube-system $MULTUS_POD -c kube-multus --tail=10 2>&1 | head -5
    echo ""
fi

# 2. 检查 DaemonSet 配置
echo_info "2. 检查 DaemonSet 配置"
echo ""

DS_NAME="kube-multus-ds"
NAMESPACE="kube-system"

# 获取挂载配置
CNI_MOUNT=$(kubectl get daemonset -n $NAMESPACE $DS_NAME -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")
CNI_HOST=$(kubectl get daemonset -n $NAMESPACE $DS_NAME -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")

echo_info "  CNI 挂载: $CNI_HOST -> $CNI_MOUNT"

# 3. 检查并创建所有必要的配置文件
echo ""
echo_info "3. 创建/修复所有配置文件"
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
sudo mkdir -p "$CNI_CONF_DIR/multus.d"

# 3.1 创建 daemon-config.json（如果不存在）
DAEMON_CONFIG="$CNI_CONF_DIR/multus.d/daemon-config.json"
if [ ! -f "$DAEMON_CONFIG" ]; then
    echo_info "  创建 daemon-config.json..."
    
    # 使用 Pod 内路径（根据挂载点）
    CONF_DIR_POD="/host/etc/cni/net.d"
    KUBECONFIG_POD="/host/etc/cni/net.d/multus.d/multus.kubeconfig"
    
    sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "$CONF_DIR_POD",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log",
  "kubeconfig": "$KUBECONFIG_POD"
}
EOF
    
    sudo chmod 644 "$DAEMON_CONFIG"
    echo_info "  ✓ 已创建"
else
    echo_info "  ✓ 已存在，检查内容..."
    CURRENT_CONF_DIR=$(sudo cat "$DAEMON_CONFIG" | jq -r '.confDir // ""' 2>/dev/null || echo "")
    if [[ "$CURRENT_CONF_DIR" == /var/lib/rancher/k3s* ]]; then
        echo_warn "  ⚠️  路径是主机路径，需要修复..."
        sudo cp "$DAEMON_CONFIG" "$DAEMON_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"
        sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "/host/etc/cni/net.d",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log",
  "kubeconfig": "/host/etc/cni/net.d/multus.d/multus.kubeconfig"
}
EOF
        echo_info "  ✓ 已修复"
    else
        echo_info "  ✓ 路径正确"
    fi
fi

# 3.2 检查 00-multus.conf
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"
if [ -f "$MULTUS_CONF" ]; then
    echo_info "  ✓ 00-multus.conf 存在"
    KUBECONFIG_IN_CONF=$(sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // ""' 2>/dev/null || echo "")
    echo_info "    kubeconfig 路径: $KUBECONFIG_IN_CONF"
    
    # 确保是主机路径
    if [[ "$KUBECONFIG_IN_CONF" == /host/* ]]; then
        echo_warn "  ⚠️  路径是 Pod 内路径，需要修复为主机路径..."
        sudo cp "$MULTUS_CONF" "$MULTUS_CONF.backup.$(date +%Y%m%d-%H%M%S)"
        HOST_KUBECONFIG="$CNI_CONF_DIR/multus.d/multus.kubeconfig"
        sudo cat "$MULTUS_CONF" | jq ".kubeconfig = \"$HOST_KUBECONFIG\"" | sudo tee "${MULTUS_CONF}.tmp" > /dev/null
        sudo mv "${MULTUS_CONF}.tmp" "$MULTUS_CONF"
        echo_info "  ✓ 已修复为主机路径"
    fi
else
    echo_warn "  ⚠️  00-multus.conf 不存在，需要创建"
fi

# 3.3 确保 kubeconfig 存在
KUBECONFIG_FILE="$CNI_CONF_DIR/multus.d/multus.kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo_warn "  ⚠️  kubeconfig 不存在，创建..."
    sudo ./scripts/create-kubeconfig-official.sh
fi

# 4. 重启 Pod
echo ""
echo_info "4. 重启 Multus Pod"
echo ""

kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo_info "  ✓ Pod 已删除，等待重新创建..."
sleep 10

# 5. 检查新 Pod 状态
echo ""
echo_info "5. 检查新 Pod 状态"
echo ""

MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  新 Pod: $MULTUS_POD"
    kubectl get pod -n kube-system $MULTUS_POD
    
    echo ""
    echo_info "  等待 5 秒后查看日志..."
    sleep 5
    
    echo_info "  最新日志:"
    kubectl logs -n kube-system $MULTUS_POD -c kube-multus --tail=20 2>&1 || echo_warn "  无法获取日志"
else
    echo_warn "  ⚠️  Pod 尚未创建"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 仍有问题，查看完整日志:"
echo "  kubectl logs -n kube-system -l app=multus -c kube-multus --tail=50"
echo ""


#!/bin/bash

# 创建正确的 daemon-config.json

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "创建正确的 daemon-config.json"
echo ""

# 1. 检查 DaemonSet 挂载配置
echo_info "1. 检查 DaemonSet 挂载配置"
echo ""

DS_NAME="kube-multus-ds"
NAMESPACE="kube-system"

MOUNT_PATH=$(kubectl get daemonset -n $NAMESPACE $DS_NAME -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}' 2>/dev/null || echo "")
HOST_PATH=$(kubectl get daemonset -n $NAMESPACE $DS_NAME -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}' 2>/dev/null || echo "")

echo_info "  DaemonSet 挂载:"
echo_info "    主机路径: $HOST_PATH"
echo_info "    Pod 内挂载点: $MOUNT_PATH"
echo ""

if [ -z "$MOUNT_PATH" ] || [ -z "$HOST_PATH" ]; then
    echo_error "  ✗ 无法获取挂载配置"
    exit 1
fi

# 2. 创建正确的配置
echo_info "2. 创建 daemon-config.json"
echo ""

DAEMON_CONFIG="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json"

# confDir 应该是 Pod 内的路径（挂载后的路径）
# 根据错误信息，应该是 /host/etc/cni/net.d
CONF_DIR_IN_POD="/host/etc/cni/net.d"
KUBECONFIG_IN_POD="/host/etc/cni/net.d/multus.d/multus.kubeconfig"

echo_info "  配置:"
echo_info "    confDir (Pod 内): $CONF_DIR_IN_POD"
echo_info "    kubeconfig (Pod 内): $KUBECONFIG_IN_POD"
echo ""

sudo mkdir -p "$(dirname "$DAEMON_CONFIG")"

sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "$CONF_DIR_IN_POD",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log",
  "kubeconfig": "$KUBECONFIG_IN_POD"
}
EOF

sudo chmod 644 "$DAEMON_CONFIG"

echo_info "  ✓ 文件已创建: $DAEMON_CONFIG"
echo ""
echo_info "  内容:"
sudo cat "$DAEMON_CONFIG" | jq '.'
echo ""

# 3. 验证文件存在
echo_info "3. 验证"
echo ""

if [ -f "$DAEMON_CONFIG" ]; then
    echo_info "  ✓ 文件存在"
    
    # 验证 Pod 内是否可以访问
    echo_info "  验证 Pod 内路径:"
    echo_info "    confDir: $CONF_DIR_IN_POD"
    echo_info "    kubeconfig: $KUBECONFIG_IN_POD"
    
    # 检查主机上的对应文件
    HOST_KUBECONFIG="$HOST_PATH/multus.d/multus.kubeconfig"
    if [ -f "$HOST_KUBECONFIG" ]; then
        echo_info "  ✓ kubeconfig 文件存在: $HOST_KUBECONFIG"
    else
        echo_warn "  ⚠️  kubeconfig 文件不存在: $HOST_KUBECONFIG"
    fi
else
    echo_error "  ✗ 文件创建失败"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "完成"
echo_info "=========================================="
echo ""
echo_info "现在重启 Multus Pod 以应用新配置:"
echo "  kubectl delete pod -n kube-system -l app=multus --force --grace-period=0"
echo ""


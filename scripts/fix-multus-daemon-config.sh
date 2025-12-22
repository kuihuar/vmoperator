#!/bin/bash

# 修复 daemon-config.json 的路径配置

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "修复 daemon-config.json 路径配置"
echo ""

DAEMON_CONFIG="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json"

if [ ! -f "$DAEMON_CONFIG" ]; then
    echo_error "配置文件不存在: $DAEMON_CONFIG"
    exit 1
fi

echo_info "当前配置:"
sudo cat "$DAEMON_CONFIG" | jq '.'
echo ""

# confDir 应该是 Pod 内的路径，不是主机路径
# 因为 DaemonSet 已经将 /var/lib/rancher/k3s/agent/etc/cni/net.d 挂载到 /host/etc/cni/net.d
# 所以 confDir 应该是 /host/etc/cni/net.d（Pod 内路径）

echo_info "修复配置..."
echo ""

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

sudo chmod 644 "$DAEMON_CONFIG"

echo_info "✓ 配置已修复"
echo ""
echo_info "新配置:"
sudo cat "$DAEMON_CONFIG" | jq '.'
echo ""

# 重启 Pod
echo_info "重启 Multus Pod 以应用新配置..."
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true

echo ""
echo_info "等待 Pod 重新创建..."
sleep 5

echo_info "新的 Pod 状态:"
kubectl get pods -n kube-system -l app=multus

echo ""


#!/bin/bash

# 立即修复 daemon-config.json 路径问题

set -e

DAEMON_CONFIG="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json"

echo "修复 daemon-config.json..."
echo ""

# 创建目录
sudo mkdir -p "$(dirname "$DAEMON_CONFIG")"

# 创建正确的配置（使用 Pod 内路径）
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

echo "✓ 已创建: $DAEMON_CONFIG"
echo ""
echo "内容:"
sudo cat "$DAEMON_CONFIG" | jq '.'
echo ""
echo "重启 Pod:"
echo "kubectl delete pod -n kube-system -l app=multus --force --grace-period=0"
echo ""


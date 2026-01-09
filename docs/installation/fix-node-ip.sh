#!/bin/bash
# 修复节点 IP 地址不匹配问题
# 当节点 IP 从 192.168.1.151 变为 192.168.1.141 后，需要更新 Kubernetes 配置

set -e

echo "=== 修复节点 IP 地址配置 ==="

# 1. 更新 Kubernetes API 服务器端点
echo "1. 更新 Kubernetes endpoints..."
kubectl patch endpoints kubernetes -n default --type=json -p='[{"op": "replace", "path": "/subsets/0/addresses/0/ip", "value": "192.168.1.141"}]' || true

# 2. 更新 EndpointSlice（如果存在）
echo "2. 更新 EndpointSlice..."
ENDPOINTSLICE=$(kubectl get endpointslices -n default -l kubernetes.io/service-name=kubernetes -o name 2>/dev/null | head -1)
if [ -n "$ENDPOINTSLICE" ]; then
    kubectl patch "$ENDPOINTSLICE" -n default --type=json -p='[{"op": "replace", "path": "/endpoints/0/addresses/0", "value": "192.168.1.141"}]' || true
fi

# 3. 检查当前节点 IP
CURRENT_IP=$(ip addr show ens160 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "3. 当前节点 IP: $CURRENT_IP"

# 4. 检查 k3s 配置
echo "4. 检查 k3s 配置..."
if [ -f /etc/systemd/system/k3s.service.d/override.conf ]; then
    echo "   k3s override.conf 存在"
    if ! grep -q "node-ip" /etc/systemd/system/k3s.service.d/override.conf; then
        echo "   建议：添加 node-ip=$CURRENT_IP 到 k3s 配置中"
    fi
fi

# 5. 重启 k3s 服务（需要 root 权限）
echo ""
echo "5. 要完全修复节点 IP，需要重启 k3s 服务："
echo "   sudo systemctl restart k3s"
echo ""
echo "   或者，如果 k3s 配置中没有指定 node-ip，可以添加："
echo "   sudo mkdir -p /etc/systemd/system/k3s.service.d/"
echo "   sudo bash -c 'echo \"[Service]\" >> /etc/systemd/system/k3s.service.d/override.conf'"
echo "   sudo bash -c 'echo \"ExecStartPre=/bin/sh -c \\\"echo K3S_NODE_IP=$CURRENT_IP\\\"\" >> /etc/systemd/system/k3s.service.d/override.conf'"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl restart k3s"

echo ""
echo "=== 修复完成 ==="
echo "等待几秒钟后，检查节点状态："
echo "kubectl get nodes -o wide"
echo "kubectl get endpoints -n default kubernetes"




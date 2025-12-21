#!/bin/bash

# 检查 00-multus.conf 中的 kubeconfig 路径

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_DIR/00-multus.conf"

echo "检查 00-multus.conf 配置..."
echo ""

if [ -f "$MULTUS_CONF" ]; then
    echo "文件: $MULTUS_CONF"
    echo ""
    echo "kubeconfig 配置:"
    sudo cat "$MULTUS_CONF" | jq -r '.kubeconfig // "未配置"'
    echo ""
    echo "完整配置:"
    sudo cat "$MULTUS_CONF" | jq '.'
else
    echo "✗ 文件不存在: $MULTUS_CONF"
fi

echo ""
echo "检查 DaemonSet 挂载:"
echo "主机路径: $(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}')"
echo "Pod 内挂载点: $(kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}')"

echo ""
echo "检查 Pod 内实际路径:"
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo "Pod: $MULTUS_POD"
    echo ""
    echo "检查 /host/etc/cni/net.d/multus.d/multus.kubeconfig:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/multus.d/multus.kubeconfig 2>&1 || echo "✗ 不存在"
    echo ""
    echo "检查 /etc/cni/net.d/multus.d/multus.kubeconfig:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -la /etc/cni/net.d/multus.d/multus.kubeconfig 2>&1 || echo "✗ 不存在"
fi


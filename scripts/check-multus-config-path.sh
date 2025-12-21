#!/bin/bash

# 检查 Multus 配置文件中的 kubeconfig 路径

CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_DIR/00-multus.conf"

echo "检查 Multus 配置文件中的 kubeconfig 路径..."
echo ""

if [ -f "$MULTUS_CONF" ]; then
    echo "配置文件: $MULTUS_CONF"
    echo ""
    echo "kubeconfig 路径配置:"
    sudo grep -i "kubeconfig" "$MULTUS_CONF" || echo "未找到 kubeconfig 配置"
    echo ""
    echo "完整配置:"
    sudo cat "$MULTUS_CONF"
else
    echo "✗ 配置文件不存在: $MULTUS_CONF"
fi

echo ""
echo "检查 DaemonSet 挂载:"
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}'
echo " -> "
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}'


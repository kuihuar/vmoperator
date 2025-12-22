#!/bin/bash

# 检查实际情况

echo "=== 1. 检查主机文件 ==="
sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/ 2>&1 || echo "目录不存在"

echo ""
echo "=== 2. 检查 DaemonSet 挂载 ==="
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")]}' | jq '.'

echo ""
echo "=== 3. 检查 volumeMounts ==="
kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")]}' | jq '.'

echo ""
echo "=== 4. 检查 Multus 配置文件 ==="
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | jq '.kubeconfig' 2>/dev/null || echo "配置文件不存在或无法读取"

echo ""
echo "=== 5. 检查 Multus Pod 状态 ==="
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "无")
echo "Pod: $MULTUS_POD"
if [ "$MULTUS_POD" != "无" ]; then
    echo "状态: $(kubectl get pod -n kube-system $MULTUS_POD -o jsonpath='{.status.phase}')"
    echo ""
    echo "Pod 内查看:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/multus.d/ 2>&1 || echo "无法访问"
fi


#!/bin/bash

# 检查 virt-handler 状态

echo "=== 1. virt-handler Pod 状态 ==="
kubectl get pods -n kubevirt | grep virt-handler

echo -e "\n=== 2. virt-handler Pod 详情 ==="
POD_NAME=$(kubectl get pods -n kubevirt -o name | grep virt-handler | head -1 | cut -d/ -f2)
if [ -n "$POD_NAME" ]; then
    kubectl describe pod $POD_NAME -n kubevirt | tail -30
fi

echo -e "\n=== 3. 尝试查看 virt-handler 容器日志 ==="
if [ -n "$POD_NAME" ]; then
    kubectl logs $POD_NAME -n kubevirt -c virt-handler --tail=50 2>&1 || echo "无法获取日志"
fi

echo -e "\n=== 4. 检查节点的设备资源 ==="
kubectl describe node docker-desktop | grep -A 5 "Capacity:" | grep -E "devices.kubevirt.io|kvm|tun|vhost" || echo "节点没有虚拟化设备资源"

echo -e "\n=== 5. 检查 KubeVirt 配置 ==="
kubectl get kubevirt -n kubevirt -o jsonpath='{.spec.configuration.developerConfiguration.useEmulation}' && echo ""


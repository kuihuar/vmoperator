#!/bin/bash

# 检查设备资源

echo "=== 1. 检查节点的设备资源 ==="
NODE_NAME=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
kubectl describe node $NODE_NAME | grep -A 30 "Allocated resources"

echo -e "\n=== 2. 检查 KubeVirt 设备插件 ==="
kubectl get daemonset -n kubevirt 2>/dev/null | grep device-plugin || echo "未找到设备插件 DaemonSet"
kubectl get pods -n kubevirt 2>/dev/null | grep device-plugin || echo "未找到设备插件 Pod"

echo -e "\n=== 3. 检查 KubeVirt 配置（useEmulation） ==="
kubectl get kubevirt -n kubevirt -o yaml 2>/dev/null | grep -A 5 "useEmulation" || echo "未找到 useEmulation 配置"

echo -e "\n=== 4. 检查节点是否支持虚拟化 ==="
kubectl get node $NODE_NAME -o yaml | grep -A 10 "status.capacity" | grep -E "devices.kubevirt.io|kvm|tun|vhost"


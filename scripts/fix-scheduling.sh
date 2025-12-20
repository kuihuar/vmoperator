#!/bin/bash

# 修复调度问题的脚本

echo "=== 1. 删除现有的 VM 和 VMI ==="
kubectl delete vm ubuntu-noble-local-vm -n default --ignore-not-found
kubectl delete vmi ubuntu-noble-local-vm -n default --ignore-not-found

echo "=== 2. 等待资源清理 ==="
sleep 5

echo "=== 3. 检查 Wukong 资源 ==="
kubectl get wukong ubuntu-noble-local -n default

echo "=== 4. 重新触发 Reconcile（通过更新 Wukong） ==="
kubectl annotate wukong ubuntu-noble-local -n default novasphere.dev/restart=$(date +%s) --overwrite

echo "=== 5. 等待几秒后检查 VM 状态 ==="
sleep 10
kubectl get vm -n default
kubectl get vmi -n default

echo "=== 6. 检查 virt-launcher Pod ==="
kubectl get pods -n default | grep virt-launcher

echo ""
echo "如果 Pod 仍然无法调度，请运行："
echo "  kubectl describe pod <virt-launcher-pod-name> -n default"
echo "  kubectl get vm ubuntu-noble-local-vm -n default -o yaml | grep -A 10 nodeSelector"


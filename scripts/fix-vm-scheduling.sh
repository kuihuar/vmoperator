#!/bin/bash

# 修复 VM 调度问题的脚本

echo "=== 1. 检查节点 label ==="
kubectl get node docker-desktop --show-labels | grep kubevirt.io/schedulable

echo -e "\n=== 2. 如果 label 不存在，添加它 ==="
if ! kubectl get node docker-desktop --show-labels | grep -q "kubevirt.io/schedulable=true"; then
    echo "添加 kubevirt.io/schedulable=true label..."
    kubectl label node docker-desktop kubevirt.io/schedulable=true
else
    echo "Label 已存在"
fi

echo -e "\n=== 3. 删除旧的 VMI 和 VM ==="
kubectl delete vmi ubuntu-noble-local-vm -n default --ignore-not-found
kubectl delete vm ubuntu-noble-local-vm -n default --ignore-not-found

echo -e "\n=== 4. 等待资源清理 ==="
sleep 5

echo -e "\n=== 5. 重新触发 Wukong Reconcile ==="
kubectl annotate wukong ubuntu-noble-local -n default novasphere.dev/restart=$(date +%s) --overwrite

echo -e "\n=== 6. 等待 10 秒后检查状态 ==="
sleep 10

echo -e "\n=== 7. 检查 VM 和 VMI 状态 ==="
kubectl get vm -n default
kubectl get vmi -n default
kubectl get pods -n default | grep virt-launcher

echo -e "\n=== 8. 如果 Pod 仍然 Pending，查看详细信息 ==="
POD_NAME=$(kubectl get pods -n default -o name | grep virt-launcher | head -1 | cut -d/ -f2)
if [ -n "$POD_NAME" ]; then
    echo "Pod 状态:"
    kubectl get pod $POD_NAME -n default
    echo -e "\nPod 调度事件:"
    kubectl describe pod $POD_NAME -n default | tail -10
fi


#!/bin/bash

# 调度问题排查脚本

echo "=== 1. 节点信息 ==="
kubectl get nodes -o wide

echo -e "\n=== 2. 节点资源 ==="
NODE_NAME=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
kubectl describe node $NODE_NAME | grep -A 10 "Allocated resources"

echo -e "\n=== 3. VMI 状态 ==="
kubectl get vmi -A

echo -e "\n=== 4. virt-launcher Pod ==="
kubectl get pods -A | grep virt-launcher

echo -e "\n=== 5. virt-launcher Pod 详情 ==="
POD_NAME=$(kubectl get pods -n default -o name | grep virt-launcher | head -1 | cut -d/ -f2)
if [ -n "$POD_NAME" ]; then
    kubectl describe pod $POD_NAME -n default | tail -30
else
    echo "未找到 virt-launcher Pod"
fi

echo -e "\n=== 6. 最近的调度事件 ==="
kubectl get events -n default --sort-by='.lastTimestamp' | tail -10

echo -e "\n=== 7. VMI 配置（nodeSelector/affinity） ==="
VMI_NAME=$(kubectl get vmi -n default -o name | head -1 | cut -d/ -f2)
if [ -n "$VMI_NAME" ]; then
    echo "NodeSelector:"
    kubectl get vmi $VMI_NAME -n default -o jsonpath='{.spec.nodeSelector}' 2>/dev/null || echo "无"
    echo -e "\nAffinity:"
    kubectl get vmi $VMI_NAME -n default -o jsonpath='{.spec.affinity}' 2>/dev/null || echo "无"
    echo -e "\nTolerations:"
    kubectl get vmi $VMI_NAME -n default -o jsonpath='{.spec.tolerations}' 2>/dev/null || echo "无"
else
    echo "未找到 VMI"
fi


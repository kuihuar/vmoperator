#!/bin/bash

# 完整的调度问题调试脚本

echo "=== 1. 节点资源容量和已分配 ==="
NODE_NAME=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
kubectl describe node $NODE_NAME | grep -A 15 "Allocated resources"

echo -e "\n=== 2. virt-launcher Pod 信息 ==="
POD_NAME=$(kubectl get pods -n default -o name | grep virt-launcher | head -1 | cut -d/ -f2)
if [ -z "$POD_NAME" ]; then
    echo "未找到 virt-launcher Pod"
else
    echo "Pod 名称: $POD_NAME"
    echo -e "\nPod 的 nodeSelector:"
    kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.nodeSelector}' 2>/dev/null || echo "无"
    echo -e "\nPod 的 affinity:"
    kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.affinity}' 2>/dev/null || echo "无"
    echo -e "\nPod 的 tolerations:"
    kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.tolerations}' 2>/dev/null || echo "无"
    echo -e "\nPod 的资源请求:"
    kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.containers[*].resources}' 2>/dev/null || echo "无"
fi

echo -e "\n=== 3. Pod 的详细调度信息 ==="
if [ -n "$POD_NAME" ]; then
    kubectl describe pod $POD_NAME -n default | tail -40
fi

echo -e "\n=== 4. KubeVirt 配置 ==="
kubectl get kubevirt -n kubevirt -o yaml 2>/dev/null | grep -A 30 "infra\|nodePlacement\|default" || echo "未找到相关配置"

echo -e "\n=== 5. 所有运行中的 Pod 资源使用 ==="
kubectl top node $NODE_NAME 2>/dev/null || echo "metrics-server 未安装，无法查看资源使用"


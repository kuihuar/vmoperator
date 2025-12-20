#!/bin/bash

echo "=== virt-operator Pod 诊断 ==="

# 1. 获取 Pod 名称
POD_NAME=$(kubectl get pods -n kubevirt -l app=virt-operator -o name | head -1 | cut -d/ -f2)

if [ -z "$POD_NAME" ]; then
    echo "未找到 virt-operator Pod"
    exit 1
fi

echo "检查 Pod: $POD_NAME"
echo ""

# 2. 查看 Pod 详情（重点关注 Events）
echo "=== Pod 详情和事件 ==="
kubectl describe pod -n kubevirt $POD_NAME | tail -40

echo ""
echo "=== 最近事件 ==="
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10

echo ""
echo "=== 使用的镜像 ==="
kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}' && echo ""

echo ""
echo "=== 节点资源 ==="
kubectl describe node | grep -A 10 "Allocated resources" | head -15


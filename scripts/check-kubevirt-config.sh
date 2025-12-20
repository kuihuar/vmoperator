#!/bin/bash

# 检查 KubeVirt 的配置

echo "=== 检查 KubeVirt CR 配置 ==="
kubectl get kubevirt -n kubevirt -o yaml 2>/dev/null | grep -A 30 "nodeSelector\|affinity\|default" || echo "未找到 KubeVirt CR 或没有相关配置"

echo -e "\n=== 检查 KubeVirt Operator 配置 ==="
kubectl get deployment kubevirt-operator -n kubevirt -o yaml 2>/dev/null | grep -A 10 "nodeSelector\|affinity" || echo "未找到 KubeVirt Operator"

echo -e "\n=== 检查节点的资源 ==="
NODE_NAME=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
kubectl describe node $NODE_NAME | grep -A 10 "Allocated resources"

echo -e "\n=== 检查节点的容量 ==="
kubectl describe node $NODE_NAME | grep -A 5 "Capacity:"


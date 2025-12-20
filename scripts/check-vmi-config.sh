#!/bin/bash

# 检查 VMI 的调度配置

VMI_NAME="ubuntu-noble-local-vm"
NAMESPACE="default"

echo "=== 检查 VMI 的 nodeSelector ==="
kubectl get vmi $VMI_NAME -n $NAMESPACE -o jsonpath='{.spec.nodeSelector}' 2>/dev/null
echo ""

echo "=== 检查 VMI 的 affinity ==="
kubectl get vmi $VMI_NAME -n $NAMESPACE -o jsonpath='{.spec.affinity}' 2>/dev/null
echo ""

echo "=== 检查 VMI 的 tolerations ==="
kubectl get vmi $VMI_NAME -n $NAMESPACE -o jsonpath='{.spec.tolerations}' 2>/dev/null
echo ""

echo "=== 检查 VM 的 template.spec.nodeSelector ==="
kubectl get vm $VMI_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null
echo ""

echo "=== 检查 VM 的 template.spec.affinity ==="
kubectl get vm $VMI_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.affinity}' 2>/dev/null
echo ""

echo "=== 检查节点的 labels ==="
NODE_NAME=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
kubectl get node $NODE_NAME --show-labels


#!/bin/bash

echo "=== KubeVirt 完整状态检查 ==="

# 1. 检查命名空间
echo -e "\n1. 检查 kubevirt 命名空间:"
if kubectl get namespace kubevirt > /dev/null 2>&1; then
    echo "   ✓ kubevirt 命名空间存在"
    kubectl get namespace kubevirt
else
    echo "   ✗ kubevirt 命名空间不存在"
    echo "   需要重新安装 KubeVirt Operator"
    exit 1
fi

# 2. 检查 Deployment
echo -e "\n2. 检查 virt-operator Deployment:"
if kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1; then
    echo "   ✓ virt-operator Deployment 存在"
    kubectl get deployment -n kubevirt virt-operator
    echo ""
    echo "   Deployment 状态:"
    kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.status.conditions[*].type}' | tr ' ' '\n' | while read condition; do
        STATUS=$(kubectl get deployment -n kubevirt virt-operator -o jsonpath="{.status.conditions[?(@.type==\"$condition\")].status}")
        echo "     $condition: $STATUS"
    done
else
    echo "   ✗ virt-operator Deployment 不存在"
    echo "   需要重新安装 KubeVirt Operator"
fi

# 3. 检查所有 Pods
echo -e "\n3. kubevirt 命名空间中的所有 Pods:"
PODS=$(kubectl get pods -n kubevirt --no-headers 2>/dev/null | wc -l)
if [ "$PODS" -gt 0 ]; then
    kubectl get pods -n kubevirt
    echo ""
    echo "   Pod 详情:"
    kubectl get pods -n kubevirt -o wide
else
    echo "   ⚠️  没有运行中的 Pods"
fi

# 4. 检查 ReplicaSet
echo -e "\n4. 检查 ReplicaSet:"
kubectl get replicaset -n kubevirt -l app=virt-operator 2>/dev/null || echo "   没有找到 ReplicaSet"

# 5. 检查事件
echo -e "\n5. 最近的事件:"
kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "   没有事件"

# 6. 检查 KubeVirt CR
echo -e "\n6. 检查 KubeVirt CR:"
if kubectl get kubevirt -n kubevirt kubevirt > /dev/null 2>&1; then
    echo "   ✓ KubeVirt CR 已创建"
    kubectl get kubevirt -n kubevirt kubevirt
else
    echo "   ✗ KubeVirt CR 未创建"
    echo "   需要安装 KubeVirt CR"
fi

# 7. 总结
echo -e "\n=== 总结 ==="
if kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1; then
    READY=$(kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
        echo "✓ KubeVirt Operator 运行正常"
    elif [ "$DESIRED" != "0" ]; then
        echo "⚠️  KubeVirt Operator 未就绪 (Ready: $READY/$DESIRED)"
        echo "   检查 Pods 状态: kubectl get pods -n kubevirt"
    else
        echo "⚠️  KubeVirt Operator Deployment 存在但未运行"
    fi
else
    echo "✗ KubeVirt Operator 未安装"
    echo "   运行: ./scripts/install-kubevirt.sh"
fi


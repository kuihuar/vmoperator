#!/bin/bash

# 检查 KubeVirt 安装状态

echo "=== KubeVirt 安装检查 ==="

# 1. 检查命名空间
echo -e "\n1. 检查 kubevirt 命名空间:"
if kubectl get namespace kubevirt > /dev/null 2>&1; then
    echo "   ✓ kubevirt 命名空间存在"
    kubectl get namespace kubevirt
else
    echo "   ✗ kubevirt 命名空间不存在"
    echo "   需要安装 KubeVirt Operator"
fi

# 2. 检查 Operator Deployment
echo -e "\n2. 检查 virt-operator Deployment:"
if kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1; then
    echo "   ✓ virt-operator Deployment 存在"
    kubectl get deployment -n kubevirt virt-operator
    echo ""
    kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.status.conditions[*].type}' | tr ' ' '\n' | while read condition; do
        STATUS=$(kubectl get deployment -n kubevirt virt-operator -o jsonpath="{.status.conditions[?(@.type==\"$condition\")].status}")
        echo "     $condition: $STATUS"
    done
else
    echo "   ✗ virt-operator Deployment 不存在"
fi

# 3. 检查所有 Pods
echo -e "\n3. kubevirt 命名空间中的所有 Pods:"
kubectl get pods -n kubevirt 2>/dev/null || echo "   命名空间不存在或无 Pods"

# 4. 检查 CRD
echo -e "\n4. 检查 KubeVirt CRD:"
if kubectl get crd virtualmachines.kubevirt.io > /dev/null 2>&1; then
    echo "   ✓ VirtualMachine CRD 已安装"
else
    echo "   ✗ VirtualMachine CRD 未安装"
fi

if kubectl get crd virtualmachineinstances.kubevirt.io > /dev/null 2>&1; then
    echo "   ✓ VirtualMachineInstance CRD 已安装"
else
    echo "   ✗ VirtualMachineInstance CRD 未安装"
fi

# 5. 检查 KubeVirt CR
echo -e "\n5. 检查 KubeVirt CR:"
if kubectl get kubevirt -n kubevirt kubevirt > /dev/null 2>&1; then
    echo "   ✓ KubeVirt CR 已创建"
    kubectl get kubevirt -n kubevirt kubevirt
    echo ""
    kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.phase}' && echo " (phase)"
else
    echo "   ✗ KubeVirt CR 未创建"
fi

# 6. 检查 API 资源
echo -e "\n6. 检查 KubeVirt API 资源:"
if kubectl api-resources | grep -q virtualmachines; then
    echo "   ✓ VirtualMachine API 已注册"
    kubectl api-resources | grep virtualmachine
else
    echo "   ✗ VirtualMachine API 未注册"
fi

# 7. 总结
echo -e "\n=== 总结 ==="
if kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1 && \
   kubectl get pods -n kubevirt -l app=virt-operator | grep -q Running; then
    echo "✓ KubeVirt Operator 已安装并运行"
elif kubectl get deployment -n kubevirt virt-operator > /dev/null 2>&1; then
    echo "⚠️  KubeVirt Operator 已安装但未运行"
    echo "   运行: ./scripts/check-kubevirt-operator.sh 查看详情"
else
    echo "✗ KubeVirt Operator 未安装"
    echo "   需要安装 KubeVirt:"
    echo "   ./scripts/install-kubevirt.sh"
    echo "   或参考: docs/K3S_SETUP.md"
fi


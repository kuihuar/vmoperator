#!/bin/bash

# 检查 KubeVirt 完整状态

echo "=== 检查 KubeVirt 完整状态 ==="

# 1. 检查 virt-operator Pods
echo -e "\n1. 检查 virt-operator Pods..."
kubectl get pods -n kubevirt -l app=virt-operator
OPERATOR_READY=$(kubectl get pods -n kubevirt -l app=virt-operator -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
if echo "$OPERATOR_READY" | grep -q "Running"; then
    echo "✓ virt-operator Pods 正在运行"
else
    echo "⚠️  virt-operator Pods 未完全运行"
fi

# 2. 检查 KubeVirt CR
echo -e "\n2. 检查 KubeVirt CR..."
if kubectl get kubevirt -n kubevirt 2>/dev/null | grep -q kubevirt; then
    echo "✓ KubeVirt CR 存在:"
    kubectl get kubevirt -n kubevirt
    echo ""
    echo "KubeVirt CR 详情:"
    kubectl get kubevirt kubevirt -n kubevirt -o yaml | grep -A 20 "status:" | head -25
else
    echo "⚠️  KubeVirt CR 不存在，virt-operator 可能还在初始化"
    echo "等待 virt-operator 创建 KubeVirt CR..."
    sleep 10
    if kubectl get kubevirt -n kubevirt 2>/dev/null | grep -q kubevirt; then
        echo "✓ KubeVirt CR 已创建"
        kubectl get kubevirt -n kubevirt
    else
        echo "⚠️  KubeVirt CR 仍未创建，检查 virt-operator 日志:"
        kubectl logs -n kubevirt -l app=virt-operator --tail=20 | head -20
    fi
fi

# 3. 检查所有 KubeVirt 组件
echo -e "\n3. 检查所有 KubeVirt 组件..."
echo "所有 kubevirt namespace 的 Pods:"
kubectl get pods -n kubevirt

# 检查各个组件
COMPONENTS=("virt-operator" "virt-controller" "virt-handler" "virt-api")
for component in "${COMPONENTS[@]}"; do
    echo -e "\n检查 $component:"
    if kubectl get pods -n kubevirt -l kubevirt.io=$component 2>/dev/null | grep -q .; then
        kubectl get pods -n kubevirt -l kubevirt.io=$component
        READY=$(kubectl get pods -n kubevirt -l kubevirt.io=$component -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
        if echo "$READY" | grep -q "Running"; then
            echo "  ✓ $component 正在运行"
        else
            echo "  ⚠️  $component 未完全运行"
        fi
    else
        echo "  ⚠️  $component 未找到"
    fi
done

# 4. 检查 KubeVirt CRDs
echo -e "\n4. 检查 KubeVirt CRDs..."
KUBEVIRT_CRDS=("virtualmachines" "virtualmachineinstances" "virtualmachineinstancemigrations")
for crd in "${KUBEVIRT_CRDS[@]}"; do
    if kubectl get crd ${crd}.kubevirt.io 2>/dev/null | grep -q ${crd}; then
        echo "  ✓ $crd CRD 存在"
    else
        echo "  ⚠️  $crd CRD 不存在"
    fi
done

# 5. 检查 KubeVirt 版本
echo -e "\n5. 检查 KubeVirt 版本..."
if kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.observedKubeVirtVersion}' 2>/dev/null; then
    VERSION=$(kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.observedKubeVirtVersion}' 2>/dev/null)
    echo "KubeVirt 版本: $VERSION"
else
    echo "⚠️  无法获取 KubeVirt 版本"
fi

# 6. 检查节点标签
echo -e "\n6. 检查节点标签..."
kubectl get nodes --show-labels | grep -E "NAME|kubevirt"

# 7. 检查 virt-handler DaemonSet
echo -e "\n7. 检查 virt-handler DaemonSet..."
if kubectl get daemonset -n kubevirt virt-handler 2>/dev/null | grep -q virt-handler; then
    echo "virt-handler DaemonSet:"
    kubectl get daemonset -n kubevirt virt-handler
    echo ""
    echo "virt-handler Pods:"
    kubectl get pods -n kubevirt -l kubevirt.io=virt-handler
else
    echo "⚠️  virt-handler DaemonSet 不存在"
fi

# 8. 检查最新事件
echo -e "\n8. 检查最新事件..."
kubectl get events -n kubevirt --sort-by='.lastTimestamp' 2>/dev/null | tail -10

# 9. 总结
echo -e "\n=== 状态总结 ==="
echo ""
echo "✓ virt-operator: 运行中"
if kubectl get kubevirt -n kubevirt kubevirt 2>/dev/null | grep -q kubevirt; then
    echo "✓ KubeVirt CR: 已创建"
    
    # 检查 KubeVirt 是否就绪
    PHASE=$(kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$PHASE" = "Deployed" ]; then
        echo "✓ KubeVirt: 已部署"
    else
        echo "⚠️  KubeVirt 状态: $PHASE"
    fi
else
    echo "⚠️  KubeVirt CR: 未创建（virt-operator 可能还在初始化）"
fi

echo ""
echo "下一步操作："
echo "  1. 等待 KubeVirt 完全部署（如果还未完成）"
echo "  2. 验证 KubeVirt CRDs: kubectl get crd | grep kubevirt"
echo "  3. 创建 Wukong 资源测试 VM: kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml"
echo "  4. 检查 VM 状态: kubectl get wukong, kubectl get vm, kubectl get vmi"

echo ""
echo "=== 检查完成 ==="

#!/bin/bash

# 检查 KubeVirt Operator 状态

echo "=== KubeVirt Operator 诊断 ==="

# 1. 检查 Pod 状态
echo -e "\n1. virt-operator Pod 状态:"
kubectl get pods -n kubevirt -l app=virt-operator

# 2. 检查 Pod 详情
echo -e "\n2. virt-operator Pod 详情:"
POD_NAME=$(kubectl get pods -n kubevirt -l app=virt-operator -o name | head -1 | cut -d/ -f2)
if [ -n "$POD_NAME" ]; then
    echo "检查 Pod: $POD_NAME"
    kubectl describe pod -n kubevirt $POD_NAME | tail -30
else
    echo "未找到 virt-operator Pod"
fi

# 3. 检查事件
echo -e "\n3. 最近的事件:"
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -20

# 4. 检查镜像拉取
echo -e "\n4. 检查镜像拉取问题:"
if [ -n "$POD_NAME" ]; then
    kubectl describe pod -n kubevirt $POD_NAME | grep -A 5 "Events:" | grep -i "pull\|image\|error\|failed" || echo "未发现明显的镜像拉取错误"
fi

# 5. 检查节点资源
echo -e "\n5. 节点资源状态:"
kubectl describe node | grep -A 10 "Allocated resources" | head -15

# 6. 检查节点条件
echo -e "\n6. 节点条件:"
kubectl get node -o jsonpath='{.items[0].status.conditions[*].type}' | tr ' ' '\n' | while read condition; do
    STATUS=$(kubectl get node -o jsonpath="{.items[0].status.conditions[?(@.type==\"$condition\")].status}")
    echo "  $condition: $STATUS"
done

# 7. 检查 KubeVirt Operator 部署
echo -e "\n7. KubeVirt Operator 部署状态:"
kubectl get deployment -n kubevirt virt-operator -o yaml | grep -A 5 "image:" || echo "无法获取部署信息"

# 8. 常见问题检查
echo -e "\n=== 常见问题检查 ==="

# 检查镜像拉取策略
echo -e "\n8. 镜像拉取策略:"
kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' && echo "" || echo "无法获取"

# 检查节点是否 Ready
NODE_READY=$(kubectl get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
if [ "$NODE_READY" != "True" ]; then
    echo -e "\n⚠️  节点未就绪: $NODE_READY"
    kubectl get node
fi

# 检查存储
echo -e "\n9. 检查存储:"
kubectl get pvc -n kubevirt 2>/dev/null || echo "无 PVC"

# 10. 建议
echo -e "\n=== 建议 ==="
echo "如果 Pod 一直处于 ContainerCreating 状态，常见原因："
echo "  1. 镜像拉取失败 - 检查网络连接和镜像仓库访问"
echo "  2. 节点资源不足 - 检查节点 CPU/内存"
echo "  3. 存储问题 - 检查 PV/PVC"
echo "  4. 网络问题 - 检查 CNI 插件"
echo ""
echo "查看详细日志:"
echo "  kubectl describe pod -n kubevirt <pod-name>"
echo "  kubectl logs -n kubevirt <pod-name> (如果 Pod 已启动)"


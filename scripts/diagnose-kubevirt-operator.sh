#!/bin/bash

# 诊断 virt-operator 为什么没有创建 KubeVirt CR

echo "=== 诊断 virt-operator ==="

# 1. 检查 virt-operator Pods 状态
echo -e "\n1. 检查 virt-operator Pods 状态..."
kubectl get pods -n kubevirt -l app=virt-operator

# 2. 检查 virt-operator 日志
echo -e "\n2. 检查 virt-operator 日志（最近 50 行）..."
for pod in $(kubectl get pods -n kubevirt -l app=virt-operator -o jsonpath='{.items[*].metadata.name}'); do
    echo -e "\n--- Pod: $pod ---"
    kubectl logs -n kubevirt "$pod" --tail=50 | tail -30
done

# 3. 检查是否有错误事件
echo -e "\n3. 检查错误事件..."
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | grep -i "error\|fail\|denied" | tail -10

# 4. 检查 KubeVirt CR 是否存在
echo -e "\n4. 检查 KubeVirt CR..."
if kubectl get kubevirt -n kubevirt 2>/dev/null | grep -q kubevirt; then
    echo "✓ KubeVirt CR 存在:"
    kubectl get kubevirt -n kubevirt
else
    echo "⚠️  KubeVirt CR 不存在"
    echo "尝试手动创建 KubeVirt CR..."
    
    # 检查是否有 KubeVirt CRD
    if kubectl get crd kubevirts.kubevirt.io 2>/dev/null | grep -q kubevirt; then
        echo "✓ KubeVirt CRD 存在，可以创建 CR"
        echo ""
        echo "创建 KubeVirt CR..."
        kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: KubeVirt
metadata:
  name: kubevirt
  namespace: kubevirt
spec:
  certificateRotateStrategy: {}
  configuration:
    developerConfiguration:
      useEmulation: true
  customizeComponents: {}
  imagePullPolicy: IfNotPresent
  workloadUpdateStrategy: {}
EOF
        echo ""
        echo "等待 KubeVirt CR 创建..."
        sleep 10
        
        if kubectl get kubevirt -n kubevirt kubevirt 2>/dev/null | grep -q kubevirt; then
            echo "✓ KubeVirt CR 已创建"
        else
            echo "⚠️  KubeVirt CR 创建失败，检查错误:"
            kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -5
        fi
    else
        echo "❌ KubeVirt CRD 不存在，virt-operator 可能没有正确安装"
        echo "检查 CRD:"
        kubectl get crd | grep kubevirt
    fi
fi

# 5. 检查 virt-operator 的 RBAC 权限
echo -e "\n5. 检查 virt-operator 的 RBAC 权限..."
echo "ServiceAccount:"
kubectl get sa -n kubevirt virt-operator 2>/dev/null || echo "  virt-operator ServiceAccount 不存在"

echo ""
echo "ClusterRole:"
kubectl get clusterrole | grep virt-operator || echo "  virt-operator ClusterRole 不存在"

echo ""
echo "ClusterRoleBinding:"
kubectl get clusterrolebinding | grep virt-operator || echo "  virt-operator ClusterRoleBinding 不存在"

# 6. 检查 virt-operator Deployment
echo -e "\n6. 检查 virt-operator Deployment..."
kubectl get deployment -n kubevirt virt-operator -o yaml | grep -A 10 "spec:" | head -15

# 7. 检查 Pod 描述
echo -e "\n7. 检查 Pod 描述（查看是否有错误）..."
for pod in $(kubectl get pods -n kubevirt -l app=virt-operator -o jsonpath='{.items[*].metadata.name}'); do
    echo -e "\n--- Pod: $pod ---"
    kubectl describe pod -n kubevirt "$pod" | grep -A 10 "Events:" | head -15
done

# 8. 检查是否有 KubeVirt Operator 安装文件
echo -e "\n8. 检查 KubeVirt Operator 安装..."
echo "检查是否有安装相关的资源:"
kubectl get all -n kubevirt | grep -E "operator|virt"

# 9. 建议
echo -e "\n=== 诊断总结 ==="
echo ""
if kubectl get kubevirt -n kubevirt kubevirt 2>/dev/null | grep -q kubevirt; then
    echo "✓ KubeVirt CR 已存在"
    echo "等待 virt-operator 创建其他组件..."
    echo "运行以下命令检查进度:"
    echo "  kubectl get pods -n kubevirt"
    echo "  kubectl get kubevirt -n kubevirt kubevirt -o yaml | grep -A 20 status"
else
    echo "⚠️  KubeVirt CR 不存在"
    echo ""
    echo "可能的原因："
    echo "  1. virt-operator 没有自动创建 KubeVirt CR"
    echo "  2. 需要手动创建 KubeVirt CR"
    echo "  3. virt-operator 没有权限创建资源"
    echo ""
    echo "解决方案："
    echo "  1. 检查 virt-operator 日志（见上方）"
    echo "  2. 手动创建 KubeVirt CR（脚本已尝试）"
    echo "  3. 检查 RBAC 权限"
    echo ""
    echo "如果手动创建失败，可以尝试重新安装 KubeVirt:"
    echo "  ./scripts/install-kubevirt.sh"
fi

echo ""
echo "=== 诊断完成 ==="


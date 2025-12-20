#!/bin/bash

echo "=== virt-operator Pods 详细诊断 ==="

# 1. 获取 Pod 名称
POD_NAME=$(kubectl get pods -n kubevirt -l app=virt-operator -o name | head -1 | cut -d/ -f2)

if [ -z "$POD_NAME" ]; then
    echo "未找到 virt-operator Pod"
    exit 1
fi

echo "检查 Pod: $POD_NAME"
echo ""

# 2. 查看 Pod 详情（重点关注 Events 和 Status）
echo "=== Pod 详情 ==="
kubectl describe pod -n kubevirt $POD_NAME

echo ""
echo "=== 最近事件（kubevirt 命名空间）==="
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -15

echo ""
echo "=== 使用的镜像 ==="
kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}' && echo ""

echo ""
echo "=== 节点资源 ==="
kubectl describe node | grep -A 10 "Allocated resources" | head -15

echo ""
echo "=== 建议 ==="
echo "如果看到 'ImagePullBackOff' 或 'ErrImagePull'，说明镜像拉取失败"
echo "解决方案："
echo "  1. 在节点上手动拉取镜像: sudo crictl pull quay.io/kubevirt/virt-operator:v1.2.0"
echo "  2. 删除 Pod 让它重新创建: kubectl delete pod -n kubevirt $POD_NAME"
echo "  3. 检查网络连接: curl -I https://quay.io"


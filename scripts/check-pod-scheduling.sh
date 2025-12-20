#!/bin/bash

# 检查 virt-launcher Pod 的调度配置

POD_NAME=$(kubectl get pods -n default -o name | grep virt-launcher | head -1 | cut -d/ -f2)

if [ -z "$POD_NAME" ]; then
    echo "未找到 virt-launcher Pod"
    exit 1
fi

echo "=== Pod 名称 ==="
echo $POD_NAME

echo -e "\n=== Pod 的 nodeSelector ==="
kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.nodeSelector}' 2>/dev/null
echo ""

echo -e "\n=== Pod 的 affinity ==="
kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.affinity}' 2>/dev/null
echo ""

echo -e "\n=== Pod 的 tolerations ==="
kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.tolerations}' 2>/dev/null
echo ""

echo -e "\n=== Pod 的资源请求 ==="
kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.containers[*].resources}' 2>/dev/null
echo ""

echo -e "\n=== Pod 的完整调度信息 ==="
kubectl get pod $POD_NAME -n default -o yaml | grep -A 30 "nodeSelector\|affinity\|tolerations\|resources:"

echo -e "\n=== Pod 的调度事件 ==="
kubectl describe pod $POD_NAME -n default | grep -A 10 "Events:"


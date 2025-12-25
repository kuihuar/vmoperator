#!/bin/bash

# 检查 CoreDNS 配置（修复版，处理没有 cat 的情况）

echo "=========================================="
echo "检查 CoreDNS 配置"
echo "=========================================="
echo ""

# 方法 1：直接查看 ConfigMap（最简单，推荐）
echo "方法 1：查看 CoreDNS ConfigMap（推荐）"
echo ""
kubectl get configmap coredns -n kube-system -o yaml | grep -A 100 "Corefile:" | head -80

echo ""
echo "=========================================="
echo ""

# 方法 2：在 Pod 内使用 sh -c
echo "方法 2：在 Pod 内使用 sh -c"
COREDNS_POD_NAME=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1 | cut -d'/' -f2)
if [ -n "${COREDNS_POD_NAME}" ]; then
    echo "CoreDNS Pod: ${COREDNS_POD_NAME}"
    echo ""
    echo "Corefile 内容："
    kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "cat /etc/coredns/Corefile" 2>/dev/null || \
    kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "ls -la /etc/coredns/" 2>/dev/null || \
    echo "无法读取（可能 Pod 内没有 sh 或文件不存在）"
else
    echo "未找到 CoreDNS Pod"
fi

echo ""
echo "=========================================="
echo ""

# 方法 3：使用 kubectl describe 查看 Pod 配置
echo "方法 3：查看 Pod 配置"
if [ -n "${COREDNS_POD_NAME}" ]; then
    echo "Pod 环境变量和挂载："
    kubectl describe pod -n kube-system ${COREDNS_POD_NAME} | grep -A 20 "Environment\|Mounts" | head -30
fi

echo ""
echo "=========================================="
echo ""

# 方法 4：检查是否有自定义配置
echo "方法 4：检查自定义配置"
if [ -n "${COREDNS_POD_NAME}" ]; then
    echo "检查 /etc/coredns/custom/ 目录："
    kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "ls -la /etc/coredns/custom/ 2>/dev/null || echo '目录不存在'" 2>/dev/null || echo "无法访问"
fi

echo ""
echo "=========================================="
echo ""

# 方法 5：直接查看 ConfigMap 的完整内容
echo "方法 5：CoreDNS ConfigMap 完整内容"
kubectl get configmap coredns -n kube-system -o yaml


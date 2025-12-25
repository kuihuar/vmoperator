#!/bin/bash

# 简单检查 CoreDNS 配置

echo "=========================================="
echo "检查 CoreDNS 配置"
echo "=========================================="
echo ""

# 方法 1：使用 pod/name 格式（kubectl exec 支持）
echo "方法 1：使用 pod/name 格式"
COREDNS_POD=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
if [ -n "${COREDNS_POD}" ]; then
    echo "找到 CoreDNS Pod: ${COREDNS_POD}"
    echo ""
    echo "Corefile 内容："
    kubectl exec -n kube-system ${COREDNS_POD} -- cat /etc/coredns/Corefile 2>/dev/null || echo "无法读取"
else
    echo "未找到 CoreDNS Pod"
fi

echo ""
echo "=========================================="
echo ""

# 方法 2：提取 Pod 名称（更可靠）
echo "方法 2：提取 Pod 名称"
COREDNS_POD_NAME=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1 | cut -d'/' -f2)
if [ -n "${COREDNS_POD_NAME}" ]; then
    echo "找到 CoreDNS Pod: ${COREDNS_POD_NAME}"
    echo ""
    echo "Corefile 内容："
    kubectl exec -n kube-system ${COREDNS_POD_NAME} -- cat /etc/coredns/Corefile 2>/dev/null || echo "无法读取"
else
    echo "未找到 CoreDNS Pod"
fi

echo ""
echo "=========================================="
echo ""

# 方法 3：直接使用 kubectl get pods（最简单）
echo "方法 3：直接使用 kubectl get pods"
COREDNS_POD_NAME=$(kubectl get pods -n kube-system | grep -iE "coredns|dns" | head -1 | awk '{print $1}')
if [ -n "${COREDNS_POD_NAME}" ]; then
    echo "找到 CoreDNS Pod: ${COREDNS_POD_NAME}"
    echo ""
    echo "Corefile 内容："
    kubectl exec -n kube-system ${COREDNS_POD_NAME} -- cat /etc/coredns/Corefile 2>/dev/null || echo "无法读取"
else
    echo "未找到 CoreDNS Pod"
fi

echo ""
echo "=========================================="
echo ""

# 同时检查 ConfigMap
echo "检查 CoreDNS ConfigMap："
kubectl get configmap coredns -n kube-system -o yaml | grep -A 50 "Corefile:" | head -60


#!/bin/bash

# 获取 CoreDNS Pod 名称的多种方法

echo "方法 1：使用 kubectl get pods（最可靠）"
COREDNS_POD_NAME=$(kubectl get pods -n kube-system | grep -iE "coredns|dns" | head -1 | awk '{print $1}')
echo "Pod 名称: ${COREDNS_POD_NAME}"
echo ""

echo "方法 2：使用标签选择器"
COREDNS_POD_NAME=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "Pod 名称: ${COREDNS_POD_NAME}"
echo ""

echo "方法 3：使用 kubectl get pods -o name 然后提取"
COREDNS_POD_NAME=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
echo "Pod 名称（带 pod/ 前缀）: ${COREDNS_POD_NAME}"
if [ -n "${COREDNS_POD_NAME}" ]; then
    # 提取实际名称
    POD_NAME_ONLY=$(echo ${COREDNS_POD_NAME} | sed 's|pod/||')
    echo "Pod 名称（仅名称）: ${POD_NAME_ONLY}"
fi
echo ""

echo "方法 4：列出所有可能的 Pod"
echo "所有 kube-system 命名空间的 Pod："
kubectl get pods -n kube-system | grep -iE "coredns|dns" | head -5


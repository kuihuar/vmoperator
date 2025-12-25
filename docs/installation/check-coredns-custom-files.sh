#!/bin/bash

# 检查 CoreDNS Pod 内的自定义配置文件

echo "=========================================="
echo "检查 CoreDNS 自定义配置文件"
echo "=========================================="
echo ""

COREDNS_POD_NAME=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1 | cut -d'/' -f2)

if [ -z "${COREDNS_POD_NAME}" ]; then
    echo "未找到 CoreDNS Pod"
    exit 1
fi

echo "CoreDNS Pod: ${COREDNS_POD_NAME}"
echo ""

# 1. 检查 /etc/coredns/custom/ 目录
echo "1. 检查 /etc/coredns/custom/ 目录："
kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "ls -la /etc/coredns/custom/ 2>/dev/null || echo '目录不存在'" 2>/dev/null

echo ""
echo "2. 检查自定义配置文件内容："

# 检查 .override 文件
OVERRIDE_FILES=$(kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "ls /etc/coredns/custom/*.override 2>/dev/null || echo ''" 2>/dev/null)
if [ -n "${OVERRIDE_FILES}" ]; then
    echo "  发现 .override 文件："
    for file in ${OVERRIDE_FILES}; do
        echo "    文件: ${file}"
        kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "cat ${file} 2>/dev/null || echo '无法读取'" 2>/dev/null | sed 's/^/      /'
    done
else
    echo "  未发现 .override 文件"
fi

# 检查 .server 文件
SERVER_FILES=$(kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "ls /etc/coredns/custom/*.server 2>/dev/null || echo ''" 2>/dev/null)
if [ -n "${SERVER_FILES}" ]; then
    echo "  发现 .server 文件："
    for file in ${SERVER_FILES}; do
        echo "    文件: ${file}"
        kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "cat ${file} 2>/dev/null || echo '无法读取'" 2>/dev/null | sed 's/^/      /'
    done
else
    echo "  未发现 .server 文件"
fi

echo ""
echo "3. 检查 /etc/coredns/NodeHosts 文件："
kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "cat /etc/coredns/NodeHosts 2>/dev/null || echo '无法读取'" 2>/dev/null | sed 's/^/  /'

echo ""
echo "4. 检查 Pod 内的 /etc/hosts："
kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "cat /etc/hosts 2>/dev/null | grep -E '198\.18|kubernetes|kube-dns' || echo '未发现相关条目'" 2>/dev/null | sed 's/^/  /'

echo ""
echo "5. 在 Pod 内测试 DNS 查询："
kubectl exec -n kube-system ${COREDNS_POD_NAME} -- sh -c "nslookup kubernetes.default.svc.cluster.local 2>&1 || echo '查询失败'" 2>/dev/null | sed 's/^/  /'

echo ""
echo "=========================================="
echo ""


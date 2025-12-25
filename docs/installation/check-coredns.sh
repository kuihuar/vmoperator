#!/bin/bash

# 检查 CoreDNS 状态和 DNS 解析

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "CoreDNS 状态检查"
echo_info "=========================================="
echo ""

# 1. 检查 ServiceAccount
echo_info "1. 检查 CoreDNS ServiceAccount..."
SA_SECRETS=$(kubectl get sa coredns -n kube-system -o jsonpath='{.secrets[*].name}' 2>/dev/null | wc -w)
if [ "${SA_SECRETS}" -eq 0 ]; then
    echo_info "  ✓ ServiceAccount 存在，SECRETS=0（这是正常的）"
    echo_info "    说明：SECRETS 为 0 表示没有挂载 Secret，不影响 DNS 解析"
else
    echo_info "  ✓ ServiceAccount 存在，SECRETS=${SA_SECRETS}"
fi

# 2. 检查 CoreDNS Pod 状态
echo ""
echo_info "2. 检查 CoreDNS Pod 状态..."
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name 2>/dev/null || kubectl get pods -n kube-system -l k8s-app=coredns -o name 2>/dev/null)
if [ -n "${COREDNS_PODS}" ]; then
    echo_info "  ✓ 找到 CoreDNS Pod"
    kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || kubectl get pods -n kube-system -l k8s-app=coredns 2>/dev/null
    
    # 检查 Pod 状态
    COREDNS_POD_NAME=$(echo ${COREDNS_PODS} | head -1 | cut -d'/' -f2)
    POD_STATUS=$(kubectl get pod ${COREDNS_POD_NAME} -n kube-system -o jsonpath='{.status.phase}' 2>/dev/null)
    POD_READY=$(kubectl get pod ${COREDNS_POD_NAME} -n kube-system -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    
    if [ "${POD_STATUS}" = "Running" ] && [ "${POD_READY}" = "true" ]; then
        echo_info "  ✓ Pod 状态正常：Running 且 Ready"
    else
        echo_warn "  ⚠️  Pod 状态异常：${POD_STATUS}, Ready=${POD_READY}"
        echo_info "  查看 Pod 详情："
        kubectl describe pod ${COREDNS_POD_NAME} -n kube-system | tail -20
    fi
else
    echo_error "  ✗ 未找到 CoreDNS Pod"
    echo_warn "  这会导致集群 DNS 解析失败"
fi

# 3. 检查 CoreDNS Service
echo ""
echo_info "3. 检查 CoreDNS Service..."
if kubectl get svc kube-dns -n kube-system &>/dev/null; then
    echo_info "  ✓ kube-dns Service 存在"
    kubectl get svc kube-dns -n kube-system
    SERVICE_IP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    echo_info "  ClusterIP: ${SERVICE_IP}"
else
    echo_warn "  ⚠️  kube-dns Service 不存在"
fi

# 4. 检查 CoreDNS 配置
echo ""
echo_info "4. 检查 CoreDNS 配置..."
if kubectl get configmap coredns -n kube-system &>/dev/null; then
    echo_info "  ✓ CoreDNS ConfigMap 存在"
    echo_info "  配置内容："
    kubectl get configmap coredns -n kube-system -o yaml | grep -A 20 "data:" | head -25
else
    echo_warn "  ⚠️  CoreDNS ConfigMap 不存在"
fi

# 5. 测试 DNS 解析
echo ""
echo_info "5. 测试 DNS 解析..."
TEST_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name 2>/dev/null | head -1)
if [ -z "${TEST_POD}" ]; then
    # 如果没有 longhorn-manager，尝试用其他 Pod
    TEST_POD=$(kubectl get pods -A -o name 2>/dev/null | head -1)
fi

if [ -n "${TEST_POD}" ]; then
    POD_NAME=$(echo ${TEST_POD} | cut -d'/' -f2)
    POD_NS=$(kubectl get ${TEST_POD} -o jsonpath='{.metadata.namespace}' 2>/dev/null)
    echo_info "  使用测试 Pod: ${POD_NS}/${POD_NAME}"
    
    # 测试解析 kubernetes.default.svc
    echo_info "  测试解析 kubernetes.default.svc.cluster.local..."
    DNS_TEST1=$(kubectl exec -n ${POD_NS} ${POD_NAME} -- nslookup kubernetes.default.svc.cluster.local 2>&1 | grep -A 2 "Name:" || echo "解析失败")
    if echo "${DNS_TEST1}" | grep -q "Name:"; then
        echo_info "  ✓ 基础 DNS 解析正常"
        echo "${DNS_TEST1}" | head -3 | sed 's/^/    /'
    else
        echo_error "  ✗ 基础 DNS 解析失败"
        echo "${DNS_TEST1}" | head -5
    fi
    
    # 测试解析 longhorn-conversion-webhook
    echo ""
    echo_info "  测试解析 longhorn-conversion-webhook.longhorn-system.svc..."
    DNS_TEST2=$(kubectl exec -n ${POD_NS} ${POD_NAME} -- nslookup longhorn-conversion-webhook.longhorn-system.svc 2>&1 || echo "解析失败")
    if echo "${DNS_TEST2}" | grep -q "Name:"; then
        echo_info "  ✓ Longhorn Service DNS 解析成功"
        echo "${DNS_TEST2}" | grep -A 2 "Name:" | sed 's/^/    /'
    else
        echo_warn "  ⚠️  Longhorn Service DNS 解析失败或 Service 不存在"
        echo "${DNS_TEST2}" | head -5 | sed 's/^/    /'
    fi
else
    echo_warn "  无法找到测试 Pod"
fi

# 6. 检查 Pod DNS 配置
echo ""
echo_info "6. 检查 Pod DNS 配置..."
if [ -n "${TEST_POD}" ]; then
    POD_NAME=$(echo ${TEST_POD} | cut -d'/' -f2)
    POD_NS=$(kubectl get ${TEST_POD} -o jsonpath='{.metadata.namespace}' 2>/dev/null)
    RESOLV_CONF=$(kubectl exec -n ${POD_NS} ${POD_NAME} -- cat /etc/resolv.conf 2>&1 || echo "无法读取")
    echo_info "  /etc/resolv.conf 内容："
    echo "${RESOLV_CONF}" | sed 's/^/    /'
    
    # 检查是否有 nameserver
    if echo "${RESOLV_CONF}" | grep -q "nameserver"; then
        NAMESERVER=$(echo "${RESOLV_CONF}" | grep "nameserver" | head -1 | awk '{print $2}')
        echo_info "  DNS 服务器: ${NAMESERVER}"
        
        # 检查是否是 kube-dns Service IP
        if [ -n "${SERVICE_IP}" ] && [ "${NAMESERVER}" = "${SERVICE_IP}" ]; then
            echo_info "  ✓ DNS 服务器指向正确的 kube-dns Service IP"
        else
            echo_warn "  ⚠️  DNS 服务器可能不正确"
        fi
    fi
    
    # 检查 search 域
    if echo "${RESOLV_CONF}" | grep -q "search.*svc"; then
        echo_info "  ✓ 包含 svc search 域（可以解析 .svc 域名）"
    else
        echo_warn "  ⚠️  可能缺少 svc search 域"
    fi
fi

# 7. 总结
echo ""
echo_info "=========================================="
echo_info "检查总结"
echo_info "=========================================="
echo ""

if [ "${SA_SECRETS}" -eq 0 ]; then
    echo_info "✓ ServiceAccount SECRETS=0 是正常的，不影响 DNS 解析"
fi

if [ -z "${COREDNS_PODS}" ]; then
    echo_error "✗ CoreDNS Pod 未运行 - 这是主要问题！"
    echo_info "解决：检查为什么 CoreDNS Pod 没有启动"
elif [ "${POD_STATUS}" != "Running" ] || [ "${POD_READY}" != "true" ]; then
    echo_warn "⚠️  CoreDNS Pod 状态异常"
    echo_info "解决：检查 Pod 日志和事件"
else
    echo_info "✓ CoreDNS Pod 运行正常"
fi

echo ""
echo_info "如果 DNS 解析失败，可能的原因："
echo "  1. CoreDNS Pod 未运行或状态异常"
echo "  2. CoreDNS 配置错误"
echo "  3. 网络策略阻止了 DNS 查询"
echo "  4. Pod 的 DNS 配置不正确（/etc/resolv.conf）"
echo "  5. Service 不存在（对于 longhorn-conversion-webhook）"


#!/bin/bash

# 检查 Longhorn DNS 和 Service 配置

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
echo_info "Longhorn DNS 和 Service 诊断"
echo_info "=========================================="
echo ""

# 1. 检查 CoreDNS/kube-dns 是否运行
echo_info "1. 检查集群 DNS 服务..."
DNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name 2>/dev/null || kubectl get pods -n kube-system -l k8s-app=coredns -o name 2>/dev/null)
if [ -n "${DNS_PODS}" ]; then
    echo_info "  ✓ DNS 服务运行中"
    kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || kubectl get pods -n kube-system -l k8s-app=coredns 2>/dev/null
else
    echo_error "  ✗ 未找到 DNS 服务（kube-dns 或 coredns）"
    echo_warn "  这可能导致 Service DNS 解析失败"
fi

# 2. 检查 longhorn-conversion-webhook Service
echo ""
echo_info "2. 检查 longhorn-conversion-webhook Service..."
if kubectl get svc longhorn-conversion-webhook -n longhorn-system &>/dev/null; then
    echo_info "  ✓ Service 存在"
    kubectl get svc longhorn-conversion-webhook -n longhorn-system -o yaml | grep -A 10 "spec:"
else
    echo_error "  ✗ Service 不存在"
fi

# 3. 检查 Endpoints
echo ""
echo_info "3. 检查 longhorn-conversion-webhook Endpoints..."
if kubectl get endpoints longhorn-conversion-webhook -n longhorn-system &>/dev/null; then
    ENDPOINTS=$(kubectl get endpoints longhorn-conversion-webhook -n longhorn-system -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [ -n "${ENDPOINTS}" ]; then
        echo_info "  ✓ Endpoints 存在: ${ENDPOINTS}"
        kubectl get endpoints longhorn-conversion-webhook -n longhorn-system -o yaml | grep -A 5 "subsets:"
    else
        echo_warn "  ⚠️  Endpoints 为空（没有 Pod 被选中）"
    fi
else
    echo_error "  ✗ Endpoints 不存在"
fi

# 4. 测试 DNS 解析（在 Pod 内）
echo ""
echo_info "4. 测试 DNS 解析..."
TEST_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o name 2>/dev/null | head -1)
if [ -n "${TEST_POD}" ]; then
    POD_NAME=$(echo ${TEST_POD} | cut -d'/' -f2)
    echo_info "  使用 Pod: ${POD_NAME}"
    
    echo_info "  测试 DNS 解析 longhorn-conversion-webhook.longhorn-system.svc..."
    DNS_RESULT=$(kubectl exec -n longhorn-system ${POD_NAME} -c longhorn-manager -- nslookup longhorn-conversion-webhook.longhorn-system.svc 2>&1 || echo "DNS解析失败")
    
    if echo "${DNS_RESULT}" | grep -q "Name:"; then
        echo_info "  ✓ DNS 解析成功"
        echo "${DNS_RESULT}" | grep -A 5 "Name:"
    else
        echo_error "  ✗ DNS 解析失败"
        echo "${DNS_RESULT}"
    fi
    
    echo ""
    echo_info "  测试直接访问 Service IP..."
    SERVICE_IP=$(kubectl get svc longhorn-conversion-webhook -n longhorn-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "${SERVICE_IP}" ]; then
        echo_info "  Service IP: ${SERVICE_IP}"
        echo_info "  测试连接..."
        CONNECT_TEST=$(kubectl exec -n longhorn-system ${POD_NAME} -c longhorn-manager -- curl -k -m 2 -s -o /dev/null -w "%{http_code}" https://${SERVICE_IP}:9501/v1/healthz 2>&1 || echo "连接失败")
        if [ "${CONNECT_TEST}" = "200" ]; then
            echo_info "  ✓ 直接 IP 访问成功（HTTP 200）"
        else
            echo_warn "  ⚠️  直接 IP 访问返回: ${CONNECT_TEST}"
        fi
    fi
else
    echo_warn "  无法找到 longhorn-manager Pod 进行测试"
fi

# 5. 检查 /etc/resolv.conf（DNS 配置）
echo ""
echo_info "5. 检查 Pod DNS 配置..."
if [ -n "${TEST_POD}" ]; then
    POD_NAME=$(echo ${TEST_POD} | cut -d'/' -f2)
    RESOLV_CONF=$(kubectl exec -n longhorn-system ${POD_NAME} -c longhorn-manager -- cat /etc/resolv.conf 2>&1 || echo "无法读取")
    echo_info "  /etc/resolv.conf 内容："
    echo "${RESOLV_CONF}" | sed 's/^/    /'
    
    # 检查 search 域
    if echo "${RESOLV_CONF}" | grep -q "search.*svc"; then
        echo_info "  ✓ 包含 svc search 域（可以解析 .svc 域名）"
    else
        echo_warn "  ⚠️  可能缺少 svc search 域"
    fi
fi

# 6. 总结
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [ -z "${DNS_PODS}" ]; then
    echo_error "问题：DNS 服务未运行"
    echo_info "解决：检查 kube-dns 或 coredns Pod 状态"
fi

if [ -z "${ENDPOINTS}" ]; then
    echo_warn "问题：Service 没有 Endpoints"
    echo_info "解决：检查 longhorn-manager Pod 是否正常运行，以及 Service selector 是否正确"
fi

echo ""
echo_info "如果 DNS 解析失败，可能的原因："
echo "  1. CoreDNS/kube-dns 未运行或有问题"
echo "  2. Pod 的 /etc/resolv.conf 配置不正确"
echo "  3. 网络策略阻止了 DNS 查询"
echo "  4. Service 的 selector 不匹配任何 Pod"
echo ""
echo_info "如果 DNS 解析成功但连接失败，可能是："
echo "  1. Webhook 服务未正常启动"
echo "  2. TLS 证书问题"
echo "  3. 网络策略阻止了连接"
echo "  4. Longhorn 版本兼容性问题"


#!/bin/bash

# 检测 DNS 198.18.x.x 问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "DNS 198.18.x.x 问题检测"
echo_info "=========================================="
echo ""

# 检查 kubectl 是否可用
if ! command -v kubectl &>/dev/null; then
    echo_error "kubectl 未安装或不在 PATH 中"
    exit 1
fi

# 检查集群连接
if ! kubectl cluster-info &>/dev/null; then
    echo_error "无法连接到 Kubernetes 集群"
    exit 1
fi

echo_info "✓ 集群连接正常"
echo ""

# 1. 检查 ServiceLB 状态（k3s ServiceLB 是内置组件，不是 Pod）
echo_test "1. 检查 ServiceLB 状态..."
if sudo systemctl cat k3s 2>/dev/null | grep -qE "disable.*servicelb|--disable servicelb"; then
    echo_info "  ✓ ServiceLB 已禁用（在 k3s 启动参数中）"
    SERVICELB_ENABLED=false
else
    echo_warn "  ⚠️  ServiceLB 已启用（k3s 默认启用，未在启动参数中禁用）"
    SERVICELB_ENABLED=true
    echo_info "  k3s 启动参数："
    sudo systemctl cat k3s 2>/dev/null | grep "ExecStart" | sed 's/^/    /' || echo "    无法获取"
fi
echo ""

# 2. 检查 Service ClusterIP 范围
echo_test "2. 检查 Service ClusterIP 范围..."
echo_info "  所有 Service 的 ClusterIP："
kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.clusterIP}{"\n"}{end}' 2>/dev/null | \
    grep -v "None" | sort | head -10 | sed 's/^/    /'

# 检查是否有 198.18.x.x 的 Service
SVC_198=$(kubectl get svc -A -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\n"}{end}' 2>/dev/null | grep "^198.18" | wc -l)
if [ "${SVC_198}" -gt 0 ]; then
    echo_warn "  ⚠️  发现 ${SVC_198} 个 Service 使用 198.18.x.x IP："
    kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.clusterIP}{"\n"}{end}' 2>/dev/null | \
        grep "^198.18" | sed 's/^/    /'
else
    echo_info "  ✓ 没有 Service 使用 198.18.x.x IP"
fi
echo ""

# 3. 检查 LoadBalancer 类型的 Service
echo_test "3. 检查 LoadBalancer 类型的 Service..."
LB_SVCS=$(kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.type}{"\n"}{end}' 2>/dev/null | grep "LoadBalancer" | wc -l)
if [ "${LB_SVCS}" -gt 0 ]; then
    echo_warn "  ⚠️  发现 ${LB_SVCS} 个 LoadBalancer 类型的 Service："
    kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.type}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' 2>/dev/null | \
        grep "LoadBalancer" | sed 's/^/    /'
else
    echo_info "  ✓ 没有 LoadBalancer 类型的 Service"
fi
echo ""

# 4. DNS 解析测试
echo_test "4. DNS 解析测试..."
echo_info "  创建测试 Pod..."

# 清理可能存在的旧测试 Pod
kubectl delete pod dns-test 2>/dev/null || true
sleep 2

# 创建测试 Pod
kubectl run dns-test --image=busybox --restart=Never --rm -i -- sh -c "
    echo '=== 测试 1: kubernetes.default.svc.cluster.local ==='
    nslookup kubernetes.default.svc.cluster.local 2>&1 || echo '解析失败'
    echo ''
    echo '=== 测试 2: kube-dns.kube-system.svc ==='
    nslookup kube-dns.kube-system.svc 2>&1 || echo '解析失败'
    echo ''
    echo '=== 测试 3: kubernetes.default.svc ==='
    nslookup kubernetes.default.svc 2>&1 || echo '解析失败'
" 2>&1 | tee /tmp/dns-test-result.txt

# 分析结果
echo ""
echo_test "5. DNS 解析结果分析..."

# 检查是否解析到 198.18.x.x
if grep -q "198\.18\." /tmp/dns-test-result.txt; then
    echo_error "  ✗ 发现 DNS 解析到 198.18.x.x："
    grep "198\.18\." /tmp/dns-test-result.txt | sed 's/^/    /'
    echo ""
    echo_warn "  ⚠️  问题仍然存在！"
    echo_warn "  建议：禁用 ServiceLB 重新安装"
    echo_warn "    DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
else
    echo_info "  ✓ 没有解析到 198.18.x.x"
fi

# 检查是否解析到正确的 Service CIDR (10.43.x.x)
if grep -q "10\.43\." /tmp/dns-test-result.txt; then
    echo_info "  ✓ 解析到正确的 Service CIDR (10.43.x.x)"
    grep "10\.43\." /tmp/dns-test-result.txt | head -3 | sed 's/^/    /'
else
    echo_warn "  ⚠️  未发现 10.43.x.x 的解析结果"
fi
echo ""

# 6. 检查 k3s 配置
echo_test "6. 检查 k3s 实际配置..."
if sudo systemctl cat k3s 2>/dev/null | grep -q "disable.*servicelb\|--disable servicelb"; then
    echo_info "  ✓ k3s 配置中已禁用 ServiceLB"
else
    echo_warn "  ⚠️  k3s 配置中未禁用 ServiceLB"
    echo_info "  实际启动参数："
    sudo systemctl cat k3s 2>/dev/null | grep "ExecStart" | sed 's/^/    /' || echo "    无法获取"
fi
echo ""

# 7. 测试实际连接
echo_test "7. 测试实际连接..."
echo_info "  测试连接到 kubernetes Service..."

kubectl run connect-test --image=busybox --restart=Never --rm -i -- sh -c "
    echo '测试 1: 连接到 kubernetes.default.svc.cluster.local:443'
    wget -O- --timeout=3 --no-check-certificate https://kubernetes.default.svc.cluster.local:443 2>&1 | head -3 || echo '连接失败'
    echo ''
    echo '测试 2: 连接到 10.43.0.1:443（直接使用 ClusterIP）'
    wget -O- --timeout=3 --no-check-certificate https://10.43.0.1:443 2>&1 | head -3 || echo '连接失败'
" 2>&1 | tee /tmp/connect-test-result.txt

# 分析连接结果
echo ""
if grep -qi "401\|Unauthorized\|got bad TLS" /tmp/connect-test-result.txt; then
    echo_info "  ✓ 连接成功（返回 401 或 TLS 错误是正常的，说明连接已建立）"
elif grep -qi "Connection reset\|Connection refused\|timeout" /tmp/connect-test-result.txt; then
    echo_error "  ✗ 连接失败"
    echo_warn "  可能存在问题，需要进一步诊断"
else
    echo_warn "  ⚠️  连接结果不明确，请手动检查"
fi
echo ""

# 8. 总结
echo_info "=========================================="
echo_info "检测总结"
echo_info "=========================================="
echo ""

# 统计问题
ISSUES=0

if [ "${SERVICELB_ENABLED}" = "true" ]; then
    echo_warn "  - ServiceLB 已启用"
    ISSUES=$((ISSUES + 1))
fi

if [ "${SVC_198}" -gt 0 ]; then
    echo_warn "  - 发现 ${SVC_198} 个 Service 使用 198.18.x.x"
    ISSUES=$((ISSUES + 1))
fi

if grep -q "198\.18\." /tmp/dns-test-result.txt 2>/dev/null; then
    echo_error "  - DNS 解析到 198.18.x.x（问题存在）"
    ISSUES=$((ISSUES + 1))
fi

if [ "${ISSUES}" -eq 0 ]; then
    echo_info "  ✓ 未发现问题，DNS 解析正常"
    echo_info "  ✓ 可以正常使用集群"
else
    echo_warn "  ⚠️  发现 ${ISSUES} 个潜在问题"
    echo ""
    echo_info "建议："
    if grep -q "198\.18\." /tmp/dns-test-result.txt 2>/dev/null; then
        echo_info "  1. 如果 DNS 解析到 198.18.x.x，建议禁用 ServiceLB 重新安装："
        echo_info "     DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
    fi
    if [ "${SERVICELB_ENABLED}" = "true" ] && [ "${LB_SVCS}" -eq 0 ]; then
        echo_info "  2. 如果没有使用 LoadBalancer，可以禁用 ServiceLB 以减少资源占用"
    fi
fi

echo ""
echo_info "详细测试结果保存在："
echo "  - DNS 测试: /tmp/dns-test-result.txt"
echo "  - 连接测试: /tmp/connect-test-result.txt"
echo ""


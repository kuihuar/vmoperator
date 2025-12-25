#!/bin/bash

# k3s 网络问题诊断脚本

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
echo_info "k3s 网络问题诊断"
echo_info "=========================================="
echo ""

# 1. 检查 k3s 进程参数
echo_info "1. 检查 k3s 进程启动参数..."
K3S_CMD=$(sudo ps aux | grep "k3s server" | grep -v grep | head -1)
if [ -n "${K3S_CMD}" ]; then
    echo_info "  k3s 进程："
    echo "${K3S_CMD}" | sed 's/^/    /'
    
    # 提取关键参数
    if echo "${K3S_CMD}" | grep -q "cluster-cidr"; then
        CLUSTER_CIDR=$(echo "${K3S_CMD}" | grep -o "cluster-cidr=[^ ]*" | cut -d'=' -f2)
        echo_info "  cluster-cidr: ${CLUSTER_CIDR}"
    fi
    
    if echo "${K3S_CMD}" | grep -q "service-cidr"; then
        SERVICE_CIDR=$(echo "${K3S_CMD}" | grep -o "service-cidr=[^ ]*" | cut -d'=' -f2)
        echo_info "  service-cidr: ${SERVICE_CIDR}"
    fi
    
    if echo "${K3S_CMD}" | grep -q "service-node-port-range"; then
        NODE_PORT_RANGE=$(echo "${K3S_CMD}" | grep -o "service-node-port-range=[^ ]*" | cut -d'=' -f2)
        echo_info "  service-node-port-range: ${NODE_PORT_RANGE}"
    fi
else
    echo_error "  未找到 k3s server 进程"
fi

# 2. 检查 ServiceLB
echo ""
echo_info "2. 检查 ServiceLB（k3s LoadBalancer）..."
SERVICELB_PODS=$(kubectl get pods -n kube-system -l app=svclb -o name 2>/dev/null | head -1)
if [ -n "${SERVICELB_PODS}" ]; then
    echo_info "  ✓ ServiceLB Pod 存在"
    kubectl get pods -n kube-system -l app=svclb
    echo_warn "  ⚠️  ServiceLB 可能使用了 198.18.0.0/15 地址范围"
    echo_info "  这是 k3s ServiceLB 的默认行为，用于 LoadBalancer 类型的 Service"
else
    echo_info "  ServiceLB 未运行"
fi

# 3. 检查 CoreDNS 配置
echo ""
echo_info "3. 检查 CoreDNS 配置..."
if kubectl get configmap coredns -n kube-system &>/dev/null; then
    COREDNS_CONFIG=$(kubectl get configmap coredns -n kube-system -o yaml | grep -A 50 "data:" | grep -A 50 "Corefile:")
    echo_info "  CoreDNS Corefile："
    echo "${COREDNS_CONFIG}" | sed 's/^/    /' | head -30
    
    # 检查是否有 hosts 插件或其他特殊配置
    if echo "${COREDNS_CONFIG}" | grep -q "198.18"; then
        echo_warn "  ⚠️  发现 198.18 相关配置"
    fi
else
    echo_warn "  CoreDNS ConfigMap 不存在"
fi

# 4. 检查实际网络接口
echo ""
echo_info "4. 检查节点网络接口..."
if command -v ip &>/dev/null; then
    echo_info "  IP 地址："
    ip addr show | grep -E "inet |inet6 " | grep -v "127.0.0.1" | head -10 | sed 's/^/    /'
    
    echo ""
    echo_info "  路由表："
    ip route | head -10 | sed 's/^/    /'
    
    # 检查是否有 198.18 相关的路由或接口
    if ip route | grep -q "198.18"; then
        echo_warn "  ⚠️  发现 198.18 相关路由"
        ip route | grep "198.18" | sed 's/^/    /'
    fi
else
    echo_warn "  ip 命令不可用"
fi

# 5. 检查 Service 和 Endpoints
echo ""
echo_info "5. 检查 kubernetes Service..."
kubectl get svc kubernetes -n default -o yaml | grep -A 10 "spec:" | head -15

SERVICE_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo_info "  ClusterIP: ${SERVICE_IP}"

ENDPOINT_IPS=$(kubectl get endpoints kubernetes -n default -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
echo_info "  Endpoint IPs: ${ENDPOINT_IPS}"

# 6. 测试 DNS 解析
echo ""
echo_info "6. 测试 DNS 解析..."
DNS_RESULT=$(kubectl run -it --rm test-dns-$(date +%s) --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>&1 || true)
echo "${DNS_RESULT}" | sed 's/^/    /'

DNS_IP=$(echo "${DNS_RESULT}" | grep "Address:" | tail -1 | awk '{print $2}')
if [ "${DNS_IP}" != "${SERVICE_IP}" ]; then
    echo_warn "  ⚠️  DNS 解析结果 (${DNS_IP}) 与 Service ClusterIP (${SERVICE_IP}) 不一致"
fi

# 7. 总结和建议
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [[ "${DNS_IP}" =~ ^198\.18\. ]]; then
    echo_warn "问题确认：DNS 解析到 198.18.x.x（测试地址范围）"
    echo ""
    echo_info "可能的原因："
    echo "  1. k3s ServiceLB 使用了 198.18.0.0/15 作为虚拟 IP 范围"
    echo "  2. CoreDNS 配置问题"
    echo "  3. 网络代理或 NAT 配置"
    echo ""
    echo_info "建议的解决方案："
    echo "  1. 检查 k3s 启动参数，确认网络配置"
    echo "  2. 检查 CoreDNS 配置，看是否有 hosts 插件或其他特殊配置"
    echo "  3. 如果这是 ServiceLB 的行为，可能需要："
    echo "     - 禁用 ServiceLB（如果不需要 LoadBalancer）"
    echo "     - 或配置 ServiceLB 使用其他 IP 范围"
    echo "  4. 重新安装 k3s，使用明确的网络配置参数"
    echo ""
    echo_warn "对于 Longhorn webhook 问题："
    echo "  如果 DNS 解析到错误的 IP，会导致连接失败"
    echo "  需要修复 DNS 解析问题，或使用 Service IP 直接连接"
fi


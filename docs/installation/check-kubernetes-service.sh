#!/bin/bash

# 检查 kubernetes Service 的配置和 IP 地址

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
echo_info "Kubernetes Service IP 检查"
echo_info "=========================================="
echo ""

# 1. 检查 kubernetes Service
echo_info "1. 检查 kubernetes Service..."
kubectl get svc kubernetes -n default -o wide

SERVICE_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo_info "  Service ClusterIP: ${SERVICE_IP}"

# 2. 检查 DNS 解析结果
echo ""
echo_info "2. 检查 DNS 解析结果..."
DNS_RESULT=$(kubectl run -it --rm test-dns-check --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>&1 || true)
echo "${DNS_RESULT}"

DNS_IP=$(echo "${DNS_RESULT}" | grep "Address:" | tail -1 | awk '{print $2}')
echo_info "  DNS 解析到的 IP: ${DNS_IP}"

# 3. 分析 IP 地址
echo ""
echo_info "3. IP 地址分析..."

if [ "${DNS_IP}" = "${SERVICE_IP}" ]; then
    echo_info "  ✓ DNS 解析结果与 Service ClusterIP 一致（正常）"
elif [[ "${DNS_IP}" =~ ^198\.18\. ]]; then
    echo_warn "  ⚠️  解析到 198.18.x.x 地址（这是 IANA 保留的测试地址范围）"
    echo_info "  198.18.0.0/15 是 TEST-NET-1 和 TEST-NET-2，通常不应该出现在生产环境"
    echo_warn "  可能的原因："
    echo "    1. k3s 的特殊网络配置"
    echo "    2. ServiceLB 或 LoadBalancer 配置"
    echo "    3. 网络代理或 NAT 配置"
    echo "    4. 配置错误"
elif [[ "${DNS_IP}" =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.|^192\.168\. ]]; then
    echo_info "  ✓ 解析到私有 IP 地址范围（可能是正常的，取决于集群配置）"
else
    echo_warn "  ⚠️  解析到非标准 IP 地址: ${DNS_IP}"
fi

# 4. 检查 Endpoints
echo ""
echo_info "4. 检查 kubernetes Service Endpoints..."
kubectl get endpoints kubernetes -n default

ENDPOINT_IPS=$(kubectl get endpoints kubernetes -n default -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
echo_info "  Endpoint IPs: ${ENDPOINT_IPS}"

# 5. 检查 k3s 网络配置
echo ""
echo_info "5. 检查 k3s 网络配置..."
if command -v k3s &>/dev/null; then
    echo_info "  k3s 版本："
    k3s --version | head -1
    
    echo ""
    echo_info "  检查 k3s 网络配置（如果可访问）："
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        echo_info "  k3s 配置文件存在"
    fi
fi

# 6. 检查 ServiceLB（k3s 的 LoadBalancer）
echo ""
echo_info "6. 检查 ServiceLB（k3s LoadBalancer）..."
SERVICELB_PODS=$(kubectl get pods -n kube-system -l app=svclb -o name 2>/dev/null | head -1)
if [ -n "${SERVICELB_PODS}" ]; then
    echo_info "  ✓ ServiceLB Pod 存在"
    kubectl get pods -n kube-system -l app=svclb
else
    echo_info "  ServiceLB 未运行（可能未启用 LoadBalancer）"
fi

# 7. 检查网络接口
echo ""
echo_info "7. 检查节点网络接口（如果可访问）..."
if [ -f /proc/net/route ] 2>/dev/null; then
    echo_info "  节点路由表（前 10 行）："
    head -10 /proc/net/route 2>/dev/null || echo "无法访问"
fi

# 8. 总结和建议
echo ""
echo_info "=========================================="
echo_info "检查总结"
echo_info "=========================================="
echo ""

if [[ "${DNS_IP}" =~ ^198\.18\. ]]; then
    echo_warn "⚠️  发现异常：DNS 解析到 198.18.x.x（测试地址范围）"
    echo ""
    echo_info "可能的影响："
    echo "  - 如果这是 k3s 的特殊配置，可能是正常的"
    echo "  - 但如果导致网络连接问题，需要检查配置"
    echo ""
    echo_info "建议检查："
    echo "  1. k3s 的网络配置（--cluster-cidr, --service-cidr）"
    echo "  2. 是否有 ServiceLB 或其他网络组件使用了这个地址范围"
    echo "  3. 检查实际网络连接是否正常"
    echo ""
    echo_info "测试实际连接："
    echo "  kubectl run -it --rm test-connect --image=busybox --restart=Never -- wget -O- https://kubernetes.default.svc.cluster.local:443"
else
    echo_info "✓ IP 地址看起来正常"
fi

echo ""
echo_info "对于 Longhorn webhook 问题："
echo "  即使 DNS 解析到 198.18.x.x，只要能够实际连接，应该不影响功能"
echo "  关键是要测试实际连接是否成功"


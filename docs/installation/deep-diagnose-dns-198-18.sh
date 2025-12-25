#!/bin/bash

# 深入诊断 DNS 198.18.x.x 问题的真正原因

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
echo_info "深入诊断 DNS 198.18.x.x 问题"
echo_info "=========================================="
echo ""

# 1. 检查 k3s 版本和配置
echo_test "1. k3s 版本和配置..."
k3s --version | sed 's/^/  /'
echo ""
echo_info "  k3s 启动参数："
sudo systemctl cat k3s 2>/dev/null | grep -A 10 "ExecStart" | sed 's/^/  /'
echo ""

# 2. 检查 Service 的实际 ClusterIP
echo_test "2. 检查 Service 的实际 ClusterIP..."
echo_info "  kubernetes Service:"
kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null && echo ""
echo_info "  kube-dns Service:"
kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null && echo ""
echo ""

# 3. 检查 CoreDNS 配置
echo_test "3. 检查 CoreDNS 配置..."
COREDNS_CM=$(kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null)
if [ -n "${COREDNS_CM}" ]; then
    echo_info "  CoreDNS ConfigMap 内容："
    echo "${COREDNS_CM}" | grep -A 50 "Corefile:" | sed 's/^/  /'
    
    # 检查是否有 hosts 插件
    if echo "${COREDNS_CM}" | grep -q "hosts"; then
        echo_warn "  ⚠️  发现 hosts 插件配置"
        echo "${COREDNS_CM}" | grep -A 10 "hosts" | sed 's/^/    /'
    fi
    
    # 检查是否有 rewrite 插件
    if echo "${COREDNS_CM}" | grep -q "rewrite"; then
        echo_warn "  ⚠️  发现 rewrite 插件配置"
        echo "${COREDNS_CM}" | grep -A 10 "rewrite" | sed 's/^/    /'
    fi
else
    echo_warn "  未找到 CoreDNS ConfigMap"
fi
echo ""

# 4. 检查 CoreDNS Pod 内的配置
echo_test "4. 检查 CoreDNS Pod 内的实际配置..."
COREDNS_POD=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  CoreDNS Pod: ${POD_NAME}"
    
    echo_info "  Pod 内的 /etc/coredns/Corefile："
    kubectl exec -n kube-system ${POD_NAME} -- cat /etc/coredns/Corefile 2>/dev/null | sed 's/^/    /' || echo "    无法读取"
    
    echo ""
    echo_info "  Pod 内的 /etc/coredns/custom/ 目录："
    kubectl exec -n kube-system ${POD_NAME} -- ls -la /etc/coredns/custom/ 2>&1 | sed 's/^/    /' || echo "    目录不存在"
    
    if kubectl exec -n kube-system ${POD_NAME} -- ls /etc/coredns/custom/ 2>/dev/null | grep -q "\.server\|\.override"; then
        echo_warn "  ⚠️  发现自定义配置文件："
        for file in $(kubectl exec -n kube-system ${POD_NAME} -- ls /etc/coredns/custom/ 2>/dev/null | grep -E "\.server|\.override"); do
            echo_info "    文件: ${file}"
            kubectl exec -n kube-system ${POD_NAME} -- cat /etc/coredns/custom/${file} 2>/dev/null | sed 's/^/      /' || echo "      无法读取"
        done
    fi
else
    echo_warn "  未找到 CoreDNS Pod"
fi
echo ""

# 5. 检查 CoreDNS 日志
echo_test "5. 检查 CoreDNS 日志（最近 30 行）..."
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    kubectl logs -n kube-system ${POD_NAME} --tail=30 2>&1 | grep -iE "kubernetes|198.18|error|warn" | sed 's/^/  /' || echo "  未找到相关日志"
fi
echo ""

# 6. 检查 Endpoints
echo_test "6. 检查 Service Endpoints..."
echo_info "  kubernetes Service Endpoints:"
kubectl get endpoints kubernetes -n default -o yaml 2>/dev/null | grep -A 5 "addresses:" | sed 's/^/  /' || echo "  无法获取"
echo ""
echo_info "  kube-dns Service Endpoints:"
kubectl get endpoints kube-dns -n kube-system -o yaml 2>/dev/null | grep -A 5 "addresses:" | sed 's/^/  /' || echo "  无法获取"
echo ""

# 7. 在 Pod 内直接测试 DNS 查询
echo_test "7. 在 Pod 内直接测试 DNS 查询..."
kubectl run dns-debug --image=busybox --restart=Never --rm -i -- sh -c "
    echo '=== 测试 1: 直接查询 kubernetes Service IP ==='
    nslookup kubernetes.default.svc.cluster.local
    echo ''
    echo '=== 测试 2: 查询 DNS 服务器 ==='
    cat /etc/resolv.conf
    echo ''
    echo '=== 测试 3: 直接查询 ClusterIP ==='
    nslookup 10.43.0.1
    echo ''
    echo '=== 测试 4: 测试连接 ==='
    wget -O- --timeout=2 --no-check-certificate https://10.43.0.1:443 2>&1 | head -3
" 2>&1 | tee /tmp/dns-debug-result.txt

echo ""
echo_test "8. 分析结果..."
if grep -q "198\.18\." /tmp/dns-debug-result.txt; then
    echo_error "  ✗ 确认：DNS 解析到 198.18.x.x"
    echo ""
    echo_warn "  可能的原因分析："
    echo ""
    
    # 检查是否是 CoreDNS 配置问题
    if echo "${COREDNS_CM}" | grep -qE "hosts.*198\.18|rewrite.*198\.18"; then
        echo_warn "  1. CoreDNS 配置中可能有 198.18.x.x 的映射"
    fi
    
    # 检查是否是 k3s 版本问题
    K3S_VERSION=$(k3s --version | head -1)
    echo_warn "  2. k3s 版本: ${K3S_VERSION}"
    echo_warn "    可能是 k3s 版本的 bug 或特殊行为"
    
    # 检查 ServiceLB
    if sudo systemctl cat k3s 2>/dev/null | grep -qE "disable.*servicelb|--disable.*servicelb"; then
        echo_warn "  3. ServiceLB 已禁用，但问题仍然存在"
        echo_warn "    说明问题可能不是 ServiceLB 导致的"
    else
        echo_warn "  3. ServiceLB 未禁用"
    fi
    
    echo ""
    echo_info "  需要进一步调查："
    echo_info "    - CoreDNS 的 hosts 插件配置"
    echo_info "    - k3s 的 DNS 实现细节"
    echo_info "    - 是否有其他网络组件影响"
else
    echo_info "  ✓ DNS 解析正常"
fi

echo ""
echo_info "=========================================="
echo_info "诊断完成"
echo_info "=========================================="
echo ""
echo_info "详细结果保存在: /tmp/dns-debug-result.txt"
echo ""


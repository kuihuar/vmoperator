#!/bin/bash

# 诊断和修复 DNS 解析到 198.18.x.x 的问题

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
echo_info "DNS 解析问题诊断和修复"
echo_info "=========================================="
echo ""

# 1. 确认问题
echo_info "问题确认："
echo_info "  - DNS 解析到: 198.18.0.47（错误，无法连接）"
echo_info "  - 实际 ClusterIP: 10.43.0.1（正确，可以连接）"
echo ""

# 2. 检查 CoreDNS Pod 内的自定义配置
echo_info "1. 检查 CoreDNS 自定义配置..."
COREDNS_POD=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  找到 CoreDNS Pod: ${POD_NAME}"
    
    echo ""
    echo_info "  检查 /etc/coredns/custom/ 目录："
    CUSTOM_FILES=$(kubectl exec -n kube-system ${POD_NAME} -- ls -la /etc/coredns/custom/ 2>&1)
    if echo "${CUSTOM_FILES}" | grep -q "\.server\|\.override"; then
        echo_warn "  ⚠️  发现自定义配置文件："
        echo "${CUSTOM_FILES}" | grep -E "\.server|\.override" | sed 's/^/    /'
        
        # 读取自定义配置
        for file in $(echo "${CUSTOM_FILES}" | grep -E "\.server|\.override" | awk '{print $NF}'); do
            echo ""
            echo_info "  文件内容: ${file}"
            kubectl exec -n kube-system ${POD_NAME} -- cat /etc/coredns/custom/${file} 2>&1 | sed 's/^/    /' || echo "    无法读取"
        done
    else
        echo_info "  ✓ 没有自定义配置文件"
    fi
else
    echo_warn "  未找到 CoreDNS Pod"
fi

# 3. 检查 CoreDNS 日志
echo ""
echo_info "2. 检查 CoreDNS 日志（查看 DNS 查询）..."
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  最近 20 行日志："
    kubectl logs -n kube-system ${POD_NAME} --tail=20 | grep -iE "kubernetes|198.18" | sed 's/^/    /' || echo "    未找到相关日志"
fi

# 4. 检查 hosts 插件配置
echo ""
echo_info "3. 检查 CoreDNS hosts 插件..."
if kubectl get configmap coredns -n kube-system &>/dev/null; then
    HOSTS_CONFIG=$(kubectl get configmap coredns -n kube-system -o yaml | grep -A 10 "NodeHosts:")
    if echo "${HOSTS_CONFIG}" | grep -q "198.18"; then
        echo_warn "  ⚠️  NodeHosts 中包含 198.18 地址："
        echo "${HOSTS_CONFIG}" | grep "198.18" | sed 's/^/    /'
    else
        echo_info "  ✓ NodeHosts 中没有 198.18 地址"
    fi
fi

# 5. 检查是否有其他 DNS 相关配置
echo ""
echo_info "4. 检查其他可能的 DNS 配置..."
echo_info "  检查是否有其他 ConfigMap 或 Service 影响 DNS："
kubectl get configmap -n kube-system | grep -iE "dns|host" | sed 's/^/    /'

# 6. 测试不同的 DNS 查询方式
echo ""
echo_info "5. 测试不同的 DNS 查询方式..."
TEST_POD="test-dns-$(date +%s)"
kubectl run ${TEST_POD} --image=busybox --restart=Never --rm -it -- sh -c "
  echo '=== 测试 1: 完整域名 ==='
  nslookup kubernetes.default.svc.cluster.local
  echo ''
  echo '=== 测试 2: 短域名 ==='
  nslookup kubernetes.default.svc
  echo ''
  echo '=== 测试 3: 最短域名 ==='
  nslookup kubernetes
  echo ''
  echo '=== 测试 4: 直接查询 Service ==='
  nslookup kubernetes.default
" 2>&1 || echo "测试完成"

# 7. 可能的解决方案
echo ""
echo_info "=========================================="
echo_info "可能的解决方案"
echo_info "=========================================="
echo ""

echo_warn "如果确认是 DNS 解析问题，可能的解决方案："
echo ""
echo_info "方案 1: 检查并修复 CoreDNS 自定义配置"
echo "  如果有自定义配置文件导致解析错误，需要修复或删除"
echo ""
echo_info "方案 2: 重启 CoreDNS"
echo "  kubectl delete pod -n kube-system -l k8s-app=kube-dns"
echo "  或"
echo "  kubectl delete pod -n kube-system <coredns-pod-name>"
echo ""
echo_info "方案 3: 检查 k3s 版本是否有已知问题"
echo "  当前版本: $(k3s --version | head -1)"
echo "  可能需要升级或降级 k3s"
echo ""
echo_info "方案 4: 禁用 ServiceLB（如果确认是它导致的问题）"
echo "  需要重新安装 k3s，添加 --disable servicelb 参数"


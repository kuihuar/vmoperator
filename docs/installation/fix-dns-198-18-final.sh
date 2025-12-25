#!/bin/bash

# 最终修复 DNS 198.18.x.x 问题

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
echo_info "深入检查 CoreDNS 配置（找出 198.18.x.x 的真正原因）"
echo_info "=========================================="
echo ""

# 1. 检查 CoreDNS ConfigMap
echo_test "1. 检查 CoreDNS ConfigMap..."
COREDNS_CM=$(kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null)
if [ -n "${COREDNS_CM}" ]; then
    echo_info "  CoreDNS ConfigMap 完整内容："
    echo "${COREDNS_CM}" | sed 's/^/    /'
else
    echo_warn "  未找到 CoreDNS ConfigMap"
fi
echo ""

# 2. 检查 CoreDNS Pod 内的实际配置
echo_test "2. 检查 CoreDNS Pod 内的实际配置..."
COREDNS_POD=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  CoreDNS Pod: ${POD_NAME}"
    
    echo ""
    echo_info "  Pod 内的 /etc/coredns/Corefile："
    kubectl exec -n kube-system ${POD_NAME} -- cat /etc/coredns/Corefile 2>/dev/null | sed 's/^/    /' || echo "    无法读取"
    
    echo ""
    echo_info "  Pod 内的环境变量："
    kubectl exec -n kube-system ${POD_NAME} -- env 2>/dev/null | grep -iE "dns|host" | sed 's/^/    /' || echo "    无相关环境变量"
    
    echo ""
    echo_info "  Pod 内的 /etc/hosts："
    kubectl exec -n kube-system ${POD_NAME} -- cat /etc/hosts 2>/dev/null | sed 's/^/    /' || echo "    无法读取"
else
    echo_warn "  未找到 CoreDNS Pod"
fi
echo ""

# 3. 检查 Service 和 Endpoints
echo_test "3. 检查 kubernetes Service 和 Endpoints..."
echo_info "  kubernetes Service："
kubectl get svc kubernetes -n default -o yaml 2>/dev/null | grep -E "clusterIP|name:" | sed 's/^/    /'

echo ""
echo_info "  kubernetes Endpoints："
kubectl get endpoints kubernetes -n default -o yaml 2>/dev/null | grep -A 10 "addresses:" | sed 's/^/    /'
echo ""

# 4. 在 CoreDNS Pod 内直接测试
echo_test "4. 在 CoreDNS Pod 内直接测试 DNS 查询..."
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  在 CoreDNS Pod 内执行 nslookup："
    kubectl exec -n kube-system ${POD_NAME} -- nslookup kubernetes.default.svc.cluster.local 2>&1 | sed 's/^/    /' || echo "    查询失败"
fi
echo ""

# 5. 检查 k3s 的 DNS 相关配置
echo_test "5. 检查 k3s 的 DNS 相关配置..."
echo_info "  检查 k3s 数据目录："
if [ -d /var/lib/rancher/k3s/server/manifests ]; then
    echo_info "    manifests 目录："
    sudo ls -la /var/lib/rancher/k3s/server/manifests/ 2>/dev/null | sed 's/^/      /' || echo "      无法访问"
    
    # 检查是否有 coredns 相关的 manifest
    for file in $(sudo ls /var/lib/rancher/k3s/server/manifests/ 2>/dev/null); do
        if echo "${file}" | grep -qiE "coredns|dns"; then
            echo_info "      发现 DNS 相关文件: ${file}"
            sudo cat /var/lib/rancher/k3s/server/manifests/${file} 2>/dev/null | sed 's/^/        /' || echo "        无法读取"
        fi
    done
fi
echo ""

# 6. 检查 k3s 版本和已知问题
echo_test "6. 检查 k3s 版本..."
k3s --version | sed 's/^/  /'
echo ""
echo_warn "  当前版本: v1.33.6+k3s1（最新版本）"
echo_warn "  即使是最新版本，DNS 仍然解析到 198.18.x.x"
echo_warn "  这可能不是版本问题，而是配置或实现问题"
echo ""

# 7. 尝试修复方案
echo_info "=========================================="
echo_info "可能的修复方案"
echo_info "=========================================="
echo ""

echo_warn "方案 1: 检查并修复 CoreDNS 配置"
echo_info "  如果发现 CoreDNS 配置中有 198.18.x.x 的映射，需要修复"
echo ""

echo_warn "方案 2: 重启 CoreDNS"
echo_info "  kubectl delete pods -n kube-system -l k8s-app=kube-dns"
echo ""

echo_warn "方案 3: 检查是否有其他网络组件影响"
echo_info "  检查是否有其他 CNI 或网络插件影响 DNS 解析"
echo ""

echo_warn "方案 4: 手动修复 CoreDNS ConfigMap"
echo_info "  如果确认是 CoreDNS 配置问题，可以手动编辑 ConfigMap"
echo ""

echo ""
echo_info "请查看上面的检查结果，特别是："
echo_info "  1. CoreDNS ConfigMap 内容"
echo_info "  2. CoreDNS Pod 内的实际配置"
echo_info "  3. 是否有 198.18.x.x 相关的配置"
echo ""


#!/bin/bash

# 检查 CoreDNS 配置，找出 DNS 解析到 198.18.x.x 的真正原因

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
echo_info "检查 CoreDNS 配置（查找 198.18.x.x 的真正原因）"
echo_info "=========================================="
echo ""

# 1. 检查 CoreDNS ConfigMap
echo_test "1. 检查 CoreDNS ConfigMap..."
COREDNS_CM=$(kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null)
if [ -n "${COREDNS_CM}" ]; then
    echo_info "  CoreDNS ConfigMap 内容："
    echo "${COREDNS_CM}" | grep -A 100 "Corefile:" | sed 's/^/  /'
    
    # 检查是否有 198.18 相关配置
    if echo "${COREDNS_CM}" | grep -q "198\.18"; then
        echo_error "  ✗ 发现 198.18 相关配置！"
        echo "${COREDNS_CM}" | grep -B 5 -A 5 "198\.18" | sed 's/^/    /'
    else
        echo_info "  ✓ ConfigMap 中没有 198.18 相关配置"
    fi
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
    echo_info "  Pod 内的 /etc/coredns/custom/ 目录："
    kubectl exec -n kube-system ${POD_NAME} -- ls -la /etc/coredns/custom/ 2>&1 | sed 's/^/    /' || echo "    目录不存在或无法访问"
    
    # 检查自定义配置文件
    CUSTOM_FILES=$(kubectl exec -n kube-system ${POD_NAME} -- ls /etc/coredns/custom/ 2>/dev/null | grep -E "\.server|\.override" || echo "")
    if [ -n "${CUSTOM_FILES}" ]; then
        echo_warn "  ⚠️  发现自定义配置文件："
        for file in ${CUSTOM_FILES}; do
            echo_info "    文件: ${file}"
            kubectl exec -n kube-system ${POD_NAME} -- cat /etc/coredns/custom/${file} 2>/dev/null | sed 's/^/      /' || echo "      无法读取"
        done
    fi
    
    # 检查是否有 hosts 文件
    echo ""
    echo_info "  Pod 内的 /etc/hosts："
    kubectl exec -n kube-system ${POD_NAME} -- cat /etc/hosts 2>/dev/null | grep -E "198\.18|kubernetes|kube-dns" | sed 's/^/    /' || echo "    未发现相关条目"
else
    echo_warn "  未找到 CoreDNS Pod"
fi
echo ""

# 3. 检查 CoreDNS 日志
echo_test "3. 检查 CoreDNS 日志（查找 DNS 查询记录）..."
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  最近 50 行日志："
    kubectl logs -n kube-system ${POD_NAME} --tail=50 2>&1 | grep -iE "kubernetes|198\.18|error|warn" | sed 's/^/    /' || echo "    未找到相关日志"
fi
echo ""

# 4. 检查 k3s 的 DNS 相关配置
echo_test "4. 检查 k3s DNS 相关配置..."
echo_info "  检查 k3s 数据目录中的 DNS 配置："
if [ -d /var/lib/rancher/k3s/server/manifests ]; then
    echo_info "    manifests 目录内容："
    sudo ls -la /var/lib/rancher/k3s/server/manifests/ 2>/dev/null | sed 's/^/      /' || echo "      无法访问"
    
    # 检查是否有 coredns 相关的 manifest
    if sudo ls /var/lib/rancher/k3s/server/manifests/ 2>/dev/null | grep -qi "coredns\|dns"; then
        echo_warn "    ⚠️  发现 DNS 相关的 manifest 文件"
        for file in $(sudo ls /var/lib/rancher/k3s/server/manifests/ 2>/dev/null | grep -iE "coredns|dns"); do
            echo_info "      文件: ${file}"
            sudo cat /var/lib/rancher/k3s/server/manifests/${file} 2>/dev/null | grep -E "198\.18|hosts|rewrite" | sed 's/^/        /' || echo "        未发现相关配置"
        done
    fi
else
    echo_info "    manifests 目录不存在"
fi
echo ""

# 5. 检查 Service 和 Endpoints
echo_test "5. 检查 Service 和 Endpoints..."
echo_info "  kubernetes Service:"
kubectl get svc kubernetes -n default -o yaml 2>/dev/null | grep -E "clusterIP|name:" | sed 's/^/    /'
echo ""
echo_info "  kubernetes Endpoints:"
kubectl get endpoints kubernetes -n default -o yaml 2>/dev/null | grep -A 10 "addresses:" | sed 's/^/    /'
echo ""

# 6. 在 CoreDNS Pod 内直接测试 DNS 查询
echo_test "6. 在 CoreDNS Pod 内直接测试 DNS 查询..."
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  在 CoreDNS Pod 内执行 nslookup："
    kubectl exec -n kube-system ${POD_NAME} -- nslookup kubernetes.default.svc.cluster.local 2>&1 | sed 's/^/    /' || echo "    查询失败"
fi
echo ""

# 7. 检查 k3s 版本
echo_test "7. 检查 k3s 版本..."
k3s --version | sed 's/^/  /'
echo ""

# 8. 总结和建议
echo_info "=========================================="
echo_info "检查总结"
echo_info "=========================================="
echo ""

if echo "${COREDNS_CM}" | grep -q "198\.18"; then
    echo_error "  ✗ 在 CoreDNS ConfigMap 中发现 198.18 配置"
    echo_info "  建议：修复或删除相关配置"
elif [ -n "${CUSTOM_FILES}" ]; then
    echo_warn "  ⚠️  发现自定义 CoreDNS 配置文件"
    echo_info "  建议：检查这些文件是否包含 198.18 相关配置"
else
    echo_warn "  ⚠️  未在 CoreDNS 配置中发现明显问题"
    echo_info "  可能的原因："
    echo_info "    1. k3s 版本的 bug"
    echo_info "    2. CoreDNS 插件的特殊行为"
    echo_info "    3. 其他网络组件的影响"
    echo ""
    echo_info "  建议："
    echo_info "    1. 检查 k3s GitHub issues"
    echo_info "    2. 尝试升级/降级 k3s 版本"
    echo_info "    3. 手动修复 CoreDNS 配置"
fi

echo ""


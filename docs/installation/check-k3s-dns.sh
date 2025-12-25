#!/bin/bash

# k3s DNS 问题诊断脚本（修正版）

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
echo_info "k3s DNS 问题诊断（修正版）"
echo_info "=========================================="
echo ""

# 1. 检查 k3s 实际运行的参数（最重要）
echo_info "1. 检查 k3s 实际运行的参数..."
K3S_CMD=$(sudo ps aux | grep "k3s server" | grep -v grep | head -1)
if [ -n "${K3S_CMD}" ]; then
    echo_info "  k3s 进程："
    echo "${K3S_CMD}" | sed 's/^/    /'
    
    # 提取关键参数
    if echo "${K3S_CMD}" | grep -q "cluster-cidr"; then
        CLUSTER_CIDR=$(echo "${K3S_CMD}" | grep -o "cluster-cidr=[^ ]*" | cut -d'=' -f2)
        echo_info "  cluster-cidr: ${CLUSTER_CIDR}"
    else
        echo_info "  cluster-cidr: 使用默认值 10.42.0.0/16"
    fi
    
    if echo "${K3S_CMD}" | grep -q "service-cidr"; then
        SERVICE_CIDR=$(echo "${K3S_CMD}" | grep -o "service-cidr=[^ ]*" | cut -d'=' -f2)
        echo_info "  service-cidr: ${SERVICE_CIDR}"
    else
        echo_info "  service-cidr: 使用默认值 10.43.0.0/16"
    fi
    
    if echo "${K3S_CMD}" | grep -q "disable.*servicelb"; then
        echo_info "  servicelb: 已禁用"
    else
        echo_info "  servicelb: 启用（默认）"
    fi
else
    echo_error "  未找到 k3s server 进程"
fi

# 2. 查找 CoreDNS Pod（k3s 可能使用不同的标签）
echo ""
echo_info "2. 查找 CoreDNS Pod..."
COREDNS_POD=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -1)
if [ -n "${COREDNS_POD}" ]; then
    POD_NAME=$(echo ${COREDNS_POD} | cut -d'/' -f2)
    echo_info "  找到 CoreDNS Pod: ${POD_NAME}"
    kubectl get pod ${POD_NAME} -n kube-system
    
    # 检查自定义配置
    echo ""
    echo_info "  检查 CoreDNS 自定义配置..."
    CUSTOM_CONFIG=$(kubectl exec -n kube-system ${POD_NAME} -- ls -la /etc/coredns/custom/ 2>&1 || echo "目录不存在")
    if echo "${CUSTOM_CONFIG}" | grep -q "\.server\|\.override"; then
        echo_warn "  ⚠️  发现自定义配置文件"
        echo "${CUSTOM_CONFIG}" | sed 's/^/    /'
        
        # 尝试读取自定义配置
        for file in $(echo "${CUSTOM_CONFIG}" | grep -E "\.server|\.override" | awk '{print $NF}'); do
            echo ""
            echo_info "  自定义配置文件: ${file}"
            kubectl exec -n kube-system ${POD_NAME} -- cat /etc/coredns/custom/${file} 2>&1 | sed 's/^/    /' || echo "    无法读取"
        done
    else
        echo_info "  ✓ 没有自定义配置文件"
    fi
else
    echo_warn "  未找到 CoreDNS Pod"
    echo_info "  检查所有 kube-system Pod："
    kubectl get pods -n kube-system | head -10
fi

# 3. 检查 CoreDNS ConfigMap（已提供）
echo ""
echo_info "3. 检查 CoreDNS ConfigMap..."
if kubectl get configmap coredns -n kube-system &>/dev/null; then
    echo_info "  ✓ CoreDNS ConfigMap 存在"
    echo_info "  注意：有 import /etc/coredns/custom/*.server，可能有自定义配置"
else
    echo_warn "  CoreDNS ConfigMap 不存在"
fi

# 4. 检查所有 kube-system Pod（查找 ServiceLB）
echo ""
echo_info "4. 检查所有 kube-system Pod（查找 ServiceLB 相关）..."
kubectl get pods -n kube-system

SERVICELB_PODS=$(kubectl get pods -n kube-system -o name | grep -iE "svc|lb|traefik")
if [ -n "${SERVICELB_PODS}" ]; then
    echo ""
    echo_info "  找到可能的 ServiceLB 相关 Pod："
    echo "${SERVICELB_PODS}" | sed 's/^/    /'
else
    echo_info "  未找到明显的 ServiceLB Pod"
fi

# 5. 详细 DNS 解析测试
echo ""
echo_info "5. 详细 DNS 解析测试..."
TEST_POD_NAME="test-dns-$(date +%s)"
kubectl run ${TEST_POD_NAME} --image=busybox --restart=Never --rm -it -- sh -c "
  echo '=== /etc/resolv.conf ==='
  cat /etc/resolv.conf
  echo ''
  echo '=== 解析 kubernetes.default.svc.cluster.local ==='
  nslookup kubernetes.default.svc.cluster.local
  echo ''
  echo '=== 解析 kubernetes.default.svc ==='
  nslookup kubernetes.default.svc
  echo ''
  echo '=== 解析 kubernetes ==='
  nslookup kubernetes
" 2>&1 || echo "测试 Pod 已删除"

# 6. 检查网络路由
echo ""
echo_info "6. 检查网络路由..."
if command -v ip &>/dev/null; then
    ROUTES_198=$(ip route | grep 198.18 || echo "无")
    if [ "${ROUTES_198}" != "无" ]; then
        echo_warn "  ⚠️  发现 198.18 相关路由："
        echo "${ROUTES_198}" | sed 's/^/    /'
    else
        echo_info "  ✓ 没有 198.18 相关路由"
    fi
    
    ROUTES_10=$(ip route | grep -E "10\.42|10\.43" | head -5)
    if [ -n "${ROUTES_10}" ]; then
        echo_info "  10.42/10.43 相关路由："
        echo "${ROUTES_10}" | sed 's/^/    /'
    fi
else
    echo_warn "  ip 命令不可用"
fi

# 7. 检查 kubernetes Service
echo ""
echo_info "7. 检查 kubernetes Service..."
kubectl get svc kubernetes -n default -o yaml | grep -A 10 "spec:" | head -15

SERVICE_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo_info "  ClusterIP: ${SERVICE_IP}"

# 8. 总结
echo ""
echo_info "=========================================="
echo_info "诊断总结"
echo_info "=========================================="
echo ""

if [ -z "${K3S_CMD}" ]; then
    echo_error "✗ 无法获取 k3s 进程信息（需要 sudo 权限）"
fi

if [[ "${SERVICE_IP}" =~ ^10\.43\. ]]; then
    echo_info "✓ kubernetes Service ClusterIP 在正确的范围内 (10.43.x.x)"
else
    echo_warn "⚠️  kubernetes Service ClusterIP 不在预期范围"
fi

echo ""
echo_info "如果 DNS 解析到 198.18.x.x，可能的原因："
echo "  1. k3s 版本特定的网络行为"
echo "  2. CoreDNS 自定义配置（需要检查 /etc/coredns/custom/ 目录）"
echo "  3. 网络代理或 NAT 规则"
echo "  4. ServiceLB 的特殊实现方式"


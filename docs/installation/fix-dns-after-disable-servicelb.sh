#!/bin/bash

# 禁用 ServiceLB 后修复 DNS 问题的脚本

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
echo_info "修复 DNS 问题（禁用 ServiceLB 后）"
echo_info "=========================================="
echo ""

# 1. 检查 k3s 配置
echo_info "1. 检查 k3s 配置..."
if sudo systemctl cat k3s 2>/dev/null | grep -qE "disable.*servicelb|--disable.*servicelb"; then
    echo_info "  ✓ systemd 配置中已禁用 ServiceLB"
else
    echo_error "  ✗ systemd 配置中未禁用 ServiceLB"
    echo_error "  请先重新安装 k3s：DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
    exit 1
fi

# 2. 检查 k3s 是否重启过
echo ""
echo_info "2. 检查 k3s 服务状态..."
K3S_START_TIME=$(sudo systemctl show k3s --property=ActiveEnterTimestamp --value 2>/dev/null || echo "")
if [ -n "${K3S_START_TIME}" ]; then
    echo_info "  k3s 启动时间: ${K3S_START_TIME}"
    echo_warn "  如果刚修改配置，需要重启 k3s 以应用新配置"
    read -p "是否重启 k3s？(y/n，默认y): " RESTART_K3S
    RESTART_K3S=${RESTART_K3S:-y}
    if [[ $RESTART_K3S =~ ^[Yy]$ ]]; then
        echo_info "  重启 k3s..."
        sudo systemctl restart k3s
        echo_info "  等待 k3s 启动（10秒）..."
        sleep 10
        
        if sudo systemctl is-active --quiet k3s; then
            echo_info "  ✓ k3s 已重启"
        else
            echo_error "  ✗ k3s 启动失败"
            sudo systemctl status k3s --no-pager | head -10
            exit 1
        fi
    fi
else
    echo_warn "  无法获取 k3s 启动时间"
fi

# 3. 重启 CoreDNS
echo ""
echo_info "3. 重启 CoreDNS..."
COREDNS_PODS=$(kubectl get pods -n kube-system -o name | grep -iE "coredns|dns" | head -2)
if [ -n "${COREDNS_PODS}" ]; then
    echo_info "  找到 CoreDNS Pods，重启它们..."
    for pod in ${COREDNS_PODS}; do
        POD_NAME=$(echo ${pod} | cut -d'/' -f2)
        echo_info "    重启 ${POD_NAME}..."
        kubectl delete pod -n kube-system ${POD_NAME} 2>/dev/null || true
    done
    echo_info "  等待 CoreDNS 重启（5秒）..."
    sleep 5
    echo_info "  ✓ CoreDNS 已重启"
else
    echo_warn "  未找到 CoreDNS Pods"
fi

# 4. 清理可能的 DNS 缓存
echo ""
echo_info "4. 清理 DNS 缓存..."
echo_info "  注意：Pod 内的 DNS 缓存会在 Pod 重启后清除"
echo_info "  如果问题仍然存在，可能需要重启相关 Pod"

# 5. 验证
echo ""
echo_info "5. 验证 DNS 解析..."
echo_info "  等待 5 秒后测试..."
sleep 5

kubectl run dns-verify --image=busybox --restart=Never --rm -i -- sh -c "
    echo '测试 DNS 解析...'
    nslookup kubernetes.default.svc.cluster.local 2>&1
    echo ''
    nslookup kube-dns.kube-system.svc 2>&1
" 2>&1 | tee /tmp/dns-verify-result.txt

# 分析结果
echo ""
if grep -q "198\.18\." /tmp/dns-verify-result.txt; then
    echo_error "  ✗ 仍然解析到 198.18.x.x"
    echo_warn "  可能的原因："
    echo_warn "    1. k3s 版本问题（可能需要升级/降级）"
    echo_warn "    2. CoreDNS 配置问题"
    echo_warn "    3. 需要完全重新安装 k3s"
    echo ""
    echo_info "  建议："
    echo_info "    1. 检查 k3s 版本：k3s --version"
    echo_info "    2. 完全卸载并重新安装："
    echo_info "       ./docs/installation/uninstall-k3s.sh"
    echo_info "       DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
else
    echo_info "  ✓ DNS 解析正常（未发现 198.18.x.x）"
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""


#!/bin/bash

# 快速安装 k3s 最新版本（单节点）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "快速安装 k3s 最新版本（单节点）"
echo_info "=========================================="
echo ""

# 预计时间
echo_info "预计安装时间：2-5 分钟"
echo_info "  - 下载 k3s: ~30秒-2分钟（取决于网络）"
echo_info "  - 安装和启动: ~30秒-1分钟"
echo_info "  - 验证: ~30秒"
echo ""

# 1. 检查并卸载旧版本
echo_step "1/5 检查现有安装..."
if command -v k3s &>/dev/null; then
    echo_warn "  发现已安装的 k3s"
    read -p "  是否卸载并重新安装？(y/n，默认y): " REINSTALL
    REINSTALL=${REINSTALL:-y}
    if [[ $REINSTALL =~ ^[Yy]$ ]]; then
        echo_info "  卸载旧版本..."
        if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
            sudo /usr/local/bin/k3s-uninstall.sh || echo_warn "  卸载脚本执行失败，继续..."
        fi
        sudo rm -f /etc/systemd/system/k3s.service
        sudo rm -rf /etc/systemd/system/k3s.service.d
        sudo systemctl daemon-reload
        echo_info "  ✓ 卸载完成"
    else
        echo_info "  跳过安装"
        exit 0
    fi
else
    echo_info "  ✓ 未发现现有安装"
fi
echo ""

# 2. 配置参数
echo_step "2/5 配置安装参数..."
SERVER_IP="${SERVER_IP:-192.168.1.141}"
DISABLE_SERVICELB="${DISABLE_SERVICELB:-true}"  # 默认禁用，解决 DNS 问题
CLUSTER_CIDR="${CLUSTER_CIDR:-10.42.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.43.0.0/16}"

K3S_SERVER_ARGS="server --tls-san ${SERVER_IP} --cluster-cidr ${CLUSTER_CIDR} --service-cidr ${SERVICE_CIDR} --disable servicelb"

echo_info "  配置："
echo_info "    - 使用最新稳定版本"
echo_info "    - 远程访问 IP: ${SERVER_IP}"
echo_info "    - ServiceLB: 禁用（解决 DNS 198.18.x.x 问题）"
echo_info "    - Pod 网络: ${CLUSTER_CIDR}"
echo_info "    - Service 网络: ${SERVICE_CIDR}"
echo ""

# 3. 安装 k3s
echo_step "3/5 下载并安装 k3s（这可能需要 1-3 分钟）..."
echo_info "  开始下载最新版本..."
START_TIME=$(date +%s)

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="${K3S_SERVER_ARGS}" sh -

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo_info "  ✓ 安装完成（耗时: ${DURATION} 秒）"
echo ""

# 4. 等待启动
echo_step "4/5 等待 k3s 启动..."
for i in {1..30}; do
    if sudo systemctl is-active --quiet k3s 2>/dev/null; then
        echo_info "  ✓ k3s 已启动"
        break
    fi
    if [ $i -eq 30 ]; then
        echo_error "  ✗ k3s 启动超时"
        sudo systemctl status k3s --no-pager | head -10
        exit 1
    fi
    sleep 1
    echo -n "."
done
echo ""

# 5. 配置 kubeconfig
echo_step "5/5 配置 kubeconfig..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
echo_info "  ✓ kubeconfig 已配置"
echo ""

# 6. 快速验证
echo_info "=========================================="
echo_info "快速验证"
echo_info "=========================================="
echo ""

echo_info "k3s 版本："
k3s --version | sed 's/^/  /'

echo ""
echo_info "节点状态："
kubectl get nodes 2>/dev/null | sed 's/^/  /' || echo_error "  无法获取节点信息"

echo ""
echo_info "k3s 服务状态："
sudo systemctl is-active k3s && echo_info "  ✓ 运行中" || echo_error "  ✗ 未运行"

echo ""
echo_info "安装参数验证："
if sudo systemctl cat k3s 2>/dev/null | grep -qE "cluster-cidr|service-cidr|disable.*servicelb"; then
    echo_info "  ✓ 所有参数已正确配置"
    sudo systemctl cat k3s 2>/dev/null | grep -A 10 "ExecStart" | grep -E "cluster-cidr|service-cidr|disable.*servicelb" | sed 's/^/    /'
else
    echo_warn "  ⚠️  部分参数可能未正确配置"
fi

echo ""
echo_info "=========================================="
echo_info "安装完成！"
echo_info "=========================================="
echo ""
echo_info "下一步："
echo "  1. 测试 DNS 解析："
echo "     kubectl run -it --rm test-dns --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local"
echo ""
echo "  2. 如果 DNS 正常，继续安装其他组件："
echo "     ./docs/installation/install-kubevirt.sh"
echo "     ./docs/installation/install-longhorn.sh"
echo ""


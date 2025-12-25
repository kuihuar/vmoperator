#!/bin/bash

# 仅安装 k3s（不安装其他组件）

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
echo_info "安装 k3s"
echo_info "=========================================="
echo ""

# 目标 k3s 版本（与 Longhorn v1.8.1 兼容的稳定版本，可通过环境变量 K3S_VERSION 覆盖）
DEFAULT_K3S_VERSION="v1.29.6+k3s1"
K3S_VERSION="${K3S_VERSION:-$DEFAULT_K3S_VERSION}"

# 检查是否已安装
if command -v k3s &>/dev/null; then
    K3S_VERSION=$(k3s --version | head -1)
    echo_warn "  k3s 已安装: $K3S_VERSION"
    read -p "是否重新安装？(y/n，默认n): " REINSTALL
    REINSTALL=${REINSTALL:-n}
    if [[ ! $REINSTALL =~ ^[Yy]$ ]]; then
        echo_info "  跳过安装"
        exit 0
    fi
fi

# 安装 k3s（固定版本，便于与 Longhorn 兼容）
echo_info "1. 下载并安装 k3s（版本: ${K3S_VERSION}）..."

# 如果需要从远程访问，可在此增加 --tls-san（示例使用 192.168.1.141）
SERVER_IP="${SERVER_IP:-192.168.1.141}"

# 是否禁用 ServiceLB（如果遇到 DNS 解析到 198.18.x.x 的问题，可以禁用）
# 禁用 ServiceLB 后，将无法使用 LoadBalancer 类型的 Service
# 可以通过环境变量 DISABLE_SERVICELB=true 来禁用
DISABLE_SERVICELB="${DISABLE_SERVICELB:-false}"

# 网络配置（可通过环境变量覆盖，默认值与 k3s 默认值相同）
CLUSTER_CIDR="${CLUSTER_CIDR:-10.42.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.43.0.0/16}"

# 构建 k3s server 启动参数
K3S_SERVER_ARGS="server --tls-san ${SERVER_IP} --cluster-cidr ${CLUSTER_CIDR} --service-cidr ${SERVICE_CIDR}"

# 如果禁用 ServiceLB
if [[ "${DISABLE_SERVICELB}" =~ ^[Tt]rue$ ]]; then
    echo_warn "  ⚠️  将禁用 ServiceLB（无法使用 LoadBalancer 类型的 Service）"
    K3S_SERVER_ARGS="${K3S_SERVER_ARGS} --disable servicelb"
else
    echo_info "  ServiceLB 已启用（可以使用 LoadBalancer 类型的 Service）"
fi

# 显示网络配置
echo_info "  网络配置："
echo_info "    cluster-cidr: ${CLUSTER_CIDR}（Pod 网络）"
echo_info "    service-cidr: ${SERVICE_CIDR}（Service 网络）"
echo_info "  如需自定义，可通过环境变量 CLUSTER_CIDR 和 SERVICE_CIDR 覆盖"

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_EXEC="${K3S_SERVER_ARGS}" sh -

# 等待 k3s 启动
echo_info "2. 等待 k3s 启动（约 10 秒）..."
sleep 10

# 检查状态
if sudo systemctl is-active --quiet k3s; then
    echo_info "  ✓ k3s 运行中"
else
    echo_error "  ✗ k3s 未运行"
    sudo systemctl status k3s --no-pager | head -10
    exit 1
fi

# 配置 kubeconfig
echo_info "3. 配置 kubeconfig..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# 如果 server 地址是 127.0.0.1，可能需要修改
SERVER=$(grep server ~/.kube/config | awk '{print $2}')
if echo "$SERVER" | grep -q "127.0.0.1\|localhost"; then
    echo_warn "  ⚠️  server 地址是 $SERVER"
    echo_info "  如果需要从远程访问，请修改 ~/.kube/config"
fi

# 验证
echo_info "4. 验证安装..."
kubectl get nodes

# 显示版本信息
echo ""
echo_info "5. k3s 版本信息:"
k3s --version

# 显示服务状态
echo ""
echo_info "6. k3s 服务状态:"
sudo systemctl status k3s --no-pager | head -5

echo ""
echo_info "=========================================="
echo_info "k3s 安装完成"
echo_info "=========================================="
echo ""
echo_info "kubeconfig 位置: ~/.kube/config"
echo_info "k3s 配置文件: /etc/rancher/k3s/k3s.yaml"
echo ""

# 提示 DNS 验证
echo_info "7. DNS 验证提示..."
echo_info "  如果遇到 DNS 解析到 198.18.x.x 的问题，可以运行："
echo_info "    kubectl run -it --rm test-dns --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local"
echo_info "  如果解析到 198.18.x.x 且无法连接，可以禁用 ServiceLB 重新安装"

echo ""
echo_info "下一步:"
echo "  1. 安装 CDI: 参考 docs/installation/INSTALLATION_CHECKLIST.md"
echo "  2. 安装 KubeVirt: 参考 docs/installation/INSTALLATION_CHECKLIST.md"
echo "  3. 安装 Longhorn: ./docs/installation/install-longhorn.sh"
echo ""
echo_info "如果遇到 DNS 解析到 198.18.x.x 的问题："
echo "  参考文档: docs/installation/DNS_198_18_ISSUE.md"
echo "  解决方案: DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
echo ""


#!/bin/bash

# 添加 K3S_RESOLV_CONF 环境变量到 k3s 环境文件
# 根据官方文档：https://longhorn.io/docs/1.6.0/deploy/install/#installing-longhorn-on-k3s

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

RESOLV_CONF="${1:-/etc/resolv.conf}"

echo ""
echo_info "=========================================="
echo_info "配置 K3S_RESOLV_CONF 环境变量"
echo_info "=========================================="
echo ""

# 1. 检查 k3s 是否已安装
if ! command -v k3s &>/dev/null; then
    echo_error "k3s 未安装，请先安装 k3s"
    exit 1
fi

echo_info "1. 检查 k3s 环境文件..."
K3S_ENV_FILE="/etc/rancher/k3s/config.env"

# 创建目录（如果不存在）
if [ ! -d "$(dirname "${K3S_ENV_FILE}")" ]; then
    echo_info "  创建目录: $(dirname "${K3S_ENV_FILE}")"
    sudo mkdir -p "$(dirname "${K3S_ENV_FILE}")"
fi

# 2. 检查是否已存在 K3S_RESOLV_CONF
if [ -f "${K3S_ENV_FILE}" ]; then
    if grep -q "^K3S_RESOLV_CONF=" "${K3S_ENV_FILE}" 2>/dev/null; then
        echo_warn "  K3S_RESOLV_CONF 已存在，当前值："
        grep "^K3S_RESOLV_CONF=" "${K3S_ENV_FILE}" | head -1
        echo ""
        read -p "是否更新？(y/n，默认n): " UPDATE
        UPDATE=${UPDATE:-n}
        if [[ ! $UPDATE =~ ^[Yy]$ ]]; then
            echo_info "  已取消"
            exit 0
        fi
        # 删除旧的行
        sudo sed -i.bak '/^K3S_RESOLV_CONF=/d' "${K3S_ENV_FILE}"
        echo_info "  已删除旧的配置"
    else
        echo_info "  环境文件存在，但未找到 K3S_RESOLV_CONF"
    fi
else
    echo_info "  环境文件不存在，将创建"
fi

# 3. 添加 K3S_RESOLV_CONF
echo ""
echo_info "2. 添加 K3S_RESOLV_CONF=${RESOLV_CONF} 到环境文件..."
echo "K3S_RESOLV_CONF=${RESOLV_CONF}" | sudo tee -a "${K3S_ENV_FILE}" > /dev/null

if [ $? -eq 0 ]; then
    echo_info "  ✓ 已添加到 ${K3S_ENV_FILE}"
else
    echo_error "  ✗ 添加失败"
    exit 1
fi

# 4. 验证
echo ""
echo_info "3. 验证配置..."
if grep -q "^K3S_RESOLV_CONF=${RESOLV_CONF}$" "${K3S_ENV_FILE}" 2>/dev/null; then
    echo_info "  ✓ 配置已正确添加"
    echo ""
    echo "当前环境文件内容："
    sudo cat "${K3S_ENV_FILE}"
else
    echo_error "  ✗ 验证失败"
    exit 1
fi

# 5. 重启 k3s
echo ""
echo_warn "4. 需要重启 k3s 服务使配置生效"
read -p "是否现在重启 k3s？(y/n，默认y): " RESTART
RESTART=${RESTART:-y}

if [[ $RESTART =~ ^[Yy]$ ]]; then
    echo_info "  重启 k3s 服务..."
    sudo systemctl restart k3s
    
    # 等待服务启动
    echo_info "  等待 k3s 启动（10 秒）..."
    sleep 10
    
    # 检查状态
    if sudo systemctl is-active --quiet k3s; then
        echo_info "  ✓ k3s 已重启并运行中"
    else
        echo_error "  ✗ k3s 启动失败"
        sudo systemctl status k3s --no-pager | head -10
        exit 1
    fi
else
    echo_warn "  请手动重启 k3s: sudo systemctl restart k3s"
fi

echo ""
echo_info "=========================================="
echo_info "配置完成"
echo_info "=========================================="
echo ""
echo_info "配置位置: ${K3S_ENV_FILE}"
echo_info "配置内容: K3S_RESOLV_CONF=${RESOLV_CONF}"
echo ""
echo_info "验证命令:"
echo "  sudo cat ${K3S_ENV_FILE}"
echo "  sudo systemctl status k3s"
echo ""


#!/bin/bash

# 卸载 k3s 并清理相关配置

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
echo_info "卸载 k3s 并清理配置"
echo_info "=========================================="
echo ""

# 确认操作
echo_warn "⚠️  此操作将："
echo_warn "  1. 卸载 k3s"
echo_warn "  2. 删除所有集群数据"
echo_warn "  3. 清理 kubeconfig"
echo_warn "  4. 清理 DNS 相关配置"
echo ""
read -p "确认继续？(y/n，默认n): " CONFIRM
CONFIRM=${CONFIRM:-n}
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo_info "  已取消"
    exit 0
fi

# 1. 检查 k3s 是否安装
if ! command -v k3s &>/dev/null; then
    echo_warn "  k3s 未安装，跳过卸载"
else
    echo_info "1. 卸载 k3s..."
    
    # 停止 k3s 服务
    if sudo systemctl is-active --quiet k3s 2>/dev/null; then
        echo_info "  停止 k3s 服务..."
        sudo systemctl stop k3s || true
    fi
    
    # 禁用 k3s 服务
    if sudo systemctl is-enabled --quiet k3s 2>/dev/null; then
        echo_info "  禁用 k3s 服务..."
        sudo systemctl disable k3s || true
    fi
    
    # 运行 k3s 卸载脚本
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        echo_info "  运行 k3s 卸载脚本..."
        sudo /usr/local/bin/k3s-uninstall.sh || {
            echo_warn "  k3s 卸载脚本执行失败，尝试手动清理..."
        }
    else
        echo_warn "  k3s 卸载脚本不存在，尝试手动清理..."
    fi
    
    # 手动清理（如果卸载脚本不存在或失败）
    echo_info "  手动清理 k3s 文件..."
    
    # 删除 systemd 服务文件
    if [ -f /etc/systemd/system/k3s.service ]; then
        echo_info "    删除 systemd 服务文件..."
        sudo rm -f /etc/systemd/system/k3s.service
        sudo rm -rf /etc/systemd/system/k3s.service.d
    fi
    
    # 删除 k3s 数据目录
    if [ -d /var/lib/rancher/k3s ]; then
        echo_info "    删除 k3s 数据目录..."
        sudo rm -rf /var/lib/rancher/k3s
    fi
    
    # 删除 k3s 配置目录
    if [ -d /etc/rancher/k3s ]; then
        echo_info "    删除 k3s 配置目录..."
        sudo rm -rf /etc/rancher/k3s
    fi
    
    # 删除 k3s 可执行文件
    if [ -f /usr/local/bin/k3s ]; then
        echo_info "    删除 k3s 可执行文件..."
        sudo rm -f /usr/local/bin/k3s
        sudo rm -f /usr/local/bin/k3s-killall.sh
        sudo rm -f /usr/local/bin/k3s-uninstall.sh
    fi
    
    # 删除 containerd socket（如果存在）
    if [ -S /run/k3s/containerd/containerd.sock ]; then
        echo_info "    删除 containerd socket..."
        sudo rm -rf /run/k3s
    fi
    
    # 重新加载 systemd
    sudo systemctl daemon-reload
    sudo systemctl reset-failed || true
    
    echo_info "  ✓ k3s 卸载完成"
fi

# 2. 清理 kubeconfig
echo ""
echo_info "2. 清理 kubeconfig..."
if [ -f ~/.kube/config ]; then
    # 检查是否是 k3s 的配置
    if grep -q "k3s" ~/.kube/config 2>/dev/null || [ -f /etc/rancher/k3s/k3s.yaml ]; then
        echo_info "  备份并删除 kubeconfig..."
        BACKUP_FILE="${HOME}/.kube/config.backup.$(date +%Y%m%d_%H%M%S)"
        cp ~/.kube/config "${BACKUP_FILE}" 2>/dev/null || true
        rm -f ~/.kube/config
        echo_info "    已备份到: ${BACKUP_FILE}"
    else
        echo_warn "  kubeconfig 不是 k3s 配置，保留"
    fi
else
    echo_info "  kubeconfig 不存在，跳过"
fi

# 3. 清理 DNS 相关配置
echo ""
echo_info "3. 清理 DNS 相关配置..."

# 清理 CoreDNS 相关（如果还有残留）
if [ -d /var/lib/rancher/k3s/server/manifests ]; then
    echo_info "  清理 k3s manifests 目录..."
    sudo rm -rf /var/lib/rancher/k3s/server/manifests
fi

# 清理 iptables 规则（k3s 创建的）
echo_info "  清理 iptables 规则..."
if command -v iptables &>/dev/null; then
    # 清理 k3s 相关的 iptables 规则
    sudo iptables -t nat -F KUBE-SERVICES 2>/dev/null || true
    sudo iptables -t nat -F KUBE-POSTROUTING 2>/dev/null || true
    sudo iptables -t filter -F KUBE-FORWARD 2>/dev/null || true
    sudo iptables -t filter -F KUBE-SERVICES 2>/dev/null || true
    echo_info "    ✓ iptables 规则已清理"
fi

# 清理网络接口（如果 k3s 创建了虚拟接口）
echo_info "  检查网络接口..."
if ip link show | grep -q "flannel\|cni0\|veth"; then
    echo_warn "    发现可能的 CNI 网络接口，可能需要手动清理："
    ip link show | grep -E "flannel|cni0|veth" | sed 's/^/      /' || true
    echo_warn "    如果这些接口影响网络，可以手动删除"
fi

# 清理路由表（k3s 相关的路由）
echo_info "  检查路由表..."
if ip route | grep -qE "10.42.0.0/16|10.43.0.0/16"; then
    echo_warn "    发现 k3s 相关的路由规则："
    ip route | grep -E "10.42.0.0/16|10.43.0.0/16" | sed 's/^/      /' || true
    echo_warn "    这些路由规则通常在重启后会消失"
fi

# 4. 清理其他可能的残留
echo ""
echo_info "4. 清理其他残留文件..."

# 清理日志
if [ -d /var/log/k3s ]; then
    echo_info "  清理 k3s 日志..."
    sudo rm -rf /var/log/k3s
fi

# 清理临时文件
if [ -d /tmp/k3s ]; then
    echo_info "  清理临时文件..."
    sudo rm -rf /tmp/k3s
fi

# 5. 验证清理结果
echo ""
echo_info "5. 验证清理结果..."

# 检查 k3s 进程
if pgrep -f k3s &>/dev/null; then
    echo_warn "  ⚠️  仍有 k3s 相关进程运行："
    pgrep -f k3s | sed 's/^/    /'
    echo_warn "    可能需要手动终止这些进程"
else
    echo_info "  ✓ 没有 k3s 进程运行"
fi

# 检查 k3s 服务
if sudo systemctl list-units --type=service | grep -q k3s; then
    echo_warn "  ⚠️  k3s 服务仍存在（但应该已停止）"
else
    echo_info "  ✓ k3s 服务已删除"
fi

# 检查关键目录
if [ -d /var/lib/rancher/k3s ] || [ -d /etc/rancher/k3s ]; then
    echo_warn "  ⚠️  仍有 k3s 目录残留："
    [ -d /var/lib/rancher/k3s ] && echo "    /var/lib/rancher/k3s" || true
    [ -d /etc/rancher/k3s ] && echo "    /etc/rancher/k3s" || true
    echo_warn "    可以手动删除这些目录"
else
    echo_info "  ✓ k3s 目录已清理"
fi

# 6. 总结
echo ""
echo_info "=========================================="
echo_info "卸载完成"
echo_info "=========================================="
echo ""
echo_info "已清理的内容："
echo "  ✓ k3s 可执行文件"
echo "  ✓ k3s 数据目录"
echo "  ✓ k3s 配置目录"
echo "  ✓ k3s systemd 服务"
echo "  ✓ kubeconfig（已备份）"
echo "  ✓ iptables 规则"
echo ""
echo_info "建议："
echo "  1. 重启系统以确保所有网络配置清理干净（可选）"
echo "  2. 重新安装 k3s："
echo "     DISABLE_SERVICELB=true ./docs/installation/install-k3s-only.sh"
echo ""
echo_warn "注意："
echo "  - 所有集群数据已删除"
echo "  - 需要重新安装所有组件（KubeVirt、Longhorn 等）"
echo ""


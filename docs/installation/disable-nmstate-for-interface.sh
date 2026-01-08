#!/bin/bash

# 禁用 NMState 对特定网卡的管理
# 用途：让特定网卡（如 ens160）由传统网络管理器管理，不受 NMState 控制

set -e

# 配置参数
INTERFACE="ens160"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    log_error "请使用 sudo 运行此脚本"
    exit 1
fi

log_info "禁用 NMState 对 $INTERFACE 网卡的管理..."

# 1. 删除相关的 NodeNetworkConfigurationPolicy
log_info "查找并删除相关的 NodeNetworkConfigurationPolicy..."

POLICIES=$(kubectl get nncp -o name 2>/dev/null | grep -i "$INTERFACE" || true)

if [ -n "$POLICIES" ]; then
    for policy in $POLICIES; do
        log_warn "删除策略: $policy"
        kubectl delete "$policy" || log_warn "删除失败: $policy"
    done
else
    log_info "未找到相关的 NodeNetworkConfigurationPolicy"
fi

# 2. 创建排除该网卡的策略（如果需要）
log_info "创建排除策略（可选）..."

# 3. 恢复传统网络配置
log_info "恢复传统网络配置..."

# 检查 NetworkManager 状态
if systemctl is-active --quiet NetworkManager; then
    log_info "NetworkManager 正在运行"
    
    # 使用 nmcli 配置（如果可用）
    if command -v nmcli &> /dev/null; then
        log_info "使用 nmcli 管理 $INTERFACE..."
        nmcli connection show "$INTERFACE" 2>/dev/null || {
            log_info "创建新的连接配置..."
            # 这里需要根据实际情况配置
        }
    fi
fi

# 4. 使用 netplan 配置（Ubuntu 推荐）
log_info "使用 netplan 配置..."

NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
if [ -z "$NETPLAN_FILE" ]; then
    NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
fi

log_info "备份原配置: $NETPLAN_FILE"
cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

log_info "现在可以手动编辑 $NETPLAN_FILE 来配置 $INTERFACE"
log_info "配置完成后运行: sudo netplan apply"

log_info "完成！"
log_info "注意：如果 NMState 继续管理该网卡，可能需要："
log_info "1. 卸载 NMState Operator（不推荐）"
log_info "2. 配置 NMState 排除该网卡（需要修改 NMState 配置）"


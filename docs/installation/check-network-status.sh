#!/bin/bash

# 检查网络配置状态
# 用途：诊断网络配置问题，显示当前网络状态和 NMState 配置

set -e

INTERFACE="${1:-ens160}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

echo "网络配置诊断工具"
echo "=================="

# 1. 检查网卡状态
log_section "网卡状态 ($INTERFACE)"
if ip link show $INTERFACE &>/dev/null; then
    echo "网卡存在: ✓"
    ip addr show $INTERFACE | grep -E "inet |state|UP|DOWN"
else
    echo "网卡不存在: ✗"
    echo "可用网卡:"
    ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//'
    exit 1
fi

# 2. 检查 IP 配置
log_section "IP 配置"
CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | head -1)
if [ -n "$CURRENT_IP" ]; then
    echo "当前 IP: $CURRENT_IP"
else
    echo "当前 IP: 未配置"
fi

# 3. 检查路由
log_section "路由配置"
ip route show | grep -E "default|$INTERFACE" || echo "无相关路由"

# 4. 检查 DNS
log_section "DNS 配置"
if [ -f /etc/resolv.conf ]; then
    cat /etc/resolv.conf | grep -E "^nameserver" || echo "无 DNS 配置"
else
    echo "resolv.conf 不存在"
fi

# 5. 检查 NetworkManager
log_section "NetworkManager 状态"
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    echo "状态: 运行中"
    if command -v nmcli &> /dev/null; then
        echo "连接信息:"
        nmcli connection show 2>/dev/null | grep -E "NAME|$INTERFACE" || echo "无连接配置"
    fi
else
    echo "状态: 未运行或未安装"
fi

# 6. 检查 netplan
log_section "Netplan 配置"
NETPLAN_FILES=$(ls /etc/netplan/*.yaml 2>/dev/null || true)
if [ -n "$NETPLAN_FILES" ]; then
    for file in $NETPLAN_FILES; do
        echo "文件: $file"
        if grep -q "$INTERFACE" "$file" 2>/dev/null; then
            echo "包含 $INTERFACE 配置:"
            grep -A 10 "$INTERFACE" "$file" | head -15
        fi
    done
else
    echo "无 netplan 配置文件"
fi

# 7. 检查 NMState
log_section "NMState 状态"
if kubectl get crd nodenetworkconfigurationpolicies.nmstate.io &>/dev/null; then
    echo "NMState CRD: 已安装"
    
    echo -e "\nNodeNetworkConfigurationPolicy:"
    kubectl get nncp 2>/dev/null || echo "无策略"
    
    echo -e "\nNodeNetworkState (当前节点):"
    NODE_NAME=$(hostname)
    if kubectl get nns "$NODE_NAME" &>/dev/null; then
        kubectl get nns "$NODE_NAME" -o yaml | grep -A 20 "$INTERFACE" || echo "无 $INTERFACE 配置"
    else
        echo "无 NodeNetworkState 资源"
    fi
    
    echo -e "\n相关策略详情:"
    kubectl get nncp -o name 2>/dev/null | while read policy; do
        if kubectl get "$policy" -o yaml | grep -q "$INTERFACE"; then
            echo "策略: $policy"
            kubectl get "$policy" -o yaml | grep -A 10 "$INTERFACE" | head -15
        fi
    done
else
    echo "NMState CRD: 未安装"
fi

# 8. 检查网络服务
log_section "网络服务状态"
systemctl status NetworkManager --no-pager -l 2>/dev/null | head -5 || echo "NetworkManager 未运行"
systemctl status systemd-networkd --no-pager -l 2>/dev/null | head -5 || echo "systemd-networkd 未运行"

echo -e "\n诊断完成！"


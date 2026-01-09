#!/bin/bash

# 修复 NMState 导致的静态 IP 配置问题
# 用途：恢复 ens160 网卡的静态 IP 配置（192.168.1.141）

set -e

# 配置参数
INTERFACE="ens160"
STATIC_IP="192.168.1.141"
NETMASK="255.255.255.0"
GATEWAY="192.168.1.1"
DNS_SERVERS="8.8.8.8,8.8.4.4"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

log_info "开始修复 NMState 网络配置问题..."

# 1. 检查当前网络状态
log_info "检查当前网络状态..."
ip addr show $INTERFACE || {
    log_error "网卡 $INTERFACE 不存在"
    exit 1
}

# 2. 检查 NMState 是否安装
log_info "检查 NMState 状态..."
if kubectl get crd nodenetworkconfigurationpolicies.nmstate.io &>/dev/null; then
    log_info "NMState 已安装"
    
    # 检查是否有现有的 NodeNetworkConfigurationPolicy
    EXISTING_POLICY=$(kubectl get nncp -o name 2>/dev/null | grep -i $INTERFACE || true)
    if [ -n "$EXISTING_POLICY" ]; then
        log_warn "发现现有的 NodeNetworkConfigurationPolicy: $EXISTING_POLICY"
        log_warn "建议先删除或更新该策略"
    fi
else
    log_warn "NMState 未安装，将使用传统方式配置"
fi

# 3. 创建 NMState NodeNetworkConfigurationPolicy（推荐方案）
log_info "创建 NMState NodeNetworkConfigurationPolicy..."

cat <<EOF | kubectl apply -f -
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: static-ip-${INTERFACE}
  labels:
    app: novasphere
    network: static
spec:
  nodeSelector:
    kubernetes.io/hostname: $(hostname)
  desiredState:
    interfaces:
      - name: ${INTERFACE}
        type: ethernet
        state: up
        ipv4:
          enabled: true
          address:
            - ip: ${STATIC_IP}
              prefix-length: 24
          dhcp: false
        ipv6:
          enabled: false
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${INTERFACE}
          table-id: 254
    dns-resolver:
      config:
        server:
          - 8.8.8.8
          - 8.8.4.4
EOF

if [ $? -eq 0 ]; then
    log_info "NodeNetworkConfigurationPolicy 创建成功"
    log_info "等待网络配置生效（约 30 秒）..."
    sleep 30
    
    # 验证配置
    log_info "验证网络配置..."
    CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ "$CURRENT_IP" = "$STATIC_IP" ]; then
        log_info "✓ 静态 IP 配置成功: $CURRENT_IP"
    else
        log_warn "当前 IP: $CURRENT_IP，期望 IP: $STATIC_IP"
        log_warn "可能需要等待更长时间或检查配置"
    fi
else
    log_error "NodeNetworkConfigurationPolicy 创建失败"
    log_info "尝试使用传统方式配置..."
    
    # 4. 备用方案：使用 netplan 配置（如果 NMState 未安装或失败）
    log_info "使用 netplan 配置静态 IP..."
    
    # 查找 netplan 配置文件
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
    fi
    
    # 备份原配置
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 创建 netplan 配置
    cat <<EOF > "$NETPLAN_FILE"
network:
  version: 2
  renderer: networkd
  ethernets:
    ${INTERFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}/24
      gateway4: ${GATEWAY}
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF
    
    log_info "应用 netplan 配置..."
    netplan apply
    
    sleep 5
    
    # 验证配置
    CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ "$CURRENT_IP" = "$STATIC_IP" ]; then
        log_info "✓ 静态 IP 配置成功: $CURRENT_IP"
    else
        log_error "配置失败，当前 IP: $CURRENT_IP"
        log_info "可以手动检查配置文件: $NETPLAN_FILE"
    fi
fi

# 5. 显示当前网络状态
log_info "当前网络状态:"
ip addr show $INTERFACE | grep -E "inet |state"
ip route show | grep default

log_info "修复完成！"
log_info "如果问题仍然存在，请检查："
log_info "1. kubectl get nncp -o yaml"
log_info "2. kubectl get nncp static-ip-${INTERFACE} -o yaml"
log_info "3. journalctl -u NetworkManager -n 50"


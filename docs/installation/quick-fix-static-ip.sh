#!/bin/bash

# 快速恢复固定IP - 一键修复脚本
# 用途：快速将 ens160 恢复为静态 IP 192.168.1.141

set -e

INTERFACE="ens160"
STATIC_IP="192.168.1.141"
GATEWAY="192.168.1.1"

echo "正在恢复固定IP配置..."

# 方法1: 使用 NMState（如果已安装）
if kubectl get crd nodenetworkconfigurationpolicies.nmstate.io &>/dev/null 2>&1; then
    echo "检测到 NMState，使用 NMState 配置..."
    
    NODE_NAME=$(hostname)
    
    kubectl apply -f - <<EOF
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: static-ip-${INTERFACE}
spec:
  nodeSelector:
    kubernetes.io/hostname: ${NODE_NAME}
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
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${INTERFACE}
          table-id: 254
EOF
    
    echo "✓ NMState 策略已创建，等待配置生效（约30秒）..."
    sleep 30
    
    # 验证
    CURRENT_IP=$(ip addr show $INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    if [ "$CURRENT_IP" = "$STATIC_IP" ]; then
        echo "✓ 成功！IP 已恢复为: $CURRENT_IP"
        exit 0
    else
        echo "⚠ NMState 配置可能未生效，尝试备用方案..."
    fi
fi

# 方法2: 使用 netplan（备用方案）
echo "使用 netplan 配置静态IP..."

# 备份原配置
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
if [ -z "$NETPLAN_FILE" ]; then
    NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
fi

if [ -f "$NETPLAN_FILE" ]; then
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# 创建 netplan 配置
cat > "$NETPLAN_FILE" <<EOF
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

# 应用配置
netplan apply

echo "✓ netplan 配置已应用，等待生效..."
sleep 5

# 验证
CURRENT_IP=$(ip addr show $INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ "$CURRENT_IP" = "$STATIC_IP" ]; then
    echo "✓ 成功！IP 已恢复为: $CURRENT_IP"
else
    echo "⚠ 当前 IP: $CURRENT_IP (期望: $STATIC_IP)"
    echo "请检查配置或等待更长时间"
fi


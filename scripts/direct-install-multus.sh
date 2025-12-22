#!/bin/bash

# 直接安装 Multus（不依赖其他脚本）

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
echo_info "直接安装 Multus"
echo_info "=========================================="
echo ""

# 1. 检测路径
CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
CNI_BIN_DIR="/var/lib/rancher/k3s/data/current/bin"

if [ ! -d "$CNI_CONF_DIR" ]; then
    echo_error "CNI 配置目录不存在: $CNI_CONF_DIR"
    exit 1
fi

echo_info "CNI 配置目录: $CNI_CONF_DIR"
echo_info "CNI 二进制目录: $CNI_BIN_DIR"
echo ""

# 2. 下载 YAML
echo_info "1. 下载 Multus DaemonSet YAML"
echo ""

YAML_FILE="/tmp/multus-daemonset-k3s.yaml"
YAML_URL="https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml"

if [ -f "$YAML_FILE" ]; then
    echo_info "  使用已存在的文件: $YAML_FILE"
else
    echo_info "  下载: $YAML_URL"
    curl -sL "$YAML_URL" -o "$YAML_FILE"
    
    if [ $? -ne 0 ] || [ ! -f "$YAML_FILE" ]; then
        echo_error "  ✗ 下载失败"
        exit 1
    fi
    echo_info "  ✓ 下载成功"
fi

# 3. 修改路径
echo ""
echo_info "2. 修改路径以适配 k3s"
echo ""

# 创建备份
cp "$YAML_FILE" "$YAML_FILE.orig"

# 替换路径
sed -i.tmp "s|/etc/cni/net.d|$CNI_CONF_DIR|g" "$YAML_FILE"
sed -i.tmp "s|/opt/cni/bin|$CNI_BIN_DIR|g" "$YAML_FILE"
rm -f "$YAML_FILE.tmp"

echo_info "  ✓ 路径已修改"
echo ""

# 4. 应用 DaemonSet
echo_info "3. 应用 Multus DaemonSet"
echo ""

if kubectl apply -f "$YAML_FILE" 2>&1; then
    echo_info "  ✓ DaemonSet 已应用"
else
    echo_error "  ✗ 应用失败"
    exit 1
fi

# 5. 创建配置文件
echo ""
echo_info "4. 创建 Multus 配置文件"
echo ""

sudo mkdir -p "$CNI_CONF_DIR/multus.d"

# 检测默认 CNI
DEFAULT_CNI=$(ls "$CNI_CONF_DIR"/*.conf* 2>/dev/null | grep -v multus | head -1 || echo "")
if [ -n "$DEFAULT_CNI" ]; then
    CNI_NAME=$(sudo cat "$DEFAULT_CNI" | jq -r '.name // .plugins[0].name' 2>/dev/null || echo "default")
else
    CNI_NAME="default"
fi

echo_info "  使用默认 CNI: $CNI_NAME"

# 创建配置文件
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"
sudo tee "$MULTUS_CONF" > /dev/null <<EOF
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "$CNI_CONF_DIR/multus.d/multus.kubeconfig",
  "confDir": "/etc/cni/multus/net.d",
  "cniDir": "/var/lib/cni/multus",
  "binDir": "/opt/cni/bin",
  "logFile": "/var/log/multus.log",
  "logLevel": "verbose",
  "capabilities": {
    "portMappings": true
  },
  "namespaceIsolation": false,
  "clusterNetwork": "$CNI_NAME",
  "defaultNetworks": [],
  "systemNamespaces": ["kube-system"],
  "multusNamespace": "kube-system"
}
EOF

sudo chmod 644 "$MULTUS_CONF"
echo_info "  ✓ 配置文件已创建"

# 6. 验证
echo ""
echo_info "5. 验证安装"
echo ""

sleep 3

if kubectl get daemonset -n kube-system kube-multus-ds > /dev/null 2>&1; then
    echo_info "  ✓ DaemonSet 已创建"
    kubectl get daemonset -n kube-system kube-multus-ds
else
    echo_error "  ✗ DaemonSet 未创建"
fi

echo ""
echo_info "  检查 Pods:"
kubectl get pods -n kube-system -l app=multus || echo_warn "  Pods 可能还在创建中"

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""


#!/bin/bash

# 修复 Multus 配置文件缺失问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复 Multus 配置文件缺失问题"
echo_info "=========================================="
echo ""

# 错误信息：open /etc/cni/net.d/multus.d/daemon-config.json: no such file or directory

# 1. 检查 k3s CNI 配置目录
echo_info "1. 检查 k3s CNI 配置目录"
echo ""

K3S_CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if [ -d "$K3S_CNI_DIR" ]; then
    echo_info "  CNI 配置目录: $K3S_CNI_DIR"
    echo_info "  目录内容:"
    sudo ls -la "$K3S_CNI_DIR" 2>/dev/null | head -10 || echo_warn "    需要 sudo 权限查看"
else
    echo_error "  ✗ CNI 配置目录不存在: $K3S_CNI_DIR"
    exit 1
fi

# 2. 创建 multus.d 目录
echo ""
echo_info "2. 创建 multus.d 目录和配置文件"
echo ""

MULTUS_DIR="$K3S_CNI_DIR/multus.d"
if [ ! -d "$MULTUS_DIR" ]; then
    echo_info "  创建目录: $MULTUS_DIR"
    sudo mkdir -p "$MULTUS_DIR"
    echo_info "  ✓ 目录已创建"
else
    echo_info "  ✓ 目录已存在: $MULTUS_DIR"
fi

# 3. 创建 daemon-config.json 文件
echo ""
echo_info "3. 创建 daemon-config.json 配置文件"
echo ""

CONFIG_FILE="$MULTUS_DIR/daemon-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo_info "  创建配置文件: $CONFIG_FILE"
    
    # 创建默认配置
    sudo tee "$CONFIG_FILE" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "/etc/cni/net.d",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log"
}
EOF
    
    echo_info "  ✓ 配置文件已创建"
else
    echo_info "  ✓ 配置文件已存在: $CONFIG_FILE"
fi

# 4. 检查并创建 00-multus.conf（如果不存在）
echo ""
echo_info "4. 检查 Multus 主配置文件"
echo ""

MULTUS_CONF="$K3S_CNI_DIR/00-multus.conf"

if [ ! -f "$MULTUS_CONF" ]; then
    echo_warn "  ⚠️  Multus 主配置文件不存在，创建默认配置..."
    
    # 检查默认 CNI（通常是 Flannel）
    DEFAULT_CNI=$(ls "$K3S_CNI_DIR"/*.conf* 2>/dev/null | grep -v multus | head -1 || echo "")
    
    if [ -n "$DEFAULT_CNI" ]; then
        echo_info "  检测到默认 CNI 配置: $DEFAULT_CNI"
        DEFAULT_CNI_NAME=$(basename "$DEFAULT_CNI")
    else
        echo_warn "  未找到默认 CNI 配置，使用默认值"
        DEFAULT_CNI_NAME="10-flannel.conflist"
    fi
    
    # 创建 Multus 配置
    sudo tee "$MULTUS_CONF" > /dev/null <<EOF
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "capabilities": {
    "portMappings": true
  },
  "delegates": [
    {
      "cniVersion": "0.3.1",
      "name": "default",
      "type": "flannel"
    }
  ],
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig"
}
EOF
    
    echo_info "  ✓ Multus 主配置文件已创建"
else
    echo_info "  ✓ Multus 主配置文件已存在: $MULTUS_CONF"
fi

# 5. 设置正确的权限
echo ""
echo_info "5. 设置文件权限"
echo ""

sudo chmod 644 "$CONFIG_FILE" 2>/dev/null || true
sudo chmod 755 "$MULTUS_DIR" 2>/dev/null || true

echo_info "  ✓ 权限已设置"

# 6. 验证配置
echo ""
echo_info "6. 验证配置"
echo ""

if [ -f "$CONFIG_FILE" ]; then
    echo_info "  配置文件内容:"
    sudo cat "$CONFIG_FILE" | sed 's/^/    /'
    echo ""
    echo_info "  ✓ 配置文件验证通过"
else
    echo_error "  ✗ 配置文件验证失败"
    exit 1
fi

# 7. 重启 Multus Pod
echo ""
echo_info "7. 重启 Multus Pod"
echo ""

MULTUS_PODS=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$MULTUS_PODS" ]; then
    echo_info "  删除现有的 Multus Pod..."
    for pod in $MULTUS_PODS; do
        kubectl delete pod -n kube-system "$pod" --force --grace-period=0 2>/dev/null || true
        echo_info "    ✓ 已删除: $pod"
    done
    
    echo_info "  ✓ 等待 Pod 自动重新创建..."
    sleep 5
else
    echo_warn "  未找到 Multus Pod"
fi

# 8. 检查状态
echo ""
echo_info "8. 检查修复结果"
echo ""

sleep 10

echo_info "Multus Pod 状态:"
kubectl get pods -n kube-system -l app=multus 2>/dev/null || echo_warn "  未找到 Pod"

echo ""
echo_info "查看最新的 Multus 日志:"
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod: $MULTUS_POD"
    kubectl logs -n kube-system "$MULTUS_POD" --tail=20 2>&1 | head -15 || echo_warn "  无法获取日志"
else
    echo_warn "  等待 Pod 创建..."
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "如果 Pod 仍然有问题，请检查："
echo "  1. Multus DaemonSet 的 volumeMounts 是否正确挂载了配置目录"
echo "  2. 运行: kubectl describe pod -n kube-system -l app=multus"
echo "  3. 查看日志: kubectl logs -n kube-system -l app=multus --tail=50"
echo ""


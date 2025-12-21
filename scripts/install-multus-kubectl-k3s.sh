#!/bin/bash

# 使用 kubectl apply 安装 Multus 并配置 k3s 路径
# 参考: 
# - https://github.com/k8snetworkplumbingwg/multus-cni
# - https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html
# - https://docs.k3s.io/networking/multus-ipams

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
echo_info "使用 kubectl apply 安装 Multus (k3s 配置)"
echo_info "=========================================="
echo ""

# 1. 清理旧安装
echo_info "1. 清理旧的 Multus 安装"
echo ""

if kubectl get daemonset -n kube-system kube-multus-ds &>/dev/null; then
    echo_info "  发现旧的 Multus DaemonSet，先删除..."
    kubectl delete daemonset -n kube-system kube-multus-ds --ignore-not-found=true
    kubectl delete pod -n kube-system -l app=multus --ignore-not-found=true --force --grace-period=0
    sleep 5
fi

# 2. 确定 k3s 版本和路径
echo ""
echo_info "2. 检测 k3s 版本和路径"
echo ""

K3S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | grep -oP 'v\d+\.\d+' || echo "unknown")
echo_info "  k3s 版本: $K3S_VERSION"

# 检测 CNI 二进制路径
if [ -d "/var/lib/rancher/k3s/data/cni" ]; then
    CNI_BIN_DIR="/var/lib/rancher/k3s/data/cni"
    echo_info "  ✓ 使用新版本 CNI 路径: $CNI_BIN_DIR"
elif [ -d "/var/lib/rancher/k3s/data/current/bin" ]; then
    CNI_BIN_DIR="/var/lib/rancher/k3s/data/current/bin"
    echo_warn "  ⚠️  使用旧版本 CNI 路径: $CNI_BIN_DIR"
    echo_warn "      注意：k3s 升级后需要重新安装 Multus"
else
    echo_error "  ✗ 无法确定 CNI 二进制路径"
    exit 1
fi

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
echo_info "  CNI 配置目录: $CNI_CONF_DIR"

# 3. 下载并修改 DaemonSet
echo ""
echo_info "3. 下载 Multus DaemonSet YAML"
echo ""

MULTUS_YAML_URL="https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml"
TEMP_YAML="/tmp/multus-daemonset-k3s.yaml"

echo_info "  下载: $MULTUS_YAML_URL"
curl -sL "$MULTUS_YAML_URL" -o "$TEMP_YAML"

if [ $? -ne 0 ]; then
    echo_error "  ✗ 下载失败"
    exit 1
fi

echo_info "  ✓ 下载成功"

# 4. 修改 DaemonSet 以适配 k3s 路径
echo ""
echo_info "4. 修改 DaemonSet 以适配 k3s 路径"
echo ""

# 备份原始文件
cp "$TEMP_YAML" "$TEMP_YAML.orig"

# 使用 sed 修改 volumes 中的 hostPath
# 注意：需要精确匹配，避免误替换
echo_info "  更新挂载路径..."

# 使用 awk 进行精确的路径替换
# 只替换 hostPath 下的 path 值，保持 YAML 结构
echo_info "  使用 awk 进行路径替换..."

awk -v cni_conf="$CNI_CONF_DIR" -v cni_bin="$CNI_BIN_DIR" '
BEGIN { 
    in_hostpath=0 
}
/hostPath:/ { 
    in_hostpath=1 
    print
    next
}
/^[[:space:]]+path:[[:space:]]+\/etc\/cni\/net\.d/ && in_hostpath {
    gsub(/\/etc\/cni\/net\.d/, cni_conf)
    in_hostpath=0
    print
    next
}
/^[[:space:]]+path:[[:space:]]+\/opt\/cni\/bin/ && in_hostpath {
    gsub(/\/opt\/cni\/bin/, cni_bin)
    in_hostpath=0
    print
    next
}
/^[[:space:]]*-[[:space:]]+name:/ { 
    in_hostpath=0 
}
{ 
    print 
}
' "$TEMP_YAML" > "$TEMP_YAML.new" && mv "$TEMP_YAML.new" "$TEMP_YAML"

# 验证替换是否成功
if grep -q "path: $CNI_CONF_DIR" "$TEMP_YAML" && grep -q "path: $CNI_BIN_DIR" "$TEMP_YAML"; then
    echo_info "  ✓ 路径替换成功"
else
    echo_error "  ✗ 路径替换失败，请手动检查 YAML 文件"
    echo_info "  备份文件: $TEMP_YAML.orig"
    exit 1
fi

echo_info "  ✓ 路径已更新"
echo_info "  修改详情:"
echo "    CNI 配置目录: $CNI_CONF_DIR"
echo "    CNI 二进制目录: $CNI_BIN_DIR"

# 5. 应用 DaemonSet
echo ""
echo_info "5. 应用 Multus DaemonSet"
echo ""

kubectl apply -f "$TEMP_YAML"

if [ $? -eq 0 ]; then
    echo_info "  ✓ DaemonSet 已应用"
else
    echo_error "  ✗ 应用失败"
    exit 1
fi

# 6. 等待 Pod 启动
echo ""
echo_info "6. 等待 Pod 启动"
echo ""

sleep 5

# 7. 创建 Multus 配置文件
echo ""
echo_info "7. 创建 Multus 配置文件"
echo ""

# 检测默认 CNI（通常是 Flannel）
DEFAULT_CNI=$(ls "$CNI_CONF_DIR"/*.conf* 2>/dev/null | grep -v multus | head -1 || echo "")
if [ -n "$DEFAULT_CNI" ]; then
    DEFAULT_CNI_NAME=$(basename "$DEFAULT_CNI")
    echo_info "  检测到默认 CNI: $DEFAULT_CNI_NAME"
    
    # 读取默认 CNI 的名称（从 JSON 配置中）
    if command -v jq &> /dev/null; then
        CNI_NAME=$(sudo cat "$DEFAULT_CNI" | jq -r '.name // .plugins[0].name' 2>/dev/null || echo "default")
    else
        CNI_NAME="default"
    fi
else
    echo_warn "  ⚠️  未找到默认 CNI 配置，使用默认值"
    CNI_NAME="default"
fi

# 创建 Multus 配置目录
sudo mkdir -p "$CNI_CONF_DIR/multus.d"

# 创建 Multus 主配置文件
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"
echo_info "  创建 Multus 配置文件: $MULTUS_CONF"

sudo tee "$MULTUS_CONF" > /dev/null <<EOF
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig",
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
echo_info "  ✓ Multus 配置文件已创建"

# 8. 创建 daemon-config.json（Thick Plugin 需要）
echo ""
echo_info "8. 创建 daemon-config.json (Thick Plugin)"
echo ""

DAEMON_CONFIG="$CNI_CONF_DIR/multus.d/daemon-config.json"
sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "/etc/cni/net.d",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log"
}
EOF

sudo chmod 644 "$DAEMON_CONFIG"
echo_info "  ✓ daemon-config.json 已创建"

# 9. 验证安装
echo ""
echo_info "9. 验证安装"
echo ""

sleep 10

echo_info "  Pod 状态:"
kubectl get pods -n kube-system -l app=multus || kubectl get pods -n kube-system | grep multus

echo ""
echo_info "  DaemonSet 状态:"
kubectl get daemonset -n kube-system kube-multus-ds

echo ""
echo_info "  CRD:"
kubectl get crd | grep networkattachment || echo_warn "  CRD 未找到（可能需要等待）"

echo ""
MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MULTUS_POD" ]; then
    echo_info "  Pod 日志 ($MULTUS_POD):"
    kubectl logs -n kube-system $MULTUS_POD --tail=20 2>&1 | head -15
    
    echo ""
    echo_info "  检查 Pod 内的配置:"
    kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/ 2>&1 | head -10 || true
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""
echo_info "配置文件位置:"
echo "  - Multus 主配置: $MULTUS_CONF"
echo "  - Daemon 配置: $DAEMON_CONFIG"
echo ""
echo_info "参考文档:"
echo "  - Multus 配置: https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html"
echo "  - k3s Multus: https://docs.k3s.io/networking/multus-ipams"
echo ""


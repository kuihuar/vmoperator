#!/bin/bash

# 最终修复 Multus clusterNetwork - 使用正确的配置方式

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
echo_info "最终修复 Multus clusterNetwork"
echo_info "=========================================="
echo ""

CNI_CONF_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
MULTUS_CONF="$CNI_CONF_DIR/00-multus.conf"

# 1. 查找 k3s 实际使用的 CNI 配置文件名
echo_info "1. 查找 k3s CNI 配置文件名"
echo ""

# 查找第一个非 multus 的配置文件（.conf 或 .conflist）
CNI_CONFIG_FILE=$(sudo ls -1 "$CNI_CONF_DIR"/*.{conf,conflist} 2>/dev/null | grep -v multus | head -1 || echo "")
CNI_CONFIG_NAME=""

if [ -n "$CNI_CONFIG_FILE" ]; then
    CNI_CONFIG_NAME=$(basename "$CNI_CONFIG_FILE" .conf)
    CNI_CONFIG_NAME=$(basename "$CNI_CONFIG_NAME" .conflist)
    echo_info "  找到 CNI 配置文件: $CNI_CONFIG_FILE"
    echo_info "  配置文件名（不含扩展名）: $CNI_CONFIG_NAME"
    
    # 尝试从配置中读取 name
    CNI_NAME=$(sudo cat "$CNI_CONFIG_FILE" | jq -r '.name // .plugins[0].name // ""' 2>/dev/null || echo "")
    if [ -n "$CNI_NAME" ] && [ "$CNI_NAME" != "null" ]; then
        echo_info "  配置中的 name: $CNI_NAME"
    fi
else
    echo_warn "  ⚠️  未找到 CNI 配置文件"
    CNI_CONFIG_NAME="10-flannel"  # k3s 常见默认值
fi

echo ""

# 2. 检查当前 Multus 配置
echo_info "2. 检查当前 Multus 配置"
echo ""

CURRENT_VALUE=$(sudo cat "$MULTUS_CONF" | jq -r '.clusterNetwork // ""' 2>/dev/null || echo "")
echo_info "  当前 clusterNetwork: $CURRENT_VALUE"

# 3. 决定使用哪个值
echo ""
echo_info "3. 确定正确的 clusterNetwork 值"
echo ""

# Multus 的 clusterNetwork 应该指向 CNI 配置文件名（不含扩展名）
# 或者指向配置中的 name 字段
if [ -n "$CNI_NAME" ] && [ "$CNI_NAME" != "null" ] && [ "$CNI_NAME" != "multus-cni-network" ]; then
    TARGET_VALUE="$CNI_NAME"
    echo_info "  使用配置中的 name: $TARGET_VALUE"
elif [ -n "$CNI_CONFIG_NAME" ]; then
    TARGET_VALUE="$CNI_CONFIG_NAME"
    echo_info "  使用配置文件名: $TARGET_VALUE"
else
    TARGET_VALUE="flannel"
    echo_warn "  使用默认值: $TARGET_VALUE"
fi

echo ""

# 4. 检查是否需要修改
if [ "$CURRENT_VALUE" = "$TARGET_VALUE" ]; then
    echo_info "  ✓ clusterNetwork 已经是正确值: $TARGET_VALUE"
    echo_info "  但可能还需要创建对应的 NAD..."
else
    echo_warn "  需要修改 clusterNetwork:"
    echo_info "    从: $CURRENT_VALUE"
    echo_info "    到: $TARGET_VALUE"
    
    # 备份并修改
    BACKUP_FILE="$MULTUS_CONF.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp "$MULTUS_CONF" "$BACKUP_FILE"
    echo_info "  ✓ 已备份到: $BACKUP_FILE"
    
    if command -v jq &> /dev/null; then
        CURRENT_JSON=$(sudo cat "$MULTUS_CONF" | jq '.')
        echo "$CURRENT_JSON" | jq ".clusterNetwork = \"$TARGET_VALUE\"" | sudo tee "$MULTUS_CONF" > /dev/null
    else
        sudo sed -i "s|\"clusterNetwork\":\s*\"[^\"]*\"|\"clusterNetwork\": \"$TARGET_VALUE\"|g" "$MULTUS_CONF"
    fi
    
    echo_info "  ✓ 已修改"
fi

echo ""

# 5. 创建或更新 NetworkAttachmentDefinition
echo_info "5. 创建 NetworkAttachmentDefinition"
echo ""

NAD_NAME="$TARGET_VALUE"
echo_info "  创建 NAD: $NAD_NAME (在 kube-system 命名空间)"

# 检查 NAD 是否已存在
if kubectl get networkattachmentdefinition -n kube-system $NAD_NAME &>/dev/null; then
    echo_info "  ✓ NAD 已存在，更新..."
    kubectl delete networkattachmentdefinition -n kube-system $NAD_NAME --ignore-not-found=true
fi

# 创建 NAD
cat <<EOF | kubectl apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: $NAD_NAME
  namespace: kube-system
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "$NAD_NAME",
      "type": "flannel"
    }
EOF

echo_info "  ✓ NAD 已创建"

# 6. 验证
echo ""
echo_info "6. 验证配置"
echo ""

echo_info "  Multus clusterNetwork:"
sudo cat "$MULTUS_CONF" | jq -r '.clusterNetwork' 2>/dev/null || echo "无法读取"

echo ""
echo_info "  NAD 状态:"
kubectl get networkattachmentdefinition -n kube-system $NAD_NAME

echo ""
echo_info "7. 重启相关 Pod"
echo ""

# 重启 Multus Pod
kubectl delete pod -n kube-system -l app=multus --force --grace-period=0 2>/dev/null || true
echo_info "  ✓ Multus Pod 已删除"

# 等待几秒
sleep 5

# 重启 Rook Operator Pod
kubectl delete pod -n rook-ceph -l app=rook-ceph-operator --force --grace-period=0 2>/dev/null || true
echo_info "  ✓ Rook Operator Pod 已删除"

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "等待 10 秒后检查 Pod 状态..."
sleep 10

echo ""
echo_info "Multus Pod:"
kubectl get pods -n kube-system -l app=multus

echo ""
echo_info "Rook Operator Pod:"
kubectl get pods -n rook-ceph -l app=rook-ceph-operator

echo ""


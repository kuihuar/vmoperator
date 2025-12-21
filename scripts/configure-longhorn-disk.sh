#!/bin/bash

# 配置 Longhorn 使用指定的磁盘路径

set -e

DISK_PATH="${1:-/var/lib/longhorn}"

if [ -z "$1" ]; then
    echo "用法: $0 <disk-path>"
    echo "示例: $0 /mnt/longhorn"
    echo ""
    echo "当前将使用默认路径: $DISK_PATH"
    read -p "继续? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo "=== 配置 Longhorn 磁盘路径 ==="
echo "路径: $DISK_PATH"
echo ""

# 1. 检查路径是否存在
if [ ! -d "$DISK_PATH" ]; then
    echo "❌ 路径不存在: $DISK_PATH"
    echo ""
    read -p "是否创建路径? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo mkdir -p "$DISK_PATH"
        sudo chmod 755 "$DISK_PATH"
        echo "✓ 路径已创建"
    else
        echo "退出"
        exit 1
    fi
else
    echo "✓ 路径存在"
fi
echo ""

# 2. 检查路径权限
if [ ! -w "$DISK_PATH" ]; then
    echo "⚠️  路径不可写，尝试修复权限..."
    sudo chmod 755 "$DISK_PATH"
    echo "✓ 权限已修复"
else
    echo "✓ 路径可写"
fi
echo ""

# 3. 检查磁盘空间
echo "3. 检查磁盘空间..."
df -h "$DISK_PATH" | tail -1
AVAILABLE=$(df -h "$DISK_PATH" | tail -1 | awk '{print $4}')
echo "可用空间: $AVAILABLE"
echo ""

# 4. 获取节点名称
echo "4. 获取节点名称..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NODE_NAME" ]; then
    echo "❌ 无法获取节点名称"
    exit 1
fi
echo "节点名称: $NODE_NAME"
echo ""

# 5. 检查 Longhorn Node 资源是否存在
echo "5. 检查 Longhorn Node 资源..."
if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "⚠️  Longhorn Node 资源不存在，等待创建..."
    echo "   这可能需要几分钟，请等待 Longhorn Manager 创建 Node 资源"
    echo ""
    echo "   检查: kubectl get nodes.longhorn.io -n longhorn-system"
    exit 1
fi
echo "✓ Longhorn Node 资源存在"
echo ""

# 6. 检查当前磁盘配置
echo "6. 检查当前磁盘配置..."
CURRENT_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if [ -n "$CURRENT_DISKS" ] && [ "$CURRENT_DISKS" != "null" ]; then
    echo "当前配置的磁盘:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 10 "disks:" | head -15
    echo ""
    
    # 检查路径是否已配置
    if echo "$CURRENT_DISKS" | grep -q "$DISK_PATH"; then
        echo "✓ 路径 $DISK_PATH 已配置"
        read -p "是否更新配置? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "退出"
            exit 0
        fi
    fi
else
    echo "当前没有配置磁盘"
fi
echo ""

# 7. 配置磁盘
echo "7. 配置磁盘..."
DISK_NAME="data-disk"
if [ "$DISK_PATH" = "/var/lib/longhorn" ]; then
    DISK_NAME="default-disk"
fi

# 使用 patch 更新配置
PATCH=$(cat <<EOF
{
  "spec": {
    "disks": {
      "$DISK_NAME": {
        "allowScheduling": true,
        "evictionRequested": false,
        "path": "$DISK_PATH",
        "storageReserved": 0,
        "tags": []
      }
    }
  }
}
EOF
)

echo "应用配置..."
kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"

if [ $? -eq 0 ]; then
    echo "✓ 配置已应用"
else
    echo "❌ 配置失败"
    exit 1
fi
echo ""

# 8. 验证配置
echo "8. 验证配置..."
sleep 2
UPDATED_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if echo "$UPDATED_DISKS" | grep -q "$DISK_PATH"; then
    echo "✓ 配置验证成功"
    echo ""
    echo "当前磁盘配置:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 15 "disks:" | head -20
else
    echo "⚠️  配置可能未生效，请手动检查"
fi
echo ""

# 9. 提示
echo "=== 配置完成 ==="
echo ""
echo "下一步:"
echo "  1. 在 Longhorn UI 中验证:"
echo "     kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
echo "     然后访问: http://192.168.1.141:8088"
echo "     进入: Nodes → $NODE_NAME → Disks"
echo ""
echo "  2. 验证磁盘状态:"
echo "     kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 'disks:'"
echo ""
echo "  3. 测试 PVC 创建:"
echo "     kubectl apply -f - <<EOF"
echo "     apiVersion: v1"
echo "     kind: PersistentVolumeClaim"
echo "     metadata:"
echo "       name: test-pvc"
echo "     spec:"
echo "       accessModes:"
echo "         - ReadWriteOnce"
echo "       storageClassName: longhorn"
echo "       resources:"
echo "         requests:"
echo "           storage: 1Gi"
echo "     EOF"
echo ""


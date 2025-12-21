#!/bin/bash

# 修复 Longhorn 磁盘 UUID 不匹配问题

set -e

DISK_PATH="${1:-/mnt/longhorn}"

echo "=== 修复 Longhorn 磁盘 UUID 不匹配 ==="
echo "磁盘路径: $DISK_PATH"
echo ""

# 1. 检查路径
if [ ! -d "$DISK_PATH" ]; then
    echo "❌ 路径不存在: $DISK_PATH"
    exit 1
fi

if [ ! -w "$DISK_PATH" ]; then
    echo "❌ 路径不可写: $DISK_PATH"
    exit 1
fi

echo "✓ 路径存在且可写"
echo ""

# 2. 获取节点名称
echo "2. 获取节点名称..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NODE_NAME" ]; then
    echo "❌ 无法获取节点名称"
    exit 1
fi
echo "节点名称: $NODE_NAME"
echo ""

# 3. 检查 Longhorn Node 资源
echo "3. 检查 Longhorn Node 资源..."
if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "❌ Longhorn Node 资源不存在"
    exit 1
fi
echo "✓ Longhorn Node 资源存在"
echo ""

# 4. 查看当前配置
echo "4. 查看当前磁盘配置..."
CURRENT_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if [ -n "$CURRENT_DISKS" ] && [ "$CURRENT_DISKS" != "null" ]; then
    echo "当前配置:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 20 "disks:" | head -25
    echo ""
else
    echo "当前没有配置磁盘"
    echo ""
fi

# 5. 查看磁盘状态
echo "5. 查看磁盘状态..."
NODE_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' 2>/dev/null)
if [ -n "$NODE_STATUS" ] && [ "$NODE_STATUS" != "null" ]; then
    echo "磁盘状态:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 30 "diskStatus:" | head -35
    echo ""
fi

# 6. 确认操作
echo "6. 修复方案..."
echo "将执行以下操作:"
echo "  1. 删除 Longhorn Node 中的旧磁盘配置"
echo "  2. 清理磁盘路径（如果存在 Longhorn 数据）"
echo "  3. 重新配置磁盘"
echo ""
read -p "确定要继续吗? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi
echo ""

# 7. 删除旧磁盘配置
echo "7. 删除旧磁盘配置..."
# 找到使用该路径的磁盘名称
DISK_NAME=""
if [ -n "$CURRENT_DISKS" ] && [ "$CURRENT_DISKS" != "null" ]; then
    # 尝试从配置中提取磁盘名称
    DISK_NAME=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null | \
        python3 -c "import sys, json; data=json.load(sys.stdin); print([k for k,v in data.items() if v.get('path')=='$DISK_PATH'][0] if data else '')" 2>/dev/null || \
        echo "")
fi

if [ -z "$DISK_NAME" ]; then
    # 如果找不到，使用默认名称
    DISK_NAME="data-disk"
    if [ "$DISK_PATH" = "/var/lib/longhorn" ]; then
        DISK_NAME="default-disk"
    fi
fi

echo "磁盘名称: $DISK_NAME"

# 方法 1: 清空整个 disks 配置
echo "清空磁盘配置..."
PATCH='{"spec":{"disks":null}}'
kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH" || true
echo "✓ 旧配置已清空"
echo ""

# 8. 清理磁盘路径（可选）
echo "8. 清理磁盘路径（可选）..."
if [ -d "$DISK_PATH" ]; then
    # 检查是否有 Longhorn 数据
    if [ -d "$DISK_PATH/replicas" ] || [ -d "$DISK_PATH/engine-binaries" ]; then
        echo "⚠️  发现 Longhorn 数据目录"
        read -p "是否清理 Longhorn 数据? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "备份并清理数据..."
            BACKUP_DIR="${DISK_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
            sudo mv "$DISK_PATH" "$BACKUP_DIR" 2>/dev/null || true
            sudo mkdir -p "$DISK_PATH"
            sudo chmod 755 "$DISK_PATH"
            echo "✓ 数据已备份到: $BACKUP_DIR"
        else
            echo "跳过清理数据"
        fi
    else
        echo "✓ 没有 Longhorn 数据，无需清理"
    fi
fi
echo ""

# 9. 等待一下，确保清理完成
echo "9. 等待清理完成..."
sleep 3

# 10. 重新配置磁盘
echo "10. 重新配置磁盘..."
DISK_NAME="data-disk"
if [ "$DISK_PATH" = "/var/lib/longhorn" ]; then
    DISK_NAME="default-disk"
fi

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

echo "应用新配置..."
kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"

if [ $? -eq 0 ]; then
    echo "✓ 新配置已应用"
else
    echo "❌ 配置失败"
    exit 1
fi
echo ""

# 11. 验证配置
echo "11. 验证配置..."
sleep 5

UPDATED_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if echo "$UPDATED_DISKS" | grep -q "$DISK_PATH"; then
    echo "✓ 配置验证成功"
    echo ""
    echo "当前磁盘配置:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 15 "disks:" | head -20
else
    echo "⚠️  配置可能未生效"
fi
echo ""

# 12. 检查磁盘状态
echo "12. 检查磁盘状态..."
echo "等待磁盘就绪（可能需要几分钟）..."
for i in {1..30}; do
    DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' 2>/dev/null)
    if [ -n "$DISK_STATUS" ] && [ "$DISK_STATUS" != "null" ]; then
        # 检查是否有错误
        if echo "$DISK_STATUS" | grep -q "not ready"; then
            echo "  等待中... ($i/30)"
            sleep 2
        else
            echo "✓ 磁盘状态正常"
            break
        fi
    else
        echo "  等待中... ($i/30)"
        sleep 2
    fi
done
echo ""

# 13. 查看最终状态
echo "13. 查看最终状态..."
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 30 "diskStatus:" | head -35
echo ""

echo "=== 修复完成 ==="
echo ""
echo "如果磁盘仍然显示 'not ready'，请检查:"
echo "  1. 磁盘路径权限: ls -la $DISK_PATH"
echo "  2. 磁盘空间: df -h $DISK_PATH"
echo "  3. Longhorn Manager 日志:"
echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
echo ""
echo "在 Longhorn UI 中验证:"
echo "  kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
echo "  访问: http://192.168.1.141:8088"
echo "  进入: Nodes → $NODE_NAME → Disks"
echo ""


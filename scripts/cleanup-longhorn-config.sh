#!/bin/bash

# 清理 Longhorn 的旧磁盘配置

echo "=== 清理 Longhorn 旧配置 ==="
echo ""

# 确认
read -p "确定要清理 Longhorn 的旧磁盘配置吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 1. 获取节点名称
echo "1. 获取节点名称..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NODE_NAME" ]; then
    echo "❌ 无法获取节点名称"
    exit 1
fi
echo "节点名称: $NODE_NAME"
echo ""

# 2. 检查 Longhorn Node 资源
echo "2. 检查 Longhorn Node 资源..."
if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "⚠️  Longhorn Node 资源不存在"
    echo "可能 Longhorn 未安装或 Node 资源未创建"
    exit 0
fi
echo "✓ Longhorn Node 资源存在"
echo ""

# 3. 查看当前配置
echo "3. 查看当前磁盘配置..."
CURRENT_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if [ -n "$CURRENT_DISKS" ] && [ "$CURRENT_DISKS" != "null" ]; then
    echo "当前配置的磁盘:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 20 "disks:" | head -25
    echo ""
else
    echo "当前没有配置磁盘"
    echo ""
fi

# 4. 清理磁盘配置
echo "4. 清理磁盘配置..."
# 使用 patch 清空 disks 配置
PATCH='{"spec":{"disks":null}}'

echo "清空磁盘配置..."
kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"

if [ $? -eq 0 ]; then
    echo "✓ 磁盘配置已清空"
else
    echo "⚠️  清空配置可能失败，尝试其他方法..."
    # 尝试直接编辑
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml > /tmp/longhorn-node.yaml
    # 移除 disks 字段（如果存在）
    if command -v yq &>/dev/null; then
        yq eval 'del(.spec.disks)' -i /tmp/longhorn-node.yaml
        kubectl apply -f /tmp/longhorn-node.yaml
        rm -f /tmp/longhorn-node.yaml
    else
        echo "需要手动编辑: kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME"
    fi
fi
echo ""

# 5. 验证清理结果
echo "5. 验证清理结果..."
sleep 2
UPDATED_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if [ -z "$UPDATED_DISKS" ] || [ "$UPDATED_DISKS" = "null" ]; then
    echo "✓ 磁盘配置已清空"
else
    echo "⚠️  磁盘配置可能未完全清空"
    echo "当前配置:"
    echo "$UPDATED_DISKS"
fi
echo ""

# 6. 提示清理旧数据（可选）
echo "6. 清理旧数据（可选）..."
echo "注意: 以下操作会删除 Longhorn 的旧数据，请谨慎操作"
echo ""
read -p "是否删除 /var/lib/longhorn 目录下的旧数据? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "/var/lib/longhorn" ]; then
        echo "备份旧数据到 /var/lib/longhorn.backup..."
        sudo mv /var/lib/longhorn /var/lib/longhorn.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        echo "✓ 旧数据已备份"
    else
        echo "目录不存在，跳过"
    fi
else
    echo "跳过清理旧数据"
fi
echo ""

echo "=== 清理完成 ==="
echo ""
echo "下一步:"
echo "  1. 准备新磁盘: ./scripts/prepare-new-disk.sh /dev/sdb /mnt/longhorn"
echo "  2. 配置 Longhorn: ./scripts/configure-longhorn-disk.sh /mnt/longhorn"
echo ""


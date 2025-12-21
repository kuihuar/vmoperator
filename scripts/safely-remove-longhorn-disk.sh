#!/bin/bash

# 安全删除 Longhorn 磁盘配置（先禁用并移除副本）

set -e

NODE_NAME="${1:-host1}"
DISK_NAME="${2:-data-disk}"

echo "=== 安全删除 Longhorn 磁盘配置 ==="
echo "节点名称: $NODE_NAME"
echo "磁盘名称: $DISK_NAME"
echo ""

# 1. 检查节点
if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "❌ Longhorn Node 资源不存在: $NODE_NAME"
    exit 1
fi
echo "✓ Longhorn Node 资源存在"
echo ""

# 2. 查看当前磁盘状态
echo "2. 查看当前磁盘状态..."
DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME}" 2>/dev/null)
if [ -z "$DISK_STATUS" ] || [ "$DISK_STATUS" = "null" ]; then
    echo "⚠️  磁盘 $DISK_NAME 不存在或已删除"
    exit 0
fi

echo "磁盘状态:"
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME}" | python3 -m json.tool 2>/dev/null || \
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 20 "diskStatus:" | grep -A 15 "$DISK_NAME" | head -20
echo ""

# 3. 检查副本数量
echo "3. 检查副本数量..."
SCHEDULED_REPLICAS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME.scheduledReplica}" 2>/dev/null)
if [ -n "$SCHEDULED_REPLICAS" ] && [ "$SCHEDULED_REPLICAS" != "null" ] && [ "$SCHEDULED_REPLICAS" != "{}" ]; then
    REPLICA_COUNT=$(echo "$SCHEDULED_REPLICAS" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "?")
    echo "⚠️  发现 $REPLICA_COUNT 个副本在磁盘上"
    echo "副本列表:"
    echo "$SCHEDULED_REPLICAS" | python3 -m json.tool 2>/dev/null || echo "$SCHEDULED_REPLICAS"
    echo ""
else
    echo "✓ 没有副本在磁盘上"
    REPLICA_COUNT=0
fi
echo ""

# 4. 禁用磁盘调度
echo "4. 禁用磁盘调度..."
CURRENT_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if [ -n "$CURRENT_DISKS" ] && [ "$CURRENT_DISKS" != "null" ]; then
    # 获取磁盘路径
    DISK_PATH=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.spec.disks.$DISK_NAME.path}" 2>/dev/null)
    if [ -z "$DISK_PATH" ]; then
        echo "❌ 无法获取磁盘路径"
        exit 1
    fi
    echo "磁盘路径: $DISK_PATH"
    
    # 禁用调度
    PATCH=$(cat <<EOF
{
  "spec": {
    "disks": {
      "$DISK_NAME": {
        "allowScheduling": false,
        "evictionRequested": true,
        "path": "$DISK_PATH",
        "storageReserved": 0,
        "tags": []
      }
    }
  }
}
EOF
)
    
    echo "禁用磁盘调度并请求驱逐副本..."
    kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"
    echo "✓ 磁盘调度已禁用，副本驱逐已请求"
else
    echo "⚠️  磁盘配置不存在，可能已经删除"
    exit 0
fi
echo ""

# 5. 等待副本迁移
if [ "$REPLICA_COUNT" -gt 0 ]; then
    echo "5. 等待副本迁移（这可能需要几分钟）..."
    echo "Longhorn 会自动将副本迁移到其他磁盘..."
    echo ""
    
    for i in {1..120}; do
        CURRENT_REPLICAS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME.scheduledReplica}" 2>/dev/null)
        if [ -z "$CURRENT_REPLICAS" ] || [ "$CURRENT_REPLICAS" = "null" ] || [ "$CURRENT_REPLICAS" = "{}" ]; then
            echo "✓ 所有副本已迁移"
            break
        else
            CURRENT_COUNT=$(echo "$CURRENT_REPLICAS" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "?")
            echo "  等待中... ($i/120) - 剩余副本: $CURRENT_COUNT"
        fi
        sleep 2
    done
    
    # 再次检查
    FINAL_REPLICAS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME.scheduledReplica}" 2>/dev/null)
    if [ -n "$FINAL_REPLICAS" ] && [ "$FINAL_REPLICAS" != "null" ] && [ "$FINAL_REPLICAS" != "{}" ]; then
        FINAL_COUNT=$(echo "$FINAL_REPLICAS" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "?")
        echo ""
        echo "⚠️  仍有 $FINAL_COUNT 个副本未迁移"
        echo ""
        read -p "是否强制删除磁盘配置（可能导致数据丢失）? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已取消"
            echo ""
            echo "请手动处理副本:"
            echo "  1. 在 Longhorn UI 中查看卷和副本"
            echo "  2. 手动删除或迁移副本"
            echo "  3. 然后重新运行此脚本"
            exit 1
        fi
    fi
    echo ""
else
    echo "5. 跳过副本迁移（没有副本）"
    echo ""
fi

# 6. 等待一下，确保状态同步
echo "6. 等待状态同步..."
sleep 5

# 7. 删除磁盘配置
echo "7. 删除磁盘配置..."
# 获取所有磁盘配置
ALL_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)

if [ -n "$ALL_DISKS" ] && [ "$ALL_DISKS" != "null" ]; then
    # 如果只有一个磁盘，直接清空
    DISK_COUNT=$(echo "$ALL_DISKS" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "1")
    
    if [ "$DISK_COUNT" -eq 1 ]; then
        echo "只有一个磁盘，清空所有配置..."
        PATCH='{"spec":{"disks":null}}'
        kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"
    else
        echo "多个磁盘，只删除 $DISK_NAME..."
        # 需要保留其他磁盘，只删除指定的
        # 这里使用更复杂的方法：获取所有磁盘，删除指定的，然后重新应用
        # 为了简化，我们直接编辑
        echo "请手动编辑: kubectl edit nodes.longhorn.io -n longhorn-system $NODE_NAME"
        echo "删除 disks.$DISK_NAME 字段"
        exit 0
    fi
else
    echo "磁盘配置已不存在"
fi

if [ $? -eq 0 ]; then
    echo "✓ 磁盘配置已删除"
else
    echo "❌ 删除失败"
    exit 1
fi
echo ""

# 8. 验证
echo "8. 验证删除结果..."
sleep 3
UPDATED_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if [ -z "$UPDATED_DISKS" ] || [ "$UPDATED_DISKS" = "null" ]; then
    echo "✓ 磁盘配置已完全删除"
else
    echo "⚠️  磁盘配置可能未完全删除"
    echo "当前配置:"
    echo "$UPDATED_DISKS"
fi
echo ""

echo "=== 删除完成 ==="
echo ""
echo "下一步: 可以重新配置磁盘"
echo "  ./scripts/configure-longhorn-disk.sh /mnt/longhorn"
echo ""


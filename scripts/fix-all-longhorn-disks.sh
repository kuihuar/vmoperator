#!/bin/bash

# 修复所有 Longhorn 磁盘问题

set -e

NODE_NAME="${1:-host1}"
DISK_PATH="${2:-/mnt/longhorn}"

echo "=== 修复所有 Longhorn 磁盘问题 ==="
echo "节点名称: $NODE_NAME"
echo "目标磁盘路径: $DISK_PATH"
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
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 30 "diskStatus:" | head -40
echo ""

# 3. 查看当前磁盘配置
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

# 4. 确认操作
echo "4. 修复方案..."
echo "将执行以下操作:"
echo "  1. 清空所有磁盘配置"
echo "  2. 清理有问题的磁盘路径（可选）"
echo "  3. 只配置一个正确的磁盘: $DISK_PATH"
echo ""
read -p "确定要继续吗? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi
echo ""

# 5. 清空所有磁盘配置
echo "5. 清空所有磁盘配置..."
PATCH='{"spec":{"disks":null}}'
kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"
echo "✓ 所有磁盘配置已清空"
echo ""

# 6. 等待清理完成
echo "6. 等待清理完成..."
sleep 5

# 7. 清理磁盘路径（可选）
echo "7. 清理磁盘路径（可选）..."
if [ -d "$DISK_PATH" ]; then
    # 检查是否有 Longhorn 配置文件
    if [ -f "$DISK_PATH/longhorn-disk.cfg" ]; then
        echo "发现 Longhorn 配置文件，删除..."
        sudo rm -f "$DISK_PATH/longhorn-disk.cfg"
        echo "✓ 配置文件已删除"
    fi
    
    # 检查是否有其他 Longhorn 数据
    if [ -d "$DISK_PATH/replicas" ] || [ -d "$DISK_PATH/engine-binaries" ]; then
        echo "⚠️  发现 Longhorn 数据目录"
        read -p "是否清理所有 Longhorn 数据? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            BACKUP_DIR="${DISK_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
            echo "备份数据到: $BACKUP_DIR"
            sudo mv "$DISK_PATH" "$BACKUP_DIR" 2>/dev/null || true
            sudo mkdir -p "$DISK_PATH"
            sudo chmod 755 "$DISK_PATH"
            echo "✓ 数据已备份并清理"
        else
            echo "跳过清理数据"
        fi
    else
        echo "✓ 没有需要清理的数据"
    fi
else
    echo "创建磁盘路径..."
    sudo mkdir -p "$DISK_PATH"
    sudo chmod 755 "$DISK_PATH"
    echo "✓ 路径已创建"
fi
echo ""

# 8. 清理 /var/lib/longhorn（如果存在）
echo "8. 清理 /var/lib/longhorn（如果存在）..."
if [ -d "/var/lib/longhorn" ] && [ "$DISK_PATH" != "/var/lib/longhorn" ]; then
    if [ -f "/var/lib/longhorn/longhorn-disk.cfg" ]; then
        echo "删除 /var/lib/longhorn 的配置文件..."
        sudo rm -f "/var/lib/longhorn/longhorn-disk.cfg"
        echo "✓ 配置文件已删除"
    fi
fi
echo ""

# 9. 等待一下
echo "9. 等待系统同步..."
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
for i in {1..60}; do
    DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' 2>/dev/null)
    if [ -n "$DISK_STATUS" ] && [ "$DISK_STATUS" != "null" ]; then
        # 检查目标磁盘的状态
        if echo "$DISK_STATUS" | grep -q "$DISK_NAME"; then
            # 检查是否就绪
            READY_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
            if [ "$READY_STATUS" = "True" ]; then
                echo "✓ 磁盘已就绪！"
                break
            else
                MESSAGE=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME.conditions[?(@.type=='Ready')].message}" 2>/dev/null)
                if [ -n "$MESSAGE" ]; then
                    echo "  等待中... ($i/60) - $MESSAGE"
                else
                    echo "  等待中... ($i/60)"
                fi
            fi
        else
            echo "  等待磁盘状态更新... ($i/60)"
        fi
    else
        echo "  等待磁盘状态... ($i/60)"
    fi
    sleep 2
done
echo ""

# 13. 查看最终状态
echo "13. 查看最终磁盘状态..."
kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 30 "diskStatus:" | head -40
echo ""

# 14. 总结
echo "=== 修复完成 ==="
echo ""
echo "磁盘配置:"
echo "  - 磁盘名称: $DISK_NAME"
echo "  - 磁盘路径: $DISK_PATH"
echo ""

# 检查是否还有问题
PROBLEMS=0
DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.status.diskStatus}' 2>/dev/null)
if echo "$DISK_STATUS" | grep -q "not ready"; then
    echo "⚠️  仍有磁盘未就绪，请检查:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 5 "not ready" | head -10
    PROBLEMS=1
fi

if [ $PROBLEMS -eq 0 ]; then
    echo "✓ 所有磁盘已就绪"
    echo ""
    echo "可以开始使用 Longhorn 存储了！"
    echo ""
    echo "测试 PVC 创建:"
    echo "  kubectl apply -f - <<EOF"
    echo "  apiVersion: v1"
    echo "  kind: PersistentVolumeClaim"
    echo "  metadata:"
    echo "    name: test-pvc"
    echo "  spec:"
    echo "    accessModes:"
    echo "      - ReadWriteOnce"
    echo "    storageClassName: longhorn"
    echo "    resources:"
    echo "      requests:"
    echo "        storage: 1Gi"
    echo "  EOF"
else
    echo ""
    echo "如果磁盘仍然未就绪，请检查:"
    echo "  1. 磁盘路径权限: ls -la $DISK_PATH"
    echo "  2. 磁盘空间: df -h $DISK_PATH"
    echo "  3. Longhorn Manager 日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo ""
    echo "在 Longhorn UI 中验证:"
    echo "  kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
    echo "  访问: http://192.168.1.141:8088"
    echo "  进入: Nodes → $NODE_NAME → Disks"
fi
echo ""


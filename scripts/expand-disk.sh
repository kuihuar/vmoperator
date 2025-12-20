#!/bin/bash

# 扩展 VM 磁盘大小

echo "=== 扩展 VM 磁盘 ==="

# 1. 获取参数
WUKONG_NAME="${1:-ubuntu-noble-local}"
DISK_NAME="${2:-system}"
NEW_SIZE="${3:-}"

if [ -z "$NEW_SIZE" ]; then
    echo "用法: $0 <wukong-name> <disk-name> <new-size>"
    echo ""
    echo "示例:"
    echo "  $0 ubuntu-noble-local system 50Gi"
    echo "  $0 ubuntu-noble-local data 200Gi"
    echo ""
    exit 1
fi

echo "Wukong: $WUKONG_NAME"
echo "磁盘: $DISK_NAME"
echo "新大小: $NEW_SIZE"
echo ""

# 2. 检查 Wukong 是否存在
if ! kubectl get wukong "$WUKONG_NAME" &>/dev/null; then
    echo "❌ Wukong 资源不存在: $WUKONG_NAME"
    exit 1
fi

# 3. 检查磁盘是否存在
PVC_NAME="${WUKONG_NAME}-${DISK_NAME}"
if ! kubectl get pvc "$PVC_NAME" &>/dev/null; then
    echo "❌ PVC 不存在: $PVC_NAME"
    echo "请检查磁盘名称是否正确"
    exit 1
fi

# 4. 检查当前大小
CURRENT_SIZE=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
echo "当前大小: $CURRENT_SIZE"
echo "新大小: $NEW_SIZE"
echo ""

# 5. 检查 StorageClass 是否支持扩展
STORAGE_CLASS=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
if [ -n "$STORAGE_CLASS" ]; then
    echo "StorageClass: $STORAGE_CLASS"
    ALLOW_EXPANSION=$(kubectl get storageclass "$STORAGE_CLASS" -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" != "true" ]; then
        echo "⚠️  警告: StorageClass '$STORAGE_CLASS' 不支持卷扩展"
        echo "请检查 StorageClass 配置，或使用支持扩展的 StorageClass"
        read -p "是否继续？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✓ StorageClass 支持卷扩展"
    fi
else
    echo "⚠️  警告: 未找到 StorageClass"
fi
echo ""

# 6. 检查 PVC 是否已绑定
PVC_PHASE=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$PVC_PHASE" != "Bound" ]; then
    echo "⚠️  警告: PVC 未绑定 (当前状态: $PVC_PHASE)"
    echo "只有已绑定的 PVC 才能扩展"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 7. 更新 Wukong 配置
echo "7. 更新 Wukong 配置..."
echo ""

# 获取当前配置
CURRENT_CONFIG=$(kubectl get wukong "$WUKONG_NAME" -o yaml)

# 检查磁盘是否存在
if ! echo "$CURRENT_CONFIG" | grep -q "name: $DISK_NAME"; then
    echo "❌ 磁盘 '$DISK_NAME' 在 Wukong 配置中不存在"
    exit 1
fi

# 使用 kubectl patch 更新磁盘大小
echo "更新磁盘大小..."
kubectl patch wukong "$WUKONG_NAME" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/disks\", \"value\": $(kubectl get wukong "$WUKONG_NAME" -o json | jq --arg disk "$DISK_NAME" --arg size "$NEW_SIZE" '.spec.disks | map(if .name == $disk then .size = $size else . end)')}]" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✓ Wukong 配置已更新"
else
    echo "⚠️  使用 kubectl patch 失败，尝试直接编辑..."
    echo ""
    echo "请手动编辑 Wukong 配置:"
    echo "  kubectl edit wukong $WUKONG_NAME"
    echo ""
    echo "找到磁盘 '$DISK_NAME'，将 size 字段改为: $NEW_SIZE"
    exit 1
fi

# 8. 等待 Controller 处理
echo ""
echo "8. 等待 Controller 处理扩展请求..."
echo "（Controller 会自动扩展 PVC）"
echo ""

# 9. 监控扩展进度
echo "9. 监控扩展进度..."
echo ""

MAX_WAIT=300  # 最多等待 5 分钟
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # 检查 PVC 状态
    PVC_STATUS=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.status.conditions[?(@.type=="Resizing")].status}' 2>/dev/null)
    FS_RESIZE_PENDING=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.status.conditions[?(@.type=="FileSystemResizePending")].status}' 2>/dev/null)
    CURRENT_SIZE_NOW=$(kubectl get pvc "$PVC_NAME" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
    
    if [ "$CURRENT_SIZE_NOW" = "$NEW_SIZE" ]; then
        if [ "$FS_RESIZE_PENDING" = "True" ]; then
            echo "✓ PVC 扩展完成，等待文件系统扩展..."
            echo ""
            echo "⚠️  注意: 需要在 VM 内部扩展文件系统"
            echo ""
            echo "连接到 VM:"
            echo "  virtctl console ${WUKONG_NAME}-vm"
            echo ""
            echo "然后在 VM 内部执行:"
            echo "  # 对于 ext4 文件系统:"
            echo "  sudo growpart /dev/vda 1"
            echo "  sudo resize2fs /dev/vda1"
            echo ""
            echo "  # 对于 xfs 文件系统:"
            echo "  sudo xfs_growfs /"
            break
        else
            echo "✓ PVC 扩展完成"
            break
        fi
    fi
    
    if [ "$PVC_STATUS" = "True" ]; then
        echo "  [$(date +%H:%M:%S)] PVC 扩展进行中..."
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时，请手动检查 PVC 状态:"
    echo "  kubectl get pvc $PVC_NAME"
    echo "  kubectl describe pvc $PVC_NAME"
fi

echo ""
echo "=== 完成 ==="
echo ""
echo "检查 PVC 状态:"
kubectl get pvc "$PVC_NAME"
echo ""
echo "检查 Wukong 状态:"
kubectl get wukong "$WUKONG_NAME"


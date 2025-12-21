#!/bin/bash

# 完整流程：清理旧配置并重新配置 Longhorn 到 sdb

set -e

DISK_DEVICE="/dev/sdb"
MOUNT_POINT="/mnt/longhorn"

echo "=== 重新配置 Longhorn 到 sdb ==="
echo "磁盘设备: $DISK_DEVICE"
echo "挂载点: $MOUNT_POINT"
echo ""

# 确认
read -p "确定要清理旧配置并重新配置 Longhorn 到 $DISK_DEVICE 吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 步骤 1: 清理旧配置
echo "========== 步骤 1: 清理旧配置 =========="
echo ""

# 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NODE_NAME" ]; then
    echo "❌ 无法获取节点名称"
    exit 1
fi

# 检查 Longhorn Node 资源
if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "清空 Longhorn Node 磁盘配置..."
    PATCH='{"spec":{"disks":null}}'
    kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH" || true
    echo "✓ 旧配置已清空"
else
    echo "⚠️  Longhorn Node 资源不存在，跳过清理"
fi
echo ""

# 步骤 2: 准备新磁盘
echo "========== 步骤 2: 准备新磁盘 =========="
echo ""

# 检查磁盘是否存在
if [ ! -b "$DISK_DEVICE" ]; then
    echo "❌ 磁盘设备不存在: $DISK_DEVICE"
    echo "可用磁盘:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    exit 1
fi

# 检查是否已挂载
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "⚠️  挂载点已被使用，卸载..."
    sudo umount "$MOUNT_POINT" || true
fi

# 检查是否有分区
PARTITIONS=$(lsblk -n -o NAME "$DISK_DEVICE" | tail -n +2)
if [ -n "$PARTITIONS" ]; then
    echo "⚠️  磁盘已有分区，将删除并重新创建"
    read -p "继续? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
    
    # 先卸载所有分区
    echo "卸载所有分区..."
    for part in $PARTITIONS; do
        PART_DEVICE="/dev/$part"
        if [ -b "$PART_DEVICE" ]; then
            # 检查是否挂载
            MOUNT_POINT=$(findmnt -n -o TARGET "$PART_DEVICE" 2>/dev/null || true)
            if [ -n "$MOUNT_POINT" ]; then
                echo "  卸载 $PART_DEVICE (挂载在 $MOUNT_POINT)..."
                sudo umount "$MOUNT_POINT" 2>/dev/null || sudo umount "$PART_DEVICE" 2>/dev/null || true
            fi
            
            # 检查是否是 swap
            if swapon --show 2>/dev/null | grep -q "$PART_DEVICE"; then
                echo "  关闭 swap: $PART_DEVICE..."
                sudo swapoff "$PART_DEVICE" 2>/dev/null || true
            fi
        fi
    done
    
    # 等待一下，确保卸载完成
    sleep 2
    
    # 尝试删除分区表
    echo "删除分区表..."
    # 先尝试使用 wipefs
    sudo wipefs -a "$DISK_DEVICE" 2>/dev/null || true
    
    # 如果 wipefs 失败，尝试使用 parted
    if [ $? -ne 0 ]; then
        echo "  wipefs 失败，尝试使用 parted..."
        # 删除所有分区
        for part in $PARTITIONS; do
            PART_NUM=$(echo $part | sed 's/.*\([0-9]\)/\1/')
            if [ -n "$PART_NUM" ]; then
                sudo parted -s "$DISK_DEVICE" rm "$PART_NUM" 2>/dev/null || true
            fi
        done
        # 重新创建分区表
        sudo parted -s "$DISK_DEVICE" mklabel gpt 2>/dev/null || true
    fi
    
    # 再次尝试 wipefs
    sudo wipefs -a "$DISK_DEVICE" 2>/dev/null || {
        echo "⚠️  无法完全清理分区表，但可以继续创建新分区"
    }
fi

# 创建分区
echo "创建分区..."
sudo parted -s "$DISK_DEVICE" mklabel gpt
sudo parted -s "$DISK_DEVICE" mkpart primary ext4 0% 100%

# 获取分区设备名
PARTITION="${DISK_DEVICE}1"
if [ ! -b "$PARTITION" ]; then
    PARTITION="${DISK_DEVICE}p1"
fi

if [ ! -b "$PARTITION" ]; then
    echo "❌ 无法确定分区设备名"
    exit 1
fi

echo "✓ 分区已创建: $PARTITION"

# 格式化
echo "格式化分区..."
sudo mkfs.ext4 -F "$PARTITION"
echo "✓ 格式化完成"

# 创建挂载点
if [ ! -d "$MOUNT_POINT" ]; then
    sudo mkdir -p "$MOUNT_POINT"
fi

# 挂载
echo "挂载磁盘..."
sudo mount "$PARTITION" "$MOUNT_POINT"
echo "✓ 磁盘已挂载"

# 设置权限
sudo chmod 755 "$MOUNT_POINT"
echo "✓ 权限已设置"

# 配置自动挂载
UUID=$(sudo blkid -s UUID -o value "$PARTITION")
if [ -n "$UUID" ]; then
    if ! grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
        echo "配置自动挂载..."
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab
        echo "✓ 自动挂载已配置"
    else
        echo "⚠️  /etc/fstab 中已存在该挂载点"
    fi
fi
echo ""

# 步骤 3: 配置 Longhorn
echo "========== 步骤 3: 配置 Longhorn =========="
echo ""

# 等待一下，确保挂载生效
sleep 2

# 检查路径
if [ ! -d "$MOUNT_POINT" ] || [ ! -w "$MOUNT_POINT" ]; then
    echo "❌ 挂载点不可写: $MOUNT_POINT"
    exit 1
fi

# 获取节点名称（再次确认）
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# 等待 Longhorn Node 资源（如果需要）
if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo "等待 Longhorn Node 资源创建..."
    for i in {1..30}; do
        if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
            break
        fi
        echo "  等待中... ($i/30)"
        sleep 2
    done
    
    if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
        echo "❌ Longhorn Node 资源未创建"
        echo "请检查 Longhorn Manager 是否正常运行"
        exit 1
    fi
fi

# 配置磁盘
echo "配置 Longhorn 使用新磁盘..."
DISK_NAME="data-disk"
PATCH=$(cat <<EOF
{
  "spec": {
    "disks": {
      "$DISK_NAME": {
        "allowScheduling": true,
        "evictionRequested": false,
        "path": "$MOUNT_POINT",
        "storageReserved": 0,
        "tags": []
      }
    }
  }
}
EOF
)

kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "$PATCH"

if [ $? -eq 0 ]; then
    echo "✓ Longhorn 配置已应用"
else
    echo "❌ 配置失败"
    exit 1
fi
echo ""

# 步骤 4: 验证
echo "========== 步骤 4: 验证配置 =========="
echo ""

sleep 3

# 验证挂载
echo "1. 验证磁盘挂载..."
if mountpoint -q "$MOUNT_POINT"; then
    echo "✓ 磁盘已挂载"
    df -h "$MOUNT_POINT" | tail -1
else
    echo "❌ 磁盘未挂载"
fi
echo ""

# 验证 Longhorn 配置
echo "2. 验证 Longhorn 配置..."
UPDATED_DISKS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' 2>/dev/null)
if echo "$UPDATED_DISKS" | grep -q "$MOUNT_POINT"; then
    echo "✓ Longhorn 配置成功"
    echo ""
    echo "当前磁盘配置:"
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath='{.spec.disks}' | python3 -m json.tool 2>/dev/null || \
    kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o yaml | grep -A 15 "disks:" | head -20
else
    echo "⚠️  Longhorn 配置可能未生效"
fi
echo ""

# 步骤 5: 测试
echo "========== 步骤 5: 测试 PVC 创建 =========="
echo ""

read -p "是否创建测试 PVC 验证配置? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "创建测试 PVC..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-$(date +%s)
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF
    
    echo "等待 PVC 绑定..."
    sleep 5
    
    TEST_PVC=$(kubectl get pvc | grep test-pvc | awk '{print $1}' | head -1)
    if [ -n "$TEST_PVC" ]; then
        kubectl get pvc "$TEST_PVC"
        echo ""
        read -p "测试完成后是否删除测试 PVC? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete pvc "$TEST_PVC" --ignore-not-found=true
            echo "✓ 测试 PVC 已删除"
        fi
    fi
fi
echo ""

echo "=== 配置完成 ==="
echo ""
echo "总结:"
echo "  - 磁盘设备: $DISK_DEVICE"
echo "  - 挂载点: $MOUNT_POINT"
echo "  - 分区: $PARTITION"
echo "  - UUID: $UUID"
echo ""
echo "下一步:"
echo "  1. 在 Longhorn UI 中验证:"
echo "     kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
echo "     然后访问: http://192.168.1.141:8088"
echo "     进入: Nodes → $NODE_NAME → Disks"
echo ""
echo "  2. 检查磁盘状态:"
echo "     kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 'disks:'"
echo ""
echo "  3. 创建 Wukong VM 测试:"
echo "     kubectl apply -f config/samples/vm_v1alpha1_wukong_longhorn_test.yaml"
echo ""


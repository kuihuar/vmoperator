#!/bin/bash

# 准备新数据盘用于 Longhorn

set -e

DISK_DEVICE="${1}"
MOUNT_POINT="${2:-/mnt/longhorn}"

if [ -z "$DISK_DEVICE" ]; then
    echo "用法: $0 <disk-device> [mount-point]"
    echo "示例: $0 /dev/sdb /mnt/longhorn"
    echo ""
    echo "可用磁盘:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    exit 1
fi

echo "=== 准备新数据盘 ==="
echo "磁盘设备: $DISK_DEVICE"
echo "挂载点: $MOUNT_POINT"
echo ""

# 确认
read -p "确定要格式化 $DISK_DEVICE 并挂载到 $MOUNT_POINT 吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 1. 检查磁盘是否存在
if [ ! -b "$DISK_DEVICE" ]; then
    echo "❌ 磁盘设备不存在: $DISK_DEVICE"
    exit 1
fi
echo "✓ 磁盘设备存在"
echo ""

# 2. 检查是否已挂载
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "⚠️  挂载点已被使用: $MOUNT_POINT"
    read -p "是否卸载? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo umount "$MOUNT_POINT"
        echo "✓ 已卸载"
    else
        echo "退出"
        exit 1
    fi
fi
echo ""

# 3. 检查是否有分区
echo "3. 检查磁盘分区..."
PARTITIONS=$(lsblk -n -o NAME "$DISK_DEVICE" | tail -n +2)
if [ -n "$PARTITIONS" ]; then
    echo "⚠️  磁盘已有分区:"
    lsblk "$DISK_DEVICE"
    echo ""
    read -p "是否删除所有分区并重新创建? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 删除所有分区
        echo "删除分区..."
        sudo wipefs -a "$DISK_DEVICE"
        echo "✓ 分区已删除"
    else
        echo "退出"
        exit 1
    fi
fi
echo ""

# 4. 创建分区
echo "4. 创建分区..."
echo "使用 fdisk 创建分区..."
echo "注意: 将创建单个主分区，占用整个磁盘"
echo ""

# 使用 parted 自动创建分区（非交互式）
sudo parted -s "$DISK_DEVICE" mklabel gpt
sudo parted -s "$DISK_DEVICE" mkpart primary ext4 0% 100%

# 获取分区设备名
PARTITION="${DISK_DEVICE}1"
if [ ! -b "$PARTITION" ]; then
    # 可能是 nvme 设备
    PARTITION="${DISK_DEVICE}p1"
fi

if [ ! -b "$PARTITION" ]; then
    echo "❌ 无法确定分区设备名"
    echo "请手动创建分区:"
    echo "  sudo fdisk $DISK_DEVICE"
    exit 1
fi

echo "✓ 分区已创建: $PARTITION"
echo ""

# 5. 格式化分区
echo "5. 格式化分区..."
echo "使用 ext4 文件系统格式化 $PARTITION..."
sudo mkfs.ext4 -F "$PARTITION"
echo "✓ 格式化完成"
echo ""

# 6. 创建挂载点
echo "6. 创建挂载点..."
if [ ! -d "$MOUNT_POINT" ]; then
    sudo mkdir -p "$MOUNT_POINT"
    echo "✓ 挂载点已创建"
else
    echo "✓ 挂载点已存在"
fi
echo ""

# 7. 挂载磁盘
echo "7. 挂载磁盘..."
sudo mount "$PARTITION" "$MOUNT_POINT"
if mountpoint -q "$MOUNT_POINT"; then
    echo "✓ 磁盘已挂载"
else
    echo "❌ 挂载失败"
    exit 1
fi
echo ""

# 8. 设置权限
echo "8. 设置权限..."
sudo chmod 755 "$MOUNT_POINT"
echo "✓ 权限已设置"
echo ""

# 9. 配置自动挂载
echo "9. 配置自动挂载..."
UUID=$(sudo blkid -s UUID -o value "$PARTITION")
if [ -n "$UUID" ]; then
    # 检查是否已存在
    if ! grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
        echo "添加 /etc/fstab 条目..."
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab
        echo "✓ 自动挂载已配置"
    else
        echo "⚠️  /etc/fstab 中已存在该挂载点"
    fi
else
    echo "⚠️  无法获取 UUID，请手动配置 /etc/fstab"
    echo "   添加: $PARTITION $MOUNT_POINT ext4 defaults 0 2"
fi
echo ""

# 10. 验证
echo "10. 验证配置..."
echo "挂载信息:"
df -h "$MOUNT_POINT" | tail -1
echo ""

echo "磁盘信息:"
lsblk "$DISK_DEVICE"
echo ""

# 11. 提示配置 Longhorn
echo "=== 完成 ==="
echo ""
echo "下一步: 配置 Longhorn 使用此磁盘"
echo ""
echo "方法 1: 使用脚本（推荐）"
echo "  ./scripts/configure-longhorn-disk.sh $MOUNT_POINT"
echo ""
echo "方法 2: 通过 Longhorn UI"
echo "  1. kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
echo "  2. 访问: http://192.168.1.141:8088"
echo "  3. 进入: Nodes → <node-name> → Disks → Add Disk"
echo "  4. 配置:"
echo "     - Path: $MOUNT_POINT"
echo "     - Allow Scheduling: true"
echo ""


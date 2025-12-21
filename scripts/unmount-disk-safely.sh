#!/bin/bash

# 安全卸载磁盘

set -e

DISK_DEVICE="${1:-/dev/sdb}"

if [ ! -b "$DISK_DEVICE" ]; then
    echo "❌ 磁盘设备不存在: $DISK_DEVICE"
    exit 1
fi

echo "=== 安全卸载磁盘 ==="
echo "磁盘设备: $DISK_DEVICE"
echo ""

# 1. 检查并卸载所有挂载的分区
echo "1. 卸载挂载的分区..."
PARTITIONS=$(lsblk -n -o NAME "$DISK_DEVICE" | tail -n +2)
UNMOUNTED_COUNT=0

for part in $PARTITIONS; do
    PART_DEVICE="/dev/$part"
    if [ -b "$PART_DEVICE" ]; then
        MOUNT_POINT=$(findmnt -n -o TARGET "$PART_DEVICE" 2>/dev/null || true)
        if [ -n "$MOUNT_POINT" ]; then
            echo "  卸载 $PART_DEVICE (挂载在 $MOUNT_POINT)..."
            sudo umount "$MOUNT_POINT" 2>/dev/null || sudo umount "$PART_DEVICE" 2>/dev/null || true
            if [ $? -eq 0 ]; then
                echo "  ✓ 已卸载 $PART_DEVICE"
                UNMOUNTED_COUNT=$((UNMOUNTED_COUNT + 1))
            else
                echo "  ⚠️  卸载失败，可能需要强制卸载"
            fi
        fi
    fi
done

if [ $UNMOUNTED_COUNT -eq 0 ]; then
    echo "  ✓ 没有需要卸载的分区"
fi
echo ""

# 2. 关闭 swap
echo "2. 关闭 swap..."
SWAP_DEVICES=$(swapon --show 2>/dev/null | grep "$DISK_DEVICE" | awk '{print $1}' || true)
if [ -n "$SWAP_DEVICES" ]; then
    for swap_dev in $SWAP_DEVICES; do
        echo "  关闭 swap: $swap_dev..."
        sudo swapoff "$swap_dev" 2>/dev/null || true
        if [ $? -eq 0 ]; then
            echo "  ✓ 已关闭 $swap_dev"
        else
            echo "  ⚠️  关闭失败"
        fi
    done
else
    echo "  ✓ 没有 swap 分区"
fi
echo ""

# 3. 检查 LVM
echo "3. 检查 LVM..."
if command -v pvs &>/dev/null; then
    LVM_PVS=$(pvs 2>/dev/null | grep "$DISK_DEVICE" || true)
    if [ -n "$LVM_PVS" ]; then
        echo "  ⚠️  发现 LVM 物理卷:"
        echo "$LVM_PVS"
        echo ""
        echo "  需要手动处理 LVM:"
        echo "    1. 移除卷组: sudo vgremove <vg-name>"
        echo "    2. 移除物理卷: sudo pvremove $DISK_DEVICE"
        echo ""
        read -p "是否尝试自动移除 LVM? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 获取卷组名
            VG_NAME=$(echo "$LVM_PVS" | awk '{print $2}' | head -1)
            if [ -n "$VG_NAME" ] && [ "$VG_NAME" != "VG" ]; then
                echo "  移除卷组: $VG_NAME..."
                sudo vgremove -f "$VG_NAME" 2>/dev/null || true
            fi
            echo "  移除物理卷..."
            sudo pvremove -f "$DISK_DEVICE" 2>/dev/null || true
        fi
    else
        echo "  ✓ 没有 LVM"
    fi
else
    echo "  pvs 命令不可用，跳过 LVM 检查"
fi
echo ""

# 4. 检查进程
echo "4. 检查使用该设备的进程..."
if command -v lsof &>/dev/null; then
    LSOF_PROCESSES=$(sudo lsof "$DISK_DEVICE" 2>/dev/null | tail -n +2 || true)
    if [ -n "$LSOF_PROCESSES" ]; then
        echo "  ⚠️  发现使用该设备的进程:"
        echo "$LSOF_PROCESSES"
        echo ""
        echo "  这些进程可能需要手动停止"
    else
        echo "  ✓ 没有进程使用该设备"
    fi
fi
echo ""

# 5. 尝试卸载所有相关设备（包括设备本身）
echo "5. 尝试卸载设备..."
# 使用 umount 尝试卸载设备本身（如果被挂载）
sudo umount "$DISK_DEVICE" 2>/dev/null || true

# 再次检查所有分区
for part in $PARTITIONS; do
    PART_DEVICE="/dev/$part"
    if [ -b "$PART_DEVICE" ]; then
        # 尝试强制卸载
        MOUNT_POINT=$(findmnt -n -o TARGET "$PART_DEVICE" 2>/dev/null || true)
        if [ -n "$MOUNT_POINT" ]; then
            echo "  强制卸载 $PART_DEVICE..."
            sudo umount -l "$MOUNT_POINT" 2>/dev/null || true
        fi
    fi
done
echo ""

# 6. 验证
echo "6. 验证卸载结果..."
sleep 1

REMAINING_MOUNTS=$(mount | grep "$DISK_DEVICE" || true)
if [ -z "$REMAINING_MOUNTS" ]; then
    echo "  ✓ 所有挂载已卸载"
else
    echo "  ⚠️  仍有挂载:"
    echo "$REMAINING_MOUNTS"
fi

REMAINING_SWAP=$(swapon --show 2>/dev/null | grep "$DISK_DEVICE" || true)
if [ -z "$REMAINING_SWAP" ]; then
    echo "  ✓ 所有 swap 已关闭"
else
    echo "  ⚠️  仍有 swap:"
    echo "$REMAINING_SWAP"
fi
echo ""

# 7. 检查是否可以安全使用
echo "7. 检查是否可以安全使用..."
if mount | grep -q "$DISK_DEVICE"; then
    echo "  ❌ 仍有挂载，可能需要手动处理"
    echo ""
    echo "  手动卸载命令:"
    mount | grep "$DISK_DEVICE" | while read line; do
        MOUNT_POINT=$(echo $line | awk '{print $3}')
        echo "    sudo umount -l $MOUNT_POINT  # 懒卸载"
        echo "    sudo umount -f $MOUNT_POINT  # 强制卸载"
    done
    exit 1
else
    echo "  ✓ 磁盘可以安全使用"
    echo ""
    echo "可以继续执行:"
    echo "  ./scripts/reconfigure-longhorn-to-sdb.sh"
fi


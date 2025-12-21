#!/bin/bash

# 检查磁盘使用情况

DISK_DEVICE="${1:-/dev/sdb}"

if [ ! -b "$DISK_DEVICE" ]; then
    echo "❌ 磁盘设备不存在: $DISK_DEVICE"
    exit 1
fi

echo "=== 检查磁盘使用情况 ==="
echo "磁盘设备: $DISK_DEVICE"
echo ""

# 1. 检查分区挂载情况
echo "1. 检查分区挂载情况..."
MOUNTED=$(mount | grep "$DISK_DEVICE" || true)
if [ -n "$MOUNTED" ]; then
    echo "⚠️  发现挂载的分区:"
    echo "$MOUNTED"
    echo ""
    echo "挂载点:"
    mount | grep "$DISK_DEVICE" | awk '{print $3}'
else
    echo "✓ 没有挂载的分区"
fi
echo ""

# 2. 检查 LVM
echo "2. 检查 LVM..."
if command -v pvs &>/dev/null; then
    LVM_PVS=$(pvs 2>/dev/null | grep "$DISK_DEVICE" || true)
    if [ -n "$LVM_PVS" ]; then
        echo "⚠️  发现 LVM 物理卷:"
        echo "$LVM_PVS"
    else
        echo "✓ 没有 LVM 物理卷"
    fi
else
    echo "  pvs 命令不可用，跳过 LVM 检查"
fi
echo ""

# 3. 检查 swap
echo "3. 检查 swap..."
SWAP_USAGE=$(swapon --show 2>/dev/null | grep "$DISK_DEVICE" || true)
if [ -n "$SWAP_USAGE" ]; then
    echo "⚠️  发现 swap 分区:"
    echo "$SWAP_USAGE"
else
    echo "✓ 没有 swap 分区"
fi
echo ""

# 4. 检查进程使用
echo "4. 检查进程使用..."
# 检查 lsof
if command -v lsof &>/dev/null; then
    LSOF_PROCESSES=$(sudo lsof "$DISK_DEVICE" 2>/dev/null || true)
    if [ -n "$LSOF_PROCESSES" ]; then
        echo "⚠️  发现使用该设备的进程:"
        echo "$LSOF_PROCESSES"
    else
        echo "✓ 没有进程使用该设备"
    fi
else
    echo "  lsof 命令不可用，跳过进程检查"
fi
echo ""

# 5. 检查 fuser
if command -v fuser &>/dev/null; then
    FUSER_PROCESSES=$(sudo fuser -v "$DISK_DEVICE" 2>/dev/null || true)
    if [ -n "$FUSER_PROCESSES" ]; then
        echo "⚠️  发现使用该设备的进程 (fuser):"
        echo "$FUSER_PROCESSES"
    fi
fi
echo ""

# 6. 检查分区表
echo "5. 检查分区表..."
PARTITIONS=$(lsblk -n -o NAME "$DISK_DEVICE" | tail -n +2)
if [ -n "$PARTITIONS" ]; then
    echo "分区列表:"
    lsblk "$DISK_DEVICE"
    echo ""
    
    # 检查每个分区
    for part in $PARTITIONS; do
        PART_DEVICE="/dev/$part"
        if [ -b "$PART_DEVICE" ]; then
            MOUNT_POINT=$(findmnt -n -o TARGET "$PART_DEVICE" 2>/dev/null || true)
            if [ -n "$MOUNT_POINT" ]; then
                echo "  $PART_DEVICE 挂载在: $MOUNT_POINT"
            fi
        fi
    done
else
    echo "✓ 没有分区"
fi
echo ""

# 7. 总结和建议
echo "=== 总结和建议 ==="
echo ""

HAS_ISSUES=false

if mount | grep -q "$DISK_DEVICE"; then
    HAS_ISSUES=true
    echo "❌ 发现挂载的分区，需要先卸载:"
    mount | grep "$DISK_DEVICE" | while read line; do
        MOUNT_POINT=$(echo $line | awk '{print $3}')
        echo "  sudo umount $MOUNT_POINT"
    done
fi

if command -v pvs &>/dev/null && pvs 2>/dev/null | grep -q "$DISK_DEVICE"; then
    HAS_ISSUES=true
    echo "❌ 发现 LVM，需要先移除:"
    echo "  sudo vgremove <vg-name>  # 先移除卷组"
    echo "  sudo pvremove $DISK_DEVICE  # 再移除物理卷"
fi

if swapon --show 2>/dev/null | grep -q "$DISK_DEVICE"; then
    HAS_ISSUES=true
    echo "❌ 发现 swap，需要先关闭:"
    swapon --show | grep "$DISK_DEVICE" | awk '{print $1}' | while read swap_dev; do
        echo "  sudo swapoff $swap_dev"
    done
fi

if [ "$HAS_ISSUES" = false ]; then
    echo "✓ 磁盘可以安全使用"
    echo ""
    echo "可以继续执行:"
    echo "  ./scripts/reconfigure-longhorn-to-sdb.sh"
else
    echo ""
    echo "请先解决上述问题，然后再继续"
fi


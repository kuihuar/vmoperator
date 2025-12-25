#!/bin/bash

# 检查 Longhorn 数据盘配置

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "检查 Longhorn 数据盘配置"
echo_info "=========================================="
echo ""

# 1. 检查 Longhorn 数据路径设置
echo_info "1. 检查 Longhorn 数据路径设置："
DATA_PATH=$(kubectl get settings.longhorn.io default-data-path -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "")
if [ -n "${DATA_PATH}" ]; then
    echo_info "  默认数据路径: ${DATA_PATH}"
    if echo "${DATA_PATH}" | grep -qE "^/data|^/mnt|^/var/lib/longhorn"; then
        echo_info "  ✓ 配置为使用数据盘路径"
    else
        echo_warn "  ⚠️  可能不是数据盘路径"
    fi
else
    echo_warn "  未找到 default-data-path 设置"
fi
echo ""

# 2. 检查 Longhorn Manager DaemonSet 的数据路径配置
echo_info "2. 检查 Longhorn Manager 数据路径配置："
LONGHORN_MANAGER=$(kubectl get daemonset longhorn-manager -n longhorn-system -o yaml 2>/dev/null || echo "")
if [ -n "${LONGHORN_MANAGER}" ]; then
    echo_info "  Longhorn Manager 的 volumeMounts："
    echo "${LONGHORN_MANAGER}" | grep -A 10 "volumeMounts:" | grep -E "name:|mountPath:" | head -10 | sed 's/^/    /'
    
    echo ""
    echo_info "  Longhorn Manager 的 volumes："
    echo "${LONGHORN_MANAGER}" | grep -A 10 "volumes:" | grep -E "name:|hostPath:" | head -10 | sed 's/^/    /'
else
    echo_warn "  未找到 Longhorn Manager DaemonSet"
fi
echo ""

# 3. 检查节点上的实际数据路径
echo_info "3. 检查节点上的实际数据路径："
if [ -d /data/longhorn ]; then
    echo_info "  ✓ /data/longhorn 目录存在"
    echo_info "  目录信息："
    sudo ls -lah /data/longhorn 2>/dev/null | head -10 | sed 's/^/    /' || echo "    无法访问"
    
    echo ""
    echo_info "  磁盘使用情况："
    df -h /data/longhorn 2>/dev/null | sed 's/^/    /' || echo "    无法获取"
else
    echo_warn "  /data/longhorn 目录不存在"
fi

if [ -d /var/lib/longhorn ]; then
    echo_info "  /var/lib/longhorn 目录存在（默认路径）"
    echo_info "  磁盘使用情况："
    df -h /var/lib/longhorn 2>/dev/null | sed 's/^/    /' || echo "    无法获取"
else
    echo_info "  /var/lib/longhorn 目录不存在"
fi
echo ""

# 4. 检查数据盘挂载情况
echo_info "4. 检查数据盘挂载情况："
echo_info "  所有挂载点："
mount | grep -E "/data|/mnt|/dev/sd" | sed 's/^/    /' || echo "    未发现相关挂载"
echo ""

# 5. 检查 Longhorn 节点配置
echo_info "5. 检查 Longhorn 节点配置："
kubectl get nodes.longhorn.io -n longhorn-system -o yaml 2>/dev/null | grep -A 10 "disks:" | head -20 | sed 's/^/    /' || echo "  无法获取节点配置"
echo ""

# 6. 检查 Longhorn 设置中的存储相关配置
echo_info "6. 检查 Longhorn 存储相关设置："
echo_info "  default-data-path:"
kubectl get settings.longhorn.io default-data-path -n longhorn-system -o jsonpath='{.value}' 2>/dev/null && echo "" || echo "  未找到"
echo ""

# 7. 总结
echo_info "=========================================="
echo_info "配置总结"
echo_info "=========================================="
echo ""

if [ -d /data/longhorn ]; then
    echo_info "  ✓ 数据盘路径 /data/longhorn 存在"
    DATA_DISK_MOUNTED=$(mount | grep -q "/data" && echo "yes" || echo "no")
    if [ "${DATA_DISK_MOUNTED}" = "yes" ]; then
        echo_info "  ✓ /data 已挂载到数据盘"
    else
        echo_warn "  ⚠️  /data 可能未挂载到数据盘"
    fi
else
    echo_warn "  ⚠️  数据盘路径 /data/longhorn 不存在"
    echo_info "  可能使用默认路径 /var/lib/longhorn"
fi

echo ""


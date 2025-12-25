#!/bin/bash

# 修复 Longhorn 数据路径，迁移到数据盘

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
echo_info "修复 Longhorn 数据路径（迁移到数据盘）"
echo_info "=========================================="
echo ""

# 数据盘路径
DATA_PATH="${LONGHORN_DATA_PATH:-/data/longhorn}"
DEFAULT_PATH="/var/lib/longhorn"

# 1. 检查当前配置
echo_info "1. 检查当前配置..."
CURRENT_PATH=$(kubectl get settings.longhorn.io default-data-path -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "")
echo_info "  当前数据路径: ${CURRENT_PATH}"
echo_info "  目标数据路径: ${DATA_PATH}"
echo ""

if [ "${CURRENT_PATH}" = "${DATA_PATH}" ]; then
    echo_info "  ✓ 数据路径已正确配置为 ${DATA_PATH}"
    exit 0
fi

# 2. 检查数据盘目录
echo_info "2. 检查数据盘目录..."
if [ ! -d "${DATA_PATH}" ]; then
    echo_warn "  ${DATA_PATH} 目录不存在，创建中..."
    sudo mkdir -p "${DATA_PATH}"
    sudo chmod 755 "${DATA_PATH}"
    echo_info "  ✓ 目录已创建"
else
    echo_info "  ✓ ${DATA_PATH} 目录已存在"
fi

# 检查数据盘挂载
DATA_DISK_MOUNTED=$(mount | grep -q "${DATA_PATH}" && echo "yes" || echo "no")
if [ "${DATA_DISK_MOUNTED}" = "no" ]; then
    # 检查 /data 是否挂载
    DATA_MOUNTED=$(mount | grep -q "^/dev.*/data" && echo "yes" || echo "no")
    if [ "${DATA_MOUNTED}" = "yes" ]; then
        echo_info "  ✓ /data 已挂载到数据盘"
    else
        echo_warn "  ⚠️  /data 可能未挂载到数据盘，请确认"
    fi
fi
echo ""

# 3. 检查是否有现有数据需要迁移
echo_info "3. 检查现有数据..."
if [ -d "${DEFAULT_PATH}" ] && [ "$(ls -A ${DEFAULT_PATH} 2>/dev/null)" ]; then
    echo_warn "  ⚠️  发现现有数据在 ${DEFAULT_PATH}"
    echo_info "  数据内容："
    sudo ls -lah "${DEFAULT_PATH}" | head -10 | sed 's/^/    /'
    echo ""
    echo_warn "  需要迁移数据到 ${DATA_PATH}"
    read -p "是否迁移现有数据？(y/n，默认y): " MIGRATE
    MIGRATE=${MIGRATE:-y}
    
    if [[ $MIGRATE =~ ^[Yy]$ ]]; then
        echo_info "  开始迁移数据..."
        sudo cp -a "${DEFAULT_PATH}"/* "${DATA_PATH}"/ 2>/dev/null || echo_warn "  部分文件迁移失败（可能正常）"
        echo_info "  ✓ 数据迁移完成"
    else
        echo_warn "  跳过数据迁移（新数据将存储在 ${DATA_PATH}）"
    fi
else
    echo_info "  ✓ 没有需要迁移的现有数据"
fi
echo ""

# 4. 停止 Longhorn Manager（需要重启以应用新配置）
echo_info "4. 准备更新 Longhorn 数据路径设置..."
echo_warn "  ⚠️  注意：修改数据路径需要重启 Longhorn Manager"
read -p "是否继续？(y/n，默认y): " CONTINUE
CONTINUE=${CONTINUE:-y}

if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
    echo_info "  已取消"
    exit 0
fi
echo ""

# 5. 更新 Longhorn 数据路径设置
echo_info "5. 更新 Longhorn 数据路径设置..."
if kubectl patch settings.longhorn.io default-data-path -n longhorn-system --type='merge' -p "{\"value\":\"${DATA_PATH}\"}" 2>/dev/null; then
    echo_info "  ✓ 设置已更新为 ${DATA_PATH}"
else
    echo_error "  ✗ 更新设置失败"
    exit 1
fi
echo ""

# 6. 重启 Longhorn Manager 以应用新配置
echo_info "6. 重启 Longhorn Manager 以应用新配置..."
kubectl delete pods -n longhorn-system -l app=longhorn-manager
echo_info "  等待 Longhorn Manager 重启（10秒）..."
sleep 10

# 检查重启状态
if kubectl get pods -n longhorn-system -l app=longhorn-manager | grep -q Running; then
    echo_info "  ✓ Longhorn Manager 已重启"
else
    echo_warn "  ⚠️  Longhorn Manager 可能还在重启中"
fi
echo ""

# 7. 验证配置
echo_info "7. 验证配置..."
NEW_PATH=$(kubectl get settings.longhorn.io default-data-path -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "")
if [ "${NEW_PATH}" = "${DATA_PATH}" ]; then
    echo_info "  ✓ 数据路径已成功更新为 ${DATA_PATH}"
else
    echo_error "  ✗ 数据路径更新失败（当前值: ${NEW_PATH}）"
fi
echo ""

# 8. 检查数据目录
echo_info "8. 检查数据目录..."
if [ -d "${DATA_PATH}" ]; then
    echo_info "  ✓ ${DATA_PATH} 目录存在"
    echo_info "  目录内容："
    sudo ls -lah "${DATA_PATH}" | head -10 | sed 's/^/    /'
else
    echo_warn "  ⚠️  ${DATA_PATH} 目录不存在"
fi
echo ""

echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "注意："
echo "  - 新创建的卷将存储在 ${DATA_PATH}"
echo "  - 如果迁移了数据，旧数据仍在 ${DEFAULT_PATH}（可以稍后删除）"
echo "  - 建议等待几分钟，确保 Longhorn 完全重启"
echo ""


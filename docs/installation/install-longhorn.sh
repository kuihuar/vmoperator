#!/bin/bash

# 安装 Longhorn（适用于单节点或多节点 k3s/k8s 集群）
# 使用本地修改后的 longhorn_v1.8.1.yaml（已恢复 healthz 探针）
#
# 使用方法：
#   1. 使用环境变量指定数据盘路径：
#      LONGHORN_DATA_PATH=/data/longhorn ./docs/installation/install-longhorn.sh
#   2. 使用命令行参数指定数据盘路径：
#      ./docs/installation/install-longhorn.sh /data/longhorn
#   3. 使用默认路径 /data/longhorn：
#      ./docs/installation/install-longhorn.sh
#
# ⚠️  重要提示：
# - 已恢复 Kubernetes readinessProbe（healthz 健康检查）
# - 如果遇到 "conversion webhook service is not accessible" 错误导致 CrashLoop，
#   这是 Longhorn v1.8.1 在当前 k3s 环境下的兼容性问题
# - 建议：如果持续 CrashLoop，考虑使用 k3s 自带的 local-path 存储
# - 数据盘路径：脚本会替换 hostPath 中的路径，但保持容器内的 mountPath 为 /var/lib/longhorn/

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
echo_info "安装 Longhorn（适配 k3s，使用数据盘存储）"
echo_info "=========================================="
echo ""

# ------------------------------------------
# 0. 前置检查：k3s / k8s 是否可用
# ------------------------------------------
if ! kubectl get nodes &>/dev/null; then
    echo_error "无法连接到 Kubernetes 集群（kubectl get nodes 失败）"
    echo_info "请先安装并配置好 k3s，再执行本脚本。"
    exit 1
fi

# ------------------------------------------
# 1. 检查是否已安装 Longhorn
# ------------------------------------------
if kubectl get ns longhorn-system &>/dev/null; then
    echo_warn "检测到已有 longhorn-system 命名空间，可能已安装 Longhorn。"
    kubectl get pods -n longhorn-system || true
    echo ""
    echo_info "重新安装选项："
    echo "  1. 清理所有配置并重新安装（保留镜像）"
    echo "  2. 直接重新安装（不清理）"
    echo "  3. 跳过安装"
    read -p "请选择 (1/2/3，默认3): " REINSTALL_OPTION
    REINSTALL_OPTION=${REINSTALL_OPTION:-3}
    
    case "${REINSTALL_OPTION}" in
        1)
            echo_info "  选择：清理所有配置并重新安装（保留镜像）"
            echo ""
            echo_warn "  将执行以下操作："
            echo "    - 删除 longhorn-system 命名空间（包括所有资源）"
            echo "    - 删除 Longhorn CRDs"
            echo "    - 删除 Longhorn StorageClass"
            echo "    - 保留容器镜像（不删除）"
            echo ""
            echo_info "  清理模式："
            echo "    1. 快速模式（推荐，跳过等待，直接强制清理）"
            echo "    2. 标准模式（等待资源正常删除，较慢）"
            read -p "  选择清理模式 (1/2，默认1): " CLEAN_MODE
            CLEAN_MODE=${CLEAN_MODE:-1}
            
            read -p "  确认继续？(y/n，默认n): " CONFIRM_CLEAN
            CONFIRM_CLEAN=${CONFIRM_CLEAN:-n}
            if [[ ! $CONFIRM_CLEAN =~ ^[Yy]$ ]]; then
                echo_info "  已取消"
                exit 0
            fi
            
            # 清理 Longhorn
            echo_info "  开始清理 Longhorn（模式: $([ "${CLEAN_MODE}" = "1" ] && echo "快速" || echo "标准")）..."
            
            # 1. 先清理 finalizers（快速模式优先清理，避免等待）
            if [ "${CLEAN_MODE}" = "1" ]; then
                echo_info "    快速模式：先清理 finalizers..."
                
                # 清理 Volume finalizers
                echo_info "      清理 Volume finalizers..."
                kubectl get volumes.longhorn.io -A -o json 2>/dev/null | \
                    jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null | \
                    while read ns name; do
                        kubectl patch volumes.longhorn.io "${name}" -n "${ns}" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
                    done || true
                
                # 清理 Engine Image finalizers
                echo_info "      清理 Engine Image finalizers..."
                kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
                    jq -r '.items[] | .metadata.name' 2>/dev/null | \
                    while read name; do
                        kubectl patch engineimages.longhorn.io "${name}" -n longhorn-system \
                            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
                    done || true
            fi
            
            # 2. 删除所有 PVC（可选，避免数据丢失）
            echo_info "    检查 PVC..."
            PVC_COUNT=$(kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l)
            if [ "${PVC_COUNT}" -gt 0 ]; then
                echo_warn "    发现 ${PVC_COUNT} 个 PVC，删除 PVC 会导致数据丢失"
                read -p "    是否删除所有 PVC？(y/n，默认n): " DELETE_PVC
                DELETE_PVC=${DELETE_PVC:-n}
                if [[ $DELETE_PVC =~ ^[Yy]$ ]]; then
                    echo_info "    删除所有 PVC..."
                    kubectl delete pvc --all -A --timeout=10s 2>/dev/null || true
                fi
            fi
            
            # 3. 删除 StorageClass
            echo_info "    删除 StorageClass..."
            kubectl delete storageclass longhorn longhorn-static --timeout=10s 2>/dev/null || true
            
            # 4. 删除命名空间
            echo_info "    删除 longhorn-system 命名空间..."
            kubectl delete namespace longhorn-system --timeout=10s 2>/dev/null || true
            
            # 5. 等待或强制清理命名空间
            if [ "${CLEAN_MODE}" = "1" ]; then
                # 快速模式：只等待 5 秒，然后强制清理
                echo_info "    快速模式：等待 5 秒后强制清理..."
                sleep 5
                if kubectl get namespace longhorn-system &>/dev/null; then
                    echo_warn "    命名空间仍在，强制清理 finalizers..."
                    kubectl get namespace longhorn-system -o json 2>/dev/null | \
                        jq '.spec.finalizers = []' 2>/dev/null | \
                        kubectl replace --raw /api/v1/namespaces/longhorn-system/finalize -f - 2>/dev/null || true
                    sleep 2
                fi
            else
                # 标准模式：等待最多 30 秒
                echo_info "    等待命名空间删除完成（最多 30 秒）..."
                for i in {1..30}; do
                    if ! kubectl get ns longhorn-system &>/dev/null; then
                        echo_info "    ✓ 命名空间已删除"
                        break
                    fi
                    if [ $i -eq 30 ]; then
                        echo_warn "    ⚠️  命名空间删除超时，强制清理..."
                        kubectl get namespace longhorn-system -o json 2>/dev/null | \
                            jq '.spec.finalizers = []' 2>/dev/null | \
                            kubectl replace --raw /api/v1/namespaces/longhorn-system/finalize -f - 2>/dev/null || true
                        break
                    fi
                    sleep 1
                    echo -n "."
                done
                echo ""
            fi
            
            # 6. 删除 CRDs（并行删除，加快速度）
            echo_info "    删除 Longhorn CRDs..."
            kubectl delete crd -l app.kubernetes.io/name=longhorn --timeout=10s 2>/dev/null || true
            kubectl delete crd volumes.longhorn.io replicas.longhorn.io engines.longhorn.io nodes.longhorn.io settings.longhorn.io engineimages.longhorn.io backingimagedatasources.longhorn.io backingimagemanagers.longhorn.io backingimages.longhorn.io --timeout=10s 2>/dev/null || true
            
            # 7. 清理残留资源（快速模式已清理，这里只做补充）
            if [ "${CLEAN_MODE}" != "1" ]; then
                echo_info "    清理残留资源..."
                kubectl get volumes.longhorn.io -A -o json 2>/dev/null | \
                    jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null | \
                    while read ns name; do
                        kubectl patch volumes.longhorn.io "${name}" -n "${ns}" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
                    done || true
            fi
            
            echo_info "  ✓ Longhorn 清理完成（镜像已保留）"
            echo ""
            ;;
        2)
            echo_info "  选择：直接重新安装（不清理）"
            ;;
        3)
            echo_info "  跳过安装 Longhorn"
            exit 0
            ;;
        *)
            echo_info "  无效选择，跳过安装"
            exit 0
            ;;
    esac
fi

# ------------------------------------------
# 2. 配置数据盘路径（可通过环境变量或命令行参数覆盖）
# ------------------------------------------
# 优先使用命令行参数，然后是环境变量，最后是默认值
if [ -n "$1" ]; then
    LONGHORN_DATA_PATH="$1"
elif [ -n "${LONGHORN_DATA_PATH}" ]; then
    LONGHORN_DATA_PATH="${LONGHORN_DATA_PATH}"
else
    LONGHORN_DATA_PATH="/data/longhorn"
fi

# 规范化路径（确保以 / 结尾，且只有一个斜杠）
# 先移除所有末尾的斜杠，然后添加一个
while [[ "${LONGHORN_DATA_PATH}" == */ ]]; do
    LONGHORN_DATA_PATH="${LONGHORN_DATA_PATH%/}"
done
LONGHORN_DATA_PATH="${LONGHORN_DATA_PATH}/"

echo_info "1. 配置 Longhorn 数据存储路径: ${LONGHORN_DATA_PATH}"

# 尝试设置权限（如果失败会在后续检查中处理）
sudo chmod 755 "${LONGHORN_DATA_PATH}" 2>/dev/null || true

# ------------------------------------------
# 2.1 数据盘要求说明
# ------------------------------------------
echo ""
echo_info "Longhorn 数据盘要求："
echo "  - 文件系统: ext4 或 xfs（推荐 ext4）"
echo "  - 最小空间: 10GB（生产环境建议 50GB+）"
echo "  - 挂载选项: 建议包含 noatime（提升性能）"
echo "  - 权限: 需要写权限（建议 755 或 777）"
echo "  - 多节点: 每个节点都需要有数据盘"
echo "  - 建议: 使用独立的数据盘，不要使用系统盘"
echo ""

# ------------------------------------------
# 2.2 检查当前节点数据盘（仅检查，不自动修改）
# ------------------------------------------
check_data_disk() {
    local path="$1"
    local issues=0
    
    echo_info "检查数据盘路径: ${path}"
    
    # 检查路径是否存在
    if [ ! -d "${path}" ]; then
        echo_warn "  ✗ 路径不存在: ${path}"
        echo_info "    需要创建目录，脚本可以自动创建（需要 sudo 权限）"
        issues=$((issues + 1))
    else
        echo_info "  ✓ 路径存在"
        
        # 检查写权限
        # 注意：Longhorn Pod 以 root 权限运行，所以检查目录权限是否允许 root（所有者）写入
        local dir_perms=$(stat -c "%a" "${path}" 2>/dev/null || stat -f "%OLp" "${path}" 2>/dev/null || echo "")
        if [ -n "${dir_perms}" ]; then
            # 检查所有者权限（第一位数字）：7 = rwx, 6 = rw-, 5 = r-x
            # 如果所有者有写权限（>= 6），Longhorn 可以写入
            local owner_perm="${dir_perms:0:1}"
            if [ "${owner_perm}" -ge 6 ] 2>/dev/null; then
                echo_info "  ✓ 目录权限: ${dir_perms}（所有者可写，Longhorn 可以写入）"
            else
                echo_warn "  ✗ 目录权限不足: ${dir_perms}（所有者无写权限）"
                echo_info "    需要设置权限: sudo chmod 755 ${path}"
                issues=$((issues + 1))
            fi
        else
            # 如果无法获取权限，回退到检查当前用户写权限
            if [ ! -w "${path}" ]; then
                echo_warn "  ⚠️  当前用户无写权限: ${path}"
                echo_info "    如果目录权限是 755 或 777，Longhorn 仍可正常使用（Pod 以 root 运行）"
                echo_info "    建议检查: ls -ld ${path}"
                # 不增加 issues，因为 Longhorn Pod 以 root 运行，可能仍然可用
            else
                echo_info "  ✓ 有写权限"
            fi
        fi
        
        # 检查磁盘空间（至少 10GB）
        local available_kb=$(df -k "${path}" | tail -1 | awk '{print $4}')
        local available_gb=$((available_kb / 1024 / 1024))
        
        if [ "${available_gb}" -lt 10 ]; then
            echo_warn "  ✗ 可用空间不足: ${available_gb}GB（建议至少 10GB）"
            issues=$((issues + 1))
        else
            echo_info "  ✓ 可用空间: ${available_gb}GB"
        fi
        
        # 检查文件系统类型
        local fstype=$(df -T "${path}" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
        if [[ "${fstype}" =~ ^(ext4|xfs)$ ]]; then
            echo_info "  ✓ 文件系统类型: ${fstype}（推荐）"
        else
            echo_warn "  ⚠️  文件系统类型: ${fstype}（建议使用 ext4 或 xfs）"
        fi
    fi
    
    return ${issues}
}

# 检查当前节点数据盘
check_data_disk "${LONGHORN_DATA_PATH}"
DISK_CHECK_RESULT=$?

if [ ${DISK_CHECK_RESULT} -gt 0 ]; then
    echo ""
    echo_warn "数据盘检查发现问题，是否自动修复？"
    echo_info "  自动修复将执行："
    echo "    1. 创建目录（如果不存在）: sudo mkdir -p ${LONGHORN_DATA_PATH}"
    echo "    2. 设置权限: sudo chmod 755 ${LONGHORN_DATA_PATH}"
    echo ""
    read -p "是否自动修复？(y/n，默认n): " AUTO_FIX
    AUTO_FIX=${AUTO_FIX:-n}
    
    if [[ "${AUTO_FIX}" =~ ^[Yy]$ ]]; then
        echo_info "正在修复..."
        if sudo mkdir -p "${LONGHORN_DATA_PATH}" 2>/dev/null; then
            echo_info "  ✓ 目录已创建"
        else
            echo_error "  ✗ 创建目录失败（需要 sudo 权限或无权限）"
            echo_info "    请手动执行: sudo mkdir -p ${LONGHORN_DATA_PATH}"
        fi
        
        if sudo chmod 755 "${LONGHORN_DATA_PATH}" 2>/dev/null; then
            echo_info "  ✓ 权限已设置"
        else
            echo_error "  ✗ 设置权限失败（需要 sudo 权限或无权限）"
            echo_info "    请手动执行: sudo chmod 755 ${LONGHORN_DATA_PATH}"
        fi
        
        # 重新检查
        echo ""
        echo_info "重新检查数据盘..."
        check_data_disk "${LONGHORN_DATA_PATH}"
        DISK_CHECK_RESULT=$?
    else
        echo_warn "跳过自动修复，请手动准备数据盘"
    fi
fi

echo ""
echo_warn "重要提示："
echo "  - 如果这是多节点集群，需要在每个节点上准备数据盘"
echo "  - 如果使用独立数据盘，需要先格式化并挂载："
echo "    1. 格式化: sudo mkfs.ext4 /dev/sdX  # 替换为实际磁盘"
echo "    2. 挂载: sudo mount /dev/sdX ${LONGHORN_DATA_PATH}"
echo "    3. 添加到 /etc/fstab 实现开机自动挂载（示例）："
echo "       /dev/sdX ${LONGHORN_DATA_PATH} ext4 defaults,noatime 0 2"
echo ""

# ------------------------------------------
# 2.3 自动检测并配置 sdb 磁盘（可选）
# ------------------------------------------
echo_info "2.3 检查是否有未使用的磁盘（如 /dev/sdb）..."
if lsblk /dev/sdb &>/dev/null && [ -z "$(lsblk -n -o MOUNTPOINT /dev/sdb 2>/dev/null | grep -v '^$')" ]; then
    SDB_SIZE=$(lsblk -b -d -n -o SIZE /dev/sdb 2>/dev/null | awk '{printf "%.1f", $1/1024/1024/1024}')
    echo_warn "  检测到未挂载的磁盘: /dev/sdb (大小: ${SDB_SIZE}GB)"
    echo ""
    echo_info "  是否自动配置 /dev/sdb 作为 Longhorn 数据盘？"
    echo_warn "  ⚠️  警告：这将执行以下操作："
    echo "    1. 格式化 /dev/sdb（会删除磁盘上的所有数据！）"
    echo "    2. 创建挂载点: ${LONGHORN_DATA_PATH}"
    echo "    3. 挂载磁盘到: ${LONGHORN_DATA_PATH}"
    echo "    4. 设置权限: chmod 755"
    echo "    5. 添加到 /etc/fstab（开机自动挂载）"
    echo ""
    read -p "是否自动配置 /dev/sdb？(y/n，默认n): " AUTO_SETUP_SDB
    AUTO_SETUP_SDB=${AUTO_SETUP_SDB:-n}
    
    if [[ "${AUTO_SETUP_SDB}" =~ ^[Yy]$ ]]; then
        echo_info "  开始配置 /dev/sdb..."
        
        # 1. 检查磁盘是否已有文件系统
        if blkid /dev/sdb &>/dev/null; then
            echo_warn "  ⚠️  /dev/sdb 已有文件系统"
            read -p "  是否继续格式化（会删除所有数据）？(y/n，默认n): " FORMAT_CONFIRM
            FORMAT_CONFIRM=${FORMAT_CONFIRM:-n}
            if [[ ! "${FORMAT_CONFIRM}" =~ ^[Yy]$ ]]; then
                echo_info "  已取消格式化"
            else
                echo_info "  正在格式化 /dev/sdb 为 ext4..."
                if sudo mkfs.ext4 -F /dev/sdb 2>&1; then
                    echo_info "  ✓ 格式化完成"
                else
                    echo_error "  ✗ 格式化失败"
                    exit 1
                fi
            fi
        else
            echo_info "  正在格式化 /dev/sdb 为 ext4..."
            if sudo mkfs.ext4 -F /dev/sdb 2>&1; then
                echo_info "  ✓ 格式化完成"
            else
                echo_error "  ✗ 格式化失败"
                exit 1
            fi
        fi
        
        # 2. 创建挂载点
        if [ ! -d "${LONGHORN_DATA_PATH}" ]; then
            echo_info "  创建挂载点: ${LONGHORN_DATA_PATH}"
            if sudo mkdir -p "${LONGHORN_DATA_PATH}" 2>&1; then
                echo_info "  ✓ 挂载点已创建"
            else
                echo_error "  ✗ 创建挂载点失败"
                exit 1
            fi
        else
            echo_info "  ✓ 挂载点已存在: ${LONGHORN_DATA_PATH}"
        fi
        
        # 3. 挂载磁盘
        echo_info "  挂载 /dev/sdb 到 ${LONGHORN_DATA_PATH}..."
        if sudo mount /dev/sdb "${LONGHORN_DATA_PATH}" 2>&1; then
            echo_info "  ✓ 挂载成功"
        else
            echo_error "  ✗ 挂载失败"
            exit 1
        fi
        
        # 4. 设置权限
        echo_info "  设置权限: chmod 755"
        if sudo chmod 755 "${LONGHORN_DATA_PATH}" 2>&1; then
            echo_info "  ✓ 权限已设置"
        else
            echo_warn "  ⚠️  设置权限失败（继续）"
        fi
        
        # 5. 添加到 /etc/fstab（如果还没有）
        if ! grep -q "^/dev/sdb.*${LONGHORN_DATA_PATH}" /etc/fstab 2>/dev/null; then
            echo_info "  添加到 /etc/fstab（开机自动挂载）..."
            # 获取 UUID（更可靠）
            SDB_UUID=$(sudo blkid -s UUID -o value /dev/sdb 2>/dev/null)
            if [ -n "${SDB_UUID}" ]; then
                FSTAB_ENTRY="UUID=${SDB_UUID} ${LONGHORN_DATA_PATH} ext4 defaults,noatime 0 2"
            else
                FSTAB_ENTRY="/dev/sdb ${LONGHORN_DATA_PATH} ext4 defaults,noatime 0 2"
            fi
            
            echo "${FSTAB_ENTRY}" | sudo tee -a /etc/fstab > /dev/null
            if [ $? -eq 0 ]; then
                echo_info "  ✓ 已添加到 /etc/fstab"
                echo_info "    内容: ${FSTAB_ENTRY}"
            else
                echo_warn "  ⚠️  添加到 /etc/fstab 失败（需要手动添加）"
            fi
        else
            echo_info "  ✓ /dev/sdb 已在 /etc/fstab 中"
        fi
        
        echo_info "  ✓ /dev/sdb 配置完成"
        echo ""
        
        # 重新检查数据盘
        echo_info "重新检查数据盘..."
        check_data_disk "${LONGHORN_DATA_PATH}"
        DISK_CHECK_RESULT=$?
    else
        echo_info "  跳过自动配置 /dev/sdb"
    fi
else
    if ! lsblk /dev/sdb &>/dev/null; then
        echo_info "  ✓ 未检测到 /dev/sdb 磁盘"
    else
        echo_info "  ✓ /dev/sdb 已挂载: $(lsblk -n -o MOUNTPOINT /dev/sdb 2>/dev/null)"
    fi
fi

echo ""

if [ ${DISK_CHECK_RESULT} -gt 0 ]; then
    echo_warn "数据盘检查仍有问题，是否继续安装？"
    read -p "继续安装？(y/n，默认n): " CONTINUE
    CONTINUE=${CONTINUE:-n}
    if [[ ! "${CONTINUE}" =~ ^[Yy]$ ]]; then
        echo_warn "请先准备数据盘，然后重新运行脚本"
        exit 1
    fi
fi

# ------------------------------------------
# 3. 定位本地 yaml 文件
# ------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LONGHORN_YAML="${SCRIPT_DIR}/longhorn_v1.8.1.yaml"

if [ ! -f "${LONGHORN_YAML}" ]; then
    echo_error "找不到 Longhorn YAML 文件: ${LONGHORN_YAML}"
    echo_info "请确保 longhorn_v1.8.1.yaml 文件存在于 docs/installation/ 目录"
    exit 1
fi

echo_info "2. 使用本地 YAML 文件: ${LONGHORN_YAML}"
echo_info "  - 已恢复 healthz 探针（readinessProbe）"
echo_info "  - 已优化 driver-deployer init 容器（添加超时机制，避免无限等待）"

# ------------------------------------------
# 4. 准备临时 yaml 文件（替换数据盘路径）
# ------------------------------------------
TEMP_YAML=$(mktemp)
echo_info "3. 准备安装配置（数据盘路径: ${LONGHORN_DATA_PATH}）..."

# 替换策略：
# 1. 先替换所有的 path: /var/lib/longhorn/ 为新的数据盘路径
# 2. 然后恢复 mountPath（容器内路径必须保持 /var/lib/longhorn/）
# 这样可以确保只替换 hostPath 中的 path，而不影响 mountPath

# 第一步：替换所有 path: /var/lib/longhorn/（hostPath）
# 第二步：替换 default-data-path（如果有的话）
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS 使用 BSD sed
    sed "s|path: /var/lib/longhorn/|path: ${LONGHORN_DATA_PATH}|g" "${LONGHORN_YAML}" > "${TEMP_YAML}"
    # 替换 default-data-path（在 ConfigMap 中）
    sed -i '' "s|default-data-path: /var/lib/longhorn|default-data-path: ${LONGHORN_DATA_PATH%/}|g" "${TEMP_YAML}" 2>/dev/null || true
    # 恢复 mountPath（容器内路径必须保持 /var/lib/longhorn/）
    sed -i '' "s|mountPath: ${LONGHORN_DATA_PATH}|mountPath: /var/lib/longhorn/|g" "${TEMP_YAML}" 2>/dev/null || true
else
    # Linux 使用 GNU sed
    sed "s|path: /var/lib/longhorn/|path: ${LONGHORN_DATA_PATH}|g" "${LONGHORN_YAML}" > "${TEMP_YAML}"
    # 替换 default-data-path（在 ConfigMap 中）
    sed -i.bak "s|default-data-path: /var/lib/longhorn|default-data-path: ${LONGHORN_DATA_PATH%/}|g" "${TEMP_YAML}" 2>/dev/null || true
    # 恢复 mountPath（容器内路径必须保持 /var/lib/longhorn/）
    sed -i.bak "s|mountPath: ${LONGHORN_DATA_PATH}|mountPath: /var/lib/longhorn/|g" "${TEMP_YAML}" 2>/dev/null || true
    rm -f "${TEMP_YAML}.bak" 2>/dev/null || true
fi

# 验证替换结果
HOSTPATH_COUNT=$(grep -c "path: ${LONGHORN_DATA_PATH}" "${TEMP_YAML}" 2>/dev/null || echo "0")
MOUNTPATH_COUNT=$(grep -c "mountPath: /var/lib/longhorn/" "${TEMP_YAML}" 2>/dev/null || echo "0")

if [ "${HOSTPATH_COUNT}" -gt 0 ]; then
    echo_info "  ✓ 已替换 ${HOSTPATH_COUNT} 处 hostPath 路径为: ${LONGHORN_DATA_PATH}"
    if [ "${MOUNTPATH_COUNT}" -gt 0 ]; then
        echo_info "  ✓ mountPath 已恢复为容器内路径: /var/lib/longhorn/ (${MOUNTPATH_COUNT} 处)"
    fi
else
    echo_error "  ✗ 路径替换失败，请检查 LONGHORN_DATA_PATH 设置"
    echo_debug "  当前 LONGHORN_DATA_PATH: ${LONGHORN_DATA_PATH}"
    exit 1
fi

# ------------------------------------------
# 4.1 检查并处理默认 StorageClass 冲突
# ------------------------------------------
echo ""
echo_info "3.1 检查默认 StorageClass..."

# 查找现有的默认 StorageClass
EXISTING_DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)

if [ -n "${EXISTING_DEFAULT_SC}" ] && [ "${EXISTING_DEFAULT_SC}" != "longhorn" ]; then
    echo_warn "检测到已有默认 StorageClass: ${EXISTING_DEFAULT_SC}"
    echo_info "Longhorn 安装后也会设置为默认 StorageClass，这会导致冲突。"
    echo ""
    echo_info "当前默认 StorageClass 信息："
    kubectl get storageclass "${EXISTING_DEFAULT_SC}" -o yaml | grep -A 5 "metadata:" | head -10 || true
    echo ""
    echo_warn "是否取消 ${EXISTING_DEFAULT_SC} 的默认设置？"
    echo_info "  选择 'y': 取消 ${EXISTING_DEFAULT_SC} 的默认设置，让 Longhorn 成为默认"
    echo_info "  选择 'n': 保留 ${EXISTING_DEFAULT_SC} 为默认，Longhorn 不会成为默认（需要手动指定 storageClassName）"
    echo ""
    read -p "取消 ${EXISTING_DEFAULT_SC} 的默认设置？(y/n，默认y): " REMOVE_DEFAULT
    REMOVE_DEFAULT=${REMOVE_DEFAULT:-y}
    
    if [[ "${REMOVE_DEFAULT}" =~ ^[Yy]$ ]]; then
        echo_info "正在取消 ${EXISTING_DEFAULT_SC} 的默认设置..."
        if kubectl patch storageclass "${EXISTING_DEFAULT_SC}" \
            -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>&1; then
            echo_info "  ✓ 已取消 ${EXISTING_DEFAULT_SC} 的默认设置"
        else
            echo_error "  ✗ 取消默认设置失败"
            echo_warn "  继续安装，但可能会有默认 StorageClass 冲突"
        fi
    else
        echo_info "保留 ${EXISTING_DEFAULT_SC} 为默认 StorageClass"
        echo_warn "安装完成后，需要修改 longhorn StorageClass，取消其默认设置"
        echo_info "  执行命令: kubectl patch storageclass longhorn -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
    fi
else
    if [ -n "${EXISTING_DEFAULT_SC}" ] && [ "${EXISTING_DEFAULT_SC}" = "longhorn" ]; then
        echo_info "  ✓ longhorn 已经是默认 StorageClass"
    else
        echo_info "  ✓ 未发现其他默认 StorageClass，Longhorn 将设置为默认"
    fi
fi

# ------------------------------------------
# 5. 安装 Longhorn
# ------------------------------------------
echo ""
echo_info "4. 安装 Longhorn（版本: v1.8.1，已适配 k3s，已恢复 healthz 探针）..."

if kubectl apply -f "${TEMP_YAML}" 2>&1; then
    echo_info "  ✓ Longhorn manifest 已应用"
    rm -f "${TEMP_YAML}"
else
    echo_error "  ✗ 应用 Longhorn manifest 失败"
    rm -f "${TEMP_YAML}"
    exit 1
fi

# ------------------------------------------
# 6. 等待 Longhorn Pod 就绪
# ------------------------------------------
echo ""
echo_info "5. 等待 Longhorn Pod 就绪（命名空间: longhorn-system，最长 10 分钟）..."

# 注意：longhorn-manager 是 DaemonSet，不是 Deployment
echo_info "  等待 longhorn-manager DaemonSet 就绪..."
kubectl wait --for=condition=Ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s 2>&1 \
    && echo_info "  ✓ longhorn-manager Pod 已就绪" \
    || echo_warn "  ⚠️ longhorn-manager 等待超时，请检查 Pod 状态"

echo ""
echo_info "当前 Longhorn Pod 状态："
kubectl get pods -n longhorn-system

# ------------------------------------------
# 6.1 更新 Longhorn default-data-path 设置
# ------------------------------------------
echo ""
echo_info "5.1 更新 Longhorn 数据路径设置..."
sleep 5  # 等待 Longhorn manager 完全启动

# 检查 default-data-path 设置是否存在
if kubectl get settings.longhorn.io default-data-path -n longhorn-system &>/dev/null; then
    CURRENT_PATH=$(kubectl get settings.longhorn.io default-data-path -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "")
    if [ "${CURRENT_PATH}" != "${LONGHORN_DATA_PATH%/}" ]; then
        echo_info "  当前 default-data-path: ${CURRENT_PATH}"
        echo_info "  更新为: ${LONGHORN_DATA_PATH%/}"
        if kubectl patch settings.longhorn.io default-data-path -n longhorn-system \
            --type='merge' -p "{\"value\":\"${LONGHORN_DATA_PATH%/}\"}" 2>&1; then
            echo_info "  ✓ default-data-path 已更新"
        else
            echo_warn "  ⚠️  更新 default-data-path 失败，可能需要手动更新"
        fi
    else
        echo_info "  ✓ default-data-path 已正确配置: ${LONGHORN_DATA_PATH%/}"
    fi
else
    echo_warn "  ⚠️  default-data-path 设置不存在，等待 Longhorn 完全启动..."
fi

# ------------------------------------------
# 7. 检查 / 创建 StorageClass
# ------------------------------------------
echo ""
echo_info "6. 检查 Longhorn StorageClass..."

if kubectl get sc longhorn &>/dev/null; then
    echo_info "  ✓ 已存在 StorageClass: longhorn"
else
    echo_warn "  未发现名为 longhorn 的 StorageClass，尝试创建..."
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "30"
EOF
    echo_info "  ✓ 已创建 StorageClass: longhorn"
fi

echo ""
echo_info "7. 验证 StorageClass 和默认设置："
kubectl get sc

# 检查是否有多个默认 StorageClass
DEFAULT_SC_COUNT=$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')

if [ "${DEFAULT_SC_COUNT}" -gt 1 ]; then
    echo_warn "  ⚠️ 检测到多个默认 StorageClass，这可能导致问题"
    echo_info "  默认 StorageClass 列表："
    kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null
    echo_warn "  建议只保留一个默认 StorageClass"
elif [ "${DEFAULT_SC_COUNT}" -eq 1 ]; then
    DEFAULT_SC_NAME=$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
    echo_info "  ✓ 当前默认 StorageClass: ${DEFAULT_SC_NAME}"
fi

# ------------------------------------------
# 8. 总结
# ------------------------------------------
echo ""
echo_info "=========================================="
echo_info "Longhorn 安装流程完成（版本: v1.8.1）"
echo_info "=========================================="
echo ""
echo_info "配置信息："
echo "  - 数据存储路径: ${LONGHORN_DATA_PATH}"
echo "  - 已恢复 healthz 探针（readinessProbe）"
echo ""
echo_info "常用后续操作："
echo "  1. 访问 Longhorn UI:"
echo "     kubectl -n longhorn-system get svc longhorn-frontend"
echo "     kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80"
echo ""
echo_info "  2. 在 Wukong 中使用 Longhorn:"
echo "     在 Wukong CR 的 disks[*].storageClassName 中设置为: longhorn"
echo ""
echo_info "  3. 检查数据盘使用情况:"
echo "     kubectl -n longhorn-system exec -it <longhorn-manager-pod> -- df -h ${LONGHORN_DATA_PATH}"
echo ""

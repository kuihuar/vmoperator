#!/bin/bash

# 安装 Longhorn（适用于单节点或多节点 k3s/k8s 集群）
# 使用本地修改后的 longhorn_v1.8.1.yaml（已去掉 healthz 探针，适配当前 k3s）
#
# ⚠️  重要提示：
# - 已去掉 Kubernetes readinessProbe（kubelet 的外部检查）
# - 但 longhorn-manager 进程内部的 webhook 健康检查无法通过 YAML 配置禁用
# - 如果遇到 "conversion webhook service is not accessible" 错误导致 CrashLoop，
#   这是 Longhorn v1.8.1 在当前 k3s 环境下的兼容性问题
# - 建议：如果持续 CrashLoop，考虑使用 k3s 自带的 local-path 存储

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
    read -p "是否继续重新安装 Longhorn？(y/n，默认n): " REINSTALL
    REINSTALL=${REINSTALL:-n}
    if [[ ! $REINSTALL =~ ^[Yy]$ ]]; then
        echo_info "  跳过安装 Longhorn"
        exit 0
    fi
fi

# ------------------------------------------
# 2. 配置数据盘路径（可通过环境变量覆盖）
# ------------------------------------------
LONGHORN_DATA_PATH="${LONGHORN_DATA_PATH:-/data/longhorn}"
echo_info "1. 配置 Longhorn 数据存储路径: ${LONGHORN_DATA_PATH}"

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
        if [ ! -w "${path}" ]; then
            echo_warn "  ✗ 无写权限: ${path}"
            echo_info "    需要设置写权限: sudo chmod 755 ${path}"
            issues=$((issues + 1))
        else
            echo_info "  ✓ 有写权限"
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
echo_info "  - 已去掉 healthz 探针（适配当前 k3s）"
echo_info "  - 已优化 driver-deployer init 容器（添加超时机制，避免无限等待）"

# ------------------------------------------
# 4. 准备临时 yaml 文件（替换数据盘路径）
# ------------------------------------------
TEMP_YAML=$(mktemp)
echo_info "3. 准备安装配置（数据盘路径: ${LONGHORN_DATA_PATH}）..."

# 复制 yaml 文件并替换数据盘路径
sed "s|/var/lib/longhorn/|${LONGHORN_DATA_PATH}/|g" "${LONGHORN_YAML}" > "${TEMP_YAML}"

# 确保路径以 / 结尾（如果用户输入的路径没有 /，自动添加）
sed -i.bak "s|path: ${LONGHORN_DATA_PATH}[^/]|path: ${LONGHORN_DATA_PATH}/|g" "${TEMP_YAML}" 2>/dev/null || true
rm -f "${TEMP_YAML}.bak" 2>/dev/null || true

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
echo_info "4. 安装 Longhorn（版本: v1.8.1，已适配 k3s，已去掉 healthz 探针）..."

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
echo "  - 已去掉 healthz 探针（适配当前 k3s）"
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

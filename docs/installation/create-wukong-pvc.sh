#!/bin/bash

# 创建 wukong PVC（使用 Longhorn）

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
echo_info "创建 wukong PVC（使用 Longhorn）"
echo_info "=========================================="
echo ""

# 1. 检查 Longhorn 是否已安装
echo_info "1. 检查 Longhorn 是否已安装..."

if ! kubectl get storageclass longhorn &>/dev/null; then
    echo_error "  ✗ Longhorn StorageClass 未找到"
    echo_warn "  请先安装 Longhorn："
    echo_warn "    ./docs/installation/install-longhorn.sh"
    exit 1
fi

echo_info "  ✓ Longhorn StorageClass 已存在"

# 检查 Longhorn Pod 状态
LONGHORN_PODS=$(kubectl get pods -n longhorn-system 2>/dev/null | grep -v NAME | wc -l)
if [ "${LONGHORN_PODS}" -eq 0 ]; then
    echo_warn "  ⚠️  Longhorn Pod 未运行，请检查安装状态"
else
    echo_info "  ✓ 发现 ${LONGHORN_PODS} 个 Longhorn Pod"
fi
echo ""

# 2. 检查是否已存在 wukong PVC
echo_info "2. 检查是否已存在 wukong PVC..."
if kubectl get pvc wukong &>/dev/null; then
    echo_warn "  ⚠️  wukong PVC 已存在"
    kubectl get pvc wukong
    read -p "是否删除并重新创建？(y/n，默认n): " RECREATE
    RECREATE=${RECREATE:-n}
    if [[ $RECREATE =~ ^[Yy]$ ]]; then
        echo_info "  删除现有 PVC..."
        kubectl delete pvc wukong
        sleep 2
    else
        echo_info "  跳过创建"
        exit 0
    fi
else
    echo_info "  ✓ wukong PVC 不存在，可以创建"
fi
echo ""

# 3. 创建 PVC
echo_info "3. 创建 wukong PVC..."

# PVC 配置
PVC_YAML=$(cat <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wukong
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
EOF
)

# 显示配置
echo_info "  PVC 配置："
echo "${PVC_YAML}" | sed 's/^/    /'
echo ""

# 应用配置
if echo "${PVC_YAML}" | kubectl apply -f -; then
    echo_info "  ✓ wukong PVC 已创建"
else
    echo_error "  ✗ 创建 wukong PVC 失败"
    exit 1
fi
echo ""

# 4. 等待 PVC 绑定
echo_info "4. 等待 PVC 绑定（最多 60 秒）..."
for i in {1..60}; do
    PVC_STATUS=$(kubectl get pvc wukong -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "${PVC_STATUS}" = "Bound" ]; then
        echo_info "  ✓ PVC 已绑定"
        break
    fi
    if [ $i -eq 60 ]; then
        echo_warn "  ⚠️  PVC 绑定超时，请检查 Longhorn 状态"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# 5. 显示 PVC 信息
echo_info "5. wukong PVC 信息："
kubectl get pvc wukong -o wide
echo ""

# 6. 显示 PV 信息（如果已绑定）
PV_NAME=$(kubectl get pvc wukong -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
if [ -n "${PV_NAME}" ]; then
    echo_info "6. 关联的 PV 信息："
    kubectl get pv ${PV_NAME} -o wide
    echo ""
fi

echo_info "=========================================="
echo_info "wukong PVC 创建完成"
echo_info "=========================================="
echo ""
echo_info "使用方式："
echo "  在 Pod 中挂载："
echo "    volumes:"
echo "    - name: wukong-storage"
echo "      persistentVolumeClaim:"
echo "        claimName: wukong"
echo ""


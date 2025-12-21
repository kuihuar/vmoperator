#!/bin/bash

# Longhorn Helm 安装脚本
# 用法: ./scripts/install-longhorn-helm.sh [version] [values-file]
# 例如: ./scripts/install-longhorn-helm.sh 1.6.0 longhorn-values.yaml

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取参数
LONGHORN_VERSION="${1:-1.10.1}"
VALUES_FILE="${2:-}"

echo_info "准备使用 Helm 安装 Longhorn $LONGHORN_VERSION"

# 检查 Helm 是否安装
if ! command -v helm &> /dev/null; then
    echo_warn "Helm 未安装，开始安装..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo_info "Helm 安装完成"
else
    echo_info "Helm 已安装: $(helm version --short)"
fi

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo_error "kubectl 未安装，请先安装 kubectl"
    exit 1
fi

# 检查集群连接
if ! kubectl cluster-info &> /dev/null; then
    echo_error "无法连接到 Kubernetes 集群"
    exit 1
fi

echo_info "集群连接正常"

# 检查 open-iscsi（提醒用户）
echo_warn "请确保所有节点已安装 open-iscsi 并启动 iscsid 服务"
echo_warn "Ubuntu/Debian: sudo apt-get install -y open-iscsi && sudo systemctl enable iscsid && sudo systemctl start iscsid"
echo_warn "CentOS/RHEL: sudo yum install -y iscsi-initiator-utils && sudo systemctl enable iscsid && sudo systemctl start iscsid"

read -p "是否继续安装? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_info "安装已取消"
    exit 0
fi

# 检查是否已安装 Longhorn
if kubectl get namespace longhorn-system &> /dev/null; then
    echo_warn "检测到 longhorn-system 命名空间已存在"
    read -p "是否要先卸载现有 Longhorn? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo_info "卸载现有 Longhorn..."
        if helm list -n longhorn-system | grep -q longhorn; then
            helm uninstall longhorn -n longhorn-system
        else
            echo_warn "未找到 Helm 发布，可能需要手动卸载"
        fi
        kubectl delete namespace longhorn-system --timeout=120s 2>/dev/null || true
        echo_info "等待命名空间删除..."
        sleep 10
    else
        echo_error "无法在已存在的命名空间中安装，安装已取消"
        exit 1
    fi
fi

# 添加 Helm 仓库
echo_info "添加 Longhorn Helm 仓库..."
helm repo add longhorn https://charts.longhorn.io
helm repo update

# 查看可用版本
echo_info "查看可用版本..."
helm search repo longhorn/longhorn --versions | head -5

# 准备安装命令
INSTALL_CMD="helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version $LONGHORN_VERSION"

# 如果有 values 文件，添加 --values 参数
if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
    echo_info "使用自定义配置文件: $VALUES_FILE"
    INSTALL_CMD="$INSTALL_CMD --values $VALUES_FILE"
elif [ -n "$VALUES_FILE" ]; then
    echo_warn "指定的 values 文件不存在: $VALUES_FILE，使用默认配置"
fi

# 安装 Longhorn
echo_info "开始安装 Longhorn..."
eval $INSTALL_CMD

# 等待安装完成
echo_info "等待 Longhorn Manager 就绪（最多 10 分钟）..."
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s || {
    echo_error "Longhorn Manager 未能及时就绪，请检查 Pod 状态"
    kubectl get pods -n longhorn-system
    exit 1
}

echo_info "等待 Admission Webhook 就绪（最多 5 分钟）..."
kubectl wait --for=condition=ready pod -l app=longhorn-admission-webhook -n longhorn-system --timeout=300s || {
    echo_warn "Admission Webhook 未能及时就绪，继续检查其他组件"
}

# 检查安装状态
echo_info "检查安装状态..."
echo ""
echo "=== Helm 发布状态 ==="
helm list -n longhorn-system

echo ""
echo "=== Pods 状态 ==="
kubectl get pods -n longhorn-system

echo ""
echo "=== StorageClass ==="
kubectl get storageclass longhorn

echo ""
echo "=== CSI Driver ==="
kubectl get csidriver driver.longhorn.io 2>/dev/null || echo_warn "CSI Driver 尚未创建（可能需要等待 driver-deployer 完成）"

echo ""
echo_info "Longhorn 安装完成！"
echo_info "可以使用以下命令监控安装进度:"
echo "  watch kubectl get pods -n longhorn-system"
echo ""
echo_info "访问 Longhorn UI:"
echo "  kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
echo "  然后在浏览器访问 http://localhost:8080"


#!/bin/bash

# 修复 Longhorn admission-webhook Pod 缺失问题

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo_step() {
    echo -e "${BLUE}[步骤]${NC} $1"
}

echo ""
echo_info "=========================================="
echo_info "修复 Longhorn admission-webhook Pod 缺失问题"
echo_info "=========================================="
echo ""

# 1. 检查当前状态
echo_step "1. 检查当前状态"
echo_info "检查 admission-webhook Service..."
kubectl get svc -n longhorn-system longhorn-admission-webhook

echo ""
echo_info "检查 admission-webhook Pods..."
WEBHOOK_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-admission-webhook -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "$WEBHOOK_PODS" ]; then
    echo_error "✗ 未找到 admission-webhook Pods"
else
    echo_info "✓ 找到 Pods: $WEBHOOK_PODS"
    exit 0
fi

echo ""
echo_info "检查 DaemonSet/Deployment..."
kubectl get daemonset,deployment -n longhorn-system | grep admission-webhook || echo_warn "未找到 DaemonSet/Deployment"

echo ""
echo_info "检查 ReplicaSet..."
kubectl get replicaset -n longhorn-system | grep admission || echo_warn "未找到 ReplicaSet"

# 2. 检查 Helm 安装状态
echo ""
echo_step "2. 检查 Helm 安装状态"
if helm list -n longhorn-system | grep -q longhorn; then
    HELM_RELEASE=$(helm list -n longhorn-system | grep longhorn | awk '{print $1}')
    HELM_VERSION=$(helm list -n longhorn-system | grep longhorn | awk '{print $9}')
    echo_info "找到 Helm 发布: $HELM_RELEASE (版本: $HELM_VERSION)"
    
    echo ""
    echo_info "查看 Helm 资源状态..."
    helm get manifest longhorn -n longhorn-system | grep -A 20 "admission-webhook" | head -40 || echo_warn "在 Helm manifest 中未找到 admission-webhook 资源"
else
    echo_warn "未找到 Helm 发布，可能是使用 kubectl apply 安装的"
fi

# 3. 检查 Longhorn 版本
echo ""
echo_step "3. 检查 Longhorn 版本"
MANAGER_IMAGE=$(kubectl get deployment -n longhorn-system longhorn-manager -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
if [ -n "$MANAGER_IMAGE" ]; then
    echo_info "Longhorn Manager 镜像: $MANAGER_IMAGE"
    VERSION=$(echo $MANAGER_IMAGE | grep -oP 'v\d+\.\d+\.\d+' || echo "未知")
    echo_info "版本: $VERSION"
else
    echo_warn "无法获取 Longhorn 版本"
    VERSION="1.10.1"  # 默认使用当前配置的版本
fi

# 4. 诊断和建议
echo ""
echo_step "4. 诊断结果和建议"
echo_error "问题：admission-webhook Pod/Deployment/DaemonSet 不存在"
echo ""
echo_warn "可能的原因："
echo "  1. Longhorn Helm Chart 安装不完整"
echo "  2. admission-webhook 组件安装失败"
echo "  3. 资源被误删除"
echo ""

# 5. 提供解决方案
echo_step "5. 解决方案"
echo ""
echo_warn "推荐：重新安装 Longhorn（推荐）"
echo ""
read -p "是否重新安装 Longhorn? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "开始重新安装 Longhorn..."
    
    # 5.1 备份数据（如果有重要数据）
    echo_warn "⚠️  这将删除所有 Longhorn 数据！"
    read -p "是否继续? (yes/no) " -r
    if [[ ! $REPLY == "yes" ]]; then
        echo_info "已取消"
        exit 0
    fi
    
    # 5.2 卸载现有 Longhorn
    echo_info "步骤 1: 卸载现有 Longhorn..."
    if helm list -n longhorn-system | grep -q longhorn; then
        helm uninstall longhorn -n longhorn-system
    else
        echo_warn "未找到 Helm 发布，尝试手动清理..."
        kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${VERSION}/deploy/longhorn.yaml 2>/dev/null || true
    fi
    
    # 5.3 清理命名空间
    echo_info "步骤 2: 清理命名空间..."
    kubectl delete namespace longhorn-system --timeout=120s 2>/dev/null || true
    
    # 5.4 等待清理
    echo_info "步骤 3: 等待资源清理（60 秒）..."
    sleep 60
    
    # 5.5 检查配置文件
    VALUES_FILE="config/longhorn-values.yaml"
    if [ ! -f "$VALUES_FILE" ]; then
        echo_warn "未找到配置文件 $VALUES_FILE，使用默认配置"
        VALUES_FILE=""
    fi
    
    # 5.6 重新安装
    echo_info "步骤 4: 重新安装 Longhorn..."
    if [ -n "$VALUES_FILE" ]; then
        echo_info "使用配置文件: $VALUES_FILE"
        helm install longhorn longhorn/longhorn \
          --namespace longhorn-system \
          --create-namespace \
          --version ${VERSION#v} \
          --values "$VALUES_FILE"
    else
        helm install longhorn longhorn/longhorn \
          --namespace longhorn-system \
          --create-namespace \
          --version ${VERSION#v}
    fi
    
    # 5.7 等待安装
    echo_info "步骤 5: 等待安装完成..."
    echo_info "监控 Pods 状态..."
    kubectl get pods -n longhorn-system -w &
    WATCH_PID=$!
    
    # 等待关键组件就绪
    echo_info "等待 admission-webhook 就绪（最多 5 分钟）..."
    if kubectl wait --for=condition=ready pod -l app=longhorn-admission-webhook -n longhorn-system --timeout=300s 2>/dev/null; then
        echo_info "✓ admission-webhook 已就绪"
    else
        echo_warn "admission-webhook 未能及时就绪，继续检查..."
    fi
    
    echo_info "等待 longhorn-manager 就绪（最多 10 分钟）..."
    if kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s 2>/dev/null; then
        echo_info "✓ longhorn-manager 已就绪"
    else
        echo_warn "longhorn-manager 未能及时就绪，请检查日志"
    fi
    
    # 停止监控
    kill $WATCH_PID 2>/dev/null || true
    
    # 5.8 验证安装
    echo ""
    echo_step "6. 验证安装"
    echo_info "检查所有 Pods:"
    kubectl get pods -n longhorn-system
    
    echo ""
    echo_info "检查 admission-webhook:"
    kubectl get pods -n longhorn-system -l app=longhorn-admission-webhook
    kubectl get svc -n longhorn-system longhorn-admission-webhook
    kubectl get endpoints -n longhorn-system longhorn-admission-webhook
    
    echo ""
    echo_info "安装完成！"
else
    echo_info "已取消重新安装"
    echo ""
    echo_warn "其他可能的解决方案："
    echo "  1. 检查 Helm Chart 是否有 admission-webhook 相关的资源定义"
    echo "  2. 手动检查并修复缺失的资源"
    echo "  3. 查看 Helm 安装日志: helm get manifest longhorn -n longhorn-system"
fi


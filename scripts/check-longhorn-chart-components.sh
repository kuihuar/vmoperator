#!/bin/bash

# 检查 Longhorn Helm Chart 包含的所有组件
# 用于确认哪些 Pods 是必需的，哪些是可选的

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

# 获取 Longhorn 版本
LONGHORN_VERSION="${1:-1.10.1}"

echo ""
echo_info "=========================================="
echo_info "检查 Longhorn Helm Chart 组件清单"
echo_info "版本: $LONGHORN_VERSION"
echo_info "=========================================="
echo ""

# 检查 Helm 是否安装
if ! command -v helm &> /dev/null; then
    echo_error "Helm 未安装，请先安装 Helm"
    exit 1
fi

# 添加仓库（如果还没有）
echo_step "1. 添加/更新 Longhorn Helm 仓库"
helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
helm repo update

# 获取 Chart 清单
echo_step "2. 获取 Helm Chart 清单"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo_info "获取 Chart 模板..."
helm template longhorn longhorn/longhorn \
  --version "$LONGHORN_VERSION" \
  --namespace longhorn-system \
  > "$TEMP_DIR/longhorn-manifest.yaml"

echo_info "Chart 清单已保存到临时文件"

# 分析组件
echo ""
echo_step "3. 分析组件类型和资源"

echo ""
echo_info "=== Deployment 列表 ==="
grep -E "^kind: Deployment|^\s+name:" "$TEMP_DIR/longhorn-manifest.yaml" | grep -A 1 "kind: Deployment" | grep "name:" | sed 's/.*name: //' | sed 's/^/  - /' | sort -u

echo ""
echo_info "=== DaemonSet 列表 ==="
grep -E "^kind: DaemonSet|^\s+name:" "$TEMP_DIR/longhorn-manifest.yaml" | grep -A 1 "kind: DaemonSet" | grep "name:" | sed 's/.*name: //' | sed 's/^/  - /' | sort -u

echo ""
echo_info "=== Job 列表 ==="
grep -E "^kind: Job|^\s+name:" "$TEMP_DIR/longhorn-manifest.yaml" | grep -A 1 "kind: Job" | grep "name:" | sed 's/.*name: //' | sed 's/^/  - /' | sort -u

echo ""
echo_info "=== Service 列表 ==="
grep -E "^kind: Service|^\s+name:" "$TEMP_DIR/longhorn-manifest.yaml" | grep -A 1 "kind: Service" | grep "name:" | sed 's/.*name: //' | sed 's/^/  - /' | sort -u

# 检查 admission-webhook
echo ""
echo_step "4. 检查 admission-webhook 组件"
echo_info "搜索 admission-webhook 相关资源..."

# 更全面的搜索
WEBHOOK_RESOURCES=$(grep -i "admission.*webhook\|webhook.*admission" "$TEMP_DIR/longhorn-manifest.yaml" | head -20)

if [ -n "$WEBHOOK_RESOURCES" ]; then
    echo_info "✓ 找到 admission-webhook 相关内容"
    echo "$WEBHOOK_RESOURCES" | head -10
    
    # 查找 Deployment
    WEBHOOK_DEPLOYMENT_LINE=$(grep -n "admission.*webhook" "$TEMP_DIR/longhorn-manifest.yaml" | grep -i "deployment\|name:" | head -5)
    if [ -n "$WEBHOOK_DEPLOYMENT_LINE" ]; then
        echo_info "  找到 Deployment 相关定义"
        # 获取 Deployment 定义的行号
        DEPLOYMENT_LINE=$(echo "$WEBHOOK_DEPLOYMENT_LINE" | awk -F: '{print $1}')
        sed -n "${DEPLOYMENT_LINE},$((DEPLOYMENT_LINE+50))p" "$TEMP_DIR/longhorn-manifest.yaml" | grep -E "kind:|name:|replicas:" | head -10
    fi
    
    # 查找 DaemonSet
    WEBHOOK_DAEMONSET_LINE=$(grep -n "admission.*webhook" "$TEMP_DIR/longhorn-manifest.yaml" | grep -i "daemonset\|name:" | head -5)
    if [ -n "$WEBHOOK_DAEMONSET_LINE" ]; then
        echo_info "  找到 DaemonSet 相关定义"
        DAEMONSET_LINE=$(echo "$WEBHOOK_DAEMONSET_LINE" | awk -F: '{print $1}')
        sed -n "${DAEMONSET_LINE},$((DAEMONSET_LINE+50))p" "$TEMP_DIR/longhorn-manifest.yaml" | grep -E "kind:|name:" | head -10
    fi
    
    # 查找 Service
    WEBHOOK_SERVICE_LINE=$(grep -n "admission.*webhook" "$TEMP_DIR/longhorn-manifest.yaml" | grep -i "service\|name:" | head -5)
    if [ -n "$WEBHOOK_SERVICE_LINE" ]; then
        echo_info "  找到 Service 定义"
    fi
else
    echo_warn "✗ 未在 Chart 清单中找到 admission-webhook 资源定义"
    echo_info "尝试查找所有 webhook 相关内容..."
    grep -i "webhook" "$TEMP_DIR/longhorn-manifest.yaml" | head -20
fi

# 检查是否有条件启用/禁用
echo ""
echo_info "检查是否有条件渲染（可能在 values 中控制）..."
if grep -q "{{.*admission.*webhook.*}}" "$TEMP_DIR/longhorn-manifest.yaml" || grep -q "{{.*webhook.*admission.*}}" "$TEMP_DIR/longhorn-manifest.yaml"; then
    echo_info "✓ 找到条件渲染（可能在 values.yaml 中控制启用/禁用）"
    grep -i "{{.*admission.*webhook.*}}\|{{.*webhook.*admission.*}}" "$TEMP_DIR/longhorn-manifest.yaml" | head -10
fi

# 检查 values 中是否有控制开关
echo ""
echo_step "5. 获取 Chart 默认 Values"
helm show values longhorn/longhorn --version "$LONGHORN_VERSION" > "$TEMP_DIR/values.yaml" 2>/dev/null || {
    echo_warn "无法获取 values，尝试查看本地 Chart"
}

if [ -f "$TEMP_DIR/values.yaml" ]; then
    echo_info "检查 admission-webhook 相关配置..."
    
    # 更全面的搜索
    WEBHOOK_VALUES=$(grep -i -E "admission|webhook" "$TEMP_DIR/values.yaml" | grep -v "^#" | head -30)
    
    if [ -n "$WEBHOOK_VALUES" ]; then
        echo_info "找到 webhook/admission 相关配置："
        echo "$WEBHOOK_VALUES"
        
        # 检查是否有 enabled 选项
        if echo "$WEBHOOK_VALUES" | grep -i "enabled"; then
            echo_info ""
            echo_info "✓ 找到 enabled 选项（可以控制启用/禁用）："
            echo "$WEBHOOK_VALUES" | grep -i "enabled"
        else
            echo_info ""
            echo_info "未找到 enabled 选项（可能默认启用且不可禁用）"
        fi
    else
        echo_warn "未找到 admission-webhook 相关配置"
    fi
fi

# 额外检查：查看实际安装的资源
echo ""
echo_step "6. 检查当前集群中已安装的资源"
if kubectl get namespace longhorn-system &> /dev/null; then
    echo_info "检查当前集群中的 admission-webhook 资源..."
    
    echo ""
    echo_info "Services:"
    kubectl get svc -n longhorn-system | grep -i "admission\|webhook" || echo_warn "未找到相关 Service"
    
    echo ""
    echo_info "Pods:"
    kubectl get pods -n longhorn-system | grep -i "admission\|webhook" || echo_warn "未找到相关 Pods"
    
    echo ""
    echo_info "Deployments:"
    kubectl get deployment -n longhorn-system | grep -i "admission\|webhook" || echo_warn "未找到相关 Deployment"
    
    echo ""
    echo_info "DaemonSets:"
    kubectl get daemonset -n longhorn-system | grep -i "admission\|webhook" || echo_warn "未找到相关 DaemonSet"
    
    # 检查是否有 ValidatingWebhookConfiguration 或 MutatingWebhookConfiguration
    echo ""
    echo_info "Webhook Configurations:"
    kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration | grep -i "longhorn\|admission" || echo_warn "未找到相关 Webhook Configuration"
else
    echo_warn "longhorn-system 命名空间不存在（Longhorn 可能尚未安装）"
fi

# 总结
echo ""
echo_info "=========================================="
echo_info "总结"
echo_info "=========================================="

echo ""
echo_info "预期的 Longhorn Pods（基于 Chart 清单）："
echo ""
echo "必需组件（核心功能）："
echo "  ✅ longhorn-manager (DaemonSet) - 存储管理器"
echo "  ✅ longhorn-ui (Deployment) - Web UI"
echo "  ✅ longhorn-driver-deployer (Job) - CSI Driver 安装"
echo "  ✅ longhorn-csi-plugin (DaemonSet) - CSI 插件"
echo "  ✅ longhorn-csi-attacher (Deployment) - CSI 附加器"
echo "  ✅ longhorn-csi-provisioner (Deployment) - CSI 供应器"
echo "  ✅ longhorn-csi-resizer (Deployment) - CSI 扩展器"
echo "  ✅ longhorn-backing-image-manager (DaemonSet) - 备份镜像管理器"
echo "  ✅ longhorn-engine-image (DaemonSet) - 引擎镜像"
echo ""

# 检查是否在 Chart 或集群中找到
if [ -n "$WEBHOOK_RESOURCES" ] || kubectl get svc -n longhorn-system longhorn-admission-webhook &> /dev/null; then
    echo "Webhook 组件："
    if kubectl get svc -n longhorn-system longhorn-admission-webhook &> /dev/null; then
        echo "  ✅ longhorn-admission-webhook Service 存在（已安装）"
        echo "  ⚠️  但 Pod 可能不存在或未运行"
    fi
    if [ -n "$WEBHOOK_RESOURCES" ]; then
        echo "  ✅ Chart 中包含 admission-webhook 定义"
    fi
    echo ""
    echo_warn "admission-webhook 是必需的组件，用于："
    echo "  - 验证和修改 Longhorn 资源"
    echo "  - 资源验证和默认值设置"
    echo "  - Manager 启动时需要访问此服务"
else
    echo_warn "未找到 admission-webhook 定义"
    echo ""
    echo_info "可能的情况："
    echo "  1. 在 v1.10.1 中 admission-webhook 可能已被移除或重构"
    echo "  2. 可能集成到 longhorn-manager 中"
    echo "  3. 可能使用不同的实现方式"
    echo ""
    echo_info "但您的集群中有 Service，说明安装时创建了，只是 Pod 不存在"
fi

echo ""
echo "可选组件："
echo "  ⚪ longhorn-csi-snapshotter (Deployment) - CSI 快照器（如果启用快照功能）"

echo ""
echo_info "要查看完整的清单，请运行："
echo "  helm template longhorn longhorn/longhorn --version $LONGHORN_VERSION --namespace longhorn-system | grep -E 'kind:|name:'"


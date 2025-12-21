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
WEBHOOK_DEPLOYMENT=$(grep -A 50 "kind: Deployment" "$TEMP_DIR/longhorn-manifest.yaml" | grep -B 5 -A 45 "admission-webhook" | head -50)
WEBHOOK_DAEMONSET=$(grep -A 50 "kind: DaemonSet" "$TEMP_DIR/longhorn-manifest.yaml" | grep -B 5 -A 45 "admission-webhook" | head -50)

if [ -n "$WEBHOOK_DEPLOYMENT" ] || [ -n "$WEBHOOK_DAEMONSET" ]; then
    echo_info "✓ 找到 admission-webhook 资源定义"
    if [ -n "$WEBHOOK_DEPLOYMENT" ]; then
        echo_info "  类型: Deployment"
        echo "$WEBHOOK_DEPLOYMENT" | grep -E "replicas:|enabled:" | head -5
    fi
    if [ -n "$WEBHOOK_DAEMONSET" ]; then
        echo_info "  类型: DaemonSet"
    fi
else
    echo_warn "✗ 未找到 admission-webhook 资源定义"
fi

# 检查 values 中是否有控制开关
echo ""
echo_step "5. 获取 Chart 默认 Values"
helm show values longhorn/longhorn --version "$LONGHORN_VERSION" > "$TEMP_DIR/values.yaml" 2>/dev/null || {
    echo_warn "无法获取 values，尝试查看本地 Chart"
}

if [ -f "$TEMP_DIR/values.yaml" ]; then
    echo_info "检查 admission-webhook 相关配置..."
    
    # 检查是否有 enabled 选项
    if grep -i "admission.*webhook" "$TEMP_DIR/values.yaml" | grep -i "enabled"; then
        echo_info "找到 admission-webhook 的 enabled 选项："
        grep -i "admission.*webhook" "$TEMP_DIR/values.yaml" | grep -i "enabled" | head -5
    else
        echo_info "未找到 admission-webhook 的 enabled 选项（可能默认启用且不可禁用）"
    fi
    
    # 检查其他相关配置
    echo ""
    echo_info "admission-webhook 相关配置："
    grep -i "admission.*webhook" "$TEMP_DIR/values.yaml" | head -20 || echo_warn "未找到相关配置"
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

if [ -n "$WEBHOOK_DEPLOYMENT" ] || [ -n "$WEBHOOK_DAEMONSET" ]; then
    echo "Webhook 组件："
    echo "  ✅ longhorn-admission-webhook (Deployment/DaemonSet) - 准入控制器"
    echo ""
    echo_warn "admission-webhook 是必需的组件，用于："
    echo "  - 验证和修改 Longhorn 资源"
    echo "  - 资源验证和默认值设置"
    echo "  - Manager 启动时需要访问此服务"
else
    echo_warn "未找到 admission-webhook 定义，可能在较新版本中有变化"
fi

echo ""
echo "可选组件："
echo "  ⚪ longhorn-csi-snapshotter (Deployment) - CSI 快照器（如果启用快照功能）"

echo ""
echo_info "要查看完整的清单，请运行："
echo "  helm template longhorn longhorn/longhorn --version $LONGHORN_VERSION --namespace longhorn-system | grep -E 'kind:|name:'"


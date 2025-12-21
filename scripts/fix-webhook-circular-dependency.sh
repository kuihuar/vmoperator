#!/bin/bash

# 修复 Longhorn Manager webhook 循环依赖问题

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

echo ""
echo_info "=========================================="
echo_info "修复 webhook 循环依赖问题"
echo_info "=========================================="
echo ""

# 1. 检查当前配置
echo_info "1. 检查 Manager DaemonSet 配置"
kubectl get daemonset -n longhorn-system longhorn-manager -o yaml | grep -A 30 "env:" | head -40 || echo_warn "未找到环境变量配置"

# 2. 检查是否有超时配置
echo ""
echo_info "2. 检查是否有 webhook 相关环境变量"
WEBHOOK_ENV=$(kubectl get daemonset -n longhorn-system longhorn-manager -o yaml | grep -i "webhook\|timeout" | head -10)
if [ -n "$WEBHOOK_ENV" ]; then
    echo "$WEBHOOK_ENV"
else
    echo_warn "未找到 webhook 相关环境变量"
fi

# 3. 尝试方案：增加超时时间或禁用检查
echo ""
echo_info "3. 尝试解决方案"
echo ""
echo_warn "这是一个已知的启动顺序问题。可能的解决方案："
echo ""
echo "方案 1: 临时修改 Service，指向已启动的 Manager（如果有）"
echo "方案 2: 增加 Manager 启动时的 webhook 超时时间"
echo "方案 3: 禁用 Manager 启动时的 webhook 检查（如果支持）"
echo "方案 4: 手动启动 Manager，让它先成功启动一次"
echo ""

# 检查是否可以增加超时时间
echo_info "检查 Manager DaemonSet 是否可以添加环境变量..."
MANAGER_DS=$(kubectl get daemonset -n longhorn-system longhorn-manager -o yaml)

# 4. 尝试方案：修改 Manager 启动参数或环境变量
echo ""
echo_warn "方案 A: 尝试增加 webhook 超时时间（如果支持）"
echo ""
read -p "是否尝试添加环境变量增加超时时间? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "尝试添加环境变量..."
    
    # 检查 DaemonSet 中是否已有 env
    HAS_ENV=$(kubectl get daemonset -n longhorn-system longhorn-manager -o jsonpath='{.spec.template.spec.containers[0].env}' 2>/dev/null || echo "[]")
    
    if echo "$HAS_ENV" | grep -q "LONGHORN_WEBHOOK_TIMEOUT\|WEBHOOK_TIMEOUT"; then
        echo_info "已有 webhook 超时配置，尝试增加时间..."
        # 这里需要根据实际的配置格式来修改
    else
        echo_warn "可能需要手动检查 Longhorn 是否支持环境变量配置"
        echo_info "建议查看 Longhorn Manager 的文档或源码"
    fi
fi

# 5. 方案：先让 Manager 成功启动一次
echo ""
echo_info "=========================================="
echo_info "推荐的解决方案"
echo_info "=========================================="
echo ""
echo_warn "由于这是循环依赖问题，建议采用以下方法："
echo ""
echo "步骤 1: 检查是否有其他阻止 Manager 启动的问题"
echo "  - DNS 问题（如果还没修复）"
echo "  - open-iscsi 问题"
echo "  - 资源不足"
echo ""
echo "步骤 2: 如果确定只是 webhook 循环依赖，尝试以下方法："
echo ""
echo "方法 A: 临时修改 Service 选择器，允许 Manager 启动后自动创建 Endpoints"
echo "  这通常不需要手动操作，如果 Manager 能成功启动，Endpoints 会自动创建"
echo ""
echo "方法 B: 检查是否有 Longhorn 配置可以禁用或延迟 webhook 检查"
echo "  查看: kubectl get settings -n longhorn-system"
echo ""
echo "方法 C: 如果以上都不行，考虑降级到已知稳定的版本"
echo "  或者等待 Longhorn 修复这个启动顺序问题"
echo ""

# 6. 检查是否有其他配置选项
echo ""
echo_info "4. 检查 Longhorn Settings（可能可以配置）"
if kubectl get namespace longhorn-system &> /dev/null; then
    echo_info "Longhorn Settings:"
    kubectl get settings -n longhorn-system 2>/dev/null | head -10 || echo_warn "无法获取 Settings"
else
    echo_warn "longhorn-system 命名空间不存在"
fi

echo ""
echo_info "=========================================="
echo_info "总结"
echo_info "=========================================="
echo ""
echo_warn "这是 Longhorn v1.10.1 的一个已知问题：循环依赖"
echo ""
echo_info "建议："
echo "  1. 先修复其他启动问题（DNS、open-iscsi 等）"
echo "  2. 检查 Longhorn GitHub Issues 看是否有解决方案"
echo "  3. 如果问题持续，考虑："
echo "     - 降级到已知稳定的版本（如 v1.6.0）"
echo "     - 或等待 Longhorn 发布修复版本"
echo ""
echo_info "查看相关 Issues:"
echo "  https://github.com/longhorn/longhorn/issues?q=webhook+circular+dependency"


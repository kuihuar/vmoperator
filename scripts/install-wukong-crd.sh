#!/bin/bash

# 安装 Wukong CRD

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
echo_info "安装 Wukong CRD"
echo_info "=========================================="
echo ""

# 1. 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo_error "kubectl 未安装"
    exit 1
fi

# 2. 检查 kustomize
if ! command -v kustomize &> /dev/null; then
    echo_warn "kustomize 未安装，尝试使用 make install"
    if ! command -v make &> /dev/null; then
        echo_error "make 也未安装，无法继续"
        exit 1
    fi
    
    echo_info "使用 make install 安装 CRD..."
    make install
    exit $?
fi

# 3. 检查 CRD 是否已存在
echo_info "1. 检查 CRD 是否已安装"
echo ""

if kubectl get crd wukongs.vm.novasphere.dev &>/dev/null; then
    echo_info "  ✓ Wukong CRD 已存在"
    echo ""
    read -p "是否重新安装? (y/n，默认n): " REINSTALL
    REINSTALL=${REINSTALL:-n}
    
    if [ "$REINSTALL" != "y" ]; then
        echo_info "  已取消，CRD 已存在"
        exit 0
    fi
else
    echo_info "  CRD 未安装，继续安装..."
fi

echo ""

# 4. 检查项目目录
echo_info "2. 检查项目目录"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$PROJECT_ROOT/config/crd" ]; then
    echo_error "  ✗ 未找到 config/crd 目录"
    echo_error "    请确保在项目根目录运行此脚本"
    exit 1
fi

echo_info "  项目根目录: $PROJECT_ROOT"
echo ""

# 5. 安装 CRD
echo_info "3. 安装 CRD"
echo ""

cd "$PROJECT_ROOT"

# 方法 1: 使用 kustomize
if command -v kustomize &> /dev/null; then
    echo_info "  使用 kustomize 构建并安装 CRD..."
    
    CRD_YAML=$(kustomize build config/crd 2>/dev/null || echo "")
    
    if [ -n "$CRD_YAML" ]; then
        echo "$CRD_YAML" | kubectl apply -f -
        echo_info "  ✓ CRD 已安装"
    else
        echo_warn "  ⚠️  kustomize build 未生成内容，尝试使用 make"
        make install
    fi
# 方法 2: 使用 make
elif command -v make &> /dev/null; then
    echo_info "  使用 make install 安装 CRD..."
    make install
else
    echo_error "  ✗ 无法找到 kustomize 或 make"
    exit 1
fi

echo ""

# 6. 验证安装
echo_info "4. 验证安装"
echo ""

sleep 2

if kubectl get crd wukongs.vm.novasphere.dev &>/dev/null; then
    echo_info "  ✓ Wukong CRD 已成功安装"
    echo ""
    echo_info "  CRD 详情:"
    kubectl get crd wukongs.vm.novasphere.dev
    echo ""
    
    # 检查 CRD 版本
    CRD_VERSION=$(kubectl get crd wukongs.vm.novasphere.dev -o jsonpath='{.spec.versions[*].name}' 2>/dev/null || echo "")
    if [ -n "$CRD_VERSION" ]; then
        echo_info "  支持的版本: $CRD_VERSION"
    fi
else
    echo_error "  ✗ CRD 安装失败或未找到"
    echo_warn "  请检查:"
    echo "    1. kubectl 是否可以访问集群"
    echo "    2. 是否有足够的权限"
    echo "    3. 查看错误信息: kubectl get crd wukongs.vm.novasphere.dev"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "安装完成"
echo_info "=========================================="
echo ""

echo_info "现在可以创建 Wukong 资源了:"
echo "  kubectl apply -f config/samples/vm_v1alpha1_wukong_ceph_test.yaml"
echo ""


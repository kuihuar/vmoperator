#!/bin/bash

# 启用 Ceph Dashboard

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
echo_info "启用 Ceph Dashboard"
echo_info "=========================================="
echo ""

# 1. 检查 CephCluster 是否存在
echo_info "1. 检查 CephCluster"
echo ""

CEPH_CLUSTER=$(kubectl get cephcluster rook-ceph -n rook-ceph 2>/dev/null)

if [ -z "$CEPH_CLUSTER" ]; then
    echo_error "  ✗ 未找到 CephCluster"
    echo_info "    请先安装 Ceph: ./scripts/install-ceph-rook.sh"
    exit 1
fi

echo_info "  ✓ CephCluster 存在"
echo ""

# 2. 检查 Dashboard 是否已启用
echo_info "2. 检查当前 Dashboard 状态"
echo ""

DASHBOARD_ENABLED=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.spec.dashboard.enabled}' 2>/dev/null || echo "false")

if [ "$DASHBOARD_ENABLED" = "true" ]; then
    echo_info "  ✓ Dashboard 已启用"
    echo_warn "  是否要重新配置? (y/n，默认n): "
    read -t 5 RE_CONFIG || RE_CONFIG="n"
    RE_CONFIG=${RE_CONFIG:-n}
    
    if [ "$RE_CONFIG" != "y" ]; then
        echo_info "  已取消，Dashboard 已启用"
        exit 0
    fi
else
    echo_warn "  ⚠️  Dashboard 未启用"
fi

echo ""

# 3. 选择访问方式
echo_info "3. 选择 Dashboard 访问方式"
echo ""
echo "  1. ClusterIP + 端口转发（默认，安全）"
echo "  2. NodePort（方便访问，但暴露端口）"
echo ""

read -p "选择访问方式 (1/2，默认1): " ACCESS_TYPE
ACCESS_TYPE=${ACCESS_TYPE:-1}

# 4. 更新 CephCluster 配置
echo_info "4. 更新 CephCluster 配置"
echo ""

if [ "$ACCESS_TYPE" = "2" ]; then
    # NodePort 方式
    echo_info "  配置为 NodePort 方式..."
    
    # 使用 patch 更新
    kubectl patch cephcluster rook-ceph -n rook-ceph --type='merge' -p '{
      "spec": {
        "dashboard": {
          "enabled": true,
          "port": 8443,
          "ssl": true
        }
      }
    }' 2>/dev/null || {
        echo_warn "  ⚠️  Patch 失败，尝试使用 kubectl edit"
        echo_info "  请手动编辑 CephCluster，添加以下配置:"
        echo ""
        echo "  spec:"
        echo "    dashboard:"
        echo "      enabled: true"
        echo "      port: 8443"
        echo "      ssl: true"
        echo ""
        read -p "按回车键继续编辑..." 
        kubectl edit cephcluster rook-ceph -n rook-ceph
    }
    
    echo_info "  ✓ 配置已更新（NodePort 方式）"
else
    # ClusterIP 方式（默认）
    echo_info "  配置为 ClusterIP 方式（默认）..."
    
    kubectl patch cephcluster rook-ceph -n rook-ceph --type='merge' -p '{
      "spec": {
        "dashboard": {
          "enabled": true,
          "port": 8443,
          "ssl": true
        }
      }
    }' 2>/dev/null || {
        echo_warn "  ⚠️  Patch 失败，尝试使用 kubectl edit"
        echo_info "  请手动编辑 CephCluster，添加以下配置:"
        echo ""
        echo "  spec:"
        echo "    dashboard:"
        echo "      enabled: true"
        echo "      port: 8443"
        echo "      ssl: true"
        echo ""
        read -p "按回车键继续编辑..." 
        kubectl edit cephcluster rook-ceph -n rook-ceph
    }
    
    echo_info "  ✓ 配置已更新（ClusterIP 方式）"
fi

echo ""

# 5. 等待 Dashboard 就绪
echo_info "5. 等待 Dashboard 就绪（60秒）..."
echo ""

for i in {1..12}; do
    DASHBOARD_SVC=$(kubectl get svc -n rook-ceph | grep dashboard || echo "")
    if [ -n "$DASHBOARD_SVC" ]; then
        echo_info "  ✓ Dashboard Service 已创建"
        break
    fi
    echo "  等待中... ($i/12)"
    sleep 5
done

echo ""

# 6. 如果选择 NodePort，修改 Service
if [ "$ACCESS_TYPE" = "2" ]; then
    echo_info "6. 修改 Service 为 NodePort"
    echo ""
    
    DASHBOARD_SVC_NAME=$(kubectl get svc -n rook-ceph | grep dashboard | awk '{print $1}' | head -1)
    
    if [ -n "$DASHBOARD_SVC_NAME" ]; then
        kubectl patch svc "$DASHBOARD_SVC_NAME" -n rook-ceph -p '{"spec":{"type":"NodePort"}}' 2>/dev/null && \
            echo_info "  ✓ Service 已修改为 NodePort" || \
            echo_warn "  ⚠️  修改 Service 失败，请手动修改"
    else
        echo_warn "  ⚠️  未找到 Dashboard Service"
    fi
    
    echo ""
fi

# 7. 获取登录凭据
echo_info "7. 获取登录凭据"
echo ""

sleep 10  # 等待 Secret 创建

DASHBOARD_USER=$(kubectl get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.user}' 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
DASHBOARD_PASS=$(kubectl get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "$DASHBOARD_PASS" ]; then
    echo_info "  ✓ 登录凭据:"
    echo "    用户名: $DASHBOARD_USER"
    echo "    密码: $DASHBOARD_PASS"
else
    echo_warn "  ⚠️  无法获取密码，可能需要等待更长时间"
    echo_info "    稍后运行: kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath='{.data.password}' | base64 --decode && echo"
fi

echo ""

# 8. 显示访问信息
echo_info "=========================================="
echo_info "Dashboard 访问信息"
echo_info "=========================================="
echo ""

if [ "$ACCESS_TYPE" = "2" ]; then
    # NodePort
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
    NODE_PORT=$(kubectl get svc -n rook-ceph | grep dashboard | awk '{print $5}' | cut -d':' -f2 | cut -d'/' -f1 || echo "")
    
    if [ -n "$NODE_PORT" ]; then
        echo_info "✓ Dashboard 已启用（NodePort 方式）"
        echo ""
        echo "  访问地址: https://$NODE_IP:$NODE_PORT"
        echo "  用户名: $DASHBOARD_USER"
        echo "  密码: $DASHBOARD_PASS"
        echo ""
        echo_warn "  注意: 浏览器可能会显示证书警告，这是正常的（使用自签名证书）"
    else
        echo_warn "⚠️  NodePort 尚未分配，请稍后检查:"
        echo "  kubectl get svc -n rook-ceph | grep dashboard"
    fi
else
    # ClusterIP + 端口转发
    echo_info "✓ Dashboard 已启用（ClusterIP 方式）"
    echo ""
    echo "  访问方法:"
    echo "    1. 在终端运行:"
    echo "       kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443"
    echo ""
    echo "    2. 在浏览器访问:"
    echo "       https://localhost:8443"
    echo ""
    echo "  登录凭据:"
    echo "    用户名: $DASHBOARD_USER"
    echo "    密码: $DASHBOARD_PASS"
    echo ""
    echo_warn "  注意: 浏览器可能会显示证书警告，这是正常的（使用自签名证书）"
fi

echo ""


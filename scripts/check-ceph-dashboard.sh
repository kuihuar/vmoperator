#!/bin/bash

# 检查并配置 Ceph Dashboard

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
echo_info "检查 Ceph Dashboard"
echo_info "=========================================="
echo ""

# 1. 检查 CephCluster 配置中的 Dashboard
echo_info "1. 检查 CephCluster Dashboard 配置"
echo ""

DASHBOARD_ENABLED=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.spec.dashboard.enabled}' 2>/dev/null || echo "false")

if [ "$DASHBOARD_ENABLED" = "true" ]; then
    echo_info "  ✓ Dashboard 已启用"
    
    # 检查 Dashboard URL
    DASHBOARD_URL=$(kubectl get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.dashboardURL}' 2>/dev/null || echo "")
    if [ -n "$DASHBOARD_URL" ]; then
        echo_info "  Dashboard URL: $DASHBOARD_URL"
    fi
else
    echo_warn "  ⚠️  Dashboard 未启用"
fi

echo ""

# 2. 检查 Dashboard Service
echo_info "2. 检查 Dashboard Service"
echo ""

DASHBOARD_SVC=$(kubectl get svc -n rook-ceph | grep dashboard || echo "")

if [ -n "$DASHBOARD_SVC" ]; then
    echo_info "  ✓ Dashboard Service 存在:"
    echo "$DASHBOARD_SVC"
    echo ""
    
    # 获取 Service 详情
    SVC_NAME=$(echo "$DASHBOARD_SVC" | awk '{print $1}')
    SVC_TYPE=$(echo "$DASHBOARD_SVC" | awk '{print $2}')
    SVC_IP=$(echo "$DASHBOARD_SVC" | awk '{print $3}')
    SVC_PORT=$(echo "$DASHBOARD_SVC" | awk '{print $5}' | cut -d'/' -f1)
    
    echo_info "  Service 详情:"
    echo "    名称: $SVC_NAME"
    echo "    类型: $SVC_TYPE"
    echo "    IP: $SVC_IP"
    echo "    端口: $SVC_PORT"
    echo ""
    
    if [ "$SVC_TYPE" = "NodePort" ]; then
        NODE_PORT=$(echo "$DASHBOARD_SVC" | awk '{print $5}' | cut -d':' -f2 | cut -d'/' -f1)
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
        echo_info "  ✓ Dashboard 可通过 NodePort 访问:"
        echo "    http://$NODE_IP:$NODE_PORT"
    elif [ "$SVC_TYPE" = "LoadBalancer" ]; then
        EXTERNAL_IP=$(kubectl get svc "$SVC_NAME" -n rook-ceph -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$EXTERNAL_IP" ]; then
            echo_info "  ✓ Dashboard 可通过 LoadBalancer 访问:"
            echo "    http://$EXTERNAL_IP:$SVC_PORT"
        else
            echo_warn "  ⚠️  LoadBalancer IP 尚未分配"
        fi
    else
        echo_info "  Dashboard 类型: $SVC_TYPE（需要端口转发或 Ingress）"
    fi
else
    echo_warn "  ⚠️  未找到 Dashboard Service"
fi

echo ""

# 3. 检查 Dashboard Pod
echo_info "3. 检查 Dashboard Pod"
echo ""

DASHBOARD_POD=$(kubectl get pods -n rook-ceph | grep dashboard || echo "")

if [ -n "$DASHBOARD_POD" ]; then
    echo_info "  ✓ Dashboard Pod 存在:"
    echo "$DASHBOARD_POD"
else
    echo_warn "  ⚠️  未找到 Dashboard Pod"
fi

echo ""

# 4. 获取 Dashboard 登录凭据
echo_info "4. 获取 Dashboard 登录凭据"
echo ""

# 尝试从 Secret 获取用户名和密码
DASHBOARD_USER=$(kubectl get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.user}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
DASHBOARD_PASS=$(kubectl get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "$DASHBOARD_USER" ] && [ -n "$DASHBOARD_PASS" ]; then
    echo_info "  ✓ 找到登录凭据:"
    echo "    用户名: $DASHBOARD_USER"
    echo "    密码: $DASHBOARD_PASS"
else
    echo_warn "  ⚠️  未找到登录凭据 Secret"
    echo_info "    默认用户名通常是: admin"
    echo_info "    密码可以通过以下命令获取:"
    echo "      kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath=\"{.data.password}\" | base64 --decode && echo"
fi

echo ""

# 5. 提供访问方法
echo_info "5. Dashboard 访问方法"
echo ""

if [ "$DASHBOARD_ENABLED" = "true" ]; then
    echo_info "  如果 Dashboard 是 ClusterIP，可以使用以下方法访问:"
    echo ""
    echo "  方法 1: 端口转发（推荐）"
    echo "    kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443"
    echo "    然后访问: https://localhost:8443"
    echo ""
    echo "  方法 2: 修改 Service 为 NodePort"
    echo "    kubectl patch svc rook-ceph-mgr-dashboard -n rook-ceph -p '{\"spec\":{\"type\":\"NodePort\"}}'"
    echo "    然后查看端口: kubectl get svc -n rook-ceph rook-ceph-mgr-dashboard"
    echo ""
else
    echo_info "  需要启用 Dashboard，运行:"
    echo "    ./scripts/enable-ceph-dashboard.sh"
fi

echo ""

# 6. 总结
echo_info "=========================================="
echo_info "总结"
echo_info "=========================================="
echo ""

if [ "$DASHBOARD_ENABLED" = "true" ]; then
    echo_info "✓ Ceph Dashboard 已启用"
    echo ""
    echo_info "快速访问（使用端口转发）:"
    echo "  1. kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443"
    echo "  2. 浏览器访问: https://localhost:8443"
    echo "  3. 使用上面显示的凭据登录"
else
    echo_warn "⚠️  Ceph Dashboard 未启用"
    echo_info "运行以下命令启用:"
    echo "  ./scripts/enable-ceph-dashboard.sh"
fi


#!/bin/bash

# 访问 Longhorn UI

HOST_IP="${1:-0.0.0.0}"
PORT="${2:-8080}"

echo "=== 访问 Longhorn UI ==="
echo ""

# 1. 检查 Longhorn UI Service
echo "1. 检查 Longhorn UI Service..."
if ! kubectl get svc -n longhorn-system longhorn-frontend &>/dev/null; then
    echo "❌ longhorn-frontend Service 不存在"
    exit 1
fi

echo "✓ longhorn-frontend Service 存在"
echo ""

# 2. 检查端口是否被占用
echo "2. 检查端口 $PORT 是否被占用..."
if lsof -i :$PORT &>/dev/null || netstat -an | grep -q ":$PORT.*LISTEN" 2>/dev/null; then
    echo "⚠️  端口 $PORT 已被占用"
    echo "请使用其他端口或停止占用该端口的进程"
    exit 1
fi

echo "✓ 端口 $PORT 可用"
echo ""

# 3. 启动 port-forward
echo "3. 启动 port-forward..."
echo "绑定地址: $HOST_IP:$PORT"
echo "访问地址: http://$HOST_IP:$PORT"
echo ""
echo "如果 HOST_IP 是 0.0.0.0，可以通过以下地址访问:"
echo "  - http://localhost:$PORT"
echo "  - http://127.0.0.1:$PORT"
echo "  - http://192.168.1.141:$PORT (宿主机 IP)"
echo ""
echo "按 Ctrl+C 停止 port-forward"
echo ""

# 启动 port-forward
if [ "$HOST_IP" = "0.0.0.0" ]; then
    kubectl port-forward -n longhorn-system svc/longhorn-frontend --address $HOST_IP $PORT:80
else
    kubectl port-forward -n longhorn-system svc/longhorn-frontend $HOST_IP:$PORT:80
fi


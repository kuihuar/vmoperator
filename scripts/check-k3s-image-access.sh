#!/bin/bash

# 检查 k3s 环境中镜像 HTTP 源的访问性

echo "=== k3s 镜像访问检查 ==="

# 1. 获取虚拟机 IP
VM_IP=$(hostname -I | awk '{print $1}')
echo "1. 虚拟机 IP 地址: $VM_IP"

# 2. 检查 HTTP 服务器是否在运行
echo -e "\n2. 检查 HTTP 服务器 (端口 8080):"
if curl -s -I "http://${VM_IP}:8080/images/noble-server-cloudimg-amd64.img" > /dev/null 2>&1; then
    echo "   ✓ HTTP 服务器可访问"
    curl -I "http://${VM_IP}:8080/images/noble-server-cloudimg-amd64.img" 2>&1 | head -1
else
    echo "   ✗ HTTP 服务器不可访问"
    echo "   请确保:"
    echo "   - HTTP 服务器正在运行: python3 -m http.server 8080 --bind 0.0.0.0"
    echo "   - 镜像文件存在于正确路径: ~/images/noble-server-cloudimg-amd64.img"
fi

# 3. 检查 StorageClass
echo -e "\n3. 检查 k3s StorageClass:"
kubectl get storageclass 2>/dev/null | grep -E "NAME|local-path" || echo "   ⚠ 未找到 local-path StorageClass"

# 4. 在 Pod 中测试访问（如果集群可用）
if kubectl get nodes > /dev/null 2>&1; then
    echo -e "\n4. 在 Pod 中测试访问:"
    echo "   正在创建测试 Pod..."
    kubectl run -it --rm test-image-access-$$ \
        --image=curlimages/curl \
        --restart=Never \
        -- curl -I "http://${VM_IP}:8080/images/noble-server-cloudimg-amd64.img" 2>&1 | head -5
    
    if [ $? -eq 0 ]; then
        echo "   ✓ Pod 可以访问 HTTP 服务器"
    else
        echo "   ✗ Pod 无法访问 HTTP 服务器"
        echo "   可能原因:"
        echo "   - 防火墙阻止了连接"
        echo "   - HTTP 服务器只监听 localhost（应该监听 0.0.0.0）"
        echo "   - Pod 网络无法访问宿主机 IP"
    fi
else
    echo -e "\n4. 跳过 Pod 测试（集群不可用）"
fi

# 5. 检查防火墙
echo -e "\n5. 检查防火墙状态:"
if command -v ufw > /dev/null 2>&1; then
    sudo ufw status | head -5
    echo "   如果需要，允许 8080 端口:"
    echo "   sudo ufw allow from 10.42.0.0/16 to any port 8080"
elif command -v firewall-cmd > /dev/null 2>&1; then
    sudo firewall-cmd --list-all | grep -E "ports|services" || echo "   防火墙未配置或使用其他工具"
else
    echo "   未检测到常见防火墙工具"
fi

# 6. 显示配置建议
echo -e "\n=== 配置建议 ==="
echo "在 Wukong YAML 中使用:"
echo "  image: \"http://${VM_IP}:8080/images/noble-server-cloudimg-amd64.img\""
echo ""
echo "StorageClass:"
echo "  storageClassName: local-path"
echo ""
echo "如果 Pod 无法访问，尝试:"
echo "  1. 确保 HTTP 服务器监听 0.0.0.0: python3 -m http.server 8080 --bind 0.0.0.0"
echo "  2. 检查防火墙: sudo ufw allow 8080/tcp"
echo "  3. 检查 k3s Pod 网段: kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}'"


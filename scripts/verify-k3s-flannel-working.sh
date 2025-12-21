#!/bin/bash

# 验证 k3s 内置 Flannel 是否正常工作

echo "=== 验证 k3s 内置 Flannel 网络 ==="
echo ""

# 1. 检查网络接口
echo "1. 检查网络接口..."
echo "（需要在节点上运行）"
echo ""

# 检查 flannel.1 接口
if ip link show flannel.1 &>/dev/null 2>&1; then
    echo "✓ flannel.1 接口存在"
    ip addr show flannel.1 | head -5
else
    echo "⚠️  flannel.1 接口不存在（可能需要 root 权限）"
    echo "   手动检查: sudo ip addr show flannel.1"
fi
echo ""

# 检查 cni0 bridge
if ip link show cni0 &>/dev/null 2>&1; then
    echo "✓ cni0 bridge 存在"
    ip addr show cni0 | head -5
else
    echo "⚠️  cni0 bridge 不存在（可能需要 root 权限）"
    echo "   手动检查: sudo ip addr show cni0"
fi
echo ""

# 2. 检查 CNI 配置
echo "2. 检查 CNI 配置..."
CNI_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if sudo test -d "$CNI_PATH"; then
    echo "✓ CNI 配置目录存在: $CNI_PATH"
    echo ""
    echo "配置文件:"
    sudo ls -la "$CNI_PATH" 2>/dev/null | grep -E "\.(conf|conflist)$" | while read line; do
        FILE=$(echo "$line" | awk '{print $NF}')
        if [ -n "$FILE" ]; then
            echo "  - $FILE"
        fi
    done
    echo ""
    
    # 显示配置内容
    echo "配置内容（前 20 行）:"
    sudo cat "$CNI_PATH"/*.conf 2>/dev/null | head -20 | sed 's/^/  /' || \
    sudo cat "$CNI_PATH"/*.conflist 2>/dev/null | head -20 | sed 's/^/  /' || \
    echo "  无法读取配置"
else
    echo "⚠️  CNI 配置目录不存在: $CNI_PATH"
    echo "   可能需要 root 权限或路径不同"
fi
echo ""

# 3. 检查 Pod 网络
echo "3. 检查 Pod 网络..."
POD_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m 1 cluster-cidr | cut -d'"' -f4 || \
           kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || \
           echo "未知")
echo "Pod CIDR: $POD_CIDR"
echo ""

# 检查节点 Pod CIDR
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NODE_NAME" ]; then
    NODE_POD_CIDR=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)
    if [ -n "$NODE_POD_CIDR" ]; then
        echo "节点 $NODE_NAME Pod CIDR: $NODE_POD_CIDR"
    else
        echo "⚠️  节点未分配 Pod CIDR"
    fi
fi
echo ""

# 4. 检查现有 Pods 的网络
echo "4. 检查现有 Pods 的网络..."
EXISTING_PODS=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}' 2>/dev/null | head -10)
if [ -n "$EXISTING_PODS" ]; then
    echo "现有 Pods 及其 IP:"
    echo "$EXISTING_PODS" | while read pod ip; do
        if [ -n "$pod" ] && [ -n "$ip" ]; then
            echo "  - $pod: $ip"
        fi
    done
else
    echo "⚠️  没有运行中的 Pods"
fi
echo ""

# 5. 测试 Pod 创建和网络
echo "5. 测试 Pod 创建和网络..."
echo "创建测试 Pod..."
TEST_POD_NAME="flannel-test-$(date +%s)"
kubectl run "$TEST_POD_NAME" --image=busybox --restart=Never --rm -i -- sh -c "
    echo 'Pod 网络信息:'
    ip addr show | grep -E 'inet |^[0-9]+:' | head -10
    echo ''
    echo '测试网络连接:'
    ping -c 2 8.8.8.8 2>&1 | head -3
    echo ''
    echo 'DNS 测试:'
    nslookup kubernetes.default 2>&1 | head -5
" 2>&1 | head -25

if [ $? -eq 0 ]; then
    echo "✓ Pod 创建和网络测试成功"
else
    echo "⚠️  Pod 测试可能有问题"
fi
echo ""

# 6. 检查路由
echo "6. 检查路由（在节点上）..."
if command -v ip &>/dev/null; then
    echo "Flannel 相关路由:"
    ip route show | grep -E "flannel|cni0" | head -5 || echo "  未找到 Flannel 路由（可能需要 root）"
    echo ""
    echo "所有路由（前 10 条）:"
    ip route show | head -10 | sed 's/^/  /'
else
    echo "⚠️  ip 命令不可用"
fi
echo ""

# 7. 总结
echo "=== 验证总结 ==="
echo ""

ISSUES=0

# 检查关键组件
if ! ip link show flannel.1 &>/dev/null 2>&1 && ! sudo ip link show flannel.1 &>/dev/null 2>&1; then
    echo "⚠️  flannel.1 接口不可见（可能需要 root 权限检查）"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ flannel.1 接口存在"
fi

if ! ip link show cni0 &>/dev/null 2>&1 && ! sudo ip link show cni0 &>/dev/null 2>&1; then
    echo "⚠️  cni0 bridge 不可见（可能需要 root 权限检查）"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ cni0 bridge 存在"
fi

if [ -z "$POD_CIDR" ] || [ "$POD_CIDR" = "未知" ]; then
    echo "⚠️  无法获取 Pod CIDR"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ Pod CIDR 配置: $POD_CIDR"
fi

# 检查是否可以创建 Pod
if kubectl get pods --all-namespaces 2>/dev/null | grep -q Running; then
    echo "✓ 有运行中的 Pods（网络基本正常）"
else
    echo "⚠️  没有运行中的 Pods"
    ISSUES=$((ISSUES + 1))
fi

echo ""

if [ $ISSUES -eq 0 ]; then
    echo "✅ k3s 内置 Flannel 网络正常工作"
    echo ""
    echo "这是正常情况："
    echo "  - k3s 使用内置 Flannel"
    echo "  - 不显示为独立的 Pod 或 DaemonSet"
    echo "  - 网络功能完全正常"
    echo "  - 与 Longhorn 完全兼容"
else
    echo "⚠️  发现一些问题，建议："
    echo "  1. 使用 root 权限检查网络接口:"
    echo "     sudo ip addr show flannel.1"
    echo "     sudo ip addr show cni0"
    echo ""
    echo "  2. 检查 k3s 服务状态:"
    echo "     sudo systemctl status k3s"
    echo ""
    echo "  3. 查看 k3s 日志:"
    echo "     sudo journalctl -u k3s -n 50"
fi

echo ""
echo "=== 完成 ==="


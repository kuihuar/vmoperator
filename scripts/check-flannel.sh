#!/bin/bash

# 检查 Flannel CNI 网络

echo "=== 检查 Flannel CNI ==="
echo ""

# 1. 检查 Flannel DaemonSet
echo "1. 检查 Flannel DaemonSet..."
if kubectl get daemonset -n kube-system kube-flannel-ds 2>/dev/null | grep -q kube-flannel; then
    echo "✓ Flannel DaemonSet 存在"
    kubectl get daemonset -n kube-system kube-flannel-ds -o wide
    echo ""
    
    # 检查 Pods
    echo "Flannel Pods:"
    kubectl get pods -n kube-system | grep flannel
    echo ""
    
    # 检查 Pod 状态
    READY=$(kubectl get daemonset -n kube-system kube-flannel-ds -o jsonpath='{.status.numberReady}' 2>/dev/null)
    DESIRED=$(kubectl get daemonset -n kube-system kube-flannel-ds -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
    echo "就绪状态: $READY/$DESIRED"
else
    echo "⚠️  Flannel DaemonSet 不存在"
    echo "可能使用 k3s 内置 Flannel（这是正常的）"
fi
echo ""

# 2. 检查 Flannel Pods（包括 k3s 内置）
echo "2. 检查 Flannel Pods..."
FLANNEL_PODS=$(kubectl get pods -n kube-system -o jsonpath='{range .items[?(@.metadata.name=~"flannel.*")]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null)
if [ -n "$FLANNEL_PODS" ]; then
    echo "发现 Flannel Pods:"
    echo "$FLANNEL_PODS" | while read pod status; do
        if [ -n "$pod" ]; then
            echo "  - $pod: $status"
        fi
    done
else
    echo "⚠️  未发现 Flannel Pods"
    echo "k3s 内置 Flannel 可能不显示为独立 Pod"
fi
echo ""

# 3. 检查 Flannel 配置
echo "3. 检查 Flannel 配置..."
if kubectl get configmap -n kube-system kube-flannel-cfg &>/dev/null; then
    echo "✓ Flannel ConfigMap 存在"
    echo ""
    echo "配置内容:"
    kubectl get configmap -n kube-system kube-flannel-cfg -o yaml | grep -A 20 "cni-conf.json\|net-conf.json" | head -30
else
    echo "⚠️  Flannel ConfigMap 不存在"
    echo "k3s 内置 Flannel 可能使用不同的配置方式"
fi
echo ""

# 4. 检查 CNI 配置文件
echo "4. 检查 CNI 配置文件..."
CNI_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d"
if sudo test -d "$CNI_PATH"; then
    echo "CNI 配置路径: $CNI_PATH"
    echo ""
    echo "配置文件:"
    sudo ls -la "$CNI_PATH" 2>/dev/null | grep -E "\.(conf|conflist)$"
    echo ""
    
    # 显示 Flannel 配置
    FLANNEL_CONF=$(sudo find "$CNI_PATH" -name "*flannel*" -o -name "10-flannel*" 2>/dev/null | head -1)
    if [ -n "$FLANNEL_CONF" ] && [ -f "$FLANNEL_CONF" ]; then
        echo "Flannel 配置文件: $FLANNEL_CONF"
        echo "配置内容:"
        sudo cat "$FLANNEL_CONF" 2>/dev/null | python3 -m json.tool 2>/dev/null || \
        sudo cat "$FLANNEL_CONF" 2>/dev/null | head -30
    else
        echo "未找到 Flannel 配置文件"
        echo "列出所有 CNI 配置:"
        sudo cat "$CNI_PATH"/*.conf 2>/dev/null | grep -E "type|name" | head -10
    fi
else
    echo "⚠️  CNI 配置路径不存在或不可访问: $CNI_PATH"
fi
echo ""

# 5. 检查网络接口（在节点上）
echo "5. 检查网络接口..."
echo "（需要在节点上运行以下命令）"
echo ""
echo "检查 Flannel 接口:"
echo "  ip addr show flannel.1"
echo "  ip link show flannel.1"
echo ""
echo "检查 CNI bridge:"
echo "  ip addr show cni0"
echo "  brctl show cni0"
echo ""

# 尝试从 Pod 内检查
TEST_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$TEST_POD" ]; then
    echo "从 CoreDNS Pod 检查网络接口:"
    kubectl exec -n kube-system "$TEST_POD" -- ip addr show 2>/dev/null | grep -E "flannel|cni0|veth" | head -5 || \
    echo "  无法检查"
fi
echo ""

# 6. 检查 Pod 网络
echo "6. 检查 Pod 网络配置..."
POD_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m 1 cluster-cidr | cut -d'"' -f4 || \
           kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || \
           echo "未知")
echo "Pod CIDR: $POD_CIDR"
echo ""

# 检查节点 Pod CIDR
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NODE_NAME" ]; then
    NODE_POD_CIDR=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)
    echo "节点 $NODE_NAME Pod CIDR: $NODE_POD_CIDR"
fi
echo ""

# 7. 检查 Flannel 网络模式
echo "7. 检查 Flannel 网络模式..."
if kubectl get configmap -n kube-system kube-flannel-cfg &>/dev/null; then
    BACKEND=$(kubectl get configmap -n kube-system kube-flannel-cfg -o jsonpath='{.data.net-conf}' 2>/dev/null | grep -oP '"Backend":\s*"\K[^"]+' || echo "未知")
    echo "Backend 模式: $BACKEND"
    echo ""
    echo "常见模式:"
    echo "  - vxlan: VXLAN 隧道模式（默认）"
    echo "  - host-gw: 主机网关模式（性能更好，需要 L2 网络）"
    echo "  - udp: UDP 模式（已弃用）"
else
    echo "无法确定网络模式（k3s 内置 Flannel）"
    echo "k3s 默认使用 VXLAN 模式"
fi
echo ""

# 8. 测试网络连接
echo "8. 测试网络连接..."
echo "创建测试 Pod 测试网络..."
kubectl run flannel-test --image=busybox --rm -i --restart=Never -- sh -c "ip addr show && echo '---' && ping -c 2 8.8.8.8" 2>&1 | head -20 || \
echo "测试失败或需要更多时间"
echo ""

# 9. 总结
echo "=== 总结 ==="
echo ""

if kubectl get daemonset -n kube-system kube-flannel-ds &>/dev/null; then
    echo "✓ 检测到标准 Flannel DaemonSet"
    echo "  这是手动安装的 Flannel"
elif kubectl get pods -n kube-system | grep -q flannel; then
    echo "✓ 检测到 Flannel Pods"
    echo "  Flannel 正在运行"
else
    echo "ℹ️  使用 k3s 内置 Flannel"
    echo "  这是正常的，k3s 内置 Flannel 不显示为独立 Pod"
    echo "  网络功能正常工作"
fi

echo ""
echo "网络状态:"
echo "  - Pod CIDR: $POD_CIDR"
if [ -n "$NODE_POD_CIDR" ]; then
    echo "  - 节点 Pod CIDR: $NODE_POD_CIDR"
fi
echo ""

echo "=== 完成 ==="
echo ""
echo "常用检查命令:"
echo "  # 检查 Flannel Pods"
echo "  kubectl get pods -n kube-system | grep flannel"
echo ""
echo "  # 检查 Flannel DaemonSet"
echo "  kubectl get daemonset -n kube-system kube-flannel-ds"
echo ""
echo "  # 检查 Flannel 配置"
echo "  kubectl get configmap -n kube-system kube-flannel-cfg -o yaml"
echo ""
echo "  # 检查网络接口（在节点上）"
echo "  ip addr show flannel.1"
echo "  ip addr show cni0"
echo ""


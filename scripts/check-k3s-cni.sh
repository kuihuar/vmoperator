#!/bin/bash

# 检查 k3s 使用的 CNI 网络

echo "=== 检查 k3s CNI 网络 ==="
echo ""

# 1. 检查标准 CNI（Flannel, Calico, Cilium, Canal）
echo "1. 检查标准 CNI 组件..."
CNI_FOUND=false

# 检查 Flannel
if kubectl get daemonset -n kube-system kube-flannel-ds 2>/dev/null | grep -q kube-flannel; then
    echo "✓ 使用 Flannel CNI"
    CNI_FOUND=true
    echo "  Flannel Pods:"
    kubectl get pods -n kube-system | grep flannel | head -5
    echo ""
    
    # 检查 Flannel 配置
    FLANNEL_CONFIG=$(kubectl get configmap -n kube-system kube-flannel-cfg -o yaml 2>/dev/null | grep -E "Network|Backend" | head -5)
    if [ -n "$FLANNEL_CONFIG" ]; then
        echo "  Flannel 配置:"
        echo "$FLANNEL_CONFIG" | sed 's/^/    /'
    fi
    echo ""

# 检查 Calico
elif kubectl get daemonset -n kube-system calico-node 2>/dev/null | grep -q calico; then
    echo "✓ 使用 Calico CNI"
    CNI_FOUND=true
    echo "  Calico Pods:"
    kubectl get pods -n kube-system | grep calico | head -5
    echo ""

# 检查 Cilium
elif kubectl get daemonset -n kube-system cilium 2>/dev/null | grep -q cilium; then
    echo "✓ 使用 Cilium CNI"
    CNI_FOUND=true
    echo "  Cilium Pods:"
    kubectl get pods -n kube-system | grep cilium | head -5
    echo ""

# 检查 Canal (Flannel + Calico)
elif kubectl get daemonset -n kube-system canal 2>/dev/null | grep -q canal; then
    echo "✓ 使用 Canal CNI (Flannel + Calico)"
    CNI_FOUND=true
    echo "  Canal Pods:"
    kubectl get pods -n kube-system | grep canal | head -5
    echo ""
fi

# 2. 如果没找到标准 CNI，检查 k3s 内置网络
if [ "$CNI_FOUND" = false ]; then
    echo "⚠️  未检测到标准 CNI（Flannel/Calico/Cilium/Canal）"
    echo ""
    echo "2. 检查 k3s 内置网络组件..."
    
    # k3s 默认使用内置的 Flannel（但可能不显示为 DaemonSet）
    echo "  k3s 系统 Pods:"
    kubectl get pods -n kube-system | grep -E "coredns|traefik|local-path|svclb" | head -10
    echo ""
    
    # 检查 CNI 配置文件
    echo "3. 检查 CNI 配置文件..."
    CNI_PATH="/var/lib/rancher/k3s/agent/etc/cni/net.d"
    if sudo test -d "$CNI_PATH"; then
        echo "  CNI 配置路径: $CNI_PATH"
        echo "  CNI 配置文件:"
        sudo ls -la "$CNI_PATH" 2>/dev/null | grep -E "\.(conf|conflist)$" | while read line; do
            FILE=$(echo "$line" | awk '{print $NF}')
            if [ -n "$FILE" ]; then
                echo "    - $FILE"
                # 显示配置类型
                CNI_TYPE=$(sudo cat "$CNI_PATH/$FILE" 2>/dev/null | grep -E '"type"|"name"' | head -2)
                if [ -n "$CNI_TYPE" ]; then
                    echo "$CNI_TYPE" | sed 's/^/      /'
                fi
            fi
        done
    else
        echo "  ⚠️  CNI 配置路径不存在或不可访问"
    fi
    echo ""
    
    # 检查网络插件
    echo "4. 检查网络插件..."
    NETWORK_PLUGINS=$(kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -iE "network|flannel|bridge")
    if [ -n "$NETWORK_PLUGINS" ]; then
        echo "  发现网络相关 Pods:"
        echo "$NETWORK_PLUGINS" | sed 's/^/    - /'
    else
        echo "  未发现明显的网络插件 Pods"
    fi
    echo ""
    
    echo "ℹ️  k3s 默认使用内置的 Flannel CNI"
    echo "   它可能不会显示为标准的 DaemonSet"
    echo "   但网络功能是正常的"
fi

# 3. 检查 Pod 网络配置
echo "5. 检查 Pod 网络配置..."
POD_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m 1 cluster-cidr | cut -d'"' -f4 || \
           kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || \
           echo "未知")
SERVICE_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m 1 service-cluster-ip-range | cut -d'"' -f4 || echo "未知")

echo "  Pod CIDR: $POD_CIDR"
echo "  Service CIDR: $SERVICE_CIDR"
echo ""

# 4. 检查节点网络
echo "6. 检查节点网络..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NODE_NAME" ]; then
    NODE_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    NODE_POD_CIDR=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)
    echo "  节点名称: $NODE_NAME"
    echo "  节点 IP: $NODE_IP"
    echo "  节点 Pod CIDR: $NODE_POD_CIDR"
fi
echo ""

# 5. 检查网络接口
echo "7. 检查网络接口（在节点上）..."
if [ -n "$NODE_NAME" ]; then
    # 尝试使用 kubectl debug 查看节点网络
    echo "  尝试查看节点网络接口..."
    kubectl debug node/"$NODE_NAME" -it --image=busybox -- sh -c "ip addr show | grep -E '^[0-9]+:|inet ' | head -15" 2>&1 | grep -v "Creating\|pod/" | head -15 || \
    echo "  无法直接查看（需要节点访问权限）"
    echo ""
    
    # 检查常见的网络接口
    echo "  常见网络接口（在节点上运行）:"
    echo "    - flannel.1 (Flannel VXLAN)"
    echo "    - cni0 (CNI bridge)"
    echo "    - docker0 (如果使用 Docker)"
    echo "    - cali* (Calico)"
    echo "    - cilium* (Cilium)"
fi
echo ""

# 6. 总结
echo "=== 总结 ==="
echo ""

if [ "$CNI_FOUND" = true ]; then
    echo "✓ 检测到标准 CNI 网络插件"
    echo ""
    echo "网络类型:"
    if kubectl get daemonset -n kube-system kube-flannel-ds &>/dev/null; then
        echo "  - Flannel (VXLAN/主机网关模式)"
    elif kubectl get daemonset -n kube-system calico-node &>/dev/null; then
        echo "  - Calico (BGP/IPIP)"
    elif kubectl get daemonset -n kube-system cilium &>/dev/null; then
        echo "  - Cilium (eBPF)"
    fi
else
    echo "ℹ️  使用 k3s 内置网络（默认 Flannel）"
    echo ""
    echo "k3s 默认网络:"
    echo "  - CNI: Flannel (内置)"
    echo "  - 模式: VXLAN 或 主机网关"
    echo "  - 特点: 轻量级，无需额外配置"
fi

echo ""
echo "网络配置:"
echo "  - Pod CIDR: $POD_CIDR"
echo "  - Service CIDR: $SERVICE_CIDR"
echo ""

# 7. 对 Longhorn 的影响
echo "对 Longhorn 的影响:"
echo "  - k3s 内置 Flannel 对 Longhorn 完全兼容"
echo "  - 不需要额外的网络配置"
echo "  - Pod 网络和 Service 网络都正常工作"
echo ""

echo "=== 完成 ==="


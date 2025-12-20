#!/bin/bash

# 访问虚拟机的工具脚本

echo "=== 访问虚拟机 ==="

# 1. 检查 VM 和 VMI
echo -e "\n1. 检查 VM 和 VMI 状态..."
kubectl get vm
kubectl get vmi

# 获取 VMI 名称
VMI_NAME=$(kubectl get vmi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$VMI_NAME" ]; then
    echo "❌ 未找到 VMI，VM 可能还未启动"
    exit 1
fi

echo "VMI 名称: $VMI_NAME"

# 2. 检查 virtctl 是否安装
echo -e "\n2. 检查 virtctl 是否安装..."
if command -v virtctl &> /dev/null; then
    echo "✓ virtctl 已安装"
    VIRTCTL_VERSION=$(virtctl version --client 2>/dev/null | head -1)
    echo "  版本: $VIRTCTL_VERSION"
else
    echo "⚠️  virtctl 未安装"
    echo ""
    echo "安装 virtctl:"
    echo "  1. 下载: https://github.com/kubevirt/kubevirt/releases"
    echo "  2. 或使用: kubectl krew install virt"
    echo "  3. 或运行: ./scripts/install-virtctl.sh"
    exit 1
fi

# 3. 检查 VM 网络配置
echo -e "\n3. 检查 VM 网络配置..."
VMI_IP=$(kubectl get vmi "$VMI_NAME" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null)
if [ -n "$VMI_IP" ]; then
    echo "✓ VM IP 地址: $VMI_IP"
else
    echo "⚠️  VM IP 地址未分配（可能还在启动中）"
fi

# 4. 检查 SSH 配置
echo -e "\n4. 检查 SSH 配置..."
WUKONG_NAME=$(kubectl get wukong -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$WUKONG_NAME" ]; then
    SSH_KEY=$(kubectl get wukong "$WUKONG_NAME" -o jsonpath='{.spec.sshKeySecret}' 2>/dev/null)
    if [ -n "$SSH_KEY" ]; then
        echo "✓ Wukong 配置了 SSH Key Secret: $SSH_KEY"
        echo "  可以尝试 SSH 连接"
    else
        echo "⚠️  Wukong 未配置 SSH Key Secret"
        echo "  需要配置 SSH 才能使用 SSH 连接"
    fi
else
    echo "⚠️  未找到 Wukong 资源"
fi

# 5. 提供访问方法
echo -e "\n=== 访问虚拟机的方法 ==="
echo ""
echo "方法 1: 使用 virtctl console（控制台）"
echo "  命令: virtctl console $VMI_NAME"
echo "  说明: 连接到 VM 的控制台（类似物理机的串口）"
echo "  退出: 按 Ctrl+] 或输入 'quit'"
echo ""

echo "方法 2: 使用 virtctl ssh（SSH，如果配置了 SSH）"
if [ -n "$VMI_IP" ]; then
    echo "  命令: virtctl ssh $VMI_NAME"
    echo "  或: ssh -i ~/.ssh/id_rsa ubuntu@$VMI_IP"
    echo "  说明: 通过 SSH 连接到 VM"
else
    echo "  需要先获取 VM IP 地址"
fi
echo ""

echo "方法 3: 使用 VNC（图形界面，如果 VM 有图形界面）"
echo "  命令: virtctl vnc $VMI_NAME"
echo "  说明: 打开 VNC 查看器连接到 VM 的图形界面"
echo ""

echo "方法 4: 使用 kubectl exec（进入 virt-launcher Pod，不是 VM 内部）"
LAUNCHER_POD=$(kubectl get pods -o jsonpath='{.items[?(@.metadata.labels.kubevirt\.io/domain=="'$VMI_NAME'")].metadata.name}' 2>/dev/null)
if [ -n "$LAUNCHER_POD" ]; then
    echo "  Pod: $LAUNCHER_POD"
    echo "  命令: kubectl exec -it $LAUNCHER_POD -- /bin/bash"
    echo "  说明: 进入 virt-launcher Pod（不是 VM 内部）"
else
    echo "  未找到 virt-launcher Pod"
fi
echo ""

# 6. 快速访问
echo "=== 快速访问 ==="
echo ""
read -p "是否现在连接到 VM 控制台？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "连接到 VM 控制台..."
    echo "提示: 按 Ctrl+] 退出"
    virtctl console "$VMI_NAME"
fi

echo ""
echo "=== 完成 ==="


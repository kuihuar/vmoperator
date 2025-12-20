#!/bin/bash

# 在节点上安装 open-iscsi（Longhorn 必需）

set -e

echo "=== 安装 open-iscsi ==="
echo ""
echo "Longhorn 需要 open-iscsi 工具才能正常工作"
echo "此脚本需要在每个节点上运行"
echo ""

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "❌ 无法检测操作系统"
    exit 1
fi

echo "检测到操作系统: $OS $VER"
echo ""

# 安装 open-iscsi
case $OS in
    ubuntu|debian)
        echo "使用 apt 安装 open-iscsi..."
        sudo apt-get update
        sudo apt-get install -y open-iscsi
        ;;
    centos|rhel|rocky|almalinux)
        echo "使用 yum 安装 iscsi-initiator-utils..."
        sudo yum install -y iscsi-initiator-utils
        ;;
    fedora)
        echo "使用 dnf 安装 iscsi-initiator-utils..."
        sudo dnf install -y iscsi-initiator-utils
        ;;
    *)
        echo "⚠️  未识别的操作系统: $OS"
        echo "请手动安装 open-iscsi 或 iscsi-initiator-utils"
        exit 1
        ;;
esac

# 验证安装
echo ""
echo "验证安装..."
if command -v iscsiadm &> /dev/null; then
    echo "✓ iscsiadm 已安装"
    iscsiadm --version
else
    echo "❌ iscsiadm 未找到"
    exit 1
fi

# 启动服务（如果需要）
if systemctl list-units --type=service | grep -q iscsid; then
    echo ""
    echo "启动 iscsid 服务..."
    sudo systemctl enable iscsid
    sudo systemctl start iscsid
    sudo systemctl status iscsid --no-pager | head -5
fi

echo ""
echo "=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 在所有节点上运行此脚本"
echo "  2. 重启 longhorn-manager Pod:"
echo "     kubectl delete pod -n longhorn-system -l app=longhorn-manager"
echo "  3. 等待 Pod 重新创建并检查状态:"
echo "     kubectl get pods -n longhorn-system"


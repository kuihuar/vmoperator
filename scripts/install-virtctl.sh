#!/bin/bash

# 安装 virtctl 工具

echo "=== 安装 virtctl 工具 ==="

# 1. 检查是否已安装
if command -v virtctl &> /dev/null; then
    echo "✓ virtctl 已安装"
    virtctl version --client
    exit 0
fi

# 2. 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "❌ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
echo "系统: $OS $ARCH"

# 3. 获取 KubeVirt 版本
echo -e "\n获取 KubeVirt 版本..."
KUBEVIRT_VERSION=$(kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.observedKubeVirtVersion}' 2>/dev/null)
if [ -z "$KUBEVIRT_VERSION" ]; then
    echo "⚠️  无法获取 KubeVirt 版本，使用默认版本 v1.2.0"
    KUBEVIRT_VERSION="v1.2.0"
else
    echo "KubeVirt 版本: $KUBEVIRT_VERSION"
    # 移除可能的 + 后缀
    KUBEVIRT_VERSION=${KUBEVIRT_VERSION%+*}
fi

# 4. 下载 virtctl
echo -e "\n下载 virtctl..."
DOWNLOAD_URL="https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-${OS}-${ARCH}"
echo "URL: $DOWNLOAD_URL"

# 创建临时目录
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# 下载
if command -v curl &> /dev/null; then
    curl -L -o virtctl "$DOWNLOAD_URL" || {
        echo "❌ 下载失败"
        echo "请手动下载: $DOWNLOAD_URL"
        exit 1
    }
elif command -v wget &> /dev/null; then
    wget -O virtctl "$DOWNLOAD_URL" || {
        echo "❌ 下载失败"
        echo "请手动下载: $DOWNLOAD_URL"
        exit 1
    }
else
    echo "❌ 需要 curl 或 wget 来下载"
    exit 1
fi

# 5. 安装
echo -e "\n安装 virtctl..."
chmod +x virtctl
sudo mv virtctl /usr/local/bin/ || mv virtctl ~/.local/bin/ || {
    echo "⚠️  无法移动到系统目录，请手动安装:"
    echo "  sudo mv $TMP_DIR/virtctl /usr/local/bin/"
    exit 1
}

# 6. 验证
echo -e "\n验证安装..."
if command -v virtctl &> /dev/null; then
    echo "✓ virtctl 安装成功"
    virtctl version --client
else
    echo "❌ virtctl 安装失败"
    exit 1
fi

# 清理
rm -rf "$TMP_DIR"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "使用方法:"
echo "  virtctl console <vmi-name>    # 连接到 VM 控制台"
echo "  virtctl ssh <vmi-name>        # SSH 连接到 VM"
echo "  virtctl vnc <vmi-name>        # VNC 连接到 VM"


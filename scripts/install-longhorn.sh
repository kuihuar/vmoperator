#!/bin/bash

# Longhorn 安装脚本（支持 Helm 和 kubectl 两种方式）

set -e

INSTALL_METHOD="${1:-kubectl}"  # kubectl 或 helm
LONGHORN_VERSION_INPUT="${2:-latest}"  # latest 或具体版本如 v1.6.0

# 获取版本
if [ "$LONGHORN_VERSION_INPUT" = "latest" ]; then
    echo "获取最新 Longhorn 版本..."
    LONGHORN_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
    if [ -z "$LONGHORN_VERSION" ]; then
        echo "⚠️  无法获取最新版本，使用默认版本 v1.6.0"
        LONGHORN_VERSION="v1.6.0"
    else
        echo "✓ 最新版本: $LONGHORN_VERSION"
    fi
else
    LONGHORN_VERSION="$LONGHORN_VERSION_INPUT"
fi

echo "=== 安装 Longhorn 存储 ==="
echo "安装方式: $INSTALL_METHOD"
echo "版本: $LONGHORN_VERSION"
echo ""

# 1. 检查前置要求
echo "1. 检查前置要求..."

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装"
    exit 1
fi
echo "✓ kubectl 已安装"

# 检查集群
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到 Kubernetes 集群"
    exit 1
fi
echo "✓ 集群连接正常"

# 检查 open-iscsi
if ! command -v iscsiadm &> /dev/null; then
    echo "⚠️  iscsiadm 未安装（Longhorn 需要）"
    echo ""
    read -p "是否自动安装 open-iscsi? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y open-iscsi
            sudo systemctl enable iscsid
            sudo systemctl start iscsid
        elif command -v yum &> /dev/null; then
            sudo yum install -y iscsi-initiator-utils
            sudo systemctl enable iscsid
            sudo systemctl start iscsid
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y iscsi-initiator-utils
            sudo systemctl enable iscsid
            sudo systemctl start iscsid
        else
            echo "❌ 无法自动安装，请手动安装 open-iscsi 或 iscsi-initiator-utils"
            exit 1
        fi
        echo "✓ open-iscsi 已安装"
    else
        echo "❌ 需要安装 open-iscsi 才能继续"
        exit 1
    fi
else
    echo "✓ iscsiadm 已安装"
fi
echo ""

# 2. 根据安装方式安装
if [ "$INSTALL_METHOD" = "helm" ]; then
    echo "2. 使用 Helm 安装 Longhorn..."
    
    # 检查 Helm
    if ! command -v helm &> /dev/null; then
        echo "❌ Helm 未安装"
        echo "安装 Helm:"
        echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        exit 1
    fi
    echo "✓ Helm 已安装"
    
    # 添加 Helm 仓库
    echo "添加 Longhorn Helm 仓库..."
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo update
    
    # 检查是否已安装
    if helm list -n longhorn-system | grep -q longhorn; then
        echo "⚠️  Longhorn 已通过 Helm 安装"
        read -p "是否升级? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            HELM_VERSION=$(echo "$LONGHORN_VERSION" | sed 's/^v//')
            helm upgrade longhorn longhorn/longhorn \
                --namespace longhorn-system \
                --version "$HELM_VERSION" \
                --create-namespace
        else
            echo "已取消"
            exit 0
        fi
    else
    # 安装 Longhorn
    # Helm 版本需要移除 v 前缀
    HELM_VERSION=$(echo "$LONGHORN_VERSION" | sed 's/^v//')
    echo "安装 Longhorn (Helm Chart 版本: $HELM_VERSION)..."
    helm install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --create-namespace \
        --version "$HELM_VERSION"
        echo "✓ Longhorn Helm Chart 已安装"
    fi
    
elif [ "$INSTALL_METHOD" = "kubectl" ]; then
    echo "2. 使用 kubectl 安装 Longhorn..."
    
    # 检查是否已安装
    if kubectl get namespace longhorn-system &>/dev/null; then
        echo "⚠️  longhorn-system 命名空间已存在"
        read -p "是否继续安装（可能会更新现有安装）? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已取消"
            exit 0
        fi
    fi
    
    # 安装 Longhorn
    echo "应用 Longhorn 清单..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml
    echo "✓ Longhorn 清单已应用"
    
else
    echo "❌ 不支持的安装方式: $INSTALL_METHOD"
    echo "支持的方式: kubectl 或 helm"
    exit 1
fi
echo ""

# 3. 等待 Longhorn 就绪
echo "3. 等待 Longhorn 就绪..."
echo "（这可能需要几分钟）"

MAX_WAIT=600  # 最多等待 10 分钟
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    READY_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL_PODS=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$READY_PODS" -gt 0 ] && [ "$READY_PODS" -eq "$TOTAL_PODS" ]; then
        echo "✓ Longhorn Manager 已就绪"
        break
    fi
    
    echo "  [$(date +%H:%M:%S)] 等待中... ($READY_PODS/$TOTAL_PODS pods ready)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时，请检查 Longhorn 状态:"
    echo "  kubectl get pods -n longhorn-system"
    exit 1
fi
echo ""

# 4. 验证 StorageClass
echo "4. 验证 StorageClass..."

sleep 5  # 等待 StorageClass 创建

if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ Longhorn StorageClass 已创建"
    
    # 检查是否支持扩展
    ALLOW_EXPANSION=$(kubectl get storageclass longhorn -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" = "true" ]; then
        echo "✓ 支持卷扩展"
    else
        echo "⚠️  不支持卷扩展"
    fi
else
    echo "⚠️  Longhorn StorageClass 未找到，等待创建..."
    sleep 10
    if kubectl get storageclass longhorn &>/dev/null; then
        echo "✓ Longhorn StorageClass 已创建"
    else
        echo "❌ Longhorn StorageClass 创建失败"
        echo "请检查: kubectl get storageclass"
    fi
fi
echo ""

# 5. 检查 CSI Driver
echo "5. 检查 CSI Driver..."
sleep 5

if kubectl get csidriver driver.longhorn.io &>/dev/null; then
    echo "✓ CSI Driver 已安装"
else
    echo "⚠️  CSI Driver 未找到，等待安装..."
    sleep 10
    if kubectl get csidriver driver.longhorn.io &>/dev/null; then
        echo "✓ CSI Driver 已安装"
    else
        echo "⚠️  CSI Driver 可能还在安装中，请稍后检查"
    fi
fi
echo ""

# 6. 显示状态
echo "6. Longhorn 组件状态:"
kubectl get pods -n longhorn-system | head -15

echo ""
echo "7. StorageClass 列表:"
kubectl get storageclass

echo ""
echo "=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 配置磁盘（如果使用自定义路径）:"
echo "     ./scripts/configure-longhorn-disk.sh /mnt/longhorn"
echo ""
echo "  2. 单节点配置（如果是单节点）:"
echo "     ./scripts/configure-longhorn-single-node.sh"
echo ""
echo "  3. 在 Wukong 中使用:"
echo "     storageClassName: longhorn"
echo ""
echo "  4. 访问 Longhorn UI:"
echo "     kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
echo "     然后访问: http://192.168.1.141:8088"
echo ""
echo "  5. 查看详细文档:"
echo "     docs/LONGHORN_INSTALLATION_GUIDE.md"
echo ""


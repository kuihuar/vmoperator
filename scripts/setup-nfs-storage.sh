#!/bin/bash

# 安装 NFS StorageClass（推荐用于中小规模生产环境）

set -e

echo "=== 安装 NFS StorageClass ==="

# 1. 检查参数
NFS_SERVER="${1:-}"
NFS_PATH="${2:-/mnt/nfs-share}"

if [ -z "$NFS_SERVER" ]; then
    echo "用法: $0 <nfs-server-ip> [nfs-path]"
    echo ""
    echo "示例:"
    echo "  $0 192.168.1.100 /mnt/nfs-share"
    echo ""
    echo "注意: 需要先配置 NFS 服务器"
    exit 1
fi

echo "NFS 服务器: $NFS_SERVER"
echo "NFS 路径: $NFS_PATH"
echo ""

# 2. 检查 Helm
if ! command -v helm &> /dev/null; then
    echo "❌ Helm 未安装"
    echo "安装 Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo "✓ Helm 已安装"
echo ""

# 3. 检查集群状态
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到 Kubernetes 集群"
    exit 1
fi

echo "✓ 集群连接正常"
echo ""

# 4. 添加 Helm 仓库
echo "1. 添加 Helm 仓库..."
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

echo "✓ Helm 仓库已添加"
echo ""

# 5. 安装 NFS Provisioner
echo "2. 安装 NFS Provisioner..."

helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server="$NFS_SERVER" \
  --set nfs.path="$NFS_PATH" \
  --set storageClass.defaultClass=true \
  --set storageClass.allowVolumeExpansion=true \
  --namespace nfs-provisioner \
  --create-namespace

echo "✓ NFS Provisioner 安装完成"
echo ""

# 6. 等待就绪
echo "3. 等待 NFS Provisioner 就绪..."

MAX_WAIT=300  # 最多等待 5 分钟
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $MAX_WAIT ]; do
    READY=$(kubectl get pods -n nfs-provisioner -l app=nfs-subdir-external-provisioner --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$READY" -gt 0 ]; then
        echo "✓ NFS Provisioner 已就绪"
        break
    fi
    
    echo "  [$(date +%H:%M:%S)] 等待中..."
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时，请检查状态:"
    echo "  kubectl get pods -n nfs-provisioner"
    exit 1
fi

# 7. 验证 StorageClass
echo ""
echo "4. 验证 StorageClass..."

sleep 5  # 等待 StorageClass 创建

if kubectl get storageclass nfs-client &>/dev/null; then
    echo "✓ NFS StorageClass 已创建"
    
    # 检查是否支持扩展
    ALLOW_EXPANSION=$(kubectl get storageclass nfs-client -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
    if [ "$ALLOW_EXPANSION" = "true" ]; then
        echo "✓ 支持卷扩展"
    else
        echo "⚠️  不支持卷扩展（可能需要手动配置）"
    fi
    
    # 检查是否为默认 StorageClass
    IS_DEFAULT=$(kubectl get storageclass nfs-client -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
    if [ "$IS_DEFAULT" = "true" ]; then
        echo "✓ 已设置为默认 StorageClass"
    else
        echo "ℹ️  未设置为默认 StorageClass"
        echo "  可以在 Wukong 中明确指定: storageClassName: nfs-client"
    fi
else
    echo "⚠️  NFS StorageClass 未找到"
    echo "请检查: kubectl get storageclass"
fi

# 8. 显示状态
echo ""
echo "5. NFS Provisioner 状态:"
kubectl get pods -n nfs-provisioner

echo ""
echo "6. StorageClass 列表:"
kubectl get storageclass

echo ""
echo "=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 在 Wukong 中使用 NFS StorageClass:"
echo "     storageClassName: nfs-client"
echo ""
echo "  2. 测试创建 PVC:"
echo "     kubectl apply -f - <<EOF"
echo "     apiVersion: v1"
echo "     kind: PersistentVolumeClaim"
echo "     metadata:"
echo "       name: test-pvc"
echo "     spec:"
echo "       storageClassName: nfs-client"
echo "       accessModes:"
echo "         - ReadWriteOnce"
echo "       resources:"
echo "         requests:"
echo "           storage: 1Gi"
echo "     EOF"


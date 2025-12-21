#!/bin/bash

# Longhorn 完整卸载和重新安装脚本

set -e

INSTALL_METHOD="${1:-kubectl}"  # kubectl 或 helm
LONGHORN_VERSION_INPUT="${2:-latest}"  # latest 或具体版本如 v1.6.0
DISK_PATH="${3:-/mnt/longhorn}"  # 或 /var/lib/longhorn

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

echo "=== Longhorn 完整卸载和重新安装 ==="
echo "安装方式: $INSTALL_METHOD"
echo "版本: $LONGHORN_VERSION"
echo "磁盘路径: $DISK_PATH"
echo ""
echo "注意: 使用最新版本可以避免老版本的已知问题"
echo ""

# 确认
read -p "确定要卸载并重新安装 Longhorn 吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# ========== 第一部分：卸载 ==========
echo "========== 第一部分：卸载现有 Longhorn =========="
echo ""

# 1. 检查当前状态
echo "1. 检查当前状态..."
if kubectl get namespace longhorn-system &>/dev/null; then
    echo "发现 longhorn-system 命名空间"
    kubectl get pods -n longhorn-system | head -10
else
    echo "未发现 longhorn-system 命名空间，可能已卸载"
fi
echo ""

# 2. 删除所有 PVC
echo "2. 删除所有使用 longhorn 的 PVC..."
PVC_COUNT=0
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    PVC_NAMES=$(kubectl get pvc -n "$ns" -o jsonpath='{range .items[?(@.spec.storageClassName=="longhorn")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    for pvc in $PVC_NAMES; do
        if [ -n "$pvc" ]; then
            echo "  删除 $ns/$pvc..."
            kubectl delete pvc -n "$ns" "$pvc" --ignore-not-found=true
            PVC_COUNT=$((PVC_COUNT + 1))
        fi
    done
done

if [ $PVC_COUNT -gt 0 ]; then
    echo "等待 PVC 删除完成..."
    sleep 10
    echo "✓ 已删除 $PVC_COUNT 个 PVC"
else
    echo "✓ 没有需要删除的 PVC"
fi
echo ""

# 3. 删除 Longhorn Volumes
echo "3. 删除 Longhorn Volumes..."
if kubectl get crd volumes.longhorn.io &>/dev/null; then
    VOLUME_COUNT=$(kubectl get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$VOLUME_COUNT" -gt 0 ]; then
        kubectl get volumes.longhorn.io -n longhorn-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
        while read volume; do
            if [ -n "$volume" ]; then
                echo "  删除 Volume: $volume"
                kubectl delete volumes.longhorn.io -n longhorn-system "$volume" --ignore-not-found=true
            fi
        done
        echo "等待 Volumes 删除完成..."
        sleep 30
        echo "✓ 已删除 Volumes"
    else
        echo "✓ 没有需要删除的 Volumes"
    fi
else
    echo "✓ Volumes CRD 不存在"
fi
echo ""

# 4. 卸载 Longhorn
echo "4. 卸载 Longhorn..."
if [ "$INSTALL_METHOD" = "helm" ]; then
    if helm list -n longhorn-system 2>/dev/null | grep -q longhorn; then
        echo "使用 Helm 卸载..."
        helm uninstall longhorn -n longhorn-system --ignore-not-found=true
        echo "✓ Helm 卸载完成"
    else
        echo "未发现 Helm 安装"
    fi
else
    echo "使用 kubectl 卸载..."
    # 尝试使用已知版本卸载，如果失败则尝试最新版本
    if ! kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml --ignore-not-found=true 2>/dev/null; then
        echo "尝试使用最新版本卸载..."
        LATEST_VER=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
        if [ -n "$LATEST_VER" ]; then
            kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${LATEST_VER}/deploy/longhorn.yaml --ignore-not-found=true 2>/dev/null || true
        fi
    fi
    echo "✓ kubectl 卸载完成"
fi
echo ""

# 5. 删除命名空间
echo "5. 删除命名空间..."
kubectl delete namespace longhorn-system --ignore-not-found=true --timeout=120s
echo "等待命名空间删除..."
sleep 10
echo "✓ 命名空间已删除"
echo ""

# 6. 清理 CRD
echo "6. 清理 CRD..."
LONGHORN_CRDS=$(kubectl get crd 2>/dev/null | grep longhorn | awk '{print $1}' || true)
if [ -n "$LONGHORN_CRDS" ]; then
    echo "$LONGHORN_CRDS" | while read crd; do
        if [ -n "$crd" ]; then
            echo "  删除 CRD: $crd"
            kubectl delete crd "$crd" --ignore-not-found=true
        fi
    done
    echo "等待 CRD 删除..."
    sleep 10
    echo "✓ CRD 已清理"
else
    echo "✓ 没有需要清理的 CRD"
fi
echo ""

# 7. 清理本地数据（可选）
echo "7. 清理本地数据..."
read -p "是否清理本地 Longhorn 数据? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "/var/lib/longhorn" ]; then
        BACKUP_DIR="/var/lib/longhorn.backup.$(date +%Y%m%d_%H%M%S)"
        echo "备份 /var/lib/longhorn 到 $BACKUP_DIR..."
        sudo mv /var/lib/longhorn "$BACKUP_DIR" 2>/dev/null || true
        echo "✓ 已备份"
    fi
    
    if [ -d "$DISK_PATH" ] && [ "$DISK_PATH" != "/var/lib/longhorn" ]; then
        echo "清理 $DISK_PATH..."
        sudo rm -rf "$DISK_PATH/longhorn-disk.cfg" 2>/dev/null || true
        sudo rm -rf "$DISK_PATH/replicas" 2>/dev/null || true
        sudo rm -rf "$DISK_PATH/engine-binaries" 2>/dev/null || true
        echo "✓ 已清理（保留挂载点）"
    fi
else
    echo "跳过清理本地数据"
fi
echo ""

# 8. 验证卸载
echo "8. 验证卸载..."
if kubectl get namespace longhorn-system &>/dev/null; then
    echo "⚠️  命名空间仍存在"
else
    echo "✓ 命名空间已删除"
fi

REMAINING_CRDS=$(kubectl get crd 2>/dev/null | grep longhorn | wc -l | tr -d ' ')
if [ "$REMAINING_CRDS" -eq 0 ]; then
    echo "✓ CRD 已删除"
else
    echo "⚠️  仍有 $REMAINING_CRDS 个 CRD 未删除"
fi
echo ""

# ========== 第二部分：重新安装 ==========
echo "========== 第二部分：重新安装 Longhorn =========="
echo ""

# 1. 检查前置要求
echo "1. 检查前置要求..."
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装"
    exit 1
fi
echo "✓ kubectl 已安装"

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到集群"
    exit 1
fi
echo "✓ 集群连接正常"

if ! command -v iscsiadm &> /dev/null; then
    echo "❌ iscsiadm 未安装"
    echo "安装: sudo apt-get install -y open-iscsi"
    exit 1
fi
echo "✓ iscsiadm 已安装"

if ! sudo systemctl is-active --quiet iscsid; then
    echo "启动 iscsid 服务..."
    sudo systemctl enable iscsid
    sudo systemctl start iscsid
fi
echo "✓ iscsid 服务运行中"
echo ""

# 2. 准备磁盘路径
echo "2. 准备磁盘路径..."
if [ ! -d "$DISK_PATH" ]; then
    echo "创建路径: $DISK_PATH"
    sudo mkdir -p "$DISK_PATH"
fi
sudo chmod 755 "$DISK_PATH"
echo "✓ 路径就绪: $DISK_PATH"
echo ""

# 3. 安装 Longhorn
echo "3. 安装 Longhorn..."
if [ "$INSTALL_METHOD" = "helm" ]; then
    if ! command -v helm &> /dev/null; then
        echo "安装 Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo update
    
    HELM_VERSION=$(echo "$LONGHORN_VERSION" | sed 's/^v//')
    helm install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --create-namespace \
        --version "$HELM_VERSION"
    echo "✓ Helm 安装完成"
else
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml
    echo "✓ kubectl 安装完成"
fi
echo ""

# 4. 等待 Manager 就绪
echo "4. 等待 Longhorn Manager 就绪..."
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s
echo "✓ Manager 已就绪"
echo ""

# 5. 等待 CSI Driver
echo "5. 等待 CSI Driver 安装..."
MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS=$(kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Succeeded" ]; then
        echo "✓ driver-deployer 已完成"
        break
    elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Error" ]; then
        echo "❌ driver-deployer 失败"
        kubectl logs -n longhorn-system -l app=longhorn-driver-deployer --all-containers=true --tail=20
        exit 1
    fi
    echo "  等待中... ($ELAPSED/$MAX_WAIT 秒) - 状态: $STATUS"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  等待超时，但继续..."
fi

sleep 5

if kubectl get csidriver driver.longhorn.io &>/dev/null; then
    echo "✓ CSI Driver 已安装"
else
    echo "⚠️  CSI Driver 未安装，可能需要更多时间"
fi
echo ""

# 6. 验证 StorageClass
echo "6. 验证 StorageClass..."
sleep 10
if kubectl get storageclass longhorn &>/dev/null; then
    echo "✓ StorageClass 已创建"
    kubectl get storageclass longhorn
else
    echo "⚠️  StorageClass 未找到"
fi
echo ""

# 7. 配置磁盘
echo "7. 配置磁盘..."
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "节点名称: $NODE_NAME"

# 等待 Node 资源
echo "等待 Longhorn Node 资源创建..."
echo "（这可能需要几分钟，Manager 需要发现节点）"
echo ""

# 使用专门的等待脚本
if [ -f "./scripts/wait-for-longhorn-node.sh" ]; then
    ./scripts/wait-for-longhorn-node.sh "$NODE_NAME" 300
else
    # 备用等待逻辑
    ELAPSED=0
    MAX_WAIT=300
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
            echo "✓ Node 资源已创建"
            break
        fi
        echo "  等待中... ($ELAPSED/$MAX_WAIT 秒)"
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "⚠️  等待超时，Node 资源仍未创建"
        echo "继续尝试配置（可能会失败）..."
    fi
fi

# 再次检查
if ! kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" &>/dev/null; then
    echo ""
    echo "❌ Node 资源仍未创建"
    echo ""
    echo "诊断:"
    echo "  1. 检查 Manager 状态:"
    echo "     kubectl get pods -n longhorn-system -l app=longhorn-manager"
    echo ""
    echo "  2. 检查 Manager 日志:"
    echo "     kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50"
    echo ""
    echo "  3. 手动等待后重试:"
    echo "     ./scripts/wait-for-longhorn-node.sh $NODE_NAME"
    echo ""
    echo "  4. 或跳过磁盘配置，稍后手动配置"
    read -p "是否继续（跳过磁盘配置）? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 1
    fi
    echo "跳过磁盘配置，稍后可以手动配置"
    echo ""
    exit 0
fi
echo ""

DISK_NAME="data-disk"
if [ "$DISK_PATH" = "/var/lib/longhorn" ]; then
    DISK_NAME="default-disk"
fi

kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type merge -p "{
  \"spec\": {
    \"disks\": {
      \"$DISK_NAME\": {
        \"allowScheduling\": true,
        \"evictionRequested\": false,
        \"path\": \"$DISK_PATH\",
        \"storageReserved\": 0,
        \"tags\": []
      }
    }
  }
}"
echo "✓ 磁盘配置已应用"
echo ""

# 8. 等待磁盘就绪
echo "8. 等待磁盘就绪..."
for i in {1..60}; do
    DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o jsonpath="{.status.diskStatus.$DISK_NAME.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
    if [ "$DISK_STATUS" = "True" ]; then
        echo "✓ 磁盘已就绪"
        break
    fi
    echo "  等待中... ($i/60)"
    sleep 2
done
echo ""

# 9. 测试 PVC
echo "9. 测试 PVC 创建..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

echo "等待 PVC 绑定..."
for i in {1..60}; do
    STATUS=$(kubectl get pvc test-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Bound" ]; then
        echo "✓ PVC 已绑定"
        kubectl get pvc test-pvc
        break
    fi
    echo "  等待中... ($i/60) - 状态: $STATUS"
    sleep 2
done
echo ""

# 10. 清理测试 PVC
echo "10. 清理测试 PVC..."
kubectl delete pvc test-pvc --ignore-not-found=true
echo "✓ 测试完成"
echo ""

# 11. 最终状态
echo "========== 最终状态 =========="
echo ""
echo "Longhorn 组件:"
kubectl get pods -n longhorn-system | head -15
echo ""
echo "StorageClass:"
kubectl get storageclass longhorn
echo ""
echo "CSI Driver:"
kubectl get csidriver driver.longhorn.io 2>/dev/null || echo "CSI Driver 可能还在安装中"
echo ""

echo "=== 安装完成 ==="
echo ""
echo "下一步:"
echo "  1. 在 Wukong 中使用: storageClassName: longhorn"
echo "  2. 访问 Longhorn UI:"
echo "     kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8088:80"
echo ""


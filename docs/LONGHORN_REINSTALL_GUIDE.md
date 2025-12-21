# Longhorn 卸载和重新安装指南

## 概述

本指南提供完整的 Longhorn 卸载和重新安装流程，每一步都包含验证步骤，确保安装成功。

**重要提示**: 推荐使用最新版本（`latest`）以避免老版本的已知问题，如 `driver-deployer` Init 容器卡住等问题。

## 第一部分：卸载现有 Longhorn

### 步骤 1: 检查当前 Longhorn 状态

```bash
# 1.1 检查 Longhorn 命名空间
kubectl get namespace longhorn-system

# 1.2 检查 Longhorn Pods
kubectl get pods -n longhorn-system

# 1.3 检查 Longhorn 资源
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get nodes.longhorn.io -n longhorn-system

# 1.4 检查 PVC 和 PV
kubectl get pvc --all-namespaces
kubectl get pv
```

**验证**: 记录当前状态，了解需要清理的资源。

### 步骤 2: 删除所有使用 Longhorn 的 PVC

```bash
# 2.1 查找所有使用 longhorn StorageClass 的 PVC
kubectl get pvc --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.storageClassName == "longhorn") | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace name; do
    if [ -n "$namespace" ] && [ -n "$name" ]; then
      echo "删除 $namespace/$name..."
      kubectl delete pvc -n "$namespace" "$name"
    fi
  done

# 如果没有 jq，使用以下命令
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get pvc -n "$ns" -o jsonpath='{range .items[?(@.spec.storageClassName=="longhorn")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | \
  while read name; do
    if [ -n "$name" ]; then
      echo "删除 $ns/$name..."
      kubectl delete pvc -n "$ns" "$name"
    fi
  done
done
```

**验证**:
```bash
# 等待 PVC 删除完成
sleep 10

# 检查是否还有 PVC
kubectl get pvc --all-namespaces | grep longhorn
# 应该返回空或只有正在删除的 PVC
```

### 步骤 3: 删除所有 Longhorn Volumes

```bash
# 3.1 获取所有 Longhorn Volumes
kubectl get volumes.longhorn.io -n longhorn-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
  while read volume; do
    if [ -n "$volume" ]; then
      echo "删除 Volume: $volume"
      kubectl delete volumes.longhorn.io -n longhorn-system "$volume"
    fi
  done

# 3.2 等待删除完成
echo "等待 Volumes 删除完成..."
sleep 30
```

**验证**:
```bash
kubectl get volumes.longhorn.io -n longhorn-system
# 应该返回: No resources found
```

### 步骤 4: 卸载 Longhorn（根据安装方式）

#### 方法 A: 如果使用 kubectl apply 安装

```bash
# 4.1 删除 Longhorn 清单
LONGHORN_VERSION="v1.6.0"  # 使用安装时的版本
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml

# 4.2 如果上面的命令失败，手动删除资源
kubectl delete crd -l app.kubernetes.io/name=longhorn
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=longhorn
kubectl delete namespace longhorn-system
```

#### 方法 B: 如果使用 Helm 安装

```bash
# 4.1 卸载 Longhorn
helm uninstall longhorn -n longhorn-system

# 4.2 删除命名空间
kubectl delete namespace longhorn-system
```

**验证**:
```bash
# 检查命名空间是否删除
kubectl get namespace longhorn-system
# 应该返回: Error from server (NotFound): namespaces "longhorn-system" not found

# 检查 CRD 是否删除
kubectl get crd | grep longhorn
# 应该返回空或只有正在删除的 CRD
```

### 步骤 5: 清理 CRD（如果仍有残留）

```bash
# 5.1 删除所有 Longhorn CRD
kubectl get crd | grep longhorn | awk '{print $1}' | xargs -I {} kubectl delete crd {}

# 5.2 等待删除完成
sleep 10
```

**验证**:
```bash
kubectl get crd | grep longhorn
# 应该返回空
```

### 步骤 6: 清理本地数据（可选但推荐）

```bash
# 6.1 清理默认路径
if [ -d "/var/lib/longhorn" ]; then
    echo "备份 /var/lib/longhorn..."
    sudo mv /var/lib/longhorn /var/lib/longhorn.backup.$(date +%Y%m%d_%H%M%S)
    echo "✓ 已备份"
fi

# 6.2 清理自定义路径（如果使用）
if [ -d "/mnt/longhorn" ]; then
    echo "清理 /mnt/longhorn..."
    sudo rm -rf /mnt/longhorn/longhorn-disk.cfg
    sudo rm -rf /mnt/longhorn/replicas
    sudo rm -rf /mnt/longhorn/engine-binaries
    echo "✓ 已清理（保留挂载点）"
fi
```

**验证**:
```bash
# 检查路径
ls -la /var/lib/longhorn* 2>/dev/null || echo "默认路径已清理"
ls -la /mnt/longhorn 2>/dev/null || echo "自定义路径已清理"
```

### 步骤 7: 最终验证卸载

```bash
# 7.1 检查命名空间
kubectl get namespace longhorn-system 2>&1 | grep -q "NotFound" && echo "✓ 命名空间已删除" || echo "⚠️  命名空间仍存在"

# 7.2 检查 CRD
LONGHORN_CRDS=$(kubectl get crd 2>/dev/null | grep longhorn | wc -l)
if [ "$LONGHORN_CRDS" -eq 0 ]; then
    echo "✓ CRD 已删除"
else
    echo "⚠️  仍有 $LONGHORN_CRDS 个 CRD 未删除"
    kubectl get crd | grep longhorn
fi

# 7.3 检查 StorageClass
kubectl get storageclass longhorn 2>&1 | grep -q "NotFound" && echo "✓ StorageClass 已删除" || echo "⚠️  StorageClass 仍存在"

# 7.4 检查 CSI Driver
kubectl get csidriver driver.longhorn.io 2>&1 | grep -q "NotFound" && echo "✓ CSI Driver 已删除" || echo "⚠️  CSI Driver 仍存在"
```

**验证结果**: 所有检查应该显示已删除。

---

## 第二部分：重新安装 Longhorn

### 步骤 1: 检查前置要求

```bash
# 1.1 检查 k3s/kubectl
kubectl version --client
kubectl cluster-info

# 1.2 检查 open-iscsi
if command -v iscsiadm &> /dev/null; then
    echo "✓ iscsiadm 已安装"
    iscsiadm --version
else
    echo "❌ iscsiadm 未安装"
    echo "安装: sudo apt-get install -y open-iscsi"
    exit 1
fi

# 1.3 检查 iscsid 服务
if sudo systemctl is-active --quiet iscsid; then
    echo "✓ iscsid 服务运行中"
else
    echo "启动 iscsid 服务..."
    sudo systemctl enable iscsid
    sudo systemctl start iscsid
    sudo systemctl status iscsid
fi

# 1.4 检查磁盘空间
df -h | grep -E "longhorn|/$" | head -2
```

**验证**: 所有检查应该通过。

### 步骤 2: 准备存储磁盘（推荐）

```bash
# 2.1 查看可用磁盘
lsblk

# 2.2 如果使用新磁盘，准备它
# DISK_DEVICE="/dev/sdb"  # 根据实际情况修改
# ./scripts/prepare-new-disk.sh $DISK_DEVICE /mnt/longhorn

# 2.3 或使用默认路径
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn
```

**验证**:
```bash
# 检查路径存在且可写
[ -d "/var/lib/longhorn" ] && [ -w "/var/lib/longhorn" ] && echo "✓ 默认路径就绪" || echo "❌ 路径问题"
# 或
[ -d "/mnt/longhorn" ] && [ -w "/mnt/longhorn" ] && echo "✓ 自定义路径就绪" || echo "❌ 路径问题"
```

### 步骤 3: 选择 Longhorn 版本

```bash
# 3.1 获取最新版本（推荐）
LATEST_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
echo "最新版本: $LATEST_VERSION"

# 3.2 或查看所有可用版本
curl -s https://api.github.com/repos/longhorn/longhorn/releases | grep tag_name | head -10

# 3.3 设置要安装的版本
LONGHORN_VERSION="${LATEST_VERSION}"  # 使用最新版本
# 或指定版本: LONGHORN_VERSION="v1.6.0"
```

**版本选择建议**:
- ✅ **最新稳定版本**: 修复了已知问题，推荐使用
- ⚠️ **特定版本**: 如果已知某个版本稳定，可以指定
- 📋 **查看版本历史**: https://github.com/longhorn/longhorn/releases

### 步骤 4: 安装 Longhorn

#### 方法 A: 使用 kubectl apply（推荐用于快速安装）

```bash
# 4.1 安装 Longhorn
echo "安装 Longhorn $LONGHORN_VERSION..."
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml
```

**验证**:
```bash
# 检查命名空间是否创建
kubectl get namespace longhorn-system
# 应该看到: longhorn-system   Active   Xs
```

#### 方法 B: 使用 Helm（推荐用于生产环境）

```bash
# 4.1 检查 Helm
if ! command -v helm &> /dev/null; then
    echo "安装 Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 4.2 添加 Helm 仓库
helm repo add longhorn https://charts.longhorn.io
helm repo update

# 4.3 获取最新 Helm Chart 版本
HELM_LATEST=$(helm search repo longhorn/longhorn --versions | head -2 | tail -1 | awk '{print $2}')
echo "最新 Helm Chart 版本: $HELM_LATEST"

# 4.4 安装 Longhorn（使用最新版本或指定版本）
HELM_VERSION=$(echo "$LONGHORN_VERSION" | sed 's/^v//')  # 移除 v 前缀
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version "$HELM_VERSION"
```

**验证**:
```bash
# 检查 Helm 发布
helm list -n longhorn-system
# 应该看到: longhorn   longhorn-system   X   Xs
```

### 步骤 5: 等待 Longhorn Manager 就绪

```bash
# 4.1 等待 Manager Pods 就绪
echo "等待 Longhorn Manager 就绪..."
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s
```

**验证**:
```bash
# 检查 Manager Pods
kubectl get pods -n longhorn-system -l app=longhorn-manager
# 应该看到所有 Pods 状态为 Running

# 检查 Manager 日志（应该没有错误）
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=10
```

### 步骤 6: 等待 CSI Driver 安装

```bash
# 5.1 检查 driver-deployer
echo "检查 driver-deployer..."
kubectl get pods -n longhorn-system -l app=longhorn-driver-deployer

# 5.2 等待 driver-deployer 完成（最多 10 分钟）
echo "等待 driver-deployer 完成..."
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
    else
        echo "  等待中... ($ELAPSED/$MAX_WAIT 秒) - 状态: $STATUS"
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
```

**验证**:
```bash
# 检查 CSI Driver
kubectl get csidriver driver.longhorn.io
# 应该看到: driver.longhorn.io   Xs

# 检查 CSI 组件
kubectl get pods -n longhorn-system | grep csi
# 应该看到:
# - longhorn-csi-attacher-* (Running)
# - longhorn-csi-provisioner-* (Running)
# - longhorn-csi-resizer-* (Running)
# - longhorn-csi-plugin-* (Running, 每个节点一个)
```

### 步骤 7: 验证 StorageClass

```bash
# 6.1 等待 StorageClass 创建
echo "等待 StorageClass 创建..."
sleep 10

# 6.2 检查 StorageClass
kubectl get storageclass longhorn
```

**验证**:
```bash
# 检查 StorageClass 详情
kubectl get storageclass longhorn -o yaml | grep -E "provisioner|allowVolumeExpansion"
# 应该看到:
# provisioner: driver.longhorn.io
# allowVolumeExpansion: true
```

### 步骤 8: 配置磁盘

```bash
# 7.1 获取节点名称
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 7.2 等待 Longhorn Node 资源创建
echo "等待 Longhorn Node 资源创建..."
kubectl wait --for=condition=ready nodes.longhorn.io -n longhorn-system $NODE_NAME --timeout=300s 2>/dev/null || true

# 7.3 配置磁盘
DISK_PATH="/mnt/longhorn"  # 或 "/var/lib/longhorn"
DISK_NAME="data-disk"
if [ "$DISK_PATH" = "/var/lib/longhorn" ]; then
    DISK_NAME="default-disk"
fi

echo "配置磁盘: $DISK_PATH"
kubectl patch nodes.longhorn.io -n longhorn-system $NODE_NAME --type merge -p "{
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
```

**验证**:
```bash
# 检查磁盘配置
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"
# 应该看到配置的磁盘

# 等待磁盘就绪（可能需要几分钟）
echo "等待磁盘就绪..."
for i in {1..60}; do
    DISK_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o jsonpath="{.status.diskStatus.$DISK_NAME.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
    if [ "$DISK_STATUS" = "True" ]; then
        echo "✓ 磁盘已就绪"
        break
    fi
    echo "  等待中... ($i/60)"
    sleep 2
done
```

### 步骤 9: 单节点配置（如果是单节点环境）

```bash
# 8.1 设置默认副本数为 1
kubectl patch settings.longhorn.io default-replica-count -n longhorn-system --type merge -p '{"value":"1"}'
```

**验证**:
```bash
kubectl get settings.longhorn.io default-replica-count -n longhorn-system -o jsonpath='{.value}'
# 应该输出: 1
```

### 步骤 10: 测试 PVC 创建

```bash
# 9.1 创建测试 PVC
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

# 9.2 等待 PVC 绑定
echo "等待 PVC 绑定..."
for i in {1..60}; do
    STATUS=$(kubectl get pvc test-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Bound" ]; then
        echo "✓ PVC 已绑定"
        break
    fi
    echo "  等待中... ($i/60) - 状态: $STATUS"
    sleep 2
done
```

**验证**:
```bash
# 检查 PVC 状态
kubectl get pvc test-pvc
# 应该看到: test-pvc   Bound   pvc-xxx   1Gi   RWO   longhorn   Xs

# 检查 PV
kubectl get pv
# 应该看到对应的 PV

# 清理测试 PVC
kubectl delete pvc test-pvc
```

### 步骤 11: 最终验证

```bash
# 10.1 检查所有组件
echo "=== Longhorn 组件状态 ==="
kubectl get pods -n longhorn-system

# 10.2 检查 StorageClass
echo ""
echo "=== StorageClass ==="
kubectl get storageclass longhorn

# 10.3 检查 CSI Driver
echo ""
echo "=== CSI Driver ==="
kubectl get csidriver driver.longhorn.io

# 10.4 检查磁盘状态
echo ""
echo "=== 磁盘状态 ==="
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 30 "diskStatus:" | head -35
```

**验证结果**: 所有组件应该正常运行，磁盘应该就绪。

---

## 一键安装脚本

项目提供了自动化脚本：

```bash
# 使用脚本安装（自动获取最新版本）
./scripts/install-longhorn.sh kubectl latest

# 或指定版本
./scripts/install-longhorn.sh kubectl v1.6.0

# 或使用 Helm（自动获取最新版本）
./scripts/install-longhorn.sh helm latest

# 重新安装（自动获取最新版本）
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn
```

## 故障排查

### 问题 1: driver-deployer 卡在 Init:0/1

**解决**:
```bash
# 检查 longhorn-backend
kubectl get endpoints -n longhorn-system longhorn-backend

# 检查 longhorn-manager
kubectl get pods -n longhorn-system -l app=longhorn-manager

# 如果 Manager 运行正常，重启 driver-deployer
kubectl delete pod -n longhorn-system -l app=longhorn-driver-deployer
```

### 问题 2: longhorn-manager CrashLoopBackOff

**解决**:
```bash
# 检查日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# 常见原因：缺少 open-iscsi
sudo apt-get install -y open-iscsi
sudo systemctl enable iscsid
sudo systemctl start iscsid

# 重启 Manager
kubectl delete pod -n longhorn-system -l app=longhorn-manager
```

### 问题 3: PVC 一直 Pending

**解决**:
```bash
# 检查磁盘配置
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o yaml | grep -A 20 "disks:"

# 如果没有配置，配置磁盘
./scripts/configure-longhorn-disk.sh /mnt/longhorn
```

## 总结

**卸载流程**:
1. 删除 PVC → 2. 删除 Volumes → 3. 卸载 Longhorn → 4. 清理 CRD → 5. 清理本地数据

**安装流程**:
1. 检查前置要求 → 2. 准备磁盘 → 3. 安装 Longhorn → 4. 等待 Manager → 5. 等待 CSI Driver → 6. 配置磁盘 → 7. 测试 PVC

**关键验证点**:
- ✅ Manager Pods 运行
- ✅ CSI Driver 安装
- ✅ StorageClass 创建
- ✅ 磁盘配置并就绪
- ✅ PVC 可以绑定

## 版本选择

### 检查可用版本

```bash
# 查看可用版本
./scripts/check-longhorn-versions.sh

# 或手动查看
curl -s https://api.github.com/repos/longhorn/longhorn/releases | grep tag_name | head -10
```

### 版本选择建议

| 场景 | 推荐版本 | 说明 |
|------|----------|------|
| **新安装** | `latest` | 使用最新稳定版本，修复了已知问题 |
| **升级** | `latest` | 升级到最新版本以获得最新功能和修复 |
| **生产环境** | 最新稳定版本 | 经过充分测试的版本 |
| **特定需求** | 指定版本 | 如果已知某个版本稳定 |

### 为什么使用最新版本？

- ✅ **修复已知问题**: 最新版本通常修复了之前版本的问题
- ✅ **改进稳定性**: 包含稳定性改进和 bug 修复
- ✅ **新功能**: 可能包含新功能和性能优化
- ✅ **安全更新**: 包含安全补丁

### 安装最新版本

```bash
# 方法 1: 使用 latest 参数（推荐）
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn

# 方法 2: 手动获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
./scripts/reinstall-longhorn.sh kubectl "$LATEST_VERSION" /mnt/longhorn
```

## 参考

- 详细安装指南: `docs/LONGHORN_INSTALLATION_GUIDE.md`
- 安装脚本: `./scripts/install-longhorn.sh`
- 重新安装脚本: `./scripts/reinstall-longhorn.sh`
- 版本检查脚本: `./scripts/check-longhorn-versions.sh`
- 配置磁盘脚本: `./scripts/configure-longhorn-disk.sh`
- Longhorn 发布页面: https://github.com/longhorn/longhorn/releases


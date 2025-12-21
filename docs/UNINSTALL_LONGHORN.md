# Longhorn 卸载指南

## 概述

本指南说明如何完全卸载 Longhorn，包括删除所有资源、CRD 和本地数据。

## 快速卸载

### 方法 1: 使用卸载脚本（推荐）⭐

```bash
# 自动检测安装方式并卸载
./scripts/uninstall-longhorn.sh

# 或指定安装方式
./scripts/uninstall-longhorn.sh kubectl
./scripts/uninstall-longhorn.sh helm

# 自动清理本地数据
./scripts/uninstall-longhorn.sh auto yes
```

脚本会自动：
1. 检测安装方式（Helm 或 kubectl）
2. 删除所有 PVC
3. 删除所有 Longhorn Volumes
4. 卸载 Longhorn
5. 删除命名空间
6. 清理 CRD
7. 可选：清理本地数据

### 方法 2: 手动卸载

#### 步骤 1: 删除所有 PVC

```bash
# 查找并删除所有使用 longhorn 的 PVC
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get pvc -n "$ns" -o jsonpath='{range .items[?(@.spec.storageClassName=="longhorn")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | \
  while read pvc; do
    if [ -n "$pvc" ]; then
      kubectl delete pvc -n "$ns" "$pvc"
    fi
  done
done
```

**验证**:
```bash
kubectl get pvc --all-namespaces | grep longhorn
# 应该返回空
```

#### 步骤 2: 删除 Longhorn Volumes

```bash
# 删除所有 Volumes
kubectl get volumes.longhorn.io -n longhorn-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
  while read volume; do
    kubectl delete volumes.longhorn.io -n longhorn-system "$volume"
  done

# 等待删除完成
sleep 30
```

**验证**:
```bash
kubectl get volumes.longhorn.io -n longhorn-system
# 应该返回: No resources found
```

#### 步骤 3: 卸载 Longhorn

**如果使用 Helm 安装**:
```bash
helm uninstall longhorn -n longhorn-system
```

**如果使用 kubectl 安装**:
```bash
# 使用安装时的版本（如果知道）
LONGHORN_VERSION="v1.6.0"
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml

# 或尝试多个版本
for VERSION in v1.6.0 v1.5.5 v1.4.4; do
  kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${VERSION}/deploy/longhorn.yaml --ignore-not-found=true
done
```

**验证**:
```bash
kubectl get pods -n longhorn-system
# 应该返回: No resources found
```

#### 步骤 4: 删除命名空间

```bash
kubectl delete namespace longhorn-system
```

**验证**:
```bash
kubectl get namespace longhorn-system
# 应该返回: Error from server (NotFound)
```

#### 步骤 5: 清理 CRD

```bash
# 删除所有 Longhorn CRD
kubectl get crd | grep longhorn | awk '{print $1}' | xargs -I {} kubectl delete crd {}
```

**验证**:
```bash
kubectl get crd | grep longhorn
# 应该返回空
```

#### 步骤 6: 清理 StorageClass 和 CSI Driver

```bash
# 删除 StorageClass
kubectl delete storageclass longhorn --ignore-not-found=true

# 删除 CSI Driver
kubectl delete csidriver driver.longhorn.io --ignore-not-found=true
```

**验证**:
```bash
kubectl get storageclass longhorn
kubectl get csidriver driver.longhorn.io
# 都应该返回: Error from server (NotFound)
```

#### 步骤 7: 清理本地数据（可选）

```bash
# 备份并清理默认路径
if [ -d "/var/lib/longhorn" ]; then
    sudo mv /var/lib/longhorn /var/lib/longhorn.backup.$(date +%Y%m%d_%H%M%S)
fi

# 清理自定义路径（保留挂载点）
if [ -d "/mnt/longhorn" ]; then
    sudo rm -rf /mnt/longhorn/longhorn-disk.cfg
    sudo rm -rf /mnt/longhorn/replicas
    sudo rm -rf /mnt/longhorn/engine-binaries
fi
```

## 卸载脚本使用说明

### 基本用法

```bash
# 自动检测并卸载
./scripts/uninstall-longhorn.sh

# 指定安装方式
./scripts/uninstall-longhorn.sh kubectl
./scripts/uninstall-longhorn.sh helm
```

### 高级用法

```bash
# 自动清理本地数据
./scripts/uninstall-longhorn.sh auto yes

# 不清理本地数据
./scripts/uninstall-longhorn.sh auto no

# 交互式选择是否清理数据
./scripts/uninstall-longhorn.sh auto ask  # 默认
```

### 脚本参数

| 参数 1 | 说明 | 选项 |
|--------|------|------|
| `auto` | 自动检测安装方式（默认） | `auto`, `kubectl`, `helm` |
| `kubectl` | 使用 kubectl 方式卸载 | - |
| `helm` | 使用 Helm 方式卸载 | - |

| 参数 2 | 说明 | 选项 |
|--------|------|------|
| `ask` | 询问是否清理数据（默认） | `ask`, `yes`, `no` |
| `yes` | 自动清理本地数据 | - |
| `no` | 不清理本地数据 | - |

## 验证卸载

### 完整验证清单

```bash
# 1. 检查命名空间
kubectl get namespace longhorn-system
# 应该: Error from server (NotFound)

# 2. 检查 Pods
kubectl get pods -n longhorn-system
# 应该: No resources found

# 3. 检查 CRD
kubectl get crd | grep longhorn
# 应该: 空

# 4. 检查 StorageClass
kubectl get storageclass longhorn
# 应该: Error from server (NotFound)

# 5. 检查 CSI Driver
kubectl get csidriver driver.longhorn.io
# 应该: Error from server (NotFound)

# 6. 检查 PVC
kubectl get pvc --all-namespaces | grep longhorn
# 应该: 空

# 7. 检查 PV
kubectl get pv | grep longhorn
# 应该: 空
```

## 常见问题

### 问题 1: 命名空间删除卡住

**症状**: `kubectl delete namespace longhorn-system` 一直等待

**原因**: 命名空间中有资源无法删除

**解决**:
```bash
# 强制删除命名空间
kubectl get namespace longhorn-system -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw /api/v1/namespaces/longhorn-system/finalize -f -

# 或直接编辑
kubectl edit namespace longhorn-system
# 删除 finalizers 字段
```

### 问题 2: CRD 删除失败

**症状**: `kubectl delete crd` 返回错误

**解决**:
```bash
# 强制删除 CRD
kubectl patch crd <crd-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete crd <crd-name>
```

### 问题 3: 仍有残留资源

**症状**: 卸载后仍有 Longhorn 相关资源

**解决**:
```bash
# 查找所有 Longhorn 相关资源
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n longhorn-system | grep longhorn

# 手动删除
kubectl delete <resource-type> <resource-name> -n longhorn-system
```

## 卸载后重新安装

卸载完成后，可以重新安装：

```bash
# 使用最新版本重新安装
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn

# 或使用安装脚本
./scripts/install-longhorn.sh kubectl latest
```

## 总结

**推荐卸载方式**:
- ✅ 使用卸载脚本: `./scripts/uninstall-longhorn.sh`
- ✅ 自动检测安装方式
- ✅ 完整清理所有资源

**卸载步骤**:
1. 删除 PVC
2. 删除 Volumes
3. 卸载 Longhorn
4. 删除命名空间
5. 清理 CRD
6. 清理 StorageClass 和 CSI Driver
7. 可选：清理本地数据

**验证**: 运行验证清单确保完全卸载

## 参考

- 卸载脚本: `./scripts/uninstall-longhorn.sh`
- 重新安装脚本: `./scripts/reinstall-longhorn.sh`
- 安装指南: `docs/LONGHORN_INSTALLATION_GUIDE.md`


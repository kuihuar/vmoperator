#!/bin/bash

# Longhorn 卸载脚本

set -e

INSTALL_METHOD="${1:-auto}"  # auto, kubectl, helm
CLEAN_DATA="${2:-ask}"  # ask, yes, no

echo "=== 卸载 Longhorn ==="
echo ""

# 1. 检测安装方式
if [ "$INSTALL_METHOD" = "auto" ]; then
    echo "1. 检测 Longhorn 安装方式..."
    if helm list -n longhorn-system 2>/dev/null | grep -q longhorn; then
        INSTALL_METHOD="helm"
        echo "✓ 检测到 Helm 安装"
    elif kubectl get namespace longhorn-system &>/dev/null; then
        INSTALL_METHOD="kubectl"
        echo "✓ 检测到 kubectl 安装"
    else
        echo "⚠️  未发现 Longhorn 安装"
        exit 0
    fi
else
    echo "1. 使用指定方式卸载: $INSTALL_METHOD"
fi
echo ""

# 2. 检查当前状态
echo "2. 检查当前状态..."
if kubectl get namespace longhorn-system &>/dev/null; then
    echo "发现 longhorn-system 命名空间"
    echo ""
    echo "Longhorn Pods:"
    kubectl get pods -n longhorn-system | head -10
    echo ""
    
    echo "Longhorn Volumes:"
    if kubectl get crd volumes.longhorn.io &>/dev/null; then
        VOLUME_COUNT=$(kubectl get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
        echo "  发现 $VOLUME_COUNT 个 Volumes"
    else
        echo "  没有 Volumes"
    fi
    echo ""
    
    echo "使用 longhorn 的 PVC:"
    PVC_COUNT=0
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        COUNT=$(kubectl get pvc -n "$ns" -o jsonpath='{range .items[?(@.spec.storageClassName=="longhorn")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')
        PVC_COUNT=$((PVC_COUNT + COUNT))
    done
    echo "  发现 $PVC_COUNT 个 PVC"
else
    echo "未发现 longhorn-system 命名空间"
    echo "Longhorn 可能已卸载"
    exit 0
fi
echo ""

# 3. 确认
read -p "确定要卸载 Longhorn 吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi
echo ""

# 4. 删除所有 PVC
echo "3. 删除所有使用 longhorn 的 PVC..."
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

# 5. 删除 Longhorn Volumes
echo "4. 删除 Longhorn Volumes..."
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

# 6. 卸载 Longhorn
echo "5. 卸载 Longhorn..."
if [ "$INSTALL_METHOD" = "helm" ]; then
    if helm list -n longhorn-system 2>/dev/null | grep -q longhorn; then
        echo "使用 Helm 卸载..."
        helm uninstall longhorn -n longhorn-system --ignore-not-found=true
        echo "✓ Helm 卸载完成"
    else
        echo "⚠️  未发现 Helm 安装，尝试 kubectl 方式..."
        INSTALL_METHOD="kubectl"
    fi
fi

if [ "$INSTALL_METHOD" = "kubectl" ]; then
    echo "使用 kubectl 卸载..."
    
    # 尝试多个常见版本
    VERSIONS=("v1.6.0" "v1.5.5" "v1.4.4" "v1.3.3")
    UNINSTALLED=false
    
    for VERSION in "${VERSIONS[@]}"; do
        if kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${VERSION}/deploy/longhorn.yaml --ignore-not-found=true 2>/dev/null; then
            echo "✓ 使用版本 $VERSION 卸载成功"
            UNINSTALLED=true
            break
        fi
    done
    
    # 如果都失败，尝试获取最新版本
    if [ "$UNINSTALLED" = false ]; then
        echo "尝试使用最新版本卸载..."
        LATEST_VER=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
        if [ -n "$LATEST_VER" ]; then
            kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/${LATEST_VER}/deploy/longhorn.yaml --ignore-not-found=true 2>/dev/null || true
            echo "✓ 使用最新版本 $LATEST_VER 卸载"
        fi
    fi
    
    echo "✓ kubectl 卸载完成"
fi
echo ""

# 7. 删除命名空间
echo "6. 删除命名空间..."
kubectl delete namespace longhorn-system --ignore-not-found=true --timeout=120s
echo "等待命名空间删除..."
sleep 10
echo "✓ 命名空间已删除"
echo ""

# 8. 清理 CRD
echo "7. 清理 CRD..."
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

# 9. 清理本地数据（可选）
if [ "$CLEAN_DATA" = "ask" ]; then
    echo "8. 清理本地数据（可选）..."
    read -p "是否清理本地 Longhorn 数据? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEAN_DATA="yes"
    else
        CLEAN_DATA="no"
    fi
fi

if [ "$CLEAN_DATA" = "yes" ]; then
    echo "清理本地数据..."
    
    # 清理默认路径
    if [ -d "/var/lib/longhorn" ]; then
        BACKUP_DIR="/var/lib/longhorn.backup.$(date +%Y%m%d_%H%M%S)"
        echo "备份 /var/lib/longhorn 到 $BACKUP_DIR..."
        sudo mv /var/lib/longhorn "$BACKUP_DIR" 2>/dev/null || true
        echo "✓ 已备份"
    fi
    
    # 清理自定义路径（如果存在）
    if [ -d "/mnt/longhorn" ]; then
        echo "清理 /mnt/longhorn..."
        sudo rm -rf /mnt/longhorn/longhorn-disk.cfg 2>/dev/null || true
        sudo rm -rf /mnt/longhorn/replicas 2>/dev/null || true
        sudo rm -rf /mnt/longhorn/engine-binaries 2>/dev/null || true
        echo "✓ 已清理（保留挂载点）"
    fi
    
    echo "✓ 本地数据已清理"
else
    echo "8. 跳过清理本地数据"
fi
echo ""

# 10. 最终验证
echo "9. 验证卸载..."
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
    kubectl get crd | grep longhorn
fi

REMAINING_SC=$(kubectl get storageclass longhorn 2>&1 | grep -q "NotFound" && echo "0" || echo "1")
if [ "$REMAINING_SC" -eq 0 ]; then
    echo "✓ StorageClass 已删除"
else
    echo "⚠️  StorageClass 仍存在"
fi

REMAINING_CSI=$(kubectl get csidriver driver.longhorn.io 2>&1 | grep -q "NotFound" && echo "0" || echo "1")
if [ "$REMAINING_CSI" -eq 0 ]; then
    echo "✓ CSI Driver 已删除"
else
    echo "⚠️  CSI Driver 仍存在"
fi
echo ""

echo "=== 卸载完成 ==="
echo ""
echo "如果仍有残留资源，可以手动清理:"
echo "  kubectl delete crd \$(kubectl get crd | grep longhorn | awk '{print \$1}')"
echo "  kubectl delete storageclass longhorn"
echo "  kubectl delete csidriver driver.longhorn.io"
echo ""


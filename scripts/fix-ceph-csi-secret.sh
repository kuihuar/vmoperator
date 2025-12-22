#!/bin/bash

# 修复 Ceph CSI Secret 问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "=========================================="
echo_info "修复 Ceph CSI Secret 问题"
echo_info "=========================================="
echo ""

# 1. 检查 CSI Secret
echo_info "1. 检查 CSI Secret"
echo ""

# Rook 通常创建的 Secret 名称
SECRET_NAME="rook-csi-rbd-provisioner"
SECRET_NAMESPACE="rook-ceph"

if kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" &>/dev/null; then
    echo_info "  ✓ Secret 存在: $SECRET_NAME"
    
    # 检查 Secret 内容
    SECRET_DATA=$(kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" -o jsonpath='{.data}' 2>/dev/null || echo "")
    
    if [ -z "$SECRET_DATA" ] || [ "$SECRET_DATA" = "{}" ]; then
        echo_warn "  ⚠️  Secret 内容为空，需要重新创建"
        DELETE_SECRET=true
    else
        echo_info "  ✓ Secret 有内容"
        DELETE_SECRET=false
    fi
else
    echo_warn "  ⚠️  Secret 不存在: $SECRET_NAME"
    DELETE_SECRET=false
fi

echo ""

# 2. 检查 Ceph 集群 Secret
echo_info "2. 检查 Ceph 集群 Secret"
echo ""

# Rook 存储的 Ceph 认证信息
CEPH_USER_SECRET="rook-ceph-mon"
CEPH_ADMIN_SECRET="rook-ceph-admin-keyring"

if kubectl get secret "$CEPH_USER_SECRET" -n "$SECRET_NAMESPACE" &>/dev/null; then
    echo_info "  ✓ Ceph 用户 Secret 存在: $CEPH_USER_SECRET"
else
    echo_error "  ✗ Ceph 用户 Secret 不存在: $CEPH_USER_SECRET"
    echo_warn "    这可能是 Ceph 集群未完全初始化"
fi

if kubectl get secret "$CEPH_ADMIN_SECRET" -n "$SECRET_NAMESPACE" &>/dev/null; then
    echo_info "  ✓ Ceph Admin Secret 存在: $CEPH_ADMIN_SECRET"
else
    echo_warn "  ⚠️  Ceph Admin Secret 不存在: $CEPH_ADMIN_SECRET"
fi

echo ""

# 3. 获取 Ceph 认证信息
echo_info "3. 获取 Ceph 认证信息"
echo ""

# 从 Ceph 集群 Secret 获取用户名和密钥
CEPH_USER=$(kubectl get secret "$CEPH_USER_SECRET" -n "$SECRET_NAMESPACE" -o jsonpath='{.data.ceph-username}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
CEPH_KEY=$(kubectl get secret "$CEPH_USER_SECRET" -n "$SECRET_NAMESPACE" -o jsonpath='{.data.ceph-secret}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -z "$CEPH_USER" ] || [ -z "$CEPH_KEY" ]; then
    echo_warn "  ⚠️  无法从 Secret 获取认证信息"
    echo_info "  尝试从 Ceph Admin Secret 获取..."
    
    CEPH_KEY=$(kubectl get secret "$CEPH_ADMIN_SECRET" -n "$SECRET_NAMESPACE" -o jsonpath='{.data.key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    CEPH_USER="admin"
fi

if [ -z "$CEPH_KEY" ]; then
    echo_error "  ✗ 无法获取 Ceph 密钥"
    echo_warn "    可能需要等待 Ceph 集群完全初始化"
    echo_info "    或者手动从 Ceph 集群获取密钥"
    exit 1
fi

echo_info "  ✓ 获取到 Ceph 认证信息"
echo "    用户: ${CEPH_USER:-admin}"
echo "    密钥: ${CEPH_KEY:0:20}..."  # 只显示前20个字符

echo ""

# 4. 删除旧的 Secret（如果需要）
if [ "$DELETE_SECRET" = "true" ]; then
    echo_info "4. 删除旧的空 Secret"
    echo ""
    kubectl delete secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" --ignore-not-found=true
    echo_info "  ✓ 旧 Secret 已删除"
    echo ""
fi

# 5. 创建 CSI Secret
echo_info "5. 创建 CSI Secret"
echo ""

# 获取 Ceph 集群信息
CEPH_CLUSTER_ID="rook-ceph"
CEPH_MON_ENDPOINTS=$(kubectl get configmap rook-ceph-mon-endpoints -n "$SECRET_NAMESPACE" -o jsonpath='{.data.data}' 2>/dev/null | tr -d '\n' || echo "")

if [ -z "$CEPH_MON_ENDPOINTS" ]; then
    echo_warn "  ⚠️  无法获取 Mon endpoints，使用默认值"
    CEPH_MON_ENDPOINTS="rook-ceph-mon-a.rook-ceph.svc:6789"
fi

echo_info "  创建 Secret: $SECRET_NAME"
echo "    命名空间: $SECRET_NAMESPACE"
echo "    集群 ID: $CEPH_CLUSTER_ID"
echo "    Mon endpoints: $CEPH_MON_ENDPOINTS"

# 创建 Secret
kubectl create secret generic "$SECRET_NAME" \
  --from-literal=userID="${CEPH_USER:-admin}" \
  --from-literal=userKey="$CEPH_KEY" \
  --from-literal=clusterID="$CEPH_CLUSTER_ID" \
  --from-literal=monValue="$CEPH_MON_ENDPOINTS" \
  -n "$SECRET_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo_info "  ✓ Secret 已创建/更新"

echo ""

# 6. 验证 Secret
echo_info "6. 验证 Secret"
echo ""

if kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" &>/dev/null; then
    echo_info "  ✓ Secret 存在"
    
    # 检查 Secret 的 keys
    SECRET_KEYS=$(kubectl get secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")
    
    if [ -n "$SECRET_KEYS" ]; then
        echo_info "  Secret 包含的 keys:"
        echo "$SECRET_KEYS" | while read key; do
            echo "    - $key"
        done
    else
        echo_warn "  ⚠️  无法读取 Secret keys"
    fi
else
    echo_error "  ✗ Secret 创建失败"
    exit 1
fi

echo ""

# 7. 检查 StorageClass 是否引用 Secret
echo_info "7. 检查 StorageClass 配置"
echo ""

if kubectl get storageclass rook-ceph-block &>/dev/null; then
    STORAGE_CLASS_YAML=$(kubectl get storageclass rook-ceph-block -o yaml)
    
    # 检查是否配置了 secretName
    if echo "$STORAGE_CLASS_YAML" | grep -q "secretName"; then
        echo_info "  ✓ StorageClass 已配置 secretName"
        echo "$STORAGE_CLASS_YAML" | grep -A 2 "secretName"
    else
        echo_warn "  ⚠️  StorageClass 未配置 secretName"
        echo_info "  更新 StorageClass..."
        
        # 更新 StorageClass 添加 secretName
        kubectl patch storageclass rook-ceph-block -p '{"parameters":{"csi.storage.k8s.io/provisioner-secret-name":"'$SECRET_NAME'","csi.storage.k8s.io/provisioner-secret-namespace":"'$SECRET_NAMESPACE'","csi.storage.k8s.io/controller-expand-secret-name":"'$SECRET_NAME'","csi.storage.k8s.io/controller-expand-secret-namespace":"'$SECRET_NAMESPACE'","csi.storage.k8s.io/node-stage-secret-name":"'$SECRET_NAME'","csi.storage.k8s.io/node-stage-secret-namespace":"'$SECRET_NAMESPACE'","csi.storage.k8s.io/node-publish-secret-name":"'$SECRET_NAME'","csi.storage.k8s.io/node-publish-secret-namespace":"'$SECRET_NAMESPACE'"}}'
        
        echo_info "  ✓ StorageClass 已更新"
    fi
else
    echo_error "  ✗ StorageClass 不存在"
fi

echo ""

# 8. 重启 CSI Provisioner（可选）
echo_info "8. 重启 CSI Provisioner（让 Secret 生效）"
echo ""

read -p "是否重启 CSI Provisioner Pods? (y/n，默认y): " RESTART
RESTART=${RESTART:-y}

if [ "$RESTART" = "y" ]; then
    PROV_PODS=$(kubectl get pods -n rook-ceph | grep csi-rbdplugin-provisioner | awk '{print $1}' || echo "")
    
    if [ -n "$PROV_PODS" ]; then
        echo "$PROV_PODS" | while read pod; do
            if [ -n "$pod" ]; then
                echo_info "  删除 Pod: $pod"
                kubectl delete pod "$pod" -n rook-ceph --wait=false
            fi
        done
        
        echo_info "  ✓ Provisioner Pods 已重启"
        echo_info "  等待 Pods 重新启动（30秒）..."
        sleep 30
    else
        echo_warn "  ⚠️  未找到 Provisioner Pods"
    fi
else
    echo_info "  已跳过重启"
fi

echo ""

# 9. 总结
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""

echo_info "已完成的修复:"
echo "  1. ✓ 创建/更新 CSI Secret: $SECRET_NAME"
echo "  2. ✓ 更新 StorageClass 配置"
echo "  3. ✓ 重启 CSI Provisioner（如果选择）"
echo ""

echo_info "下一步:"
echo "  1. 等待 CSI Provisioner 重新启动（如果重启了）"
echo "  2. 检查 PVC 状态: kubectl get pvc"
echo "  3. 如果 PVC 仍然未绑定，删除并重新创建 PVC"
echo "  4. 查看 PVC 事件: kubectl describe pvc <pvc-name>"
echo ""


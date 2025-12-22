#!/bin/bash

# 修复 Multus RBAC 权限

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
echo_info "修复 Multus RBAC 权限"
echo_info "=========================================="
echo ""

# 1. 检查当前的 ClusterRole
echo_info "1. 检查当前的 ClusterRole"
echo ""

if kubectl get clusterrole multus > /dev/null 2>&1; then
    echo_info "  ClusterRole 存在，查看当前权限:"
    kubectl get clusterrole multus -o yaml | grep -A 20 "rules:"
else
    echo_warn "  ClusterRole 不存在，将创建"
fi

# 2. 应用正确的 ClusterRole（根据官方文档）
echo ""
echo_info "2. 应用正确的 ClusterRole 配置"
echo ""

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: multus
  namespace: kube-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: multus
rules:
  # Multus CRD 权限
  - apiGroups: ["k8s.cni.cncf.io"]
    resources:
      - '*'
    verbs:
      - '*'
  # Pod 权限（需要 get, list, update）
  - apiGroups:
      - ""
    resources:
      - pods
      - pods/status
    verbs:
      - get
      - list
      - watch
      - update
  # 节点权限（可能需要）
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
      - list
      - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: multus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: multus
subjects:
- kind: ServiceAccount
  name: multus
  namespace: kube-system
EOF

echo_info "  ✓ RBAC 配置已更新"

# 3. 验证权限
echo ""
echo_info "3. 验证权限"
echo ""

sleep 2

# 重新获取 token（因为 ServiceAccount 可能更新了）
KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"

if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  重新创建 kubeconfig（使用更新后的 ServiceAccount）"
    
    # 获取新的 token
    SERVICEACCOUNT_TOKEN=$(kubectl get secrets -n=kube-system -o json 2>/dev/null | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .data.token' | head -1 | base64 -d 2>/dev/null || echo "")
    
    if [ -n "$SERVICEACCOUNT_TOKEN" ]; then
        SERVICEACCOUNT_CA=$(kubectl get secrets -n=kube-system -o json 2>/dev/null | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .data."ca.crt"' | head -1)
        KUBERNETES_SERVICE_HOST=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "kubernetes.default.svc")
        KUBERNETES_SERVICE_PORT=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "443")
        
        sudo tee "$KUBECONFIG_FILE" > /dev/null <<EOF
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}
    certificate-authority-data: ${SERVICEACCOUNT_CA}
users:
- name: multus
  user:
    token: "${SERVICEACCOUNT_TOKEN}"
contexts:
- name: multus-context
  context:
    cluster: local
    user: multus
current-context: multus-context
EOF
        
        echo_info "  ✓ kubeconfig 已更新"
    fi
fi

# 4. 测试权限
echo ""
echo_info "4. 测试权限"
echo ""

sleep 2

if [ -f "$KUBECONFIG_FILE" ]; then
    # 测试访问 CRD
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get crd network-attachment-definitions.k8s.cni.cncf.io > /dev/null 2>&1; then
        echo_info "  ✓ 可以访问 NetworkAttachmentDefinition CRD"
    else
        echo_warn "  ⚠️  无法访问 CRD（可能需要更多时间生效）"
    fi
    
    # 测试访问 pods（在 kube-system 命名空间）
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get pods -n kube-system --limit=1 > /dev/null 2>&1; then
        echo_info "  ✓ 可以访问 pods（在 kube-system 命名空间）"
    else
        echo_warn "  ⚠️  无法访问 pods（可能需要更多时间生效）"
    fi
fi

echo ""
echo_info "=========================================="
echo_info "修复完成"
echo_info "=========================================="
echo ""
echo_info "RBAC 权限已更新，添加了 list 和 watch 权限"
echo_info "如果权限仍然有问题，可能需要等待几秒钟让配置生效"
echo ""


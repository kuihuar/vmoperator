#!/bin/bash

# 详细检查 Multus 权限配置

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo_info "详细检查 Multus 权限"
echo ""

# 0. 检查前提条件
echo_info "0. 检查前提条件"
echo ""

PREREQUISITES_OK=true

# 检查 ServiceAccount
if kubectl get sa -n kube-system multus > /dev/null 2>&1; then
    echo_info "  ✓ ServiceAccount 存在"
else
    echo_error "  ✗ ServiceAccount 不存在"
    echo_error "    前提条件不满足，请先创建 ServiceAccount"
    PREREQUISITES_OK=false
fi

# 检查 ClusterRole
if kubectl get clusterrole multus > /dev/null 2>&1; then
    echo_info "  ✓ ClusterRole 存在"
else
    echo_error "  ✗ ClusterRole 不存在"
    echo_error "    前提条件不满足，请先创建 ClusterRole"
    PREREQUISITES_OK=false
fi

# 检查 ClusterRoleBinding
if kubectl get clusterrolebinding multus > /dev/null 2>&1; then
    echo_info "  ✓ ClusterRoleBinding 存在"
else
    echo_error "  ✗ ClusterRoleBinding 不存在"
    echo_error "    前提条件不满足，请先创建 ClusterRoleBinding"
    PREREQUISITES_OK=false
fi

# 检查 Secret/token
SECRETS=$(kubectl get secrets -n=kube-system -o json 2>/dev/null | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .metadata.name' || echo "")
if [ -n "$SECRETS" ]; then
    echo_info "  ✓ ServiceAccount Secret 存在"
else
    echo_warn "  ⚠️  ServiceAccount Secret 不存在（可能需要等待创建）"
fi

# 检查 kubeconfig 文件
KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  ✓ kubeconfig 文件存在"
else
    echo_warn "  ⚠️  kubeconfig 文件不存在: $KUBECONFIG_FILE"
fi

if [ "$PREREQUISITES_OK" != true ]; then
    echo ""
    echo_error "前提条件不满足，部分检查可能无法进行"
    echo_info "建议先运行: sudo ./scripts/fix-multus-rbac.sh"
    echo ""
fi

echo ""

# 1. 检查 ClusterRole
echo_info "1. 检查 ClusterRole 配置"
echo ""

kubectl get clusterrole multus -o yaml | grep -A 30 "rules:" || echo_error "ClusterRole 不存在"

# 2. 检查 ClusterRoleBinding
echo ""
echo_info "2. 检查 ClusterRoleBinding"
echo ""

kubectl get clusterrolebinding multus -o yaml | grep -A 10 "subjects:"

# 3. 检查 ServiceAccount
echo ""
echo_info "3. 检查 ServiceAccount"
echo ""

kubectl get sa -n kube-system multus -o yaml

# 4. 检查 Secret
echo ""
echo_info "4. 检查 ServiceAccount Secret"
echo ""

SECRETS=$(kubectl get secrets -n kube-system -o json | jq -r '.items[]|select(.metadata.annotations."kubernetes.io/service-account.name"=="multus")| .metadata.name' || echo "")
if [ -n "$SECRETS" ]; then
    for secret in $SECRETS; do
        echo_info "  Secret: $secret"
        kubectl get secret -n kube-system $secret -o jsonpath='{.data.token}' | wc -c | xargs -I {} echo "    Token 长度: {} 字符"
    done
else
    echo_warn "  未找到 Secret"
fi

# 5. 使用 kubectl auth can-i 检查权限
echo ""
echo_info "5. 使用 kubectl auth can-i 检查权限"
echo ""

# 根据官方文档检查权限（只需要 get 和 update）
echo_info "  检查 pods 权限（根据官方文档要求）:"
kubectl auth can-i get pods --as=system:serviceaccount:kube-system:multus -n kube-system 2>/dev/null && echo_info "    ✓ 可以 get pods（必需）" || echo_error "    ✗ 无法 get pods（必需）"
kubectl auth can-i update pods --as=system:serviceaccount:kube-system:multus -n kube-system 2>/dev/null && echo_info "    ✓ 可以 update pods（必需）" || echo_error "    ✗ 无法 update pods（必需）"
echo_info "  注意：官方文档只要求 get 和 update，不需要 list/watch"

echo ""
echo_info "  检查 CRD 权限:"
kubectl auth can-i get network-attachment-definitions --as=system:serviceaccount:kube-system:multus --all-namespaces 2>/dev/null && echo_info "    ✓ 可以 get CRD" || echo_warn "    ✗ 无法 get CRD"
kubectl auth can-i list network-attachment-definitions --as=system:serviceaccount:kube-system:multus --all-namespaces 2>/dev/null && echo_info "    ✓ 可以 list CRD" || echo_warn "    ✗ 无法 list CRD"

echo ""
echo_info "  检查 pods/status 权限:"
kubectl auth can-i get pods/status --as=system:serviceaccount:kube-system:multus -n kube-system 2>/dev/null && echo_info "    ✓ 可以 get pods/status" || echo_warn "    ✗ 无法 get pods/status"
kubectl auth can-i update pods/status --as=system:serviceaccount:kube-system:multus -n kube-system 2>/dev/null && echo_info "    ✓ 可以 update pods/status" || echo_warn "    ✗ 无法 update pods/status"

# 6. 测试实际使用 kubeconfig
echo ""
echo_info "6. 测试使用 kubeconfig"
echo ""

KUBECONFIG_FILE="/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"

if [ -f "$KUBECONFIG_FILE" ]; then
    echo_info "  测试连接..."
    
    # 等待一下让权限生效
    sleep 3
    
    # 注意：官方文档只要求 get 和 update，list 可能失败但这是正常的
    # 测试 get（这是必需的）
    FIRST_POD=$(kubectl get pods -n kube-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$FIRST_POD" ]; then
        if KUBECONFIG="$KUBECONFIG_FILE" kubectl get pod "$FIRST_POD" -n kube-system > /dev/null 2>&1; then
            echo_info "    ✓ 可以 get pod（必需权限）"
        else
            echo_warn "    ⚠️  无法 get pod（可能需要检查权限）"
        fi
    else
        echo_warn "    ⚠️  没有可用的 Pod 用于测试"
    fi
    
    # list 不是必需的，但测试一下（使用 head 限制输出）
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get pods -n kube-system 2>&1 | head -1 | grep -q "NAME\|pod" > /dev/null 2>&1; then
        echo_info "    ✓ 可以 list pods（额外权限，非必需）"
    else
        ERROR=$(KUBECONFIG="$KUBECONFIG_FILE" kubectl get pods -n kube-system 2>&1 | head -3)
        echo_warn "    ⚠️  无法 list pods（这是正常的，官方文档不要求 list 权限）"
        echo "    错误: $ERROR"
    fi
    
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get crd network-attachment-definitions.k8s.cni.cncf.io > /dev/null 2>&1; then
        echo_info "    ✓ 可以访问 CRD"
    else
        echo_warn "    ✗ 无法访问 CRD"
    fi
fi

echo ""


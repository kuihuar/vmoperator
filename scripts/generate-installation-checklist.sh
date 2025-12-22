#!/bin/bash

# 生成安装清单（安装后运行）

OUTPUT_FILE="docs/installation/CURRENT_INSTALLATION_STATUS.md"

echo "生成安装清单..."
echo ""

cat > "$OUTPUT_FILE" << EOF
# 当前安装状态清单

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')
EOF

## 系统信息

EOF

# 系统信息
echo "### 节点信息" >> "$OUTPUT_FILE"
kubectl get nodes -o wide >> "$OUTPUT_FILE" 2>/dev/null || echo "无法获取节点信息" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### k3s 版本" >> "$OUTPUT_FILE"
k3s --version >> "$OUTPUT_FILE" 2>/dev/null || echo "无法获取版本" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 组件状态
cat >> "$OUTPUT_FILE" << 'EOF'

## 组件安装状态

### 1. k3s

EOF

if kubectl get nodes &>/dev/null; then
    echo "✅ **已安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**节点状态**:">> "$OUTPUT_FILE"
    kubectl get nodes >> "$OUTPUT_FILE" 2>/dev/null
    echo "" >> "$OUTPUT_FILE"
    echo "**系统 Pods**:">> "$OUTPUT_FILE"
    kubectl get pods -n kube-system | head -10 >> "$OUTPUT_FILE" 2>/dev/null
else
    echo "❌ **未安装**" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

### 2. CDI (Containerized Data Importer)

EOF

if kubectl get namespace cdi &>/dev/null; then
    echo "✅ **已安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**CDI 状态**:">> "$OUTPUT_FILE"
    kubectl get cdi -n cdi >> "$OUTPUT_FILE" 2>/dev/null
    echo "" >> "$OUTPUT_FILE"
    echo "**CDI Pods**:">> "$OUTPUT_FILE"
    kubectl get pods -n cdi >> "$OUTPUT_FILE" 2>/dev/null
else
    echo "❌ **未安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**安装命令**:">> "$OUTPUT_FILE"
    echo '```bash' >> "$OUTPUT_FILE"
    echo 'export CDI_VERSION=v1.62.0' >> "$OUTPUT_FILE"
    echo 'kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml' >> "$OUTPUT_FILE"
    echo 'kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s' >> "$OUTPUT_FILE"
    echo 'kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml' >> "$OUTPUT_FILE"
    echo 'kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s' >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

### 3. KubeVirt

EOF

if kubectl get namespace kubevirt &>/dev/null && kubectl get kubevirt -n kubevirt kubevirt &>/dev/null; then
    echo "✅ **已安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**KubeVirt 状态**:">> "$OUTPUT_FILE"
    kubectl get kubevirt -n kubevirt >> "$OUTPUT_FILE" 2>/dev/null
    echo "" >> "$OUTPUT_FILE"
    echo "**KubeVirt Pods**:">> "$OUTPUT_FILE"
    kubectl get pods -n kubevirt >> "$OUTPUT_FILE" 2>/dev/null
else
    echo "❌ **未安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**安装命令**:">> "$OUTPUT_FILE"
    echo '```bash' >> "$OUTPUT_FILE"
    echo 'export KUBEVIRT_VERSION=v1.2.0' >> "$OUTPUT_FILE"
    echo 'kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml' >> "$OUTPUT_FILE"
    echo 'kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s' >> "$OUTPUT_FILE"
    echo 'kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml' >> "$OUTPUT_FILE"
    echo 'kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s' >> "$OUTPUT_FILE"
    echo 'kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '"'"'{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'"'" >> "$OUTPUT_FILE"
    echo 'NODE_NAME=$(kubectl get nodes -o jsonpath='"'"'{.items[0].metadata.name}'"'"')' >> "$OUTPUT_FILE"
    echo 'kubectl label node $NODE_NAME kubevirt.io/schedulable=true --overwrite' >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

### 4. Ceph/Rook

EOF

if kubectl get namespace rook-ceph &>/dev/null; then
    echo "✅ **已安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**Ceph Cluster 状态**:">> "$OUTPUT_FILE"
    kubectl get cephcluster -n rook-ceph >> "$OUTPUT_FILE" 2>/dev/null || echo "CephCluster 不存在" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**Rook Pods**:">> "$OUTPUT_FILE"
    kubectl get pods -n rook-ceph >> "$OUTPUT_FILE" 2>/dev/null
    echo "" >> "$OUTPUT_FILE"
    echo "**StorageClass**:">> "$OUTPUT_FILE"
    kubectl get storageclass | grep rook >> "$OUTPUT_FILE" 2>/dev/null || echo "未找到 Rook StorageClass" >> "$OUTPUT_FILE"
else
    echo "❌ **未安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**安装命令**:">> "$OUTPUT_FILE"
    echo '```bash' >> "$OUTPUT_FILE"
    echo 'sudo ./scripts/install-ceph-rook.sh' >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

### 5. Multus CNI

EOF

if kubectl get daemonset -n kube-system kube-multus-ds &>/dev/null; then
    echo "✅ **已安装**" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**Multus Pods**:">> "$OUTPUT_FILE"
    kubectl get pods -n kube-system -l app=multus >> "$OUTPUT_FILE" 2>/dev/null
else
    echo "⏸️  **未安装**（可选，仅用于 VM 多网卡）" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

## 配置文件位置

- kubeconfig: `~/.kube/config`
- k3s 配置: `/etc/rancher/k3s/k3s.yaml`
- k3s 数据: `/var/lib/rancher/k3s`
- CNI 配置: `/var/lib/rancher/k3s/agent/etc/cni/net.d`

## 下一步安装

参考: `docs/installation/INSTALLATION_CHECKLIST.md`

EOF

echo "✅ 安装清单已生成: $OUTPUT_FILE"
echo ""
echo "查看清单:"
echo "  cat $OUTPUT_FILE"


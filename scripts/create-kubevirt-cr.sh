#!/bin/bash

# 创建 KubeVirt CR

echo "=== 创建 KubeVirt CR ==="

# 1. 检查 KubeVirt CRD
echo -e "\n1. 检查 KubeVirt CRD..."
if kubectl get crd kubevirts.kubevirt.io 2>/dev/null | grep -q kubevirt; then
    echo "✓ KubeVirt CRD 存在"
else
    echo "❌ KubeVirt CRD 不存在"
    echo "需要先安装 KubeVirt Operator"
    echo "运行: ./scripts/install-kubevirt.sh"
    exit 1
fi

# 2. 检查是否已存在 KubeVirt CR
echo -e "\n2. 检查是否已存在 KubeVirt CR..."
if kubectl get kubevirt -n kubevirt kubevirt 2>/dev/null | grep -q kubevirt; then
    echo "✓ KubeVirt CR 已存在"
    kubectl get kubevirt -n kubevirt kubevirt
    echo ""
    echo "查看状态:"
    kubectl get kubevirt -n kubevirt kubevirt -o yaml | grep -A 20 "status:" | head -25
    exit 0
fi

# 3. 创建 KubeVirt CR
echo -e "\n3. 创建 KubeVirt CR..."
kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: KubeVirt
metadata:
  name: kubevirt
  namespace: kubevirt
spec:
  certificateRotateStrategy: {}
  configuration:
    developerConfiguration:
      useEmulation: true
  customizeComponents: {}
  imagePullPolicy: IfNotPresent
  workloadUpdateStrategy: {}
EOF

if [ $? -eq 0 ]; then
    echo "✓ KubeVirt CR 创建成功"
else
    echo "❌ KubeVirt CR 创建失败"
    exit 1
fi

# 4. 等待并检查状态
echo -e "\n4. 等待 KubeVirt 部署..."
sleep 10

echo "检查 KubeVirt CR 状态:"
kubectl get kubevirt -n kubevirt kubevirt

echo ""
echo "检查 Pods:"
kubectl get pods -n kubevirt

echo ""
echo "等待更多组件启动（这可能需要几分钟）..."
echo "运行以下命令监控进度:"
echo "  watch kubectl get pods -n kubevirt"
echo "  kubectl get kubevirt -n kubevirt kubevirt -o yaml | grep -A 20 status"

echo -e "\n=== 完成 ==="


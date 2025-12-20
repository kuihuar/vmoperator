#!/bin/bash

# 检查 CDI 安装状态

echo "=== CDI 安装检查 ==="

# 1. 检查 CDI CRD
echo -e "\n1. 检查 DataVolume CRD:"
if kubectl get crd datavolumes.cdi.kubevirt.io > /dev/null 2>&1; then
    echo "   ✓ DataVolume CRD 已安装"
    kubectl get crd datavolumes.cdi.kubevirt.io -o jsonpath='{.spec.versions[*].name}' && echo ""
else
    echo "   ✗ DataVolume CRD 未安装"
    echo "   需要安装 CDI:"
    echo "   export CDI_VERSION=\$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print \$2}' | sed 's/,//' | xargs)"
    echo "   kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/\${CDI_VERSION}/cdi-operator.yaml"
    echo "   kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s"
    echo "   kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/\${CDI_VERSION}/cdi-cr.yaml"
fi

# 2. 检查 CDI Operator
echo -e "\n2. 检查 CDI Operator:"
if kubectl get deployment cdi-operator -n cdi > /dev/null 2>&1; then
    echo "   ✓ CDI Operator 已安装"
    kubectl get deployment cdi-operator -n cdi -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' && echo " (Available)"
else
    echo "   ✗ CDI Operator 未安装"
fi

# 3. 检查 CDI CR
echo -e "\n3. 检查 CDI CR:"
if kubectl get cdi cdi -n cdi > /dev/null 2>&1; then
    echo "   ✓ CDI CR 已创建"
    kubectl get cdi cdi -n cdi -o jsonpath='{.status.phase}' && echo ""
else
    echo "   ✗ CDI CR 未创建"
fi

# 4. 检查 CDI Pods
echo -e "\n4. 检查 CDI Pods:"
kubectl get pods -n cdi 2>/dev/null | head -10
if [ $? -eq 0 ]; then
    echo "   ✓ CDI 命名空间存在"
else
    echo "   ✗ CDI 命名空间不存在或无法访问"
fi

# 5. 检查 DataVolume API 版本
echo -e "\n5. 检查 DataVolume API 版本:"
if kubectl api-resources | grep -q datavolumes; then
    echo "   ✓ DataVolume API 资源已注册"
    kubectl api-resources | grep datavolumes
else
    echo "   ✗ DataVolume API 资源未注册"
fi

# 6. 测试创建 DataVolume（dry-run）
echo -e "\n6. 测试 DataVolume API（dry-run）:"
cat <<EOF | kubectl create --dry-run=client -f - 2>&1 | head -5
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: test-dv
  namespace: default
spec:
  source:
    http:
      url: "http://example.com/test.img"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
EOF

echo -e "\n=== 总结 ==="
if kubectl get crd datavolumes.cdi.kubevirt.io > /dev/null 2>&1 && \
   kubectl get deployment cdi-operator -n cdi > /dev/null 2>&1 && \
   kubectl get cdi cdi -n cdi > /dev/null 2>&1; then
    echo "✓ CDI 已正确安装"
else
    echo "✗ CDI 未正确安装，请按照上面的提示安装 CDI"
fi


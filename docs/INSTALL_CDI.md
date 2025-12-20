# CDI 安装指南

## 错误信息

如果看到以下错误：
```
ERROR	failed to reconcile disks	{"error": "no matches for kind \"DataVolume\" in version \"cdi.kubevirt.io/v1beta1\""}
```

这表示 CDI (Containerized Data Importer) 未安装或未正确安装。

## 快速检查

运行检查脚本：
```bash
./scripts/check-cdi-installation.sh
```

## 安装步骤

### 1. 获取 CDI 版本

```bash
# 获取最新稳定版本
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | \
  grep tag_name | grep -v -- '-rc' | head -1 | \
  awk -F': ' '{print $2}' | sed 's/,//' | xargs)

echo "CDI 版本: $CDI_VERSION"
```

或者手动指定版本：
```bash
export CDI_VERSION=v1.62.0
```

### 2. 安装 CDI Operator

```bash
# 下载并安装 CDI Operator
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

# 等待 Operator 就绪
kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s
```

### 3. 安装 CDI CR

```bash
# 安装 CDI CR（这会创建 CDI 实例和所有必要的组件）
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 等待 CDI 就绪
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s
```

### 4. 验证安装

```bash
# 检查 CRD
kubectl get crd datavolumes.cdi.kubevirt.io

# 检查 CDI Pods
kubectl get pods -n cdi

# 检查 CDI 状态
kubectl get cdi -n cdi

# 检查 DataVolume API
kubectl api-resources | grep datavolumes
```

**预期输出**：
```
NAME                              SHORTNAMES   APIVERSION                    NAMESPACED   KIND
datavolumes                       dv           cdi.kubevirt.io/v1beta1       true         DataVolume
```

## 完整安装脚本

```bash
#!/bin/bash

set -e

echo "=== 安装 CDI ==="

# 1. 获取版本
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | \
  grep tag_name | grep -v -- '-rc' | head -1 | \
  awk -F': ' '{print $2}' | sed 's/,//' | xargs)

echo "CDI 版本: $CDI_VERSION"

# 2. 安装 Operator
echo -e "\n=== 安装 CDI Operator ==="
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

echo "等待 CDI Operator 就绪..."
kubectl wait -n cdi deployment cdi-operator --for condition=Available --timeout=300s || {
    echo "CDI Operator 安装失败"
    exit 1
}

# 3. 安装 CDI CR
echo -e "\n=== 安装 CDI CR ==="
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

echo "等待 CDI 就绪..."
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=300s || {
    echo "CDI CR 安装失败"
    exit 1
}

# 4. 验证
echo -e "\n=== 验证安装 ==="
kubectl get crd datavolumes.cdi.kubevirt.io && echo "✓ DataVolume CRD 已安装" || echo "✗ DataVolume CRD 未安装"
kubectl get pods -n cdi && echo "✓ CDI Pods 运行中" || echo "✗ CDI Pods 未运行"
kubectl get cdi -n cdi && echo "✓ CDI CR 已创建" || echo "✗ CDI CR 未创建"

echo -e "\n=== 安装完成 ==="
```

## 故障排查

### 问题 1: Operator 无法启动

```bash
# 检查 Operator Pod 日志
kubectl logs -n cdi deployment/cdi-operator

# 检查 Pod 状态
kubectl describe pod -n cdi -l app=cdi-operator
```

### 问题 2: CRD 未创建

```bash
# 手动检查 CRD
kubectl get crd | grep cdi

# 如果 CRD 不存在，可能需要重新安装 Operator
kubectl delete -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml
```

### 问题 3: CDI CR 无法创建

```bash
# 检查 CDI CR 状态
kubectl get cdi -n cdi -o yaml

# 检查事件
kubectl describe cdi -n cdi cdi
```

### 问题 4: DataVolume API 未注册

```bash
# 检查 API 资源
kubectl api-resources | grep datavolumes

# 如果未找到，可能需要重启 API Server 或等待一段时间
# 或者检查 CRD 是否正确安装
kubectl get crd datavolumes.cdi.kubevirt.io -o yaml
```

## 版本兼容性

CDI 版本应该与 KubeVirt 版本兼容。参考 KubeVirt 文档获取推荐的 CDI 版本。

**常见版本对应**：
- KubeVirt 1.2.x → CDI 1.62.x
- KubeVirt 1.1.x → CDI 1.61.x
- KubeVirt 1.0.x → CDI 1.60.x

## 卸载 CDI

```bash
# 删除 CDI CR
kubectl delete -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml

# 删除 CDI Operator
kubectl delete -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml

# 清理 CRD（可选，会删除所有 DataVolume 资源）
kubectl delete crd datavolumes.cdi.kubevirt.io
```

## 下一步

安装完成后：

1. **验证安装**：
   ```bash
   ./scripts/check-cdi-installation.sh
   ```

2. **测试创建 DataVolume**：
   ```bash
   cat <<EOF | kubectl create -f -
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
   ```

3. **重新运行 Controller**：
   ```bash
   make run
   ```

4. **创建 Wukong 资源**：
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```


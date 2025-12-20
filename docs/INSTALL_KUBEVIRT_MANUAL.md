# KubeVirt 手动安装指南

当网络无法直接访问 GitHub 时，可以使用以下方法手动安装 KubeVirt。

## 方法 1: 使用镜像源

### 使用 ghproxy 镜像

```bash
# 设置版本
export KUBEVIRT_VERSION=v1.2.0

# 使用 ghproxy 镜像安装 Operator
kubectl create -f https://ghproxy.com/https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

# 等待 Operator 就绪
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s

# 使用 ghproxy 镜像安装 CR
kubectl create -f https://ghproxy.com/https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

# 等待 KubeVirt 就绪
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s
```

### 使用其他镜像源

如果 ghproxy 也不可用，可以尝试：

```bash
# 使用 fastgit 镜像
kubectl create -f https://hub.fastgit.xyz/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

# 或使用 gitee 镜像（需要先同步到 gitee）
```

## 方法 2: 手动下载后安装

### 步骤 1: 下载 YAML 文件

在有网络访问的机器上下载：

```bash
# 设置版本
export KUBEVIRT_VERSION=v1.2.0

# 下载 Operator YAML
curl -L -o kubevirt-operator.yaml \
  https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

# 下载 CR YAML
curl -L -o kubevirt-cr.yaml \
  https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
```

如果直接下载也失败，可以：

1. **使用浏览器下载**：
   - 访问：https://github.com/kubevirt/kubevirt/releases
   - 找到对应版本（如 v1.2.0）
   - 下载 `kubevirt-operator.yaml` 和 `kubevirt-cr.yaml`

2. **使用 wget 重试**：
   ```bash
   wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 5 \
     https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
   ```

### 步骤 2: 传输到目标机器

如果下载机器和目标机器不同：

```bash
# 使用 scp 传输
scp kubevirt-operator.yaml kubevirt-cr.yaml user@target-machine:/tmp/

# 或使用其他方式（U盘、内网共享等）
```

### 步骤 3: 安装

在目标机器上：

```bash
# 安装 Operator
kubectl create -f kubevirt-operator.yaml

# 等待 Operator 就绪
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s

# 安装 CR
kubectl create -f kubevirt-cr.yaml

# 等待 KubeVirt 就绪
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s
```

## 方法 3: 使用代理

如果有代理可用：

```bash
# 设置代理
export http_proxy=http://proxy.example.com:8080
export https_proxy=http://proxy.example.com:8080

# 然后正常安装
export KUBEVIRT_VERSION=v1.2.0
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s
```

## 方法 4: 使用固定版本 URL

如果自动获取版本失败，直接使用固定版本：

```bash
# 使用 v1.2.0（稳定版本）
kubectl create -f https://ghproxy.com/https://github.com/kubevirt/kubevirt/releases/download/v1.2.0/kubevirt-operator.yaml
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s
kubectl create -f https://ghproxy.com/https://github.com/kubevirt/kubevirt/releases/download/v1.2.0/kubevirt-cr.yaml
kubectl wait -n kubevirt kubevirt kubevirt --for condition=Available --timeout=600s
```

## 安装后配置

### 1. 启用软件模拟（k3s 环境）

```bash
kubectl patch kubevirt kubevirt -n kubevirt --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

### 2. 添加节点 Label

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME kubevirt.io/schedulable=true
```

## 验证安装

```bash
# 检查 Operator Pods
kubectl get pods -n kubevirt

# 检查 KubeVirt CR
kubectl get kubevirt -n kubevirt

# 检查 CRD
kubectl get crd | grep kubevirt.io

# 检查 API 资源
kubectl api-resources | grep virtualmachine
```

## 常见问题

### 问题 1: 下载超时

**解决**：
- 使用镜像源（ghproxy）
- 手动下载后安装
- 使用代理

### 问题 2: 镜像拉取失败

如果 Operator Pod 无法拉取镜像：

```bash
# 检查镜像地址
kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}'

# 在节点上手动拉取
sudo crictl pull quay.io/kubevirt/virt-operator:v1.2.0
```

### 问题 3: 网络问题

如果所有方法都失败，考虑：

1. **使用离线安装包**：
   - 在有网络的机器上下载所有需要的镜像
   - 导出为 tar 文件
   - 传输到目标机器并导入

2. **使用内网镜像仓库**：
   - 搭建私有镜像仓库
   - 同步所需镜像
   - 修改 YAML 中的镜像地址

## 推荐的安装顺序

1. **先尝试镜像源**（最快）：
   ```bash
   export KUBEVIRT_VERSION=v1.2.0
   kubectl create -f https://ghproxy.com/https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
   ```

2. **如果失败，手动下载**（最可靠）

3. **如果还是失败，使用代理**（如果有）


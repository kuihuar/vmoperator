# KubeVirt Operator 无法启动问题排查

## 问题现象

`virt-operator` Pods 一直处于 `ContainerCreating` 状态：

```bash
kubectl get pods -n kubevirt
NAME                                 READY   STATUS              RESTARTS   AGE
virt-operator-584bd468cd-d87fb       0/1     ContainerCreating   0          14h
virt-operator-584bd468cd-xssgv       0/1     ContainerCreating   0          14h
```

## 快速诊断

运行诊断脚本：
```bash
./scripts/check-kubevirt-operator.sh
```

## 常见原因和解决方案

### 1. 镜像拉取失败

**检查方法**：
```bash
# 查看 Pod 事件
kubectl describe pod -n kubevirt <pod-name> | grep -A 10 Events

# 常见错误信息：
# - "Failed to pull image"
# - "ImagePullBackOff"
# - "ErrImagePull"
```

**解决方案**：

**A. 检查网络连接**：
```bash
# 在节点上测试镜像拉取
docker pull quay.io/kubevirt/virt-operator:v1.2.0
# 或
crictl pull quay.io/kubevirt/virt-operator:v1.2.0
```

**B. 配置镜像仓库**（如果使用私有仓库）：
```bash
# 创建 imagePullSecret
kubectl create secret docker-registry regcred \
  --docker-server=<registry-url> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n kubevirt

# 更新 deployment
kubectl patch deployment virt-operator -n kubevirt -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"regcred"}]}}}}'
```

**C. 使用国内镜像源**（如果在中国）：
```bash
# 修改 deployment 使用镜像代理
kubectl edit deployment virt-operator -n kubevirt
# 将镜像地址改为代理地址，例如：
# quay.io/kubevirt/virt-operator:v1.2.0
# 改为
# registry.cn-hangzhou.aliyuncs.com/kubevirt/virt-operator:v1.2.0
```

### 2. 节点资源不足

**检查方法**：
```bash
# 检查节点资源
kubectl describe node | grep -A 10 "Allocated resources"

# 检查节点条件
kubectl get node -o wide
```

**解决方案**：
```bash
# 如果节点资源不足，需要：
# 1. 增加节点资源（CPU/内存）
# 2. 清理其他 Pods
# 3. 添加新节点
```

### 3. 存储问题

**检查方法**：
```bash
# 检查 PV/PVC
kubectl get pv
kubectl get pvc -n kubevirt

# 检查存储类
kubectl get storageclass
```

**解决方案**：
```bash
# 确保有可用的 StorageClass
kubectl get storageclass

# 如果需要，创建本地存储类（k3s 通常自带 local-path）
```

### 4. CNI 网络问题

**检查方法**：
```bash
# 检查 CNI Pods
kubectl get pods -n kube-system | grep -E "flannel|calico|weave"

# 检查节点网络
kubectl get nodes -o wide
```

**解决方案**：
```bash
# k3s 默认使用 Flannel，如果 CNI 有问题：
# 1. 重启 k3s
sudo systemctl restart k3s

# 2. 检查 CNI 配置
sudo cat /var/lib/rancher/k3s/agent/etc/flannel/net-conf.json
```

### 5. 节点未就绪

**检查方法**：
```bash
kubectl get node
kubectl describe node | grep -A 5 "Conditions:"
```

**解决方案**：
```bash
# 如果节点有 NotReady 状态，检查：
# 1. kubelet 服务
sudo systemctl status k3s

# 2. 节点资源
free -h
df -h

# 3. 系统日志
sudo journalctl -u k3s -n 50
```

## 详细排查步骤

### 步骤 1: 查看 Pod 详情

```bash
POD_NAME=$(kubectl get pods -n kubevirt -l app=virt-operator -o name | head -1 | cut -d/ -f2)
kubectl describe pod -n kubevirt $POD_NAME
```

重点关注：
- `Events:` 部分
- `Status:` 部分
- `Conditions:` 部分

### 步骤 2: 查看节点事件

```bash
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -20
```

### 步骤 3: 检查镜像

```bash
# 查看使用的镜像
kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}'

# 在节点上测试拉取
docker pull $(kubectl get deployment -n kubevirt virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}')
```

### 步骤 4: 检查资源限制

```bash
# 查看 deployment 的资源请求
kubectl get deployment -n kubevirt virt-operator -o yaml | grep -A 10 resources
```

## 快速修复尝试

### 方法 1: 删除并重新创建

```bash
# 删除 deployment（会自动重新创建）
kubectl delete deployment -n kubevirt virt-operator

# 等待重新创建
kubectl get pods -n kubevirt -w
```

### 方法 2: 重新安装 KubeVirt

如果问题持续，考虑重新安装：

```bash
# 1. 删除 KubeVirt CR
kubectl delete kubevirt -n kubevirt kubevirt

# 2. 删除 Operator
kubectl delete deployment -n kubevirt virt-operator

# 3. 清理 CRD（可选，会删除所有 VM）
# kubectl delete crd virtualmachines.kubevirt.io virtualmachineinstances.kubevirt.io

# 4. 重新安装
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
kubectl wait -n kubevirt deployment virt-operator --for condition=Available --timeout=300s
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
```

### 方法 3: 检查 k3s 日志

```bash
# 查看 k3s 服务日志
sudo journalctl -u k3s -n 100 --no-pager

# 查看 k3s 容器日志（如果使用 Docker）
docker logs k3s 2>&1 | tail -50
```

## 特定环境问题

### k3s 环境

k3s 使用 containerd，检查：

```bash
# 检查 containerd
sudo systemctl status containerd

# 检查镜像
sudo crictl images | grep virt-operator

# 手动拉取镜像
sudo crictl pull quay.io/kubevirt/virt-operator:v1.2.0
```

### 网络受限环境

如果无法访问 quay.io，需要：

1. **配置镜像代理**：
   ```bash
   # 在 k3s 配置中添加镜像仓库
   sudo vi /etc/rancher/k3s/registries.yaml
   ```

2. **使用离线镜像**：
   ```bash
   # 在可访问网络的机器上拉取镜像
   docker pull quay.io/kubevirt/virt-operator:v1.2.0
   docker save quay.io/kubevirt/virt-operator:v1.2.0 > virt-operator.tar
   
   # 传输到目标机器并加载
   docker load < virt-operator.tar
   ```

## 验证修复

修复后，验证：

```bash
# 1. 检查 Pod 状态
kubectl get pods -n kubevirt

# 2. 等待 Pod Ready
kubectl wait -n kubevirt pod -l app=virt-operator --for condition=Ready --timeout=300s

# 3. 检查 Operator 日志
kubectl logs -n kubevirt -l app=virt-operator --tail=50

# 4. 检查 KubeVirt CR
kubectl get kubevirt -n kubevirt
```

## 获取帮助

如果问题仍然存在，收集以下信息：

```bash
# 1. Pod 详情
kubectl describe pod -n kubevirt <pod-name> > pod-describe.txt

# 2. Pod 日志（如果可用）
kubectl logs -n kubevirt <pod-name> > pod-logs.txt

# 3. 节点信息
kubectl describe node > node-info.txt

# 4. 事件
kubectl get events -n kubevirt --sort-by='.lastTimestamp' > events.txt

# 5. k3s 日志
sudo journalctl -u k3s -n 100 > k3s-logs.txt
```


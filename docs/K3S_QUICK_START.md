# k3s 环境快速启动指南

## 前置检查 ✅

运行检查脚本确认环境就绪：

```bash
./scripts/check-k3s-image-access.sh
```

**检查结果应该显示**：
- ✅ 虚拟机 IP 地址正确
- ✅ HTTP 服务器可访问
- ✅ StorageClass 存在（local-path）
- ✅ Pod 可以访问 HTTP 服务器

## 快速启动步骤

### 1. 确保 Wukong CRD 已安装

```bash
# 在项目目录中
make install

# 验证 CRD
kubectl get crd wukongs.vm.novasphere.dev
```

### 2. 确保 Controller 正在运行

**选项 A：本地运行（开发模式）**
```bash
# 确保 kubeconfig 已配置
export KUBECONFIG=~/.kube/config

# 运行 controller
make run
```

**选项 B：部署到集群（生产模式）**
```bash
# 构建镜像
make docker-build IMG=your-registry/novasphere:latest

# 部署
make deploy IMG=your-registry/novasphere:latest
```

### 3. 创建 Wukong 资源

```bash
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

### 4. 观察创建过程

```bash
# 查看 Wukong 状态
kubectl get wukong ubuntu-noble-local -o yaml

# 查看 DataVolume 状态
kubectl get datavolume -A

# 查看 PVC 状态
kubectl get pvc

# 查看 VM 状态
kubectl get vm

# 查看 VMI 状态
kubectl get vmi

# 查看 virt-launcher Pod
kubectl get pods | grep virt-launcher
```

### 5. 查看详细日志

```bash
# 查看 DataVolume 导入进度
kubectl describe datavolume ubuntu-noble-local-system

# 查看 importer Pod 日志
kubectl logs -f importer-ubuntu-noble-local-system

# 查看 VM 事件
kubectl describe vm ubuntu-noble-local-vm

# 查看 VMI 事件
kubectl describe vmi ubuntu-noble-local-vm
```

## 预期时间线

1. **0-30 秒**：Wukong 资源创建，Controller 开始协调
2. **30 秒-2 分钟**：DataVolume 创建，importer Pod 启动
3. **2-10 分钟**：镜像导入（取决于镜像大小和网络速度）
4. **10-15 分钟**：PVC 绑定，VM 创建，VMI 启动

## 常见状态检查

### Wukong 状态

```bash
# 查看 Wukong 状态
kubectl get wukong ubuntu-noble-local -o jsonpath='{.status.phase}'

# 查看详细状态
kubectl get wukong ubuntu-noble-local -o yaml | grep -A 20 status:
```

**预期状态变化**：
- `Creating` → `Pending` → `Running`

### DataVolume 状态

```bash
kubectl get datavolume ubuntu-noble-local-system -o jsonpath='{.status.phase}'
```

**预期状态变化**：
- `Pending` → `ImportScheduled` → `ImportInProgress` → `Succeeded`

### VM 状态

```bash
kubectl get vm ubuntu-noble-local-vm -o jsonpath='{.status.printableStatus}'
```

**预期状态**：
- `Stopped` → `Starting` → `Running`

## 故障排查

### 问题 1: DataVolume 一直 Pending

```bash
# 检查 PVC
kubectl get pvc ubuntu-noble-local-system
kubectl describe pvc ubuntu-noble-local-system

# 检查 StorageClass
kubectl get storageclass local-path

# 检查节点资源
kubectl describe node | grep -A 10 "Allocated resources"
```

### 问题 2: importer Pod 无法下载镜像

```bash
# 查看 importer Pod 日志
kubectl logs importer-ubuntu-noble-local-system

# 在 Pod 中测试连接
kubectl run -it --rm test-curl --image=curlimages/curl --restart=Never -- \
  curl -I http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img
```

### 问题 3: VM 无法启动

```bash
# 检查 virt-handler
kubectl get pods -n kubevirt | grep virt-handler
kubectl logs -n kubevirt -l app=virt-handler --tail=50

# 检查 virt-launcher Pod
kubectl get pods | grep virt-launcher
kubectl describe pod <virt-launcher-pod-name>

# 检查 KubeVirt 配置
kubectl get kubevirt -n kubevirt -o yaml | grep -A 5 useEmulation
```

### 问题 4: 调度失败

```bash
# 检查节点 label
kubectl get nodes --show-labels | grep kubevirt.io/schedulable

# 如果没有，添加 label
kubectl label node <node-name> kubevirt.io/schedulable=true

# 检查 VMI 调度事件
kubectl describe vmi ubuntu-noble-local-vm | grep -A 10 Events
```

## 验证 VM 运行

### 1. 检查 VMI 状态

```bash
kubectl get vmi ubuntu-noble-local-vm
```

**预期输出**：
```
NAME                    AGE   PHASE     IP            NODENAME
ubuntu-noble-local-vm   5m    Running   10.42.0.10    k3s-node
```

### 2. 获取 VMI IP

```bash
kubectl get vmi ubuntu-noble-local-vm -o jsonpath='{.status.interfaces[0].ipAddress}'
```

### 3. 通过 VNC 访问（如果配置了）

```bash
# 获取 VNC 端口
kubectl get vmi ubuntu-noble-local-vm -o jsonpath='{.status.vnc}'
```

### 4. 通过 SSH 访问（如果配置了 Cloud-Init）

```bash
# 获取 IP
VMI_IP=$(kubectl get vmi ubuntu-noble-local-vm -o jsonpath='{.status.interfaces[0].ipAddress}')

# SSH 连接（需要配置 SSH 密钥）
ssh ubuntu@$VMI_IP
```

## 清理资源

```bash
# 删除 Wukong（会自动清理相关资源）
kubectl delete wukong ubuntu-noble-local

# 手动清理（如果自动清理失败）
kubectl delete vm ubuntu-noble-local-vm
kubectl delete datavolume ubuntu-noble-local-system
kubectl delete pvc ubuntu-noble-local-system
```

## 下一步

1. ✅ 环境检查通过
2. ✅ 配置文件已更新
3. ⏭️ 安装 CRD：`make install`
4. ⏭️ 运行 Controller：`make run`
5. ⏭️ 创建 Wukong：`kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml`
6. ⏭️ 观察状态：使用上面的命令监控创建过程


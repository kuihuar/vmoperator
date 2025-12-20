# 暂时跳过 KubeVirt 的替代方案

## 当前情况

由于网络限制，无法拉取 Docker Hub 镜像，导致 KubeVirt Operator 无法启动。

## 可以继续的工作

即使 KubeVirt 暂时无法运行，你仍然可以：

### 1. 安装和测试 CDI

CDI 不依赖 KubeVirt，可以独立安装和测试：

```bash
# 安装 CDI
./scripts/install-cdi.sh

# 验证 CDI 安装
./scripts/check-cdi-installation.sh

# 测试创建 DataVolume
cat <<EOF | kubectl create -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: test-dv
  namespace: default
spec:
  source:
    http:
      url: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 5Gi
    storageClassName: local-path
EOF
```

### 2. 安装和测试 Wukong CRD

Wukong CRD 可以独立安装和验证：

```bash
# 安装 Wukong CRD
make install

# 验证 CRD
kubectl get crd wukongs.vm.novasphere.dev

# 创建 Wukong 资源（虽然无法创建 VM，但可以验证 CRD 和 Controller）
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml

# 查看 Wukong 状态
kubectl get wukong
kubectl describe wukong ubuntu-noble-local
```

### 3. 测试 Controller 逻辑

即使无法创建 VM，Controller 仍然会尝试协调资源：

```bash
# 运行 Controller
make run

# 在另一个终端创建 Wukong
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml

# 观察 Controller 日志
# 应该会看到：
# - 网络协调（如果没有配置 networks，会使用默认网络）
# - 存储协调（创建 DataVolume）
# - VM 协调（会失败，因为 KubeVirt 未就绪，但可以验证逻辑）
```

### 4. 验证 DataVolume 创建

即使 VM 无法创建，DataVolume 应该可以正常工作：

```bash
# 查看 DataVolume
kubectl get datavolume

# 查看 DataVolume 详情
kubectl describe datavolume ubuntu-noble-local-system

# 查看 importer Pod
kubectl get pods | grep importer

# 查看 importer Pod 日志
kubectl logs -f importer-ubuntu-noble-local-system
```

### 5. 测试网络配置（如果配置了 Multus）

如果配置了 Multus 网络：

```bash
# 检查 NetworkAttachmentDefinition
kubectl get networkattachmentdefinition

# 测试创建 NAD
cat <<EOF | kubectl create -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: test-net
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-test",
      "ipam": {
        "type": "dhcp"
      }
    }
EOF
```

## 当前可以验证的功能

### ✅ 可以测试

1. **Wukong CRD 定义** - 验证 API 定义是否正确
2. **Controller 基本逻辑** - 验证 reconcile 流程
3. **网络协调** - 验证 Multus NAD 创建
4. **存储协调** - 验证 DataVolume/PVC 创建
5. **CDI 功能** - 验证镜像导入

### ❌ 暂时无法测试

1. **VM 创建** - 需要 KubeVirt Operator 运行
2. **VMI 启动** - 需要 KubeVirt 组件
3. **实际 VM 运行** - 需要完整的 KubeVirt 环境

## 下一步建议

### 选项 1: 继续开发其他功能

即使 KubeVirt 暂时无法运行，可以：

1. **完善 Controller 逻辑**
   - 优化错误处理
   - 添加更多验证
   - 完善状态同步

2. **测试存储功能**
   - 验证 DataVolume 创建
   - 测试不同镜像源（HTTP、registry）
   - 验证 PVC 绑定

3. **测试网络功能**
   - 配置 Multus
   - 测试不同网络类型
   - 验证网络配置

### 选项 2: 解决网络问题后再继续

1. **配置代理/VPN**
2. **使用内网镜像仓库**
3. **手动下载镜像**

### 选项 3: 使用其他环境

如果当前环境网络限制太严格，可以考虑：

1. **使用云环境**（有更好的网络访问）
2. **使用本地 Linux 机器**（可能有更好的网络）
3. **使用 VPN 连接**

## 当前状态总结

- ✅ k3s 已安装
- ✅ Wukong CRD 可以安装
- ✅ Controller 可以运行
- ✅ CDI 可以安装（如果网络允许）
- ⚠️  KubeVirt Operator 无法启动（网络问题）
- ❌ VM 无法创建（需要 KubeVirt）

## 建议

**现在可以做的：**

1. **安装 CDI**（如果网络允许）：
   ```bash
   ./scripts/install-cdi.sh
   ```

2. **安装 Wukong CRD**：
   ```bash
   make install
   ```

3. **运行 Controller 并测试**：
   ```bash
   make run
   # 在另一个终端
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```

4. **观察 Controller 日志**，验证协调逻辑是否正确

即使无法创建 VM，这些测试仍然有价值，可以验证：
- CRD 定义是否正确
- Controller 逻辑是否正确
- 存储协调是否正常
- 网络协调是否正常

等网络问题解决后，KubeVirt 启动，VM 创建应该就能正常工作了。


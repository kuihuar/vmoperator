# Multus 配置规划文档

## 一、安装前的准备工作

### 1.1 确认需求

- [ ] 是否需要 Multus？
  - 如果只需要 Ceph 存储，**可以暂不安装 Multus**
  - 如果需要多网络接口（如虚拟机多网卡），需要 Multus

- [ ] 当前环境状态
  - k3s 版本：`k3s --version`
  - 默认 CNI：k3s 默认使用 Flannel
  - 是否已有其他 CNI 插件？

### 1.2 环境检查

```bash
# 1. 检查 k3s CNI 配置目录
CNI_DIR="/var/lib/rancher/k3s/agent/etc/cni/net.d"
ls -la $CNI_DIR

# 2. 检查是否已有 Multus 配置
ls -la $CNI_DIR/*multus* 2>/dev/null || echo "未找到 Multus 配置"

# 3. 检查 Multus DaemonSet
kubectl get daemonset -n kube-system kube-multus-ds 2>/dev/null || echo "未找到 Multus DaemonSet"

# 4. 检查 Multus Pod 状态
kubectl get pods -n kube-system -l app=multus 2>/dev/null || echo "未找到 Multus Pod"
```

## 二、配置规划

### 2.1 路径规划

| 配置项 | 值 | 说明 |
|--------|-----|------|
| k3s CNI 配置目录 | `/var/lib/rancher/k3s/agent/etc/cni/net.d` | k3s 默认 CNI 配置目录 |
| Multus 配置文件 | `00-multus.conf` | 主配置文件，按字母顺序排在前面 |
| DaemonSet 主机挂载路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d` | 与 CNI 配置目录一致 |
| DaemonSet Pod 内挂载点 | `/host/etc/cni/net.d` | 标准路径，避免与 Pod 内其他路径冲突 |
| kubeconfig 配置文件路径（Pod 内） | `/host/etc/cni/net.d/multus.d/multus.kubeconfig` | 与挂载点对应 |
| kubeconfig 主机文件路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig` | 与 CNI 目录对应 |

### 2.2 配置文件规划

#### 2.2.1 Multus 主配置文件：`00-multus.conf`

```json
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "/host/etc/cni/net.d/multus.d/multus.kubeconfig",
  "confDir": "/etc/cni/multus/net.d",
  "cniDir": "/var/lib/cni/multus",
  "binDir": "/opt/cni/bin",
  "logFile": "/var/log/multus.log",
  "logLevel": "verbose",
  "capabilities": {
    "portMappings": true
  },
  "namespaceIsolation": false,
  "clusterNetwork": "flannel",  // k3s 默认 CNI 名称
  "defaultNetworks": [],
  "systemNamespaces": ["kube-system"],
  "multusNamespace": "kube-system"
}
```

**关键配置说明**：
- `kubeconfig`：必须使用 Pod 内的实际路径（与 DaemonSet 挂载点对应）
- `clusterNetwork`：k3s 默认使用 Flannel，需要确认实际名称
- `defaultNetworks`：空数组，表示默认只使用主网络接口

#### 2.2.2 kubeconfig 文件

```bash
# 创建目录
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d

# 从 k3s kubeconfig 创建
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 修改 server 地址为集群内部地址
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://kubernetes.default.svc:443|g' \
  /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig

# 设置权限
sudo chmod 644 /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
```

#### 2.2.3 DaemonSet 挂载配置

```yaml
volumes:
  - name: cni
    hostPath:
      path: /var/lib/rancher/k3s/agent/etc/cni/net.d
      type: Directory
  - name: cnibin
    hostPath:
      path: /var/lib/rancher/k3s/data/cni/bin  # k3s CNI 二进制目录
      type: Directory

volumeMounts:
  - name: cni
    mountPath: /host/etc/cni/net.d
  - name: cnibin
    mountPath: /host/opt/cni/bin
```

## 三、安装步骤规划

### 方案 A：使用 Helm 安装（推荐）

**优点**：自动处理路径配置，减少错误

```bash
# 1. 添加 Helm repo
helm repo add multus https://k8snetworkplumbingwg.github.io/multus-cni/
helm repo update

# 2. 使用 k3s 专用 values 文件
helm install multus multus/multus \
  --namespace kube-system \
  --create-namespace \
  --values config/multus-values-k3s.yaml

# 3. 验证安装
kubectl get pods -n kube-system -l app=multus
kubectl get daemonset -n kube-system kube-multus-ds
```

### 方案 B：使用 kubectl apply（手动控制）

**优点**：完全控制配置，适合调试

```bash
# 1. 使用安装脚本
./scripts/install-multus-kubectl-k3s.sh

# 2. 验证配置
./scripts/find-multus-kubeconfig-path.sh
```

## 四、验证清单

安装或修复后，按以下清单验证：

- [ ] **1. Multus Pod 正常运行**
  ```bash
  kubectl get pods -n kube-system -l app=multus
  # 应该显示 Running 状态
  ```

- [ ] **2. kubeconfig 文件存在且可访问**
  ```bash
  # 主机上
  sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig
  
  # Pod 内
  MULTUS_POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n kube-system $MULTUS_POD -- ls -la /host/etc/cni/net.d/multus.d/multus.kubeconfig
  ```

- [ ] **3. 配置文件路径正确**
  ```bash
  # 检查配置文件中的路径
  sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | jq '.kubeconfig'
  # 应该显示：/host/etc/cni/net.d/multus.d/multus.kubeconfig
  
  # 检查 DaemonSet 挂载
  kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cni")].hostPath.path}'
  kubectl get daemonset -n kube-system kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="cni")].mountPath}'
  ```

- [ ] **4. 测试创建普通 Pod**
  ```bash
  kubectl run test-pod --image=nginx --rm -it --restart=Never
  # 应该能正常创建并运行
  ```

- [ ] **5. 测试 Ceph 等组件不受影响**
  ```bash
  kubectl get pods -n rook-ceph
  # 应该能正常创建和运行
  ```

## 五、问题排查

### 5.1 如果 Multus Pod CrashLoopBackOff

1. 检查日志
   ```bash
   kubectl logs -n kube-system -l app=multus --tail=50
   ```

2. 常见错误：
   - `kubeconfig file not found`：检查文件路径和挂载配置
   - `failed to get k8s client`：检查 kubeconfig 内容是否正确
   - `daemon-config.json not found`：检查配置文件是否存在

### 5.2 如果其他 Pod（如 Ceph）无法创建

1. 检查错误信息
   ```bash
   kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Events:"
   ```

2. 如果错误是 `Multus: error getting k8s client`：
   - Multus 的 kubeconfig 配置有问题
   - 按照上面的验证清单检查配置

3. 如果暂时不需要 Multus：
   - 禁用 Multus（删除或重命名配置文件）
   - 删除 Multus DaemonSet
   - 重启受影响的 Pod

## 六、决策树

```
是否需要 Multus？
├─ 否 → 暂不安装，直接使用 Ceph 等组件
│
└─ 是 → 选择安装方式
   ├─ Helm（推荐）→ 使用 config/multus-values-k3s.yaml
   │                → 验证安装
   │
   └─ kubectl apply → 使用 scripts/install-multus-kubectl-k3s.sh
                      → 验证配置
                      → 修复 kubeconfig 路径（如需要）
```

## 七、关键原则

1. **路径一致性**：配置文件中的路径必须与 DaemonSet 挂载路径对应
2. **先验证后使用**：安装后先测试普通 Pod，再测试关键组件
3. **保留回退方案**：如果出现问题，知道如何禁用 Multus
4. **文档化配置**：记录实际的路径配置，便于后续维护


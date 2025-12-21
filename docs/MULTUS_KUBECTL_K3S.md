# 使用 kubectl apply 在 k3s 上安装 Multus

根据 [Multus 官方文档](https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html) 和 [k3s Multus 文档](https://docs.k3s.io/networking/multus-ipams) 使用 `kubectl apply` 方式安装 Multus。

## 安装方式

### 方法 1: 使用安装脚本（推荐）

```bash
./scripts/install-multus-kubectl-k3s.sh
```

脚本会自动：
1. 检测 k3s 版本和 CNI 路径
2. 下载 Multus DaemonSet YAML
3. 修改挂载路径以适配 k3s
4. 创建 Multus 配置文件
5. 应用 DaemonSet

### 方法 2: 手动安装

#### 步骤 1: 确定 k3s CNI 路径

```bash
# 新版本 (2024年10月及之后)
# CNI 二进制: /var/lib/rancher/k3s/data/cni/
# 旧版本
# CNI 二进制: /var/lib/rancher/k3s/data/current/bin/

# CNI 配置目录（所有版本）
# /var/lib/rancher/k3s/agent/etc/cni/net.d

# 检查路径
ls -la /var/lib/rancher/k3s/data/cni/ 2>/dev/null || ls -la /var/lib/rancher/k3s/data/current/bin/
ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
```

#### 步骤 2: 下载并修改 DaemonSet

```bash
# 下载原始 YAML
curl -sL https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml -o multus-daemonset.yaml

# 修改挂载路径（使用编辑器或 sed）
# 将 volumes 中的 path 修改为 k3s 路径：
# - name: cni
#   hostPath:
#     path: /var/lib/rancher/k3s/agent/etc/cni/net.d  # 修改这里
# - name: cnibin
#   hostPath:
#     path: /var/lib/rancher/k3s/data/cni/  # 或 /var/lib/rancher/k3s/data/current/bin/  # 修改这里
```

#### 步骤 3: 应用 DaemonSet

```bash
kubectl apply -f multus-daemonset.yaml
```

#### 步骤 4: 创建 Multus 配置文件

参考 [Multus 配置文档](https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html) 创建配置文件：

```bash
# 创建配置目录
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d

# 创建 Multus 主配置文件
sudo tee /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf > /dev/null <<EOF
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig",
  "confDir": "/etc/cni/multus/net.d",
  "cniDir": "/var/lib/cni/multus",
  "binDir": "/opt/cni/bin",
  "logFile": "/var/log/multus.log",
  "logLevel": "verbose",
  "capabilities": {
    "portMappings": true
  },
  "namespaceIsolation": false,
  "clusterNetwork": "default",
  "defaultNetworks": [],
  "systemNamespaces": ["kube-system"],
  "multusNamespace": "kube-system"
}
EOF

# 创建 daemon-config.json (Thick Plugin 需要)
sudo tee /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json > /dev/null <<EOF
{
  "binDir": "/opt/cni/bin",
  "confDir": "/etc/cni/net.d",
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log"
}
EOF
```

## 配置说明

### clusterNetwork 配置

`clusterNetwork` 用于指定默认 CNI 插件（如 Flannel）。可以是：

1. **NetworkAttachmentDefinition 名称**（如果定义在 kube-system 命名空间）
2. **CNI 配置文件名中的 name 值**
3. **CNI 配置文件路径**

示例（检测 Flannel）：

```bash
# 查看默认 CNI 配置
ls /var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf*

# 查看配置中的 name
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist | jq '.name'
# 输出: "cni0" 或类似

# 然后在 Multus 配置中使用该名称
"clusterNetwork": "cni0"
```

### 使用 delegates（替代 clusterNetwork）

如果不想使用 `clusterNetwork`，可以使用 `delegates`：

```json
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig",
  "delegates": [{
    "type": "flannel",
    "delegate": {
      "hairpinMode": true
    }
  }]
}
```

**注意**: `clusterNetwork` 和 `delegates` 是互斥的，只能使用其中一个。

### 完整配置选项

参考 [Multus 配置文档](https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html) 的完整选项：

- `confDir`: CNI 配置文件目录，默认 `/etc/cni/multus/net.d`
- `cniDir`: Multus CNI 数据目录，默认 `/var/lib/cni/multus`
- `binDir`: CNI 插件二进制目录，默认 `/opt/cni/bin`
- `logLevel`: 日志级别（`debug`, `verbose`, `error`, `panic`）
- `namespaceIsolation`: 命名空间隔离（默认 `false`）
- `systemNamespaces`: 系统命名空间列表
- `defaultNetworks`: 默认附加的网络列表

## 验证安装

```bash
# 检查 Pod 状态
kubectl get pods -n kube-system -l app=multus

# 检查 DaemonSet
kubectl get daemonset -n kube-system kube-multus-ds

# 检查 CRD
kubectl get crd | grep networkattachment

# 查看日志
kubectl logs -n kube-system -l app=multus

# 检查配置文件
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json
```

## 创建 NetworkAttachmentDefinition

安装完成后，可以创建 `NetworkAttachmentDefinition`：

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-conf
  namespace: default
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.1.0/24",
        "rangeStart": "192.168.1.200",
        "rangeEnd": "192.168.1.216",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ],
        "gateway": "192.168.1.1"
      }
    }
```

## 卸载

```bash
# 删除 DaemonSet
kubectl delete -f multus-daemonset.yaml

# 删除配置文件（可选）
sudo rm -f /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
sudo rm -rf /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d

# 删除 CRD（可选，会删除所有 NetworkAttachmentDefinition）
kubectl delete crd networkattachmentdefinitions.k8s.cni.cncf.io
```

## 故障排查

### Pod 无法启动

1. 检查日志：`kubectl logs -n kube-system -l app=multus`
2. 检查配置文件路径是否正确
3. 检查 DaemonSet 挂载路径是否匹配 k3s 路径

### 配置文件找不到

1. 确认配置文件在 `/var/lib/rancher/k3s/agent/etc/cni/net.d/`
2. 检查 Pod 内挂载：`kubectl exec -n kube-system <multus-pod> -- ls -la /host/etc/cni/net.d/`

### clusterNetwork 配置错误

1. 检查默认 CNI 配置文件名和内容
2. 确保 `clusterNetwork` 值匹配配置中的 `name` 字段

## 参考文档

- [Multus 配置参考](https://k8snetworkplumbingwg.github.io/multus-cni/docs/configuration.html)
- [k3s Multus 文档](https://docs.k3s.io/networking/multus-ipams)
- [Multus GitHub](https://github.com/k8snetworkplumbingwg/multus-cni)


# Multus CNI 插件二进制文件说明

## 关键理解

**Multus 有两个部分**：

1. **Multus CNI 插件二进制** - 由 kubelet 在**主机上**直接调用
2. **Multus DaemonSet** - 运行在 **Pod 内**的守护进程

## CNI 插件调用流程

当 kubelet 创建 Pod 时：

```
1. kubelet (主机进程)
   ↓
2. 读取 CNI 配置文件 (/var/lib/rancher/k3s/agent/etc/cni/net.d/*.conf)
   ↓
3. 调用 CNI 二进制文件 (在主机上运行)
   ↓
4. CNI 二进制读取配置文件中的路径（必须是主机路径）
   ↓
5. Multus CNI 插件使用 kubeconfig 访问 Kubernetes API
```

## Multus CNI 二进制文件位置

### k3s 环境

Multus 二进制文件通常安装在：
- `/var/lib/rancher/k3s/data/current/bin/multus`
- 或 `/opt/cni/bin/multus`（如果手动安装）

### 安装方式

Multus DaemonSet 通常有一个 **init 容器**负责安装二进制文件：

```yaml
initContainers:
  - name: install-multus-binary
    image: ...
    command:
      - cp
      - /usr/src/multus-cni/bin/multus
      - /host/opt/cni/bin/multus  # 复制到主机的 /opt/cni/bin/
    volumeMounts:
      - name: cnibin
        mountPath: /host/opt/cni/bin
```

对应的主机路径挂载：
```yaml
volumes:
  - name: cnibin
    hostPath:
      path: /var/lib/rancher/k3s/data/current/bin  # 或 /opt/cni/bin
```

## 为什么路径必须是主机路径？

**关键点**：CNI 插件是**主机进程**，不是 Pod 内进程。

当 Multus CNI 插件被 kubelet 调用时：
- 它在**主机上**运行（与 kubelet 同一进程空间）
- 它读取配置文件中的路径
- **配置文件中的路径必须是主机绝对路径**，不能是 Pod 内路径

### 错误示例

```json
{
  "kubeconfig": "/host/etc/cni/net.d/multus.d/multus.kubeconfig"
}
```

❌ **错误**：`/host/etc/cni/net.d/...` 是 Pod 内路径，CNI 插件在主机上无法访问

### 正确示例

```json
{
  "kubeconfig": "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"
}
```

✅ **正确**：这是主机绝对路径，CNI 插件可以直接访问

## Multus DaemonSet vs CNI 插件

| 组件 | 运行位置 | 作用 | 需要的路径 |
|------|---------|------|-----------|
| **Multus CNI 插件** | 主机上（kubelet 调用） | 处理 Pod 网络创建 | **主机路径** |
| **Multus DaemonSet** | Pod 内 | 守护进程，处理额外功能 | Pod 内路径或挂载的主机路径 |

## 检查 Multus 二进制文件

运行脚本检查：

```bash
./scripts/find-multus-binary.sh
```

或手动检查：

```bash
# 检查 k3s CNI 目录
ls -lh /var/lib/rancher/k3s/data/current/bin/multus

# 检查标准 CNI 目录
ls -lh /opt/cni/bin/multus

# 检查 DaemonSet 安装位置
kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 10 "cnibin"
```

## 修复 kubeconfig 路径

配置文件中的路径必须是主机绝对路径：

```bash
# 修复配置
sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf | \
  jq '.kubeconfig = "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"' | \
  sudo tee /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf.tmp > /dev/null

sudo mv /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf.tmp \
       /var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
```

## 总结

- **Multus CNI 插件二进制**：由 Multus DaemonSet 的 init 容器安装到主机
- **运行位置**：主机上（kubelet 调用），不是 Pod 内
- **配置文件路径**：必须是**主机绝对路径**，不能是 Pod 内路径（如 `/host/...`）
- **kubeconfig 路径**：必须指向主机文件系统的路径


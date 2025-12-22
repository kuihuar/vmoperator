# Multus 路径问题完整分析

## 1. 问题分析：为什么路径一直不存在？

### 1.1 错误信息分析

错误信息：
```
cni-conf-dir is not found: stat /host/var/lib/rancher/k3s/agent/var/lib/rancher/k3s/agent/etc/cni/net.d: no such file or directory
```

**关键发现**：路径重复了！
- 实际路径：`/host/var/lib/rancher/k3s/agent/var/lib/rancher/k3s/agent/etc/cni/net.d`
- 正确路径应该是：`/host/etc/cni/net.d` 或 `/var/lib/rancher/k3s/agent/etc/cni/net.d`

### 1.2 路径重复的原因

**根本原因**：`daemon-config.json` 中的 `confDir` 配置错误

1. **DaemonSet 挂载配置**：
   - 主机路径：`/var/lib/rancher/k3s/agent/etc/cni/net.d`
   - Pod 内挂载点：`/host/etc/cni/net.d`（假设）

2. **daemon-config.json 配置错误**：
   - 如果配置为：`"confDir": "/var/lib/rancher/k3s/agent/etc/cni/net.d"`（主机路径）
   - Multus 容器在 `/host` 下查找，变成：`/host/var/lib/rancher/k3s/agent/etc/cni/net.d`
   - 但容器内可能又拼接了路径，导致重复

3. **Multus Thick Plugin 的工作方式**：
   - Thick Plugin 在 Pod 内运行
   - 它读取 `daemon-config.json` 中的 `confDir`
   - `confDir` 必须是 **Pod 内的路径**（挂载后的路径），不是主机路径

### 1.3 为什么一直解决不了？

1. **混淆了两种路径**：
   - 主机路径：`/var/lib/rancher/k3s/agent/etc/cni/net.d`
   - Pod 内路径：`/host/etc/cni/net.d`（通过挂载访问主机路径）

2. **配置文件中的路径类型不一致**：
   - `00-multus.conf` 中的 `kubeconfig`：应该是主机路径（CNI 插件在主机运行）
   - `daemon-config.json` 中的 `confDir`：应该是 Pod 内路径（Thick Plugin 在 Pod 内运行）

3. **没有正确理解 Multus 的两种模式**：
   - **Thin Plugin**：CNI 插件在主机运行，配置文件路径是主机路径
   - **Thick Plugin**：Daemon 在 Pod 内运行，`daemon-config.json` 路径是 Pod 内路径

## 2. 项目中尝试过的解决方法

### 2.1 方法 1：修改 daemon-config.json 中的 confDir

**尝试的脚本**：
- `fix-daemon-config-now.sh`
- `fix-multus-daemon-config.sh`
- `create-daemon-config-correct.sh`

**尝试的配置**：
- `"confDir": "/host/etc/cni/net.d"` ✅ 正确
- `"confDir": "/var/lib/rancher/k3s/agent/etc/cni/net.d"` ❌ 错误（主机路径）

**问题**：有时文件不存在，有时路径配置错误

### 2.2 方法 2：修改 DaemonSet 挂载路径

**尝试的脚本**：
- `fix-multus-daemonset-mount.sh`
- `fix-multus-mount-path.sh`

**尝试的修改**：
- 修改 `hostPath` 指向正确的 k3s 目录
- 修改 `mountPath` 为 `/host/etc/cni/net.d`

**问题**：挂载配置可能正确，但 `daemon-config.json` 中的路径仍然错误

### 2.3 方法 3：创建配置文件

**尝试的脚本**：
- `install-multus-kubectl-k3s.sh`（第 219-231 行）

**创建的配置**：
```json
{
  "confDir": "/etc/cni/net.d"  // ❌ 错误：这是容器内的路径，但容器内没有这个目录
}
```

**问题**：使用了容器内路径，但容器内没有挂载这个路径

### 2.4 方法 4：检查并修复路径不匹配

**尝试的脚本**：
- `fix-multus-path-mismatch.sh`

**问题**：没有正确理解 Thick Plugin 的路径要求

## 3. 官方文档如何配置

### 3.1 Multus 官方文档

根据 [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md)：

**对于标准 Kubernetes**：
- `daemon-config.json` 中的 `confDir` 通常是 `/etc/cni/net.d`（容器内路径）
- 但这是假设 DaemonSet 将主机 `/etc/cni/net.d` 挂载到容器内的 `/etc/cni/net.d`

**对于 k3s**：
- k3s 的 CNI 配置目录是 `/var/lib/rancher/k3s/agent/etc/cni/net.d`
- DaemonSet 需要将这个目录挂载到容器内
- `daemon-config.json` 中的 `confDir` 应该是**挂载后的 Pod 内路径**

### 3.2 k3s 官方文档

根据 [k3s Multus 文档](https://docs.k3s.io/networking/multus-ipams)：

**关键点**：
- k3s 使用自定义的 CNI 路径
- 需要正确配置 DaemonSet 的挂载
- `daemon-config.json` 中的路径必须是 Pod 内路径

### 3.3 Thick Plugin 的路径要求

**Thick Plugin 模式**：
- Daemon 在 Pod 内运行
- 读取 `daemon-config.json` 中的配置
- `confDir` 必须是 Pod 内可以访问的路径（通过挂载）

**正确的配置流程**：
1. DaemonSet 将主机路径挂载到 Pod 内（如 `/host/etc/cni/net.d`）
2. `daemon-config.json` 中的 `confDir` 使用 Pod 内路径（如 `/host/etc/cni/net.d`）
3. Multus Daemon 在 Pod 内读取配置

## 4. 正确的配置方案

### 4.1 DaemonSet 挂载配置

```yaml
volumes:
  - name: cni
    hostPath:
      path: /var/lib/rancher/k3s/agent/etc/cni/net.d  # 主机路径
      type: Directory
volumeMounts:
  - name: cni
    mountPath: /host/etc/cni/net.d  # Pod 内路径
```

### 4.2 daemon-config.json 配置

```json
{
  "binDir": "/opt/cni/bin",
  "confDir": "/host/etc/cni/net.d",  // ✅ Pod 内路径（挂载后的路径）
  "cniVersion": "0.3.1",
  "logLevel": "verbose",
  "logFile": "/var/log/multus.log",
  "kubeconfig": "/host/etc/cni/net.d/multus.d/multus.kubeconfig"  // ✅ Pod 内路径
}
```

### 4.3 00-multus.conf 配置

```json
{
  "kubeconfig": "/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig"  // ✅ 主机路径（CNI 插件在主机运行）
}
```

## 5. 路径配置总结

| 配置项 | 路径类型 | 路径示例 | 说明 |
|--------|---------|---------|------|
| **DaemonSet hostPath** | 主机路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d` | 主机上的实际目录 |
| **DaemonSet mountPath** | Pod 内路径 | `/host/etc/cni/net.d` | Pod 内访问主机路径的挂载点 |
| **daemon-config.json confDir** | Pod 内路径 | `/host/etc/cni/net.d` | Thick Plugin 在 Pod 内运行，使用 Pod 内路径 |
| **daemon-config.json kubeconfig** | Pod 内路径 | `/host/etc/cni/net.d/multus.d/multus.kubeconfig` | Thick Plugin 在 Pod 内运行 |
| **00-multus.conf kubeconfig** | 主机路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/multus.kubeconfig` | CNI 插件在主机运行 |

## 6. 为什么之前的修复都失败了？

1. **没有检查 DaemonSet 的实际挂载配置**：直接假设挂载点是 `/host/etc/cni/net.d`
2. **混淆了主机路径和 Pod 内路径**：在 `daemon-config.json` 中使用了主机路径
3. **没有验证配置是否正确**：修复后没有验证 Pod 内是否可以访问
4. **多次修复导致配置混乱**：不同脚本使用了不同的路径配置

## 7. 正确的修复流程

1. **检查 DaemonSet 实际挂载配置**
2. **根据挂载配置确定 Pod 内路径**
3. **创建/修复 daemon-config.json，使用 Pod 内路径**
4. **验证 Pod 内可以访问配置**
5. **重启 Pod 应用配置**


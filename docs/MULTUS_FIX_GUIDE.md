# Multus 路径问题修复指南

## 问题描述

Multus Pod 一直处于 `CrashLoopBackOff` 状态，错误信息：
```
cni-conf-dir is not found: stat /host/var/lib/rancher/k3s/agent/var/lib/rancher/k3s/agent/etc/cni/net.d: no such file or directory
```

**关键问题**：路径重复，说明 `daemon-config.json` 中的 `confDir` 配置错误。

## 快速修复

运行修复脚本：

```bash
sudo ./scripts/fix-multus-path-final.sh
```

## 修复原理

### 1. 问题根源

- **Thick Plugin 模式**：Multus Daemon 在 Pod 内运行
- **路径混淆**：`daemon-config.json` 中使用了主机路径，而不是 Pod 内路径
- **路径重复**：Multus 在 `/host` 下查找，又拼接了主机路径，导致重复

### 2. 正确的配置

| 配置项 | 路径类型 | 示例 |
|--------|---------|------|
| DaemonSet hostPath | 主机路径 | `/var/lib/rancher/k3s/agent/etc/cni/net.d` |
| DaemonSet mountPath | Pod 内路径 | `/host/etc/cni/net.d` |
| daemon-config.json confDir | **Pod 内路径** | `/host/etc/cni/net.d` |

### 3. 修复步骤

1. **检查 DaemonSet 挂载配置**
   - 获取 `hostPath`（主机路径）
   - 获取 `mountPath`（Pod 内路径）

2. **创建正确的 daemon-config.json**
   - 使用 Pod 内路径（`mountPath`）作为 `confDir`
   - 使用 Pod 内路径作为 `kubeconfig`

3. **验证并重启**
   - 验证文件存在
   - 重启 Pod 应用配置

## 详细分析

请参考：[MULTUS_PATH_ISSUE_ANALYSIS.md](./MULTUS_PATH_ISSUE_ANALYSIS.md)

## 验证修复

修复后，检查 Pod 状态：

```bash
kubectl get pods -n kube-system -l app=multus
kubectl logs -n kube-system -l app=multus -c kube-multus --tail=20
```

如果 Pod 处于 `Running` 状态，且日志中没有路径错误，说明修复成功。

## 如果修复失败

1. **检查 DaemonSet 配置**：
   ```bash
   kubectl get daemonset -n kube-system kube-multus-ds -o yaml | grep -A 10 "volumes:"
   ```

2. **检查 Pod 内路径**：
   ```bash
   POD=$(kubectl get pods -n kube-system -l app=multus -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n kube-system $POD -- ls -la /host/etc/cni/net.d
   ```

3. **检查 daemon-config.json**：
   ```bash
   sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/multus.d/daemon-config.json | jq '.'
   ```

## 相关文档

- [Multus 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md)
- [k3s Multus 文档](https://docs.k3s.io/networking/multus-ipams)
- [Thick Plugin 文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/thick-plugin.md)


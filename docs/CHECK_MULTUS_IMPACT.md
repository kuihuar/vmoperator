# 检查 Multus 是否影响 Longhorn Manager

## 问题背景

用户怀疑 `kube-multus-ds-ftm9q`（Multus CNI 的 DaemonSet Pod）可能影响了 Longhorn Manager 的启动。

## Multus 简介

**Multus CNI** 是一个 Kubernetes CNI 元插件，用于为 Pod 提供多个网络接口。它通过以下方式工作：

1. **默认网络**: Multus 本身不提供默认网络，它依赖于主 CNI（在 k3s 中是 Flannel）
2. **额外网络**: 当 Pod 使用 Multus 注解时，Multus 会为 Pod 添加额外的网络接口
3. **安装位置**: Multus 通过 DaemonSet 部署在 `kube-system` 命名空间

## Multus 是否会影响 Longhorn Manager？

### 一般情况下：**不会直接影响**

- ✅ **默认网络不受影响**: 如果 Longhorn Manager Pod 没有配置 Multus 注解，它使用默认的网络（Flannel），Multus 不会影响它
- ✅ **Multus 是可选功能**: Multus 只有在 Pod 明确请求额外网络时才会介入

### 可能影响的情况：

1. **Multus Pod 本身有问题**:
   - Multus DaemonSet Pod 无法启动或崩溃
   - 可能导致 CNI 配置混乱

2. **Manager Pod 配置了 Multus 网络**:
   - 如果 Manager Pod 的 annotations 中有 `k8s.v1.cni.cncf.io/networks`
   - 可能导致网络配置问题，影响 Service 连接

3. **Multus 配置错误**:
   - CNI 配置文件错误
   - 网络路径配置错误（k3s 特定问题）

## 诊断步骤

### 1. 检查 Multus 安装位置

Multus 通过以下方式安装（根据项目文档）：

```bash
# 官方安装方式（项目文档中提到的）
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
```

### 2. 运行诊断脚本

```bash
./scripts/check-multus-impact-on-longhorn.sh
```

脚本会检查：
- Multus DaemonSet 和 Pod 状态
- Multus 日志中的错误
- Longhorn Manager Pod 是否使用 Multus 网络
- Service 和 Endpoints 连接状态

### 3. 手动检查

```bash
# 1. 检查 Multus Pod 状态
kubectl get pods -n kube-system -l app=multus

# 2. 查看 Multus 日志
kubectl logs -n kube-system kube-multus-ds-ftm9q --tail=50

# 3. 检查 Manager Pod 是否使用 Multus
kubectl get pod -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks}'

# 如果没有输出，说明未使用 Multus

# 4. 检查 Manager Pod 的网络接口
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-system $MANAGER_POD -- ip addr show

# 5. 测试网络连接
kubectl exec -n longhorn-system $MANAGER_POD -- nslookup longhorn-admission-webhook.longhorn-system.svc
```

## 如果 Multus 有问题

### 方案 1: 修复 Multus（如果 Manager 依赖 Multus 网络）

如果发现 Manager Pod 使用了 Multus 网络，需要修复 Multus：

```bash
# 运行 Multus 修复脚本
./scripts/fix-multus-k3s.sh
```

### 方案 2: 禁用 Multus 对 Manager 的影响（如果不需要）

如果 Manager Pod 不应该使用 Multus，但被错误配置了，需要移除 Multus 注解：

```bash
# 检查 DaemonSet 配置
kubectl get daemonset -n longhorn-system longhorn-manager -o yaml | grep -A 10 "annotations:"

# 如果发现 Multus 注解，需要修改 DaemonSet（不建议手动修改，可能影响 Helm 管理）
```

### 方案 3: 临时删除 Multus（如果确定不需要）

**警告**: 只有在确认不需要 Multus 功能时才这样做。

```bash
# 删除 Multus DaemonSet
kubectl delete -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# 注意：这会影响所有依赖 Multus 的 Pod
```

## 结论

**最可能的情况**：

1. ✅ **Multus 不是根本原因**: Longhorn Manager 的 webhook 循环依赖问题是主要问题
2. ✅ **Multus 运行正常**: 如果 Multus Pod 状态正常，它不应该影响 Longhorn Manager
3. ⚠️ **如果 Multus 有问题**: 可能会加剧网络问题，但不会直接导致 webhook 连接失败

**建议的排查顺序**：

1. 先解决 webhook 循环依赖问题（主要问题）
2. 检查并修复 DNS 问题（k3s systemd-resolved）
3. 检查 Multus 状态（次要，通常不影响）
4. 如果以上都正常，考虑降级 Longhorn 版本

## 相关文档

- [Multus 安装指南](MULTUS_INSTALLATION.md)
- [修复 Multus k3s 配置](FIX_MULTUS_K3S.md)
- [修复 Longhorn Webhook 循环依赖](FIX_WEBHOOK_CIRCULAR_DEPENDENCY.md)
- [k3s Longhorn 问题排查](K3S_LONGHORN_ISSUES.md)


# Multus RBAC 配置（官方文档标准）

根据 [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md)，以下是标准的 RBAC 配置。

## 官方文档中的 ClusterRole 配置

```yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: multus
rules:
  - apiGroups: ["k8s.cni.cncf.io"]
    resources:
      - '*'
    verbs:
      - '*'
  - apiGroups:
      - ""
    resources:
      - pods
      - pods/status
    verbs:
      - get
      - update
```

## 关键点

### 1. 权限范围

**必需的权限**：
- `k8s.cni.cncf.io` API group：所有资源，所有操作（`*`）
- `pods` 和 `pods/status`：只需要 `get` 和 `update`

**不需要的权限**：
- ❌ `list` pods（官方文档不要求）
- ❌ `watch` pods（官方文档不要求）
- ❌ `nodes` 资源（官方文档不要求）

### 2. 为什么只需要 get 和 update？

Multus CNI 插件的工作方式：
1. **get pods**：获取 Pod 信息，读取网络注解
2. **update pods/status**：更新 Pod 的网络状态

Multus **不需要**：
- 列出所有 Pods（它只处理特定的 Pod）
- 监听 Pod 变化（由 kubelet 调用，不是主动监听）

### 3. 验证权限时的注意事项

当使用 `kubectl get pods` 测试时，如果失败，**这是正常的**，因为：
- `get pods`（不带名称）实际上需要 `list` 权限
- 官方文档只要求 `get`（单个资源）和 `update`

正确的测试方式：
```bash
# 测试 get（单个 Pod）- 这是必需的
kubectl get pod <pod-name> -n <namespace> --as=system:serviceaccount:kube-system:multus

# 测试 update - 这是必需的
kubectl auth can-i update pods --as=system:serviceaccount:kube-system:multus -n kube-system

# list 测试失败是正常的（不是必需的）
kubectl get pods -n kube-system --as=system:serviceaccount:kube-system:multus
# 这个可能会失败，但这是正常的
```

## 项目中的配置

### 当前配置问题

在 `fix-multus-rbac.sh` 中，我最初添加了 `list` 和 `watch` 权限，这**不符合官方文档**。

**已修复**：现在脚本使用官方文档的标准配置。

### 正确的配置

```yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: multus
rules:
  - apiGroups: ["k8s.cni.cncf.io"]
    resources:
      - '*'
    verbs:
      - '*'
  - apiGroups:
      - ""
    resources:
      - pods
      - pods/status
    verbs:
      - get
      - update
```

## 验证脚本

`check-multus-permissions-detailed.sh` 脚本已更新，现在：
1. ✅ 检查官方文档要求的权限（get 和 update）
2. ✅ 说明 list 权限不是必需的
3. ✅ 使用正确的测试方式

## 总结

- **遵循官方文档**：只配置必需的权限（get 和 update）
- **最小权限原则**：不添加不必要的权限
- **验证时注意**：list 测试失败是正常的，因为不是必需的

参考：
- [Multus CNI 官方文档 - how-to-use.md](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md)
- [Multus CNI 配置文档 - configuration.md](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/configuration.md)


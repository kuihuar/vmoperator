# 安装 Wukong CRD

## 🔴 错误信息

```
error: resource mapping not found for name: "ubuntu-noble-local" namespace: ""
no matches for kind "Wukong" in version "vm.novasphere.dev/v1alpha1"
ensure CRDs are installed first
```

这个错误表示 **Wukong CRD 还没有安装**到 Kubernetes 集群中。

## ✅ 解决方案：安装 CRD

### 方法 1: 使用 make install（推荐）

```bash
# 在项目根目录执行
make install
```

这个命令会：
1. 生成 CRD YAML 文件
2. 安装 CRD 到 Kubernetes 集群
3. 安装 RBAC 权限

### 方法 2: 手动安装

如果 `make install` 失败，可以手动安装：

```bash
# 1. 生成 manifests（如果还没生成）
make manifests

# 2. 安装 CRD
kubectl apply -f config/crd/bases/vm.novasphere.dev_wukongs.yaml

# 3. 验证安装
kubectl get crd wukongs.vm.novasphere.dev
```

## 🔍 验证 CRD 安装

### 检查 CRD 是否存在

```bash
# 查看 Wukong CRD
kubectl get crd wukongs.vm.novasphere.dev

# 查看详细信息
kubectl describe crd wukongs.vm.novasphere.dev
```

**应该看到**:
```
NAME                      CREATED AT
wukongs.vm.novasphere.dev   2024-01-01T00:00:00Z
```

### 验证 API 资源

```bash
# 查看 API 资源
kubectl api-resources | grep wukong

# 应该看到:
# wukongs          vm.novasphere.dev/v1alpha1
```

## 📝 完整安装流程

### 步骤 1: 确保在项目根目录

```bash
cd /Users/jianfenliu/Workspace/vmoperator
```

### 步骤 2: 安装 CRD

```bash
make install
```

**预期输出**:
```
/Users/jianfenliu/Workspace/vmoperator/bin/controller-gen rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
kubectl apply -f config/crd/bases/vm.novasphere.dev_wukongs.yaml
customresourcedefinition.apiextensions.k8s.io/wukongs.vm.novasphere.dev created
```

### 步骤 3: 验证安装

```bash
# 检查 CRD
kubectl get crd wukongs.vm.novasphere.dev

# 检查 API 资源
kubectl api-resources | grep wukong
```

### 步骤 4: 创建 Wukong 资源

```bash
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

## 🐛 故障排查

### 问题 1: make install 失败

**错误**: `make: *** No rule to make target 'install'`

**解决**:
```bash
# 检查 Makefile 是否存在
ls -la Makefile

# 如果不存在，可能需要初始化项目
# 或者手动安装 CRD
kubectl apply -f config/crd/bases/vm.novasphere.dev_wukongs.yaml
```

### 问题 2: CRD 文件不存在

**错误**: `config/crd/bases/vm.novasphere.dev_wukongs.yaml: No such file or directory`

**解决**:
```bash
# 生成 manifests
make manifests

# 然后再安装
make install
```

### 问题 3: 权限不足

**错误**: `Error from server (Forbidden)`

**解决**:
```bash
# 检查当前用户权限
kubectl auth can-i create crd

# 如果返回 no，需要：
# 1. 使用有权限的用户
# 2. 或者联系集群管理员
```

### 问题 4: CRD 已存在但版本不匹配

**错误**: `resource already exists`

**解决**:
```bash
# 删除旧 CRD（谨慎操作）
kubectl delete crd wukongs.vm.novasphere.dev

# 重新安装
make install
```

## ✅ 安装成功标志

当看到以下输出时，说明安装成功：

```bash
$ kubectl get crd wukongs.vm.novasphere.dev
NAME                      CREATED AT
wukongs.vm.novasphere.dev   2024-01-01T00:00:00Z

$ kubectl api-resources | grep wukong
wukongs          vm.novasphere.dev/v1alpha1   true         Wukong
```

## 📚 相关命令

### 查看所有 CRD

```bash
kubectl get crd
```

### 查看 CRD 定义

```bash
kubectl get crd wukongs.vm.novasphere.dev -o yaml
```

### 删除 CRD（如果需要）

```bash
# 注意：删除 CRD 会删除所有相关的 Wukong 资源
kubectl delete crd wukongs.vm.novasphere.dev
```

## 🎯 下一步

CRD 安装成功后：

1. **创建 Wukong 资源**:
   ```bash
   kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
   ```

2. **监控创建过程**:
   ```bash
   kubectl get wukong ubuntu-noble-local -w
   ```

3. **查看详细信息**:
   ```bash
   kubectl describe wukong ubuntu-noble-local
   ```

---

**提示**: 如果 `make install` 失败，检查是否在项目根目录，以及 Makefile 是否存在。


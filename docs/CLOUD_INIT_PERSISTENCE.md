# Cloud-Init 数据持久化说明

## Cloud-Init 数据存储位置

### 1. 在 VM 内部（虚拟机文件系统）

Cloud-Init 在 VM 内部运行时，数据存储在以下位置：

#### 配置数据
- **`/var/lib/cloud/`**: Cloud-Init 的主要数据目录
  - `instance/`: 当前实例的配置和数据
  - `seed/`: 初始种子数据
  - `data/`: 运行时数据
  - `instances/`: 所有实例的历史数据

#### 日志文件
- **`/var/log/cloud-init.log`**: Cloud-Init 主日志
- **`/var/log/cloud-init-output.log`**: Cloud-Init 输出日志（包括用户脚本输出）

#### 元数据缓存
- **`/var/lib/cloud/instance/`**: 当前实例的元数据缓存
  - `user-data.txt`: 用户数据（cloud-init 配置）
  - `meta-data.json`: 元数据
  - `vendor-data.txt`: 供应商数据

### 2. 在 Kubernetes 中（VM 定义）

Cloud-Init 配置存储在 KubeVirt VirtualMachine 资源中：

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
spec:
  template:
    spec:
      volumes:
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              users:
                - name: ubuntu
                  passwd: $6$...
```

**持久化位置**：
- **etcd**: Kubernetes 集群的 etcd 数据库（VM 定义）
- **VM YAML**: 通过 `kubectl get vm <name> -o yaml` 可以看到完整配置

## 持久化机制

### 1. VM 定义中的配置（持久化）

**位置**: Kubernetes etcd + VM YAML 定义

**特点**:
- ✅ **持久化**: VM 定义存储在 etcd 中，即使 VM 删除重建，配置也会保留
- ✅ **版本控制**: 可以通过 Git 管理 VM 定义 YAML
- ✅ **可重复**: 每次创建/重建 VM 时，cloud-init 配置都会应用

**示例**:
```bash
# 查看 VM 定义（包含 cloud-init 配置）
kubectl get vm ubuntu-noble-local-vm -o yaml

# 导出 VM 定义
kubectl get vm ubuntu-noble-local-vm -o yaml > vm-backup.yaml
```

### 2. VM 内部的运行时数据（临时）

**位置**: VM 文件系统（`/var/lib/cloud/`）

**特点**:
- ⚠️ **临时性**: 存储在 VM 的磁盘中，如果磁盘被删除，数据会丢失
- ✅ **运行时**: 只在 VM 运行期间有效
- ⚠️ **不持久化**: 如果使用新的磁盘镜像，这些数据不会保留

**示例**:
```bash
# 在 VM 内部查看
virtctl console ubuntu-noble-local-vm
# 登录后执行：
ls -la /var/lib/cloud/
cat /var/lib/cloud/instance/user-data.txt
```

## Cloud-Init 执行时机

### 首次启动
1. VM 首次启动时
2. Cloud-Init 读取 `cloudInitNoCloud` volume 中的配置
3. 执行配置（创建用户、设置密码、配置网络等）
4. 将配置缓存到 `/var/lib/cloud/instance/`

### 后续启动
1. Cloud-Init 检测到已经初始化过（`/var/lib/cloud/instance/sem/config_scripts_user` 存在）
2. **不会重新执行**用户数据配置
3. 只执行网络配置等需要每次启动都执行的配置

### 重新初始化
如果需要重新执行 cloud-init：
1. 删除 VM 的磁盘（或使用新磁盘）
2. 删除 `/var/lib/cloud/instance/` 目录（在 VM 内部）
3. 重启 VM

## 数据持久化策略

### 方案 1: 通过 VM 定义持久化（推荐）

**优点**:
- 配置存储在 Kubernetes 中，持久化且可版本控制
- 每次创建/重建 VM 都会应用配置
- 可以通过 Git 管理

**实现**:
```yaml
# 在 Wukong 或 VM 定义中配置
spec:
  template:
    spec:
      volumes:
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              users:
                - name: ubuntu
                  passwd: $6$...
```

### 方案 2: 通过自定义镜像持久化

**优点**:
- 配置已经内置在镜像中
- 不需要每次启动都执行 cloud-init

**实现**:
1. 创建基础镜像
2. 在镜像中预配置用户和密码
3. 使用该镜像创建 VM

### 方案 3: 通过 Secret 持久化敏感数据

**优点**:
- 敏感数据（如密码）存储在 Kubernetes Secret 中
- 可以加密存储
- 可以轮换

**实现**:
```yaml
# 创建 Secret
kubectl create secret generic vm-user-password \
  --from-literal=password='your-password'

# 在 VM 定义中引用
spec:
  template:
    spec:
      volumes:
        - name: cloudinitdisk
          cloudInitNoCloud:
            userDataSecretRef:
              name: vm-user-password
```

## 检查 Cloud-Init 状态

### 在 VM 内部检查

```bash
# 连接到 VM
virtctl console ubuntu-noble-local-vm

# 检查 cloud-init 状态
sudo cloud-init status
# 输出: status: done 或 status: running

# 查看日志
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# 查看配置
cat /var/lib/cloud/instance/user-data.txt
```

### 在 Kubernetes 中检查

```bash
# 查看 VM 定义（包含 cloud-init 配置）
kubectl get vm ubuntu-noble-local-vm -o yaml | grep -A 20 "cloudInitNoCloud"

# 查看 VMI 状态
kubectl get vmi ubuntu-noble-local-vm -o yaml | grep -A 10 "conditions"
```

## 重要提示

### 1. 配置持久化 vs 运行时数据

- **VM 定义中的配置**: 持久化在 Kubernetes etcd 中 ✅
- **VM 内部的运行时数据**: 存储在 VM 磁盘中，磁盘删除后丢失 ⚠️

### 2. Cloud-Init 只执行一次

- Cloud-Init 在首次启动时执行用户数据配置
- 后续启动不会重新执行（除非删除 `/var/lib/cloud/instance/`）
- 如果需要修改配置，需要：
  1. 修改 VM 定义中的 cloud-init 配置
  2. 删除 VM 磁盘或使用新磁盘
  3. 重新创建 VM

### 3. 密码哈希的持久化

- 密码哈希存储在 VM 定义中（etcd）
- 即使 VM 删除，只要 VM 定义还在，密码配置就会保留
- 重建 VM 时，新 VM 会使用相同的密码

## 总结

| 数据类型 | 存储位置 | 持久化 | 说明 |
|---------|---------|--------|------|
| Cloud-Init 配置 | Kubernetes etcd (VM 定义) | ✅ 是 | 通过 `kubectl get vm -o yaml` 查看 |
| Cloud-Init 运行时数据 | VM 文件系统 (`/var/lib/cloud/`) | ⚠️ 否 | 存储在 VM 磁盘中，磁盘删除后丢失 |
| Cloud-Init 日志 | VM 文件系统 (`/var/log/`) | ⚠️ 否 | 存储在 VM 磁盘中 |

**关键点**：
- ✅ **配置持久化**: Cloud-Init 配置存储在 Kubernetes 中，持久化且可版本控制
- ⚠️ **运行时数据不持久化**: VM 内部的 cloud-init 数据存储在磁盘中，磁盘删除后丢失
- ✅ **可重复应用**: 每次创建/重建 VM 时，配置都会从 VM 定义中读取并应用


# Cloud-Init 用户配置快速开始

## 已完成的功能

✅ 在 Wukong CRD 中添加了 `cloudInitUser` 字段
✅ 支持配置用户名、密码（明文或哈希）、sudo 权限、shell、用户组等
✅ 自动生成 Cloud-Init 配置
✅ 更新了示例文件

## 快速使用

### 1. 更新现有 Wukong 资源

编辑现有的 Wukong 资源，添加 `cloudInitUser` 配置：

```bash
kubectl edit wukong ubuntu-noble-local
```

添加以下内容：

```yaml
spec:
  cloudInitUser:
    name: ubuntu
    password: "ubuntu123"  # 明文密码（开发环境）
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: "/bin/bash"
    lockPasswd: false
```

### 2. 或使用新的示例文件

```bash
# 查看示例
cat config/samples/vm_v1alpha1_wukong_with_user.yaml

# 应用示例（需要修改密码哈希）
kubectl apply -f config/samples/vm_v1alpha1_wukong_with_user.yaml
```

### 3. 生成密码哈希（推荐）

```bash
# 方法 1: 使用 openssl
echo -n "your-password" | openssl passwd -1 -stdin

# 方法 2: 使用 Python（更安全）
python3 -c "import crypt; print(crypt.crypt('your-password', crypt.mksalt(crypt.METHOD_SHA512)))"
```

然后在 YAML 中使用 `passwordHash` 而不是 `password`。

### 4. 重启 VM 以应用配置

```bash
# 停止 VM
virtctl stop ubuntu-noble-local-vm
# 或
kubectl patch vm ubuntu-noble-local-vm --type merge -p '{"spec":{"running":false}}'

# 等待几秒
sleep 5

# 启动 VM
virtctl start ubuntu-noble-local-vm
# 或
kubectl patch vm ubuntu-noble-local-vm --type merge -p '{"spec":{"running":true}}'
```

### 5. 登录 VM

```bash
# 获取 VMI 名称
kubectl get vmi

# 连接到控制台
virtctl console ubuntu-noble-local-vm

# 输入用户名和密码登录
```

## 配置选项

### 最小配置（仅用户名和密码）

```yaml
cloudInitUser:
  name: ubuntu
  password: "ubuntu123"
```

### 完整配置

```yaml
cloudInitUser:
  name: ubuntu
  passwordHash: "$6$rounds=4096$salt$hashed_password"  # 推荐
  sudo: "ALL=(ALL) NOPASSWD:ALL"
  shell: "/bin/bash"
  groups:
    - sudo
    - adm
    - docker
  lockPasswd: false
```

## 注意事项

1. **首次启动**：Cloud-Init 只在 VM 首次启动时执行用户配置
2. **重启 VM**：如果 VM 已经启动，需要删除并重新创建，或使用新磁盘
3. **密码安全**：生产环境建议使用 `passwordHash` 而不是 `password`
4. **持久化**：配置存储在 Kubernetes etcd 中，持久化且可版本控制

## 验证

```bash
# 1. 检查 VM 定义中是否有 cloud-init 配置
kubectl get vm ubuntu-noble-local-vm -o yaml | grep -A 30 "cloudInitNoCloud"

# 2. 检查 VMI 状态
kubectl get vmi

# 3. 登录 VM 验证用户
virtctl console ubuntu-noble-local-vm
# 输入用户名和密码
```

## 下一步

1. 运行 `make manifests` 生成更新的 CRD（如果还没有运行）
2. 运行 `make install` 安装更新的 CRD
3. 更新现有的 Wukong 资源，添加 `cloudInitUser` 配置
4. 重启 VM 以应用配置
5. 使用新配置的用户名和密码登录


# Cloud-Init 用户配置指南

## 概述

Wukong CRD 现在支持通过 `cloudInitUser` 字段配置 VM 的默认用户和密码，无需手动编辑 VM 资源。

## 配置方式

### 方式 1: 使用明文密码（仅开发环境）

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
spec:
  cloudInitUser:
    name: ubuntu
    password: "ubuntu123"  # 明文密码
```

**注意**：明文密码会存储在 etcd 中，生产环境不推荐使用。

### 方式 2: 使用密码哈希（推荐）

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
spec:
  cloudInitUser:
    name: ubuntu
    passwordHash: "$6$rounds=4096$salt$hashed_password"
```

**生成密码哈希**：

```bash
# 方法 1: 使用 openssl
echo -n "your-password" | openssl passwd -1 -stdin

# 方法 2: 使用 Python（SHA512，更安全）
python3 -c "import crypt; print(crypt.crypt('your-password', crypt.mksalt(crypt.METHOD_SHA512)))"
```

## 完整配置示例

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: my-vm
spec:
  cpu: 2
  memory: 4Gi
  
  cloudInitUser:
    name: ubuntu                    # 用户名（必填）
    password: "ubuntu123"           # 明文密码（可选，与 passwordHash 二选一）
    # passwordHash: "$6$..."        # 密码哈希（可选，更安全）
    sudo: "ALL=(ALL) NOPASSWD:ALL"  # Sudo 权限（可选，默认值）
    shell: "/bin/bash"              # Shell（可选，默认值）
    groups:                         # 用户组（可选）
      - sudo
      - adm
      - docker
    lockPasswd: false               # 是否锁定密码（可选，默认 false）
  
  disks:
    - name: system
      size: 20Gi
      storageClassName: local-path
      boot: true
  
  startStrategy:
    autoStart: true
```

## 字段说明

| 字段 | 类型 | 必填 | 说明 | 默认值 |
|------|------|------|------|--------|
| `name` | `string` | 是 | 用户名 | - |
| `password` | `string` | 否 | 明文密码（与 passwordHash 二选一） | - |
| `passwordHash` | `string` | 否 | 密码哈希（推荐，更安全） | - |
| `sudo` | `string` | 否 | Sudo 权限配置 | `ALL=(ALL) NOPASSWD:ALL` |
| `shell` | `string` | 否 | 默认 Shell | `/bin/bash` |
| `groups` | `[]string` | 否 | 用户组列表 | `sudo, adm, dialout, ...` |
| `lockPasswd` | `bool` | 否 | 是否锁定密码 | `false` |

## 使用步骤

### 1. 生成密码哈希（如果使用 passwordHash）

```bash
# 使用 openssl（MD5，快速但不安全）
echo -n "your-password" | openssl passwd -1 -stdin

# 使用 Python（SHA512，推荐）
python3 -c "import crypt; print(crypt.crypt('your-password', crypt.mksalt(crypt.METHOD_SHA512)))"
```

### 2. 创建 Wukong 资源

```bash
# 使用示例文件
kubectl apply -f config/samples/vm_v1alpha1_wukong_with_user.yaml

# 或编辑现有文件添加 cloudInitUser 配置
kubectl edit wukong ubuntu-noble-local
```

### 3. 等待 VM 启动

```bash
# 检查 VM 状态
kubectl get vm
kubectl get vmi

# 等待 VMI 状态变为 Running
```

### 4. 登录 VM

```bash
# 方法 1: 使用控制台
virtctl console <vmi-name>
# 输入用户名和密码

# 方法 2: 使用 SSH（如果配置了网络）
ssh ubuntu@<VM_IP>
```

## 安全建议

### 生产环境

1. **使用 passwordHash**：不要使用明文密码
2. **使用 Secret**：将密码哈希存储在 Kubernetes Secret 中，通过 `passwordHashSecret` 引用（未来功能）
3. **使用 SSH Key**：优先使用 SSH Key 而不是密码
4. **定期轮换**：定期更换密码

### 开发环境

- 可以使用明文密码，方便测试
- 确保不要将包含密码的 YAML 提交到公共仓库

## 与 SSH Key 的配合使用

`cloudInitUser` 和 `sshKeySecret` 可以同时使用：

```yaml
spec:
  cloudInitUser:
    name: ubuntu
    passwordHash: "$6$..."
  sshKeySecret: "my-ssh-keys"  # 同时配置 SSH Key
```

这样用户既可以通过密码登录，也可以通过 SSH Key 登录。

## 验证配置

### 检查 Cloud-Init 配置

```bash
# 查看 VM 定义中的 cloud-init 配置
kubectl get vm <vm-name> -o yaml | grep -A 30 "cloudInitNoCloud"
```

### 在 VM 内部验证

```bash
# 连接到 VM
virtctl console <vmi-name>

# 检查用户
id ubuntu

# 检查 sudo 权限
sudo -l

# 查看 cloud-init 日志
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

## 故障排查

### Cloud-Init 未执行

1. 检查 VM 是否首次启动（cloud-init 只在首次启动时执行）
2. 检查 cloud-init 日志：`sudo cat /var/log/cloud-init.log`
3. 检查 VM 定义中是否有 cloud-init 配置

### 用户未创建

1. 检查 cloud-init 日志中的错误
2. 验证密码哈希格式是否正确
3. 检查用户名是否符合系统要求

### 密码无法登录

1. 确认 `lockPasswd: false`
2. 确认 `ssh_pwauth: true`（代码中已自动设置）
3. 检查密码哈希是否正确

## 示例文件

- `config/samples/vm_v1alpha1_wukong_with_user.yaml`: 完整示例
- `config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml`: 已更新，包含用户配置


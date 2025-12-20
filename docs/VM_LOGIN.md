# VM 登录指南

## 问题：VM 没有用户名和密码，如何登录？

对于 Ubuntu cloud image，默认情况下：
- 没有预设密码
- 需要通过 SSH Key 登录
- 或者通过 cloud-init 配置用户和密码

## 解决方案

### 方案 1: 使用脚本自动配置（推荐）

运行脚本为 VM 添加用户和密码：

```bash
./scripts/add-vm-user-password.sh
```

脚本会：
1. 检测 VM 和 VMI
2. 提示输入用户名和密码
3. 生成密码哈希
4. 更新 VM 的 cloud-init 配置
5. 重启 VM 以应用配置

### 方案 2: 手动配置 cloud-init

#### 步骤 1: 编辑 VM

```bash
kubectl edit vm ubuntu-noble-local-vm
```

#### 步骤 2: 添加 cloud-init 配置

在 `spec.template.spec.volumes` 中添加：

```yaml
spec:
  template:
    spec:
      volumes:
        # ... 其他 volumes ...
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              users:
                - name: ubuntu
                  sudo: ALL=(ALL) NOPASSWD:ALL
                  shell: /bin/bash
                  lock_passwd: false
                  passwd: $6$rounds=4096$salt$hashed_password
                  ssh_authorized_keys: []
              
              ssh_pwauth: true
              disable_root: false
```

**生成密码哈希**：
```bash
# 方法 1: 使用 openssl
echo -n "your-password" | openssl passwd -1 -stdin

# 方法 2: 使用 Python
python3 -c "import crypt; print(crypt.crypt('your-password', crypt.mksalt(crypt.METHOD_SHA512)))"
```

#### 步骤 3: 重启 VM

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

### 方案 3: 通过控制台直接配置（临时方案）

如果 VM 已经启动，可以通过控制台进入并手动配置：

```bash
# 连接到控制台
virtctl console ubuntu-noble-local-vm
```

在控制台中：
1. 按 Enter 尝试登录（可能需要多次）
2. 如果进入系统，创建用户：
   ```bash
   sudo useradd -m -s /bin/bash ubuntu
   sudo passwd ubuntu
   sudo usermod -aG sudo ubuntu
   ```

**注意**：这种方法只在当前会话有效，重启后可能丢失。

### 方案 4: 更新 Wukong 配置（永久方案）

修改 Wukong 资源，添加 cloud-init 配置。但当前代码还不支持直接配置用户和密码，需要修改代码。

## 推荐流程

1. **使用脚本自动配置**（最简单）：
   ```bash
   ./scripts/add-vm-user-password.sh
   ```

2. **等待 VM 重启完成**：
   ```bash
   kubectl get vmi
   # 等待状态变为 Running
   ```

3. **获取 VM IP**：
   ```bash
   kubectl get vmi ubuntu-noble-local-vm -o jsonpath='{.status.interfaces[0].ipAddress}'
   ```

4. **登录 VM**：
   ```bash
   # 方法 1: 控制台
   virtctl console ubuntu-noble-local-vm
   # 输入用户名和密码
   
   # 方法 2: SSH（如果配置了网络）
   ssh ubuntu@<VM_IP>
   ```

## 常见问题

### Q: 为什么 cloud-init 配置没有生效？

A: 可能的原因：
1. VM 已经启动，cloud-init 只在首次启动时运行
2. 需要重启 VM 才能应用新配置
3. cloud-init 配置格式错误

**解决**：重启 VM

### Q: 如何验证 cloud-init 是否运行？

A: 在 VM 中检查：
```bash
# 查看 cloud-init 日志
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

### Q: Ubuntu cloud image 的默认用户是什么？

A: 通常是 `ubuntu`，但不同镜像可能不同。可以通过控制台查看或检查镜像文档。

## 注意事项

1. **密码安全**：生产环境建议使用 SSH Key 而不是密码
2. **cloud-init 时机**：cloud-init 只在首次启动或重启时运行
3. **配置持久化**：通过 Wukong 配置的 cloud-init 会持久化，手动修改 VM 的配置在重新创建时会丢失


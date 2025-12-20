# 配置 crictl 无需 sudo

## 问题

默认情况下，`crictl` 需要 `sudo` 才能访问 containerd socket，而 `kubectl` 不需要。可以通过配置用户组权限来解决这个问题。

## 解决方案

### 方法 1: 配置 crictl 使用 k3s socket（推荐）

k3s 使用自己的 containerd socket，需要配置 crictl 使用正确的 socket 路径。

#### 步骤 1: 创建 crictl 配置文件

```bash
# 创建配置目录
mkdir -p ~/.config/crictl

# 创建配置文件
cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

#### 步骤 2: 配置 socket 权限

```bash
# 检查 socket 文件
ls -l /run/k3s/containerd/containerd.sock

# 将当前用户添加到 k3s 组（如果存在）
sudo usermod -aG k3s $USER

# 或者直接修改 socket 权限（临时方案，重启后失效）
sudo chmod 666 /run/k3s/containerd/containerd.sock
```

**注意**：socket 权限在 k3s 重启后会恢复，需要持久化配置。

#### 步骤 3: 持久化 socket 权限

创建 systemd 服务或使用 k3s 配置：

```bash
# 方法 A: 创建 systemd override（推荐）
sudo mkdir -p /etc/systemd/system/k3s.service.d/
sudo tee /etc/systemd/system/k3s.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStartPost=/bin/chmod 666 /run/k3s/containerd/containerd.sock
EOF

# 重新加载 systemd
sudo systemctl daemon-reload

# 重启 k3s（可选，如果 k3s 正在运行）
sudo systemctl restart k3s
```

### 方法 2: 使用环境变量

```bash
# 设置环境变量（临时）
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/k3s/containerd/containerd.sock
export IMAGE_SERVICE_ENDPOINT=unix:///run/k3s/containerd/containerd.sock

# 添加到 ~/.bashrc 或 ~/.zshrc 使其永久生效
echo 'export CONTAINER_RUNTIME_ENDPOINT=unix:///run/k3s/containerd/containerd.sock' >> ~/.bashrc
echo 'export IMAGE_SERVICE_ENDPOINT=unix:///run/k3s/containerd/containerd.sock' >> ~/.bashrc
source ~/.bashrc
```

### 方法 3: 创建别名（如果权限问题无法解决）

如果无法修改 socket 权限，可以创建别名：

```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
echo 'alias crictl="sudo crictl"' >> ~/.bashrc
source ~/.bashrc
```

## 验证配置

配置完成后，测试：

```bash
# 测试 crictl（不需要 sudo）
crictl version

# 测试拉取镜像
crictl pull quay.io/kubevirt/virt-operator:v1.2.0

# 查看镜像
crictl images
```

## 完整配置脚本

```bash
#!/bin/bash

# 配置 crictl 无需 sudo

echo "=== 配置 crictl 无需 sudo ==="

# 1. 创建配置文件
echo "1. 创建 crictl 配置文件..."
mkdir -p ~/.config/crictl
cat > ~/.config/crictl/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
echo "✓ 配置文件已创建"

# 2. 检查 socket 文件
echo -e "\n2. 检查 socket 文件..."
if [ -S /run/k3s/containerd/containerd.sock ]; then
    echo "✓ Socket 文件存在: /run/k3s/containerd/containerd.sock"
    ls -l /run/k3s/containerd/containerd.sock
else
    echo "✗ Socket 文件不存在"
    exit 1
fi

# 3. 配置 socket 权限
echo -e "\n3. 配置 socket 权限..."

# 检查是否有 k3s 组
if getent group k3s > /dev/null 2>&1; then
    echo "将用户添加到 k3s 组..."
    sudo usermod -aG k3s $USER
    echo "✓ 用户已添加到 k3s 组"
    echo "⚠️  需要重新登录或运行 'newgrp k3s' 使组权限生效"
else
    echo "k3s 组不存在，创建 systemd override..."
    sudo mkdir -p /etc/systemd/system/k3s.service.d/
    sudo tee /etc/systemd/system/k3s.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStartPost=/bin/chmod 666 /run/k3s/containerd/containerd.sock
EOF
    sudo systemctl daemon-reload
    echo "✓ systemd override 已创建"
    echo "⚠️  需要重启 k3s 使配置生效: sudo systemctl restart k3s"
fi

# 4. 测试
echo -e "\n4. 测试 crictl..."
if crictl version > /dev/null 2>&1; then
    echo "✓ crictl 可以正常工作（无需 sudo）"
    crictl version
else
    echo "⚠️  crictl 仍需要 sudo，可能需要："
    echo "   - 重新登录（如果添加了用户组）"
    echo "   - 重启 k3s（如果创建了 systemd override）"
    echo "   - 运行: newgrp k3s"
fi

echo -e "\n=== 配置完成 ==="
```

## 常见问题

### 问题 1: 配置后仍需要 sudo

**原因**：
- Socket 权限未生效
- 用户组权限需要重新登录

**解决**：
```bash
# 方法 1: 重新登录
logout
# 然后重新登录

# 方法 2: 使用 newgrp（临时）
newgrp k3s

# 方法 3: 直接修改 socket 权限（临时）
sudo chmod 666 /run/k3s/containerd/containerd.sock
```

### 问题 2: Socket 文件不存在

**原因**：
- k3s 未运行
- Socket 路径不正确

**解决**：
```bash
# 检查 k3s 状态
sudo systemctl status k3s

# 查找 socket 文件
sudo find /run -name "containerd.sock" 2>/dev/null

# 如果找到不同的路径，更新配置文件
```

### 问题 3: 重启后权限恢复

**原因**：
- systemd override 未正确配置
- k3s 启动脚本覆盖了权限

**解决**：
确保 systemd override 正确配置并重启 k3s：
```bash
# 检查 override 文件
cat /etc/systemd/system/k3s.service.d/override.conf

# 重新加载并重启
sudo systemctl daemon-reload
sudo systemctl restart k3s

# 验证权限
ls -l /run/k3s/containerd/containerd.sock
```

## 总结

推荐配置步骤：

1. **创建 crictl 配置文件**（指向 k3s socket）
2. **配置 socket 权限**（通过 systemd override 或用户组）
3. **重新登录或重启 k3s**（使权限生效）
4. **验证配置**（测试 crictl 命令）

配置完成后，`crictl` 就可以像 `kubectl` 一样无需 sudo 使用了。


# Longhorn 前置要求

## 必需组件

Longhorn 需要在每个节点上安装以下组件：

### 1. open-iscsi（必需）⭐

Longhorn 使用 iSCSI 协议来管理存储卷，因此每个节点都必须安装 `open-iscsi`。

#### Ubuntu/Debian

```bash
sudo apt-get update
sudo apt-get install -y open-iscsi

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

#### CentOS/RHEL/Rocky

```bash
sudo yum install -y iscsi-initiator-utils

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

#### Fedora

```bash
sudo dnf install -y iscsi-initiator-utils

# 启动服务
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

#### 验证安装

```bash
# 检查 iscsiadm 是否可用
iscsiadm --version

# 应该输出类似:
# iscsiadm version 2.0-xxx
```

### 2. NFSv4 客户端（可选，用于备份）

如果计划使用 NFS 作为备份目标：

```bash
# Ubuntu/Debian
sudo apt-get install -y nfs-common

# CentOS/RHEL
sudo yum install -y nfs-utils
```

### 3. 节点资源要求

- **CPU**: 至少 1 核心（推荐 2+）
- **内存**: 至少 1GB（推荐 2GB+）
- **磁盘**: 至少 10GB 可用空间（推荐 50GB+）

### 4. 存储路径

Longhorn 默认使用 `/var/lib/longhorn` 作为存储路径。

确保：
- 路径存在且有写权限
- 有足够的磁盘空间

```bash
# 创建路径（如果需要）
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn

# 检查磁盘空间
df -h /var/lib/longhorn
```

## 安装前检查清单

在安装 Longhorn 之前，请确保：

- [ ] 所有节点已安装 `open-iscsi` 或 `iscsi-initiator-utils`
- [ ] `iscsid` 服务已启动
- [ ] 节点有足够的 CPU/内存资源
- [ ] 节点有足够的磁盘空间
- [ ] 存储路径 `/var/lib/longhorn` 可写
- [ ] 节点网络连接正常

## 快速安装脚本

使用项目提供的脚本：

```bash
# 在每个节点上运行
./scripts/install-open-iscsi.sh
```

## 验证

安装完成后，验证：

```bash
# 检查 iscsiadm
iscsiadm --version

# 检查服务状态
sudo systemctl status iscsid

# 检查节点资源
kubectl describe nodes
```

## 常见问题

### 问题: iscsiadm: No such file or directory

**原因**: 节点上未安装 `open-iscsi`

**解决**: 按照上述步骤安装 `open-iscsi`

### 问题: iscsid 服务未启动

**解决**:
```bash
sudo systemctl enable iscsid
sudo systemctl start iscsid
sudo systemctl status iscsid
```

### 问题: 权限不足

**解决**:
```bash
# 检查存储路径权限
ls -la /var/lib/longhorn

# 如果需要，修复权限
sudo chmod 755 /var/lib/longhorn
```

## 安装 Longhorn

完成前置要求后，安装 Longhorn：

```bash
./scripts/setup-longhorn.sh
```

## 参考

- Longhorn 官方文档: https://longhorn.io/docs/
- 系统要求: https://longhorn.io/docs/1.6.0/deploy/install/#system-requirements


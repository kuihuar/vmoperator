# Longhorn 数据盘配置指南

本文档说明如何配置 Longhorn 使用独立数据盘（如 `/dev/sdb`）。

## 重要说明

**`LONGHORN_DATA_PATH` 不能直接设置为 `/dev/sdb`**，因为：
- `/dev/sdb` 是**块设备**（block device），不是文件系统目录
- Longhorn 需要的是一个**已挂载的文件系统路径**（如 `/data/longhorn`）

正确的做法是：
1. 格式化数据盘 `/dev/sdb`
2. 挂载到某个目录（如 `/data/longhorn`）
3. 设置 `LONGHORN_DATA_PATH` 为挂载点路径

## 配置步骤

### 方法一：手动准备数据盘（推荐）

#### 1. 查看可用磁盘

```bash
lsblk
# 或
fdisk -l
```

确认 `/dev/sdb` 是你要使用的数据盘（**注意：操作会格式化磁盘，确保没有重要数据**）

#### 2. 格式化数据盘

```bash
# 使用 ext4 文件系统格式化（推荐）
sudo mkfs.ext4 /dev/sdb

# 或使用 xfs 文件系统
sudo mkfs.xfs /dev/sdb
```

#### 3. 创建挂载点

```bash
# 创建挂载目录
sudo mkdir -p /data/longhorn

# 设置权限
sudo chmod 755 /data/longhorn
```

#### 4. 挂载数据盘

```bash
# 临时挂载（重启后会丢失）
sudo mount /dev/sdb /data/longhorn

# 验证挂载
df -h /data/longhorn
```

#### 5. 配置开机自动挂载

```bash
# 获取磁盘 UUID（推荐使用 UUID，更稳定）
sudo blkid /dev/sdb

# 编辑 /etc/fstab
sudo vi /etc/fstab

# 添加以下行（使用 UUID，替换为实际 UUID）
UUID=你的-UUID /data/longhorn ext4 defaults,noatime 0 2

# 或使用设备名（不推荐，设备名可能变化）
/dev/sdb /data/longhorn ext4 defaults,noatime 0 2
```

**fstab 字段说明**：
- 第1列：设备或 UUID
- 第2列：挂载点
- 第3列：文件系统类型
- 第4列：挂载选项（`defaults,noatime` 表示默认选项 + 不更新访问时间）
- 第5列：dump 备份标志（0=不备份）
- 第6列：fsck 检查顺序（0=不检查，2=非根文件系统）

#### 6. 测试自动挂载

```bash
# 测试 fstab 配置是否正确
sudo mount -a

# 如果报错，检查 fstab 语法
```

#### 7. 运行安装脚本

```bash
# 使用环境变量指定数据盘路径
LONGHORN_DATA_PATH=/data/longhorn ./docs/installation/install-longhorn.sh
```

### 方法二：使用安装脚本自动准备（仅创建目录）

安装脚本可以自动创建目录和设置权限，但**不会自动格式化或挂载磁盘**。

```bash
# 1. 先手动格式化并挂载 /dev/sdb（参考方法一的步骤 2-4）
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /data/longhorn
sudo mount /dev/sdb /data/longhorn

# 2. 运行安装脚本，脚本会自动检查并修复目录权限
LONGHORN_DATA_PATH=/data/longhorn ./docs/installation/install-longhorn.sh
```

## 脚本实现原理

### 1. 路径配置（第 49 行）

```bash
LONGHORN_DATA_PATH="${LONGHORN_DATA_PATH:-/data/longhorn}"
```

- 如果设置了环境变量 `LONGHORN_DATA_PATH`，使用该值
- 如果没有设置，默认使用 `/data/longhorn`

### 2. 数据盘检查（第 68-112 行）

脚本定义了 `check_data_disk()` 函数，检查：
- 路径是否存在
- 是否有写权限
- 可用空间是否足够（至少 10GB）
- 文件系统类型（推荐 ext4 或 xfs）

### 3. 路径替换（第 197 行）

```bash
sed "s|/var/lib/longhorn/|${LONGHORN_DATA_PATH}/|g" "${LONGHORN_YAML}" > "${TEMP_YAML}"
```

**实现逻辑**：
- 读取原始 YAML 文件（`longhorn_v1.8.1.yaml`）
- 使用 `sed` 将所有 `/var/lib/longhorn/` 替换为 `${LONGHORN_DATA_PATH}/`
- 保存到临时文件
- 使用临时文件进行安装

**替换的位置**：
- `longhorn-manager` DaemonSet 的 `volumeMounts` 中的 `mountPath`
- `volumes` 中的 `hostPath.path`

### 4. 路径规范化（第 200 行）

```bash
sed -i.bak "s|path: ${LONGHORN_DATA_PATH}[^/]|path: ${LONGHORN_DATA_PATH}/|g" "${TEMP_YAML}"
```

确保路径以 `/` 结尾，避免路径拼接错误。

## 完整示例

### 场景：使用 `/dev/sdb` 作为 Longhorn 数据盘

```bash
# 1. 查看磁盘
lsblk
# 输出：
# NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
# sda    8:0    0  100G  0 disk
# └─sda1 8:1    0  100G  0 part /
# sdb    8:16   0  500G  0 disk  ← 这是我们要用的数据盘

# 2. 格式化（注意：会删除所有数据！）
sudo mkfs.ext4 /dev/sdb

# 3. 创建挂载点
sudo mkdir -p /data/longhorn
sudo chmod 755 /data/longhorn

# 4. 挂载
sudo mount /dev/sdb /data/longhorn

# 5. 获取 UUID
sudo blkid /dev/sdb
# 输出：/dev/sdb: UUID="12345678-1234-1234-1234-123456789abc" TYPE="ext4"

# 6. 添加到 fstab（使用实际 UUID）
echo "UUID=12345678-1234-1234-1234-123456789abc /data/longhorn ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# 7. 测试自动挂载
sudo mount -a

# 8. 验证
df -h /data/longhorn
# 输出应该显示 /dev/sdb 已挂载到 /data/longhorn

# 9. 运行安装脚本
cd /Users/jianfenliu/Workspace/vmoperator
LONGHORN_DATA_PATH=/data/longhorn ./docs/installation/install-longhorn.sh
```

## 多节点集群

如果有多节点集群，需要在**每个节点**上执行上述步骤：

```bash
# 在每个节点上执行
for node in node1 node2 node3; do
    ssh $node "sudo mkfs.ext4 /dev/sdb && sudo mkdir -p /data/longhorn && sudo mount /dev/sdb /data/longhorn"
done
```

## 验证配置

安装完成后，验证数据盘是否正确使用：

```bash
# 1. 检查 Pod 挂载
kubectl -n longhorn-system get pod -l app=longhorn-manager -o yaml | grep -A 5 "volumeMounts"

# 2. 检查实际使用的磁盘
kubectl -n longhorn-system exec -it <longhorn-manager-pod> -- df -h /data/longhorn

# 3. 检查 Longhorn 设置
kubectl -n longhorn-system get settings.longhorn.io default-data-path -o yaml
```

## 常见问题

### Q1: 可以直接用 `/dev/sdb` 作为路径吗？

**不可以**。`/dev/sdb` 是块设备，不是文件系统。必须先格式化并挂载到目录。

### Q2: 如何确认数据盘已正确挂载？

```bash
# 查看挂载信息
mount | grep longhorn
# 或
df -h | grep longhorn
```

### Q3: 重启后数据盘没有自动挂载？

检查 `/etc/fstab` 配置是否正确：
```bash
# 测试 fstab
sudo mount -a

# 查看错误日志
dmesg | tail
```

### Q4: 如何更换数据盘？

1. 停止 Longhorn（备份数据）
2. 卸载旧数据盘
3. 挂载新数据盘到相同路径
4. 恢复数据
5. 重启 Longhorn

### Q5: 数据盘空间不足怎么办？

```bash
# 查看使用情况
df -h /data/longhorn

# 清理 Longhorn 数据（谨慎操作）
# 或扩展数据盘（如果支持）
```

## 相关文档

- [安装脚本说明](./install-longhorn.sh)
- [Longhorn YAML 文件详解](./LONGHORN_YAML_GUIDE.md)
- [Longhorn 官方文档 - 存储配置](https://longhorn.io/docs/)


# 存储方案说明

## 当前选择：Longhorn

本项目已选择 **Longhorn** 作为生产环境的存储方案。

### 为什么选择 Longhorn？

- ✅ **专为 k3s 设计**: 轻量级，适合边缘和中小规模环境
- ✅ **支持卷扩展**: `allowVolumeExpansion: true`，满足动态存储需求
- ✅ **高可用性**: 数据自动复制到多个节点
- ✅ **易于管理**: 提供 Web UI 界面
- ✅ **自动备份**: 支持快照和备份功能

## 快速开始

### 1. 安装 Longhorn

```bash
# 使用安装脚本（推荐）
./scripts/setup-longhorn.sh

# 或手动安装
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

### 2. 验证安装

```bash
# 运行验证脚本
./scripts/verify-longhorn.sh

# 或手动检查
kubectl get pods -n longhorn-system
kubectl get storageclass longhorn
```

### 3. 在 Wukong 中使用

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-longhorn
spec:
  disks:
    - name: system
      size: 20Gi
      storageClassName: longhorn  # 使用 Longhorn
      boot: true
    - name: data
      size: 100Gi
      storageClassName: longhorn
      boot: false
```

## 相关文档

- **安装指南**: `docs/LONGHORN_SETUP.md` - 详细的安装和使用说明
- **生产环境存储**: `docs/PRODUCTION_STORAGE.md` - 存储方案对比和选择
- **磁盘扩展**: `docs/DISK_EXPANSION.md` - 如何扩展磁盘大小
- **虚拟机迁移**: `docs/VM_MIGRATION.md` - 虚拟机迁移机制

## 示例配置

- **开发/测试**: `config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml` (使用 local-path)
- **生产环境**: `config/samples/vm_v1alpha1_wukong_production.yaml` (使用 Longhorn)
- **系统盘和数据盘分离**: `config/samples/vm_v1alpha1_wukong_separated_disks.yaml`

## 常用命令

```bash
# 安装 Longhorn
./scripts/setup-longhorn.sh

# 验证安装
./scripts/verify-longhorn.sh

# 访问 Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# 扩展磁盘
./scripts/expand-disk.sh <wukong-name> <disk-name> <new-size>

# 检查存储状态
./scripts/check-vm-storage.sh
```

## 存储对比

| 特性 | Longhorn | local-path |
|------|----------|------------|
| 卷扩展 | ✅ | ❌ |
| 高可用 | ✅ | ❌ |
| 跨节点 | ✅ | ❌ |
| 快照 | ✅ | ❌ |
| 备份 | ✅ | ❌ |
| 适用场景 | 生产环境 | 开发测试 |

## 支持

如有问题，请参考：
- Longhorn 官方文档: https://longhorn.io/docs/
- 项目文档: `docs/LONGHORN_SETUP.md`


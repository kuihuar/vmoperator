# Longhorn 版本选择指南

## 概述

本指南说明如何选择和使用 Longhorn 版本，包括获取最新版本、查看版本历史，以及为什么推荐使用最新版本。

## 为什么使用最新版本？

### 优势

1. **修复已知问题**
   - 最新版本通常修复了之前版本的问题
   - 包括 `driver-deployer` Init 容器卡住等常见问题

2. **改进稳定性**
   - 包含稳定性改进和 bug 修复
   - 更好的错误处理和恢复机制

3. **新功能**
   - 可能包含新功能和性能优化
   - 改进的用户体验

4. **安全更新**
   - 包含安全补丁
   - 修复已知安全漏洞

### 版本兼容性

- ✅ **向后兼容**: 新版本通常向后兼容
- ✅ **平滑升级**: 可以从旧版本平滑升级到新版本
- ⚠️ **API 变更**: 极少数情况下可能有 API 变更（会在发布说明中标注）

## 查看可用版本

### 方法 1: 使用脚本（推荐）

```bash
# 查看所有可用版本
./scripts/check-longhorn-versions.sh
```

脚本会显示：
- 最新版本
- 最近 10 个版本
- 当前安装的版本（如果已安装）
- 安装命令示例

### 方法 2: 通过 GitHub API

```bash
# 获取最新版本
curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4

# 查看最近 10 个版本
curl -s https://api.github.com/repos/longhorn/longhorn/releases | grep tag_name | head -10
```

### 方法 3: 访问 GitHub 页面

直接访问: https://github.com/longhorn/longhorn/releases

## 安装最新版本

### 使用脚本（推荐）

```bash
# 重新安装（自动获取最新版本）
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn

# 或首次安装
./scripts/install-longhorn.sh kubectl latest
```

### 手动安装

```bash
# 1. 获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
echo "最新版本: $LATEST_VERSION"

# 2. 安装
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/${LATEST_VERSION}/deploy/longhorn.yaml
```

### 使用 Helm

```bash
# 1. 添加仓库
helm repo add longhorn https://charts.longhorn.io
helm repo update

# 2. 获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/longhorn/longhorn/releases/latest | grep tag_name | cut -d '"' -f 4)
HELM_VERSION=$(echo "$LATEST_VERSION" | sed 's/^v//')  # 移除 v 前缀

# 3. 安装
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version "$HELM_VERSION"
```

## 安装特定版本

### 如果已知某个版本稳定

```bash
# 使用指定版本
./scripts/reinstall-longhorn.sh kubectl v1.6.0 /mnt/longhorn

# 或
./scripts/install-longhorn.sh kubectl v1.6.0
```

### 查看版本发布说明

在安装特定版本前，建议查看发布说明：

```bash
# 查看版本发布说明 URL
VERSION="v1.6.0"
echo "https://github.com/longhorn/longhorn/releases/tag/$VERSION"
```

## 版本选择建议

### 场景 1: 新安装

**推荐**: 使用 `latest`

```bash
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn
```

**原因**: 
- 避免老版本的已知问题
- 获得最新功能和修复

### 场景 2: 升级现有安装

**推荐**: 使用 `latest`

```bash
# 先备份，然后升级
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn
```

**原因**:
- 修复已知问题
- 获得改进

### 场景 3: 生产环境

**推荐**: 使用最新稳定版本

```bash
# 1. 查看最新版本
./scripts/check-longhorn-versions.sh

# 2. 查看发布说明
# 访问: https://github.com/longhorn/longhorn/releases

# 3. 安装最新稳定版本
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn
```

**原因**:
- 经过充分测试
- 包含重要修复

### 场景 4: 测试环境

**推荐**: 使用 `latest` 或特定版本

```bash
# 测试最新版本
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn

# 或测试特定版本
./scripts/reinstall-longhorn.sh kubectl v1.6.0 /mnt/longhorn
```

## 检查当前安装的版本

### 方法 1: 从 Manager Pod 镜像

```bash
MANAGER_POD=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}')
IMAGE=$(kubectl get pod -n longhorn-system "$MANAGER_POD" -o jsonpath='{.spec.containers[0].image}')
VERSION=$(echo "$IMAGE" | grep -oP 'longhorn-manager:\K[^ ]+' | cut -d ':' -f 2)
echo "当前版本: $VERSION"
```

### 方法 2: 使用脚本

```bash
./scripts/check-longhorn-versions.sh
```

## 版本升级路径

### 从旧版本升级到新版本

1. **备份数据**
   ```bash
   # 在 Longhorn UI 中创建备份
   # 或导出重要卷
   ```

2. **卸载旧版本**
   ```bash
   ./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn
   # 脚本会自动卸载旧版本
   ```

3. **安装新版本**
   ```bash
   # 脚本会自动安装新版本
   ```

4. **验证**
   ```bash
   kubectl get pods -n longhorn-system
   kubectl get storageclass longhorn
   ```

## 常见问题

### Q: 最新版本是否稳定？

**A**: 是的，Longhorn 团队会确保每个发布版本都经过充分测试。最新版本通常是最稳定的，因为它包含了所有已知问题的修复。

### Q: 如何知道某个版本修复了哪些问题？

**A**: 查看 GitHub 发布页面: https://github.com/longhorn/longhorn/releases
每个版本都有详细的发布说明，包括：
- 新功能
- Bug 修复
- 已知问题

### Q: 可以回退到旧版本吗？

**A**: 可以，但不推荐。如果必须回退：
1. 卸载当前版本
2. 安装旧版本
3. 注意：可能需要清理数据

### Q: Helm 版本和 kubectl 版本有什么区别？

**A**: 
- **kubectl 版本**: 使用 GitHub 发布的 YAML 清单，版本格式如 `v1.6.0`
- **Helm 版本**: 使用 Helm Chart，版本格式如 `1.6.0`（没有 v 前缀）
- 两者对应同一个 Longhorn 版本，只是安装方式不同

## 版本历史

### 主要版本

| 版本 | 发布日期 | 主要特性 |
|------|----------|----------|
| v1.6.0 | 最新 | 最新稳定版本 |
| v1.5.x | - | 稳定版本 |
| v1.4.x | - | 稳定版本 |

查看完整版本历史: https://github.com/longhorn/longhorn/releases

## 总结

**推荐做法**:
- ✅ **新安装**: 使用 `latest`
- ✅ **升级**: 使用 `latest`
- ✅ **生产环境**: 使用最新稳定版本（`latest`）
- ✅ **定期检查**: 使用 `./scripts/check-longhorn-versions.sh` 检查新版本

**快速命令**:
```bash
# 查看版本
./scripts/check-longhorn-versions.sh

# 安装最新版本
./scripts/reinstall-longhorn.sh kubectl latest /mnt/longhorn
```

## 参考

- Longhorn 发布页面: https://github.com/longhorn/longhorn/releases
- 版本检查脚本: `./scripts/check-longhorn-versions.sh`
- 重新安装脚本: `./scripts/reinstall-longhorn.sh`
- 安装脚本: `./scripts/install-longhorn.sh`


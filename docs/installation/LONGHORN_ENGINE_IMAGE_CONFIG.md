# Longhorn Engine Image 版本配置说明

## 问题描述

当出现 `incompatible Engine ei-db6c2b6f controller API version: found version 0 is below required minimal version 4` 错误时，说明存在旧的 Engine Image 与 Longhorn v1.8.1 不兼容。

## 相关配置位置

### 1. longhorn-manager 的 Engine Image 配置

**位置**: `longhorn_v1.8.1.yaml` 第 4957-4958 行

```yaml
command:
- longhorn-manager
- -d
- daemon
- --engine-image
- "longhornio/longhorn-engine:v1.8.1"  # <-- 这里指定了默认的 Engine Image
```

**说明**:
- `--engine-image` 参数指定了 Longhorn Manager 使用的默认 Engine Image
- 当前配置为 `longhornio/longhorn-engine:v1.8.1`
- 这个版本要求 controller API version >= 4

### 2. 版本检查开关

**位置**: `longhorn_v1.8.1.yaml` 第 4971 行

```yaml
- --upgrade-version-check  # <-- 启用版本检查
```

**说明**:
- 这个参数启用了 Engine Image 版本兼容性检查
- Manager 启动时会检查所有 Engine Image 的 controller API version
- 如果发现版本 < 4，会报错并阻止启动

### 3. Engine Image CRD 定义

**位置**: `longhorn_v1.8.1.yaml` 第 1724-1727 行

```yaml
controllerAPIMinVersion:
  type: integer
controllerAPIVersion:
  type: integer
```

**说明**:
- Engine Image 资源包含 `controllerAPIVersion` 字段
- Manager 会检查这个版本是否满足 `controllerAPIMinVersion` 要求
- Longhorn v1.8.1 要求 controller API version >= 4

### 4. Default Setting 配置

**位置**: `longhorn_v1.8.1.yaml` 第 68-82 行

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: longhorn-default-setting
  namespace: longhorn-system
data:
  default-setting.yaml: |-
    priority-class: longhorn-critical
    disable-revision-counter: true
```

**说明**:
- 这个 ConfigMap 包含 Longhorn 的默认设置
- 可能包含默认 Engine Image 的配置（如果有的话）

## 问题原因

1. **旧的 Engine Image 残留**: 之前安装的 Longhorn 版本创建的 Engine Image（如 `ei-db6c2b6f`）仍然存在
2. **版本不兼容**: 旧 Engine Image 的 controller API version 为 0，低于要求的版本 4
3. **启动检查**: Manager 启动时检查到不兼容的 Engine Image，拒绝启动

## 解决方案

### 方案 1: 在安装脚本中添加清理逻辑（推荐）

在 `install-longhorn.sh` 的清理步骤中，添加 Engine Image 的清理：

```bash
# 清理 Engine Image finalizers 并删除
kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | .metadata.name' 2>/dev/null | \
    while read name; do
        kubectl patch engineimages.longhorn.io "${name}" -n longhorn-system \
            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
        kubectl delete engineimages.longhorn.io "${name}" -n longhorn-system --timeout=5s 2>/dev/null || true
    done || true
```

### 方案 2: 在安装后添加自动修复逻辑

在 `install-longhorn.sh` 的安装后检查中，如果发现 Engine Image 版本错误，自动修复：

```bash
# 检查 Manager 日志中的 Engine Image 错误
ENGINE_IMAGE_ERROR=$(kubectl logs "${MANAGER_POD}" -n longhorn-system 2>&1 | \
    grep -i "incompatible Engine.*version\|controller API version.*below required" || echo "")

if [ -n "${ENGINE_IMAGE_ERROR}" ]; then
    # 提取并删除旧的 Engine Image
    OLD_ENGINE_IMAGE=$(echo "${ENGINE_IMAGE_ERROR}" | grep -oE "ei-[0-9a-f]+" | head -1)
    if [ -n "${OLD_ENGINE_IMAGE}" ]; then
        kubectl patch engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system \
            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
        kubectl delete engineimages.longhorn.io "${OLD_ENGINE_IMAGE}" -n longhorn-system 2>/dev/null || true
        kubectl delete pods -n longhorn-system -l app=longhorn-manager
    fi
fi
```

### 方案 3: 禁用版本检查（不推荐）

如果确实需要保留旧的 Engine Image，可以移除 `--upgrade-version-check` 参数，但**不推荐**，因为可能导致兼容性问题。

## 配置修改建议

### 在清理步骤中添加 Engine Image 清理

**位置**: `install-longhorn.sh` 清理步骤（选项 1）

在快速模式的清理逻辑中，已经添加了 Engine Image 清理，但需要确保在标准模式中也添加。

### 在安装后添加自动修复

**位置**: `install-longhorn.sh` 安装后等待 Manager 就绪的部分

添加检查逻辑，如果 Manager 启动失败且是 Engine Image 版本问题，自动修复。

## 验证方法

安装后检查：

```bash
# 1. 检查所有 Engine Image
kubectl get engineimages.longhorn.io -n longhorn-system

# 2. 检查 Manager 日志
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50 | grep -i "engine\|version"

# 3. 检查 Manager Pod 状态
kubectl get pods -n longhorn-system -l app=longhorn-manager
```

## 总结

- **关键配置**: `--engine-image` 参数（第4957-4958行）和 `--upgrade-version-check`（第4971行）
- **问题根源**: 旧的 Engine Image 残留，版本不兼容
- **解决方案**: 在清理和安装后都添加 Engine Image 的清理和修复逻辑


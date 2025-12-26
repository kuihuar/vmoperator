# Longhorn Engine Image 和 Controller API Version 详解

## 1. Longhorn 架构组件

Longhorn 是一个分布式块存储系统，由以下核心组件组成：

### 核心组件

1. **longhorn-manager** (管理组件)
   - 负责管理整个 Longhorn 系统
   - 处理 Volume、Engine、Replica 等资源的生命周期
   - 运行在每个节点上（DaemonSet）

2. **longhorn-engine** (存储引擎)
   - 实际处理数据读写的组件
   - 运行在 Pod 中，管理 Volume 的 I/O 操作
   - 这是 **Engine Image** 包含的组件

3. **longhorn-instance-manager** (实例管理器)
   - 管理 Engine 和 Replica 实例的生命周期
   - 负责启动、停止、监控这些实例

4. **longhorn-replica** (数据副本)
   - 存储实际数据的副本
   - 每个 Volume 可以有多个 Replica（用于冗余）

## 2. Engine Image 是什么？

### 定义

**Engine Image** 是一个容器镜像，包含了 `longhorn-engine` 可执行文件。它是 Longhorn 存储引擎的运行时镜像。

### 作用

- Engine Image 定义了用于处理 Volume I/O 的引擎版本
- 每个 Volume 使用特定的 Engine Image 来处理数据读写
- 不同版本的 Engine Image 可能有不同的功能和性能特性

### 在 Kubernetes 中的表示

Engine Image 在 Kubernetes 中是一个 CRD (Custom Resource Definition)：

```yaml
apiVersion: longhorn.io/v1beta2
kind: EngineImage
metadata:
  name: ei-db6c2b6f  # Engine Image 的名称（基于镜像哈希）
spec:
  image: longhornio/longhorn-engine:v1.8.1  # 容器镜像
status:
  controllerAPIVersion: 4  # Controller API 版本号
  state: ready
```

## 3. Controller API Version 是什么？

### 定义

**Controller API Version** 是 Engine Image 与 longhorn-manager 之间通信协议的版本号。

### 作用

- 定义了 Manager 和 Engine 之间的 API 接口版本
- 确保 Manager 和 Engine 使用兼容的通信协议
- 防止版本不匹配导致的通信错误

### 为什么需要版本检查？

1. **API 兼容性**: 不同版本的 Engine 可能使用不同的 API
2. **功能支持**: 新版本的 Manager 可能依赖新版本 Engine 的功能
3. **数据安全**: 版本不匹配可能导致数据损坏或功能异常

### 版本演进

- **Version 0**: 早期版本，功能有限
- **Version 1-3**: 中间版本，逐步增加功能
- **Version 4+**: Longhorn v1.8.1 要求的最低版本
  - 支持更多功能
  - 更好的性能和稳定性
  - 修复了早期版本的 bug

## 4. 组件关系图

```
┌─────────────────────────────────────────────────────────┐
│              longhorn-manager (DaemonSet)                │
│  - 管理整个系统                                          │
│  - 检查 Engine Image 版本兼容性                         │
│  - 要求 Controller API Version >= 4                     │
└─────────────────┬───────────────────────────────────────┘
                  │
                  │ 使用 Engine Image
                  │
┌─────────────────▼───────────────────────────────────────┐
│              Engine Image (CRD)                          │
│  - ei-db6c2b6f (旧版本, API version = 0) ❌             │
│  - ei-xxxxx (新版本, API version = 4) ✓                 │
│                                                          │
│  spec:                                                   │
│    image: longhornio/longhorn-engine:v1.8.1             │
│  status:                                                 │
│    controllerAPIVersion: 4                               │
└─────────────────┬───────────────────────────────────────┘
                  │
                  │ 包含
                  │
┌─────────────────▼───────────────────────────────────────┐
│         longhorn-engine (容器镜像)                        │
│  - 实际处理 Volume I/O                                   │
│  - 运行在 Engine Pod 中                                  │
│  - 与 Manager 通过 Controller API 通信                  │
└──────────────────────────────────────────────────────────┘
```

## 5. 问题场景

### 问题描述

当出现以下错误时：
```
incompatible Engine ei-db6c2b6f controller API version: 
found version 0 is below required minimal version 4
```

### 问题原因

1. **旧的 Engine Image 残留**: 
   - 之前安装的旧版本 Longhorn 创建的 Engine Image 仍然存在
   - 这个 Engine Image 的 `controllerAPIVersion` 为 0（或 < 4）

2. **版本不兼容**:
   - Longhorn v1.8.1 的 Manager 要求 Engine Image 的 Controller API Version >= 4
   - 旧的 Engine Image (version 0) 无法与新的 Manager 通信

3. **启动检查失败**:
   - Manager 启动时会检查所有 Engine Image 的版本
   - 发现不兼容的版本后，拒绝启动，避免系统不稳定

### 影响

- **longhorn-manager**: CrashLoopBackOff（因为版本检查失败）
- **longhorn-driver-deployer**: Init:0/1（等待 Manager 就绪超时）
- **整个 Longhorn 系统**: 无法正常工作

## 6. 解决方案

### 方案 1: 删除旧的 Engine Image（推荐）

```bash
# 1. 检查所有 Engine Image
kubectl get engineimages.longhorn.io -n longhorn-system

# 2. 删除旧的 Engine Image（如果有 finalizers，先清理）
kubectl patch engineimages.longhorn.io ei-db6c2b6f -n longhorn-system \
  --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

kubectl delete engineimages.longhorn.io ei-db6c2b6f -n longhorn-system

# 3. 重启 Manager
kubectl delete pods -n longhorn-system -l app=longhorn-manager
```

### 方案 2: 在安装脚本中自动清理

在 `install-longhorn.sh` 的清理步骤中添加：

```bash
# 清理所有 Engine Image
kubectl get engineimages.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | .metadata.name' 2>/dev/null | \
    while read name; do
        kubectl patch engineimages.longhorn.io "${name}" -n longhorn-system \
            --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
        kubectl delete engineimages.longhorn.io "${name}" -n longhorn-system --timeout=5s 2>/dev/null || true
    done || true
```

## 7. 版本对应关系

| Longhorn 版本 | 要求 Controller API Version | Engine Image 版本 |
|--------------|---------------------------|------------------|
| v1.0.x - v1.5.x | >= 0 | longhorn-engine:v1.0.x - v1.5.x |
| v1.6.x - v1.7.x | >= 1 | longhorn-engine:v1.6.x - v1.7.x |
| v1.8.0+ | >= 4 | longhorn-engine:v1.8.0+ |

## 8. 总结

- **Engine Image**: 包含 `longhorn-engine` 的容器镜像，用于处理 Volume I/O
- **Controller API Version**: Manager 和 Engine 之间的通信协议版本号
- **版本要求**: Longhorn v1.8.1 要求 Controller API Version >= 4
- **问题根源**: 旧的 Engine Image (version 0) 与新的 Manager 不兼容
- **解决方法**: 删除旧的 Engine Image，让系统自动创建新的兼容版本

## 9. 相关配置位置

在 `longhorn_v1.8.1.yaml` 中：

- **第 4957-4958 行**: `--engine-image "longhornio/longhorn-engine:v1.8.1"` - 指定默认 Engine Image
- **第 4971 行**: `--upgrade-version-check` - 启用版本检查
- **第 1724-1727 行**: CRD 定义中的 `controllerAPIVersion` 字段


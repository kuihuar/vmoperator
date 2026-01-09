# NMState Go API 选项

## 问题

当前使用 `unstructured` 类型操作 NMState 资源，存在以下问题：
- ❌ 容易出错（如 `int` 类型无法深度复制）
- ❌ 没有类型检查
- ❌ 代码可读性差
- ❌ 维护困难

## 解决方案

### 方案 1：使用本地类型定义（推荐）✅

**优点**：
- ✅ 类型安全
- ✅ 编译时检查
- ✅ 代码可读性好
- ✅ 避免类型转换错误

**实现**：
- 已创建 `pkg/network/nmstate_types.go` 类型定义文件
- 需要重构 `reconcileBridgePolicy` 函数使用这些类型

**示例**：
```go
// 使用类型定义
desiredState := DesiredState{
    Interfaces: []Interface{
        {
            Name:  bridgeName,
            Type:  "linux-bridge",
            State: "up",
            IPv4: &IPv4Config{
                Enabled: true,
                Address: []IPv4Address{
                    {
                        IP:          ip,
                        PrefixLength: int64(prefixLen), // 类型安全
                    },
                },
            },
            Bridge: &BridgeConfig{
                Port: []BridgePort{
                    {Name: physicalInterface},
                },
            },
        },
    },
}
```

### 方案 2：继续使用 unstructured（不推荐）⚠️

**优点**：
- ✅ 不需要额外依赖
- ✅ 代码改动小

**缺点**：
- ❌ 容易出错
- ❌ 需要手动转换类型（如 `int` → `int64`）
- ❌ 没有类型检查

**注意事项**：
- 所有数字类型必须转换为 `int64` 或 `float64`
- 需要小心处理嵌套结构
- 建议添加更多注释和验证

## 推荐方案

**推荐使用方案 1**：使用本地类型定义

**原因**：
1. 类型安全，编译时检查
2. 代码可读性好，易于维护
3. 避免类型转换错误
4. 符合 Go 最佳实践

## 实施步骤

### 步骤 1：使用类型定义重构代码

将 `reconcileBridgePolicy` 函数从使用 `map[string]interface{}` 改为使用类型定义。

### 步骤 2：使用 runtime.Object 转换

使用 `runtime.Object` 和 `scheme` 将类型定义转换为 Kubernetes 资源。

### 步骤 3：测试验证

确保重构后的代码功能正常。

## 当前状态

- ✅ 已创建类型定义文件：`pkg/network/nmstate_types.go`
- ⚠️ 代码仍使用 `unstructured`（需要重构）
- ✅ 已修复 `int` → `int64` 转换问题（临时方案）

## 下一步

1. 重构 `reconcileBridgePolicy` 使用类型定义
2. 使用 `runtime.Object` 和 `scheme` 处理资源
3. 测试验证功能


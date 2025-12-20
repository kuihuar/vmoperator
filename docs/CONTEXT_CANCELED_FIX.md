# Context Canceled 错误处理说明

## 问题描述

在 Controller 运行过程中，可能会遇到 `context canceled` 错误，这通常发生在：
- Controller-runtime 的 reconcile 超时
- 资源操作时间过长，超过了 context 的 deadline
- 正常的 requeue 过程中 context 被取消

## 错误表现

之前的日志会显示：
```
ERROR	failed to reconcile disks	{"error": "context canceled"}
```

虽然这个错误会被正确处理（requeue），但 ERROR 级别的日志会让人误以为出现了严重问题。

## 修复方案

### 1. 在 `reconcileDisks` 中检查 context

在 `internal/controller/wukong_controller.go` 的 `reconcileDisks` 函数中：

```go
func (r *WukongReconciler) reconcileDisks(ctx context.Context, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.VolumeStatus, error) {
    // ...
    volumesStatus, err := storage.ReconcileDisks(ctx, r.Client, vmp)
    if err != nil {
        // 如果是 context canceled，不记录 ERROR，直接返回让上层处理
        if ctx.Err() != nil {
            logger.V(1).Info("Context canceled during disk reconciliation, will retry", "error", err)
            return nil, err
        }
        logger.Error(err, "failed to reconcile disks")
        return nil, err
    }
    // ...
}
```

### 2. 在 `Reconcile` 中处理 context canceled

在 `Reconcile` 函数中，已经有处理逻辑：

```go
volumesStatus, err := r.reconcileDisks(ctx, &vmp)
if err != nil {
    // 如果是 context canceled，requeue 而不是报错
    if ctx.Err() != nil {
        logger.V(1).Info("Context canceled during disk reconciliation, will requeue", "error", err)
        return ctrl.Result{RequeueAfter: time.Second * 10}, nil
    }
    logger.Error(err, "failed to reconcile disks")
    // ...
}
```

## 处理流程

1. **存储模块返回 context canceled**：
   - `pkg/storage/reconcile.go` 或 `pkg/storage/datavolume.go` 检测到 context canceled
   - 返回 `ctx.Err()` 错误

2. **`reconcileDisks` 检查 context**：
   - 如果 `ctx.Err() != nil`，记录 DEBUG 级别日志
   - 返回错误给上层

3. **`Reconcile` 检查 context**：
   - 如果 `ctx.Err() != nil`，记录 V(1) 级别日志
   - 返回 requeue 结果（不返回错误）

## 日志级别

修复后的日志：
- **DEBUG/V(1) 级别**：`Context canceled during disk reconciliation, will retry`
- **不再有 ERROR 级别**：`failed to reconcile disks`（仅在真正的错误时出现）

## 为什么会出现 context canceled？

### 正常情况

1. **Reconcile 超时**：
   - Controller-runtime 默认 reconcile 超时时间
   - 如果操作时间过长，context 会被取消

2. **资源操作耗时**：
   - DataVolume 创建/检查需要时间
   - PVC 绑定需要时间
   - 网络请求可能较慢

3. **Requeue 机制**：
   - Controller 会自动 requeue 未完成的操作
   - 这是正常的行为

### 异常情况

如果频繁出现 context canceled，可能的原因：

1. **API Server 响应慢**：
   ```bash
   # 检查 API Server 延迟
   kubectl get --raw /healthz
   ```

2. **网络问题**：
   ```bash
   # 检查网络连接
   kubectl get nodes
   ```

3. **资源竞争**：
   ```bash
   # 检查集群资源使用
   kubectl top nodes
   kubectl top pods -A
   ```

## 验证修复

修复后，你应该看到：

```
DEBUG	Context canceled during disk reconciliation, will retry	{"error": "context canceled"}
```

而不是：

```
ERROR	failed to reconcile disks	{"error": "context canceled"}
```

## 相关代码位置

- `internal/controller/wukong_controller.go:244-262` - `reconcileDisks` 函数
- `internal/controller/wukong_controller.go:128-140` - `Reconcile` 函数中的处理
- `pkg/storage/reconcile.go:35-43` - 存储模块的 context 检查
- `pkg/storage/datavolume.go:93-97, 120-124` - DataVolume 的 context 检查

## 总结

`context canceled` 错误是**正常的**，表示操作需要更多时间，Controller 会自动 requeue 并在下次 reconcile 时重试。修复后，这个错误不再会打印 ERROR 级别的日志，而是使用 DEBUG/V(1) 级别，避免误导。


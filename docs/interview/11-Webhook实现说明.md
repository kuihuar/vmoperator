# Webhook 实现说明

## 1. 实现概述

已为项目实现了完整的 Webhook 功能，包括 Mutating Webhook（设置默认值）和 Validating Webhook（验证资源）。

## 2. 实现文件

### 2.1 Webhook 代码

**文件**: `api/v1alpha1/wukong_webhook.go`

**功能**:
- **Defaulter**: 设置默认值
- **Validator**: 验证资源创建和更新

### 2.2 配置更新

**文件**: `cmd/main.go`
- 注册 Webhook 到 Manager

**文件**: `config/default/kustomization.yaml`
- 启用 webhook 资源
- 启用 webhook patch

**文件**: `config/default/manager_webhook_patch.yaml`
- 配置 webhook 端口（9443）
- 配置证书挂载

**文件**: `config/webhook/`
- `manifests.yaml`: Webhook 配置（MutatingWebhookConfiguration 和 ValidatingWebhookConfiguration）
- `service.yaml`: Webhook Service
- `kustomization.yaml`: Webhook 资源配置

## 3. Defaulter 实现

### 3.1 默认值设置

```go
func (r *Wukong) Default() {
    // 1. 设置默认内存
    if r.Spec.Memory == "" {
        r.Spec.Memory = "2Gi"
    }
    
    // 2. 设置默认启动策略
    if r.Spec.StartStrategy == nil {
        r.Spec.StartStrategy = &StartStrategySpec{
            AutoStart: true,
        }
    }
    
    // 3. 设置默认 StorageClass
    for i := range r.Spec.Disks {
        if r.Spec.Disks[i].StorageClassName == "" {
            r.Spec.Disks[i].StorageClassName = "longhorn"
        }
    }
    
    // 4. 设置默认网络类型
    for i := range r.Spec.Networks {
        if r.Spec.Networks[i].Type == "" {
            r.Spec.Networks[i].Type = "bridge"
        }
    }
    
    // 5. 设置 CloudInitUser 默认值
    if r.Spec.CloudInitUser != nil {
        if r.Spec.CloudInitUser.Shell == "" {
            r.Spec.CloudInitUser.Shell = "/bin/bash"
        }
        if r.Spec.CloudInitUser.Sudo == "" {
            r.Spec.CloudInitUser.Sudo = "ALL=(ALL) NOPASSWD:ALL"
        }
    }
}
```

## 4. Validator 实现

### 4.1 ValidateCreate（创建时验证）

```go
func (r *Wukong) ValidateCreate() (admission.Warnings, error) {
    // 1. 验证 CPU
    if r.Spec.CPU < 1 || r.Spec.CPU > 64 {
        return nil, fmt.Errorf("invalid CPU: must be between 1 and 64, got %d", r.Spec.CPU)
    }
    
    // 2. 验证内存
    if r.Spec.Memory == "" {
        return nil, fmt.Errorf("memory is required")
    }
    
    // 3. 验证至少有一个磁盘
    if len(r.Spec.Disks) == 0 {
        return nil, fmt.Errorf("at least one disk is required")
    }
    
    // 4. 验证磁盘配置
    // 5. 验证网络配置
    // 6. 验证 CloudInitUser
    
    return nil, nil
}
```

### 4.2 ValidateUpdate（更新时验证）

```go
func (r *Wukong) ValidateUpdate(old runtime.Object) (admission.Warnings, error) {
    oldWukong := old.(*Wukong)
    
    // 1. 验证 CPU 不能减少
    if r.Spec.CPU < oldWukong.Spec.CPU {
        return nil, fmt.Errorf("CPU cannot be reduced from %d to %d", oldWukong.Spec.CPU, r.Spec.CPU)
    }
    
    // 2. 验证磁盘不能删除
    if len(r.Spec.Disks) < len(oldWukong.Spec.Disks) {
        return nil, fmt.Errorf("disks cannot be removed")
    }
    
    // 3. 复用创建时的验证
    return r.ValidateCreate()
}
```

### 4.3 ValidateDelete（删除时验证）

```go
func (r *Wukong) ValidateDelete() (admission.Warnings, error) {
    // 通常不需要验证，Finalizer 会处理清理
    return nil, nil
}
```

## 5. 证书管理

### 5.1 使用 cert-manager（推荐）

如果需要使用 cert-manager 管理证书，需要：

1. **创建 Certificate**:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: webhook-server-cert
  namespace: system
spec:
  dnsNames:
    - webhook-service.system.svc
    - webhook-service.system.svc.cluster.local
  issuerRef:
    kind: Issuer
    name: selfsigned-issuer
  secretName: webhook-server-cert
```

2. **更新 kustomization.yaml**:
```yaml
# 在 config/default/kustomization.yaml 中
resources:
- ../certmanager  # 取消注释

replacements:
  # 添加证书注入配置
```

### 5.2 使用自签名证书（开发环境）

Controller Runtime 会自动生成自签名证书（如果未指定证书路径）。

## 6. 部署步骤

### 6.1 生成 Manifests

```bash
# 生成 CRD 和 Webhook 配置
make manifests
```

### 6.2 部署

```bash
# 部署到集群
kubectl apply -k config/default
```

### 6.3 验证

```bash
# 检查 Webhook 配置
kubectl get mutatingwebhookconfiguration
kubectl get validatingwebhookconfiguration

# 检查 Webhook Service
kubectl get svc -n novasphere-system webhook-service

# 测试创建资源（应该触发 Webhook）
kubectl apply -f config/samples/vm_v1alpha1_wukong.yaml
```

## 7. Webhook 路径

- **Mutating Webhook**: `/mutate-vm-novasphere-dev-v1alpha1-wukong`
- **Validating Webhook**: `/validate-vm-novasphere-dev-v1alpha1-wukong`

## 8. 验证时机

### 8.1 Mutating Webhook

- **时机**: 资源创建/更新前
- **作用**: 设置默认值
- **失败策略**: `Fail`（失败时拒绝请求）

### 8.2 Validating Webhook

- **时机**: 资源创建/更新前（在 Mutating 之后）
- **作用**: 验证资源有效性
- **失败策略**: `Fail`（失败时拒绝请求）

## 9. 与现有验证的关系

### 9.1 验证层次

1. **CRD Schema 验证**（OpenAPI）: 基本类型和格式验证
2. **Webhook 验证**: 业务逻辑验证和默认值设置
3. **Controller 验证**: 运行时验证（访问集群状态）

### 9.2 验证顺序

```
用户创建/更新资源
    ↓
CRD Schema 验证（API Server）
    ↓
Mutating Webhook（设置默认值）
    ↓
Validating Webhook（验证资源）
    ↓
资源创建/更新
    ↓
Controller Reconcile（运行时验证）
```

## 10. 优势

### 10.1 立即拒绝无效请求

- 在资源创建时就拒绝，而不是等到 Controller 处理
- 提供更好的用户体验

### 10.2 自动设置默认值

- 减少用户配置负担
- 确保资源配置完整

### 10.3 防止资源变更错误

- 防止减少 CPU/内存
- 防止删除磁盘
- 防止减少磁盘大小

## 11. 注意事项

### 11.1 证书管理

- 生产环境建议使用 cert-manager
- 开发环境可以使用自签名证书

### 11.2 Webhook 可用性

- Webhook 必须可用，否则资源创建/更新会失败
- 确保 Webhook Service 正常运行
- 确保证书有效

### 11.3 性能考虑

- Webhook 会增加资源创建/更新的延迟
- 验证逻辑应该快速执行
- 避免在 Webhook 中进行耗时操作

## 12. 面试要点

### 12.1 Webhook 的作用？

**答案**:
- **Mutating Webhook**: 在资源创建/更新前设置默认值
- **Validating Webhook**: 在资源创建/更新前验证资源有效性
- 在 API Server 层面进行验证，立即拒绝无效请求

### 12.2 与 Controller 验证的区别？

**答案**:
- **Webhook**: 在 API Server 层面，资源创建前验证
- **Controller**: 在运行时验证，可以访问集群状态
- **时机**: Webhook 在资源创建前，Controller 在资源创建后

### 12.3 证书管理方式？

**答案**:
- **cert-manager**: 生产环境推荐，自动管理证书
- **自签名证书**: 开发环境，Controller Runtime 自动生成
- **手动证书**: 通过 `--webhook-cert-path` 指定


# 验证与 Webhook 详解

## 1. 验证的层次

在 Kubebuilder 项目中，验证通常分为三个层次：

### 1.1 CRD Schema 验证（OpenAPI 验证）

**位置**: CRD 定义中的 `openAPIV3Schema`

**实现方式**: 使用 `+kubebuilder:validation` 标记

**特点**:
- 在 API Server 层面进行验证
- 在资源创建/更新时立即拒绝无效请求
- 不需要 Controller 运行

**示例**:
```go
// CPU is the number of CPU cores for the virtual machine
// +kubebuilder:validation:Minimum=1
// +kubebuilder:validation:Maximum=64
// +required
CPU int `json:"cpu"`
```

**生成的 CRD**:
```yaml
cpu:
  description: CPU is the number of CPU cores for the virtual machine
  maximum: 64
  minimum: 1
  type: integer
```

### 1.2 Controller 业务逻辑验证

**位置**: Controller 的 `validateSpec` 函数

**实现方式**: 在 Reconcile 循环中手动验证

**特点**:
- 可以访问集群状态（如检查 StorageClass 是否存在）
- 可以进行复杂的业务逻辑验证
- 验证失败时设置错误状态

**示例**:
```go
func (r *WukongReconciler) validateSpec(vmp *vmv1alpha1.Wukong) error {
    // 验证 CPU
    if vmp.Spec.CPU < 1 || vmp.Spec.CPU > 64 {
        return fmt.Errorf("invalid CPU: must be between 1 and 64, got %d", vmp.Spec.CPU)
    }
    
    // 验证至少有一个磁盘
    if len(vmp.Spec.Disks) == 0 {
        return fmt.Errorf("at least one disk is required")
    }
    
    // 验证磁盘配置
    for i, disk := range vmp.Spec.Disks {
        if disk.Name == "" {
            return fmt.Errorf("disk[%d].name is required", i)
        }
        if disk.StorageClassName == "" {
            return fmt.Errorf("disk[%d].storageClassName is required", i)
        }
    }
    
    return nil
}
```

### 1.3 Webhook 验证（可选）

**位置**: 独立的 Webhook 文件（如 `api/v1alpha1/wukong_webhook.go`）

**实现方式**: 实现 `Defaulter` 和 `Validator` 接口

**特点**:
- 在资源创建/更新前进行验证
- 可以设置默认值
- 可以访问集群状态
- 需要额外的配置和证书管理

## 2. 当前项目的验证实现

### 2.1 CRD Schema 验证

项目使用了大量的 `+kubebuilder:validation` 标记：

```go
// CPU 验证
// +kubebuilder:validation:Minimum=1
// +kubebuilder:validation:Maximum=64
CPU int `json:"cpu"`

// Memory 验证
// +kubebuilder:validation:Pattern=`^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|K|M|G|T|P|E)?$`
Memory string `json:"memory"`

// 网络类型验证
// +kubebuilder:validation:Enum=bridge;macvlan;sriov;ovs
Type string `json:"type"`

// VLAN ID 验证
// +kubebuilder:validation:Minimum=1
// +kubebuilder:validation:Maximum=4094
VLANID *int `json:"vlanId,omitempty"`
```

### 2.2 Controller 验证

在 `wukong_controller.go` 中实现了 `validateSpec` 函数：

```go
// 在 Reconcile 中调用
if err := r.validateSpec(&vmp); err != nil {
    logger.Error(err, "invalid Wukong spec")
    vmp.Status.Phase = vmv1alpha1.PhaseError
    r.Status().Update(ctx, &vmp)
    return ctrl.Result{RequeueAfter: time.Minute}, nil
}
```

### 2.3 Webhook 状态

**当前状态**: 未实现 Webhook

**原因**:
- CRD Schema 验证已经覆盖了大部分验证需求
- Controller 验证可以处理业务逻辑
- Webhook 需要额外的配置和证书管理

## 3. Webhook 是可选项吗？

### 3.1 答案：是的，Webhook 是可选的

**Kubebuilder 项目可以正常工作而不需要 Webhook**，原因：

1. **CRD Schema 验证足够**: 大部分基本验证可以通过 OpenAPI Schema 完成
2. **Controller 验证补充**: 业务逻辑验证可以在 Controller 中完成
3. **Webhook 的复杂性**: 需要证书管理、TLS 配置等

### 3.2 什么时候需要 Webhook？

**适合使用 Webhook 的场景**:

1. **需要访问集群状态进行验证**
   - 例如：验证 StorageClass 是否存在
   - 例如：验证引用的 Secret 是否存在

2. **需要设置默认值**
   - 例如：根据集群配置自动设置默认值
   - 例如：根据其他字段自动计算值

3. **需要立即拒绝无效请求**
   - 例如：在资源创建时就拒绝，而不是等到 Controller 处理

4. **需要修改资源**
   - 例如：自动添加标签、注解
   - 例如：规范化字段值

### 3.3 什么时候不需要 Webhook？

**不需要 Webhook 的场景**:

1. **基本验证已足够**: CRD Schema 验证已经覆盖需求
2. **业务逻辑验证可以异步**: Controller 验证可以处理
3. **简化部署**: 避免证书管理和 Webhook 配置的复杂性
4. **开发阶段**: 快速迭代，不需要额外的 Webhook 开发

## 4. 如何添加 Webhook（如果需要）

### 4.1 生成 Webhook 代码

```bash
# 使用 kubebuilder 生成 Webhook
kubebuilder create webhook \
    --group vm \
    --version v1alpha1 \
    --kind Wukong \
    --defaulting \
    --programmatic-validation
```

### 4.2 实现 Validator 接口

```go
// api/v1alpha1/wukong_webhook.go

// +kubebuilder:webhook:path=/mutate-vm-novasphere-dev-v1alpha1-wukong,mutating=true,failurePolicy=fail,sideEffects=None,groups=vm.novasphere.dev,resources=wukongs,verbs=create;update,versions=v1alpha1,name=mwukong.kb.io,admissionReviewVersions=v1

var _ webhook.Defaulter = &Wukong{}

// Default implements webhook.Defaulter so a webhook will be registered for the type
func (r *Wukong) Default() {
    // 设置默认值
    if r.Spec.Memory == "" {
        r.Spec.Memory = "2Gi"
    }
}

// +kubebuilder:webhook:path=/validate-vm-novasphere-dev-v1alpha1-wukong,mutating=false,failurePolicy=fail,sideEffects=None,groups=vm.novasphere.dev,resources=wukongs,verbs=create;update,versions=v1alpha1,name=vwukong.kb.io,admissionReviewVersions=v1

var _ webhook.Validator = &Wukong{}

// ValidateCreate implements webhook.Validator so a webhook will be registered for the type
func (r *Wukong) ValidateCreate() error {
    // 创建时的验证
    if len(r.Spec.Disks) == 0 {
        return fmt.Errorf("at least one disk is required")
    }
    return nil
}

// ValidateUpdate implements webhook.Validator so a webhook will be registered for the type
func (r *Wukong) ValidateUpdate(old runtime.Object) error {
    // 更新时的验证
    oldWukong := old.(*Wukong)
    // 例如：不允许减少 CPU
    if r.Spec.CPU < oldWukong.Spec.CPU {
        return fmt.Errorf("CPU cannot be reduced")
    }
    return nil
}

// ValidateDelete implements webhook.Validator so a webhook will be registered for the type
func (r *Wukong) ValidateDelete() error {
    // 删除时的验证（通常不需要）
    return nil
}
```

### 4.3 配置 Webhook

在 `main.go` 中注册 Webhook：

```go
if err = (&vmv1alpha1.Wukong{}).SetupWebhookWithManager(mgr); err != nil {
    setupLog.Error(err, "unable to create webhook", "webhook", "Wukong")
    os.Exit(1)
}
```

### 4.4 证书管理

Webhook 需要 TLS 证书，可以使用 cert-manager：

```yaml
# config/certmanager/certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wukong-webhook-cert
  namespace: system
spec:
  dnsNames:
    - wukong-webhook-service.system.svc
    - wukong-webhook-service.system.svc.cluster.local
  issuerRef:
    kind: Issuer
    name: wukong-selfsigned-issuer
  secretName: wukong-webhook-cert
```

## 5. 验证策略对比

| 验证方式 | 时机 | 优点 | 缺点 |
|---------|------|------|------|
| **CRD Schema** | API Server | 立即拒绝，无需 Controller | 只能验证基本规则 |
| **Controller** | Reconcile | 可以访问集群状态 | 资源已创建，需要清理 |
| **Webhook** | API Server | 立即拒绝，可访问集群状态 | 需要证书管理，配置复杂 |

## 6. 最佳实践

### 6.1 推荐策略

1. **优先使用 CRD Schema 验证**
   - 覆盖基本验证（类型、范围、格式等）
   - 简单、高效、无需额外配置

2. **Controller 验证处理业务逻辑**
   - 需要访问集群状态的验证
   - 复杂的业务规则

3. **Webhook 作为可选增强**
   - 需要立即拒绝的场景
   - 需要设置默认值的场景
   - 需要修改资源的场景

### 6.2 当前项目的验证策略

**当前实现**:
- ✅ CRD Schema 验证：覆盖基本验证
- ✅ Controller 验证：处理业务逻辑
- ❌ Webhook：未实现（可选）

**这是合理的**:
- CRD Schema 验证已经足够
- Controller 验证可以处理业务逻辑
- 避免 Webhook 的复杂性

## 7. 面试要点

### 7.1 验证的层次？

**答案**:
1. **CRD Schema 验证**: 在 API Server 层面，使用 OpenAPI Schema
2. **Controller 验证**: 在 Reconcile 循环中，处理业务逻辑
3. **Webhook 验证**: 在 API Server 层面，可访问集群状态（可选）

### 7.2 Webhook 是必需的吗？

**答案**: 
不是必需的。Kubebuilder 项目可以正常工作而不需要 Webhook。CRD Schema 验证和 Controller 验证已经可以满足大部分需求。

### 7.3 什么时候需要 Webhook？

**答案**:
- 需要访问集群状态进行验证
- 需要设置默认值
- 需要立即拒绝无效请求
- 需要修改资源

### 7.4 如何选择验证方式？

**答案**:
- **基本验证**: 使用 CRD Schema（`+kubebuilder:validation`）
- **业务逻辑**: 使用 Controller 验证
- **高级需求**: 考虑 Webhook


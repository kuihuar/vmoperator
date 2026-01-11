# NetworkAttachmentDefinition 创建流程

## 概述

`NetworkAttachmentDefinition` (NAD) 是 Multus CNI 使用的网络配置资源，用于定义多网络接口。本文档说明 NAD 在 Wukong 控制器中的创建时机和流程。

## 创建时机

`NetworkAttachmentDefinition` 在 **Controller 的 Reconcile 循环中**创建，具体时机如下：

1. **触发时机**：当 Wukong 资源被创建或更新时
2. **执行阶段**：在处理网络配置阶段（第 7 步）
3. **调用函数**：`network.ReconcileNetworks`

## 创建流程

### 1. Controller Reconcile 循环

```go
// internal/controller/wukong_controller.go
func (r *WukongReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // ... 前面的步骤（获取资源、检查删除、验证等）
    
    // 7. 处理网络配置
    networksStatus, err := r.reconcileNetworks(ctx, &vmp)
    if err != nil {
        // 处理错误
    }
    
    // ... 后续步骤（处理存储、创建 VM 等）
}
```

### 2. reconcileNetworks 方法

```go
// internal/controller/wukong_controller.go:235
func (r *WukongReconciler) reconcileNetworks(ctx context.Context, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.NetworkStatus, error) {
    // 1. 使用 Multus 管理 NetworkAttachmentDefinition
    netStatuses, err := network.ReconcileNetworks(ctx, r.Client, vmp)
    if err != nil {
        return nil, err
    }
    
    // 2. 使用 NMState 配置节点网络
    if err := network.ReconcileNMState(ctx, r.Client, vmp); err != nil {
        return nil, err
    }
    
    return netStatuses, nil
}
```

### 3. ReconcileNetworks 函数（核心逻辑）

```go
// pkg/network/multus.go:25
func ReconcileNetworks(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) ([]vmv1alpha1.NetworkStatus, error) {
    for _, netCfg := range vmp.Spec.Networks {
        // 1. 跳过 default 网络（使用 Pod 网络）
        if netCfg.Name == "default" {
            continue
        }
        
        // 2. 确定 NAD 名称
        nadName := netCfg.NADName
        if nadName == "" {
            nadName = fmt.Sprintf("%s-%s-nad", vmp.Name, netCfg.Name)
        }
        
        // 3. 尝试获取现有的 NAD
        err := c.Get(ctx, key, nad)
        if err != nil {
            if errors.IsNotFound(err) && netCfg.NADName == "" {
                // 4. NAD 不存在且用户未指定 NADName，则创建新的 NAD
                // 检查 Multus CRD 是否存在
                // 构建 CNI 配置
                // 创建 NAD
                if err := c.Create(ctx, nad); err != nil {
                    return nil, err
                }
            }
        }
    }
}
```

## 创建条件

NAD 会在以下**所有条件都满足**时创建：

1. ✅ 网络名称不是 "default"（default 网络使用 Pod 网络，不需要 NAD）
2. ✅ 网络类型是 "bridge" 或 "ovs"（macvlan/ipvlan 不支持）
3. ✅ 用户未指定 `NADName`（如果指定了，则使用现有的 NAD，不创建）
4. ✅ NAD 不存在（`Get` 操作返回 `NotFound` 错误）
5. ✅ Multus CRD 存在（Multus CNI 已安装）

## 创建逻辑详解

### 1. NAD 名称生成

```go
// 如果用户指定了 NADName，使用用户指定的名称
nadName := netCfg.NADName

// 如果用户未指定，自动生成：<Wukong名称>-<网络名称>-nad
if nadName == "" {
    nadName = fmt.Sprintf("%s-%s-nad", vmp.Name, netCfg.Name)
}
```

**示例**：
- Wukong 名称：`ubuntu-vm-dual-network-dhcp`
- 网络名称：`external`
- 生成的 NAD 名称：`ubuntu-vm-dual-network-dhcp-external-nad`

### 2. CNI 配置构建

```go
// pkg/network/multus.go:149
configStr, cfgErr := buildCNIConfig(&netCfg)
```

`buildCNIConfig` 函数根据 `NetworkConfig` 构建 CNI 配置 JSON 字符串：

- **类型**：强制使用 "bridge" CNI
- **桥接名称**：使用 `BridgeName` 或自动生成 `br-<网络名称>`
- **IPAM**：
  - DHCP 模式：不设置 IPAM（VM 内部通过 Cloud-Init DHCP 获取 IP）
  - Static 模式：使用 host-local IPAM 配置静态 IP

### 3. NAD 对象创建

```go
nad := &unstructured.Unstructured{}
nad.SetGroupVersionKind(schema.GroupVersionKind{
    Group:   "k8s.cni.cncf.io",
    Version: "v1",
    Kind:    "NetworkAttachmentDefinition",
})
nad.SetName(nadName)
nad.SetNamespace(vmp.Namespace)

// 设置 spec.config
unstructured.SetNestedField(nad.Object, map[string]interface{}{
    "config": configStr,
}, "spec")

// 创建 NAD
c.Create(ctx, nad)
```

## 执行顺序

在 Controller 的 Reconcile 循环中，NAD 的创建顺序如下：

```
1. 获取 Wukong 资源
2. 检查是否正在删除
3. 添加 finalizer
4. 验证 spec
5. 初始化状态
6. 更新状态为 Creating
7. 🔹 处理网络配置（创建 NAD） ← 这里创建 NAD
8. 处理存储配置
9. 创建/更新 VirtualMachine
10. 同步 VM 状态
11. 更新 Wukong 状态
```

## 与 NMState 的关系

NAD 的创建**先于** NMState 策略的创建：

```
ReconcileNetworks (Multus)
    ↓
创建 NetworkAttachmentDefinition (NAD)
    ↓
ReconcileNMState
    ↓
创建 NodeNetworkConfigurationPolicy (NNCP)
    ↓
配置节点网络（桥接等）
```

**注意**：
- NAD 定义了**如何使用**网络（通过 bridge CNI 连接到哪个桥接）
- NNCP 定义了**如何创建**网络（在节点上创建桥接）

## 示例

### 配置文件

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-vm-dual-network-dhcp
spec:
  networks:
    - name: default  # 跳过，不使用 NAD
    
    - name: external
      type: bridge
      bridgeName: "br-external"
      physicalInterface: "ens192"
      ipConfig:
        mode: dhcp
```

### 生成的 NAD

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ubuntu-vm-dual-network-dhcp-external-nad
  namespace: <Wukong 的 namespace>
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-external",
      "disableContainerInterface": true
    }
```

## 总结

- **创建时机**：Controller Reconcile 循环的网络配置阶段
- **创建条件**：网络非 default、类型为 bridge/ovs、用户未指定 NADName、NAD 不存在、Multus 已安装
- **创建位置**：`pkg/network/multus.go` 的 `ReconcileNetworks` 函数
- **执行顺序**：在 NMState 策略创建之前，在 VM 创建之前

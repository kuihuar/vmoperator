# Spec 字段详解

## 1. 基础字段

### 1.1 CPU

```go
// +kubebuilder:validation:Minimum=1
// +kubebuilder:validation:Maximum=64
CPU int `json:"cpu"`
```

**说明**:
- 范围: 1-64 核心
- 必填字段
- 直接映射到 KubeVirt VM 的 CPU 配置

**使用示例**:
```yaml
spec:
  cpu: 4
```

### 1.2 Memory

```go
// +kubebuilder:validation:Pattern=`^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|K|M|G|T|P|E)?$`
Memory string `json:"memory"`
```

**说明**:
- 支持 Kubernetes 资源单位格式
- 示例: "8Gi", "4G", "512Mi"
- 必填字段

**使用示例**:
```yaml
spec:
  memory: 8Gi
```

## 2. 网络配置 (Networks)

### 2.1 NetworkConfig 结构

```go
type NetworkConfig struct {
    Name       string        `json:"name"`        // 网络接口名称
    Type       string        `json:"type"`        // 网络类型: bridge/macvlan/sriov/ovs
    NADName    string        `json:"nadName,omitempty"`  // 现有 NAD 名称
    VLANID     *int          `json:"vlanId,omitempty"`   // VLAN ID (1-4094)
    BridgeName string        `json:"bridgeName,omitempty"` // 桥接名称
    IPConfig   *IPConfigSpec `json:"ipConfig,omitempty"`   // IP 配置
}
```

### 2.2 网络类型

| 类型 | 说明 | 使用场景 |
|------|------|----------|
| `bridge` | Linux 桥接 | 最常用，支持 VLAN |
| `macvlan` | MACVLAN | 需要直接访问物理网络 |
| `sriov` | SR-IOV | 高性能网络，需要硬件支持 |
| `ovs` | Open vSwitch | 需要 OVS 支持 |

### 2.3 IPConfigSpec

```go
type IPConfigSpec struct {
    Mode       string   `json:"mode"`              // static 或 dhcp
    Address    *string  `json:"address,omitempty"` // IP 地址 (如 "192.168.1.10/24")
    Gateway    *string  `json:"gateway,omitempty"` // 网关地址
    DNSServers []string `json:"dnsServers,omitempty"` // DNS 服务器列表
}
```

**使用示例**:
```yaml
networks:
  - name: mgmt
    type: bridge
    vlanId: 100
    ipConfig:
      mode: static
      address: 192.168.100.10/24
      gateway: 192.168.100.1
      dnsServers:
        - 8.8.8.8
        - 8.8.4.4
  - name: data
    type: bridge
    ipConfig:
      mode: dhcp
```

## 3. 存储配置 (Disks)

### 3.1 DiskConfig 结构

```go
type DiskConfig struct {
    Name            string `json:"name"`              // 磁盘名称
    Size            string `json:"size"`              // 磁盘大小
    StorageClassName string `json:"storageClassName"`  // StorageClass 名称
    Boot            bool   `json:"boot,omitempty"`     // 是否为启动盘
    Image           string `json:"image,omitempty"`    // 容器镜像 URL (使用 DataVolume)
}
```

### 3.2 磁盘类型

#### 普通 PVC 磁盘

```yaml
disks:
  - name: system
    size: 80Gi
    storageClassName: longhorn
    boot: true
```

#### 从镜像创建磁盘 (DataVolume)

```yaml
disks:
  - name: system
    size: 80Gi
    storageClassName: longhorn
    image: quay.io/containerdisks/ubuntu:22.04
    boot: true
```

**说明**:
- 如果指定 `image`，会创建 `DataVolume` 来导入镜像
- 如果不指定 `image`，直接创建 `PVC`

### 3.3 多磁盘配置

```yaml
disks:
  - name: system
    size: 80Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 500Gi
    storageClassName: longhorn
```

## 4. Cloud-Init 配置

### 4.1 OSImage

```go
OSImage string `json:"osImage,omitempty"`
```

**说明**: 操作系统镜像标识（用于 Cloud-Init 配置）

### 4.2 SSHKeySecret

```go
SSHKeySecret string `json:"sshKeySecret,omitempty"`
```

**说明**: 包含 SSH 公钥的 Secret 名称

**使用示例**:
```yaml
spec:
  sshKeySecret: my-ssh-keys
```

### 4.3 CloudInitUser

```go
type CloudInitUserSpec struct {
    Name        string   `json:"name"`              // 用户名
    Password    string   `json:"password,omitempty"`      // 明文密码（不推荐）
    PasswordHash string  `json:"passwordHash,omitempty"`   // 密码哈希（推荐）
    Sudo        string   `json:"sudo,omitempty"`           // Sudo 配置
    Shell       string   `json:"shell,omitempty"`          // Shell 路径
    Groups      []string `json:"groups,omitempty"`         // 用户组
    LockPasswd  bool     `json:"lockPasswd,omitempty"`     // 是否锁定密码
}
```

**使用示例**:
```yaml
spec:
  cloudInitUser:
    name: admin
    passwordHash: "$6$..."  # 使用 openssl passwd -1 生成
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    groups:
      - sudo
      - docker
```

**密码哈希生成**:
```bash
# 方法 1: openssl
openssl passwd -1 mypassword

# 方法 2: Python
python3 -c "import crypt; print(crypt.crypt('mypassword', crypt.mksalt(crypt.METHOD_SHA512)))"
```

## 5. 高可用配置

### 5.1 HighAvailabilitySpec

```go
type HighAvailabilitySpec struct {
    RestartPolicy string                `json:"restartPolicy,omitempty"`  // Always/OnFailure/Never
    AntiAffinity  bool                  `json:"antiAffinity,omitempty"`   // 反亲和性
    NodeSelector  map[string]string     `json:"nodeSelector,omitempty"`   // 节点选择器
    Tolerations   []corev1.Toleration  `json:"tolerations,omitempty"`    // 容忍度
}
```

**使用示例**:
```yaml
spec:
  highAvailability:
    restartPolicy: Always
    antiAffinity: true
    nodeSelector:
      node-role.kubernetes.io/worker: ""
    tolerations:
      - key: "key1"
        operator: "Equal"
        value: "value1"
        effect: "NoSchedule"
```

## 6. 启动策略

### 6.1 StartStrategySpec

```go
type StartStrategySpec struct {
    RunStrategy string `json:"runStrategy,omitempty"`  // Always/RerunOnFailure/Manual
    AutoStart   bool   `json:"autoStart,omitempty"`    // 是否自动启动
}
```

**使用示例**:
```yaml
spec:
  startStrategy:
    runStrategy: Always
    autoStart: true
```

## 7. 完整示例

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: web-server-01
spec:
  # 基础配置
  cpu: 4
  memory: 8Gi
  
  # 网络配置
  networks:
    - name: mgmt
      type: bridge
      vlanId: 100
      ipConfig:
        mode: static
        address: 192.168.100.10/24
        gateway: 192.168.100.1
    - name: data
      type: bridge
      ipConfig:
        mode: dhcp
  
  # 存储配置
  disks:
    - name: system
      size: 80Gi
      storageClassName: longhorn
      image: quay.io/containerdisks/ubuntu:22.04
      boot: true
    - name: data
      size: 500Gi
      storageClassName: longhorn
  
  # Cloud-Init 配置
  sshKeySecret: my-ssh-keys
  cloudInitUser:
    name: admin
    passwordHash: "$6$..."
    sudo: "ALL=(ALL) NOPASSWD:ALL"
  
  # 高可用配置
  highAvailability:
    restartPolicy: Always
    antiAffinity: true
  
  # 启动策略
  startStrategy:
    autoStart: true
```

## 8. 面试要点

### 8.1 为什么网络和磁盘都是数组？

**答案**:
- 支持多网络接口（管理网、业务网等）
- 支持多磁盘（系统盘、数据盘等）
- 提供更灵活的配置能力

### 8.2 Image 字段的作用？

**答案**:
- 如果指定 `image`，使用 `DataVolume` 从容器镜像导入数据
- 如果不指定，直接创建空的 `PVC`
- 支持从容器镜像快速创建虚拟机磁盘

### 8.3 Cloud-Init 配置的优先级？

**答案**:
- `cloudInitUser` > `sshKeySecret` > `osImage`
- 如果同时配置，会合并所有配置
- 最终生成完整的 Cloud-Init 用户数据

### 8.4 如何实现多网络隔离？

**答案**:
- 使用不同的 `NetworkConfig` 定义多个网络
- 每个网络可以配置不同的 VLAN ID
- 通过 Multus CNI 创建多个网络接口


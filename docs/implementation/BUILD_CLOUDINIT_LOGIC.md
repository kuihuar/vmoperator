# buildCloudInitData 函数逻辑详解

## 1. 函数概述

`buildCloudInitData` 函数用于生成 Cloud-Init 用户数据（UserData），这是 VM 启动时自动执行的配置脚本。函数返回一个符合 Cloud-Init 格式的 YAML 字符串。

**函数签名：**
```go
func buildCloudInitData(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus) string
```

**输入参数：**
- `ctx`: 上下文
- `c`: Kubernetes 客户端（用于读取 Secret）
- `vmp`: Wukong CR 对象（包含用户配置）
- `networks`: 网络状态列表（包含 MAC 地址等信息）

**返回值：**
- Cloud-Init YAML 格式的字符串

## 2. 实现逻辑

### 2.1 初始化

```go
cloudInit := "#cloud-config\n"
```

生成 Cloud-Init 配置文件的头部标识。

### 2.2 用户配置（第一部分）

**条件：** `vmp.Spec.CloudInitUser != nil`

生成用户配置，包括：

#### 2.2.1 用户名
```yaml
users:
  - name: <user.Name>
```

#### 2.2.2 密码配置
- **优先使用密码哈希**（推荐）：
  ```yaml
  passwd: $1$7.t8q8zZ$59I1IiMXy5w3gIl5Yrn/4/
  ```
- **备选明文密码**（不推荐，可能不工作）：
  ```yaml
  passwd: plaintext_password
  ```

#### 2.2.3 Sudo 配置
- 如果指定了 `user.Sudo`，使用指定值
- 否则默认：`ALL=(ALL) NOPASSWD:ALL`

#### 2.2.4 Shell 配置
- 如果指定了 `user.Shell`，使用指定值
- 否则默认：`/bin/bash`

#### 2.2.5 用户组配置
- 如果指定了 `user.Groups`，使用指定值
- 否则默认：`sudo, adm, dialout, cdrom, floppy, audio, dip, video, plugdev, netdev`

#### 2.2.6 其他配置
```yaml
lock_passwd: false  # 是否锁定密码
ssh_pwauth: true   # 允许密码认证
disable_root: false # 允许 root 登录
```

### 2.3 SSH 公钥配置（第二部分）

**条件：** `vmp.Spec.SSHKeySecret != ""`

#### 2.3.1 从 Secret 读取 SSH 公钥

1. **查找 Secret**：
   ```go
   secret := &corev1.Secret{}
   key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmp.Spec.SSHKeySecret}
   c.Get(ctx, key, secret)
   ```

2. **查找 SSH 公钥**（按优先级）：
   - `ssh-publickey`
   - `id_rsa.pub`
   - `authorized_keys`
   - `publickey`
   - 如果都没找到，使用 Secret 中第一个非空值

3. **生成配置**：
   ```yaml
   ssh_authorized_keys:
     - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
     - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...
   ```
   - 按行分割 SSH 公钥
   - 过滤空行和注释行（以 `#` 开头）

### 2.4 网络配置（第三部分）

**条件：** 网络配置了静态 IP（`net.IPConfig.Mode == "static"`）

#### 2.4.1 准备工作

1. **创建网络状态映射**：
   ```go
   netStatusMap := make(map[string]vmv1alpha1.NetworkStatus)
   for _, netStatus := range networks {
       netStatusMap[netStatus.Name] = netStatus
   }
   ```

2. **初始化网络配置**：
   ```yaml
   network:
     version: 2
     ethernets:
   ```

#### 2.4.2 遍历网络配置

对于每个配置了静态 IP 的网络：

1. **跳过 default 网络**：
   - `default` 网络使用 Pod 网络，不需要静态 IP 配置

2. **检查是否为 Multus 网络**：
   - 必须有 `NADName` 才是 Multus 网络
   - 如果没有 `NADName`，跳过

3. **获取 MAC 地址**（用于接口匹配）：
   
   **优先级 1：** 从 `NetworkStatus` 获取
   ```go
   if hasStatus && netStatus.MACAddress != "" {
       macAddress = netStatus.MACAddress
   }
   ```
   
   **优先级 2：** 从现有 VMI 获取
   ```go
   if hasStatus && netStatus.NADName != "" {
       vmi := &kubevirtv1.VirtualMachineInstance{}
       c.Get(ctx, key, vmi)
       for _, iface := range vmi.Status.Interfaces {
           if iface.Name == net.Name && iface.MAC != "" {
               macAddress = iface.MAC
               break
           }
       }
   }
   ```
   **注意：** VMI 接口的 `Name` 是网络名称（`net.Name`），不是 NAD 名称。

4. **生成接口名称**：
   ```go
   interfaceName := fmt.Sprintf("enp%ds0", multusInterfaceIndex+1)
   ```
   - `enp2s0`（第一个 Multus 接口）
   - `enp3s0`（第二个 Multus 接口）
   - `enp4s0`（第三个 Multus 接口）
   - ...

5. **生成网络配置**：

   **如果有 MAC 地址**（推荐，最可靠）：
   ```yaml
   enp2s0:
     match:
       macaddress: aa:bb:cc:dd:ee:ff
     set-name: enp2s0
     addresses:
       - 192.168.1.200/24
     gateway4: 192.168.1.1
     nameservers:
       addresses:
         - 192.168.1.1
         - 114.114.114.114
   ```

   **如果没有 MAC 地址**（回退方案）：
   ```yaml
   enp2s0:
     addresses:
       - 192.168.1.200/24
     gateway4: 192.168.1.1
     nameservers:
       addresses:
         - 192.168.1.1
         - 114.114.114.114
   ```

6. **增加接口索引**：
   ```go
   multusInterfaceIndex++
   ```

## 3. 生成的 Cloud-Init 配置示例

### 3.1 完整示例

```yaml
#cloud-config
users:
  - name: ubuntu
    passwd: $1$7.t8q8zZ$59I1IiMXy5w3gIl5Yrn/4/
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo, adm, dialout
    lock_passwd: false

ssh_pwauth: true
disable_root: false

ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...

network:
  version: 2
  ethernets:
    enp2s0:
      match:
        macaddress: aa:bb:cc:dd:ee:ff
      set-name: enp2s0
      addresses:
        - 192.168.100.10/24
      gateway4: 192.168.100.1
      nameservers:
        addresses:
          - 192.168.100.1
          - 114.114.114.114
    enp3s0:
      match:
        macaddress: 11:22:33:44:55:66
      set-name: enp3s0
      addresses:
        - 192.168.1.200/24
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
          - 114.114.114.114
          - 8.8.8.8
```

## 4. 关键设计点

### 4.1 MAC 地址匹配

**为什么需要 MAC 地址匹配？**

- VM 内部的网络接口名称可能不稳定（如 `eth0`, `eth1`, `enp2s0` 等）
- 使用 MAC 地址匹配可以确保配置应用到正确的接口
- 这是 Cloud-Init/Netplan 推荐的做法

**MAC 地址获取优先级：**
1. `NetworkStatus.MACAddress`（最高优先级）
2. 从现有 VMI 状态获取（如果 VMI 已存在）
3. 如果没有 MAC 地址，直接使用接口名称（回退方案）

### 4.2 接口名称生成规则

- **默认网络**：`enp1s0`（Pod 网络，由 KubeVirt 自动配置）
- **第一个 Multus 网络**：`enp2s0`
- **第二个 Multus 网络**：`enp3s0`
- **第三个 Multus 网络**：`enp4s0`
- ...

**公式：** `enp{multusInterfaceIndex+1}s0`

### 4.3 网络过滤逻辑

只处理满足以下条件的网络：
1. ✅ 配置了 `IPConfig`
2. ✅ `IPConfig.Mode == "static"`
3. ✅ `IPConfig.Address != nil`
4. ✅ 不是 `default` 网络
5. ✅ 是 Multus 网络（有 `NADName`）

### 4.4 SSH 公钥查找策略

支持多种 Secret key 名称，按优先级查找：
1. `ssh-publickey`
2. `id_rsa.pub`
3. `authorized_keys`
4. `publickey`
5. Secret 中第一个非空值（回退方案）

## 5. 使用场景

### 5.1 首次创建 VM

- `NetworkStatus` 可能还没有 MAC 地址
- 会尝试从 VMI 获取，但如果 VMI 还未创建，则使用接口名称

### 5.2 更新 VM 配置

- `NetworkStatus` 中已有 MAC 地址
- 优先使用 `NetworkStatus.MACAddress`
- 如果 VMI 已存在，也可以从 VMI 状态获取

### 5.3 多网络场景

- 每个 Multus 网络都会生成对应的网络配置
- 接口名称按顺序递增（`enp2s0`, `enp3s0`, ...）

## 6. 注意事项

### 6.1 密码配置

- **推荐使用密码哈希**：`passwordHash` 字段
- **不推荐明文密码**：`password` 字段可能不工作
- 生成密码哈希：
  ```bash
  echo -n "password" | openssl passwd -1 -stdin
  # 或
  python3 -c "import crypt; print(crypt.crypt('password', crypt.mksalt(crypt.METHOD_SHA512)))"
  ```

### 6.2 网络配置

- **只处理静态 IP**：DHCP 模式不需要配置
- **跳过 default 网络**：使用 Pod 网络，由 KubeVirt 自动处理
- **MAC 地址匹配最可靠**：如果可能，尽量使用 MAC 地址匹配

### 6.3 SSH 公钥

- Secret 必须存在且可访问
- 支持多个 SSH 公钥（每行一个）
- 自动过滤注释和空行

## 7. 总结

`buildCloudInitData` 函数实现了完整的 Cloud-Init 配置生成逻辑，包括：

1. ✅ **用户配置**：用户名、密码、sudo、shell、groups
2. ✅ **SSH 公钥配置**：从 Secret 读取并配置
3. ✅ **网络配置**：为静态 IP 的 Multus 网络生成 Netplan 配置
4. ✅ **MAC 地址匹配**：确保配置应用到正确的网络接口
5. ✅ **多网络支持**：支持多个 Multus 网络接口

生成的 Cloud-Init 配置会在 VM 启动时自动执行，完成用户创建、SSH 配置和网络配置。


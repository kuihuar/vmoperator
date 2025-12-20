# k3s 环境镜像配置指南

## 概述

在 k3s 环境中，Pod 无法使用 `host.docker.internal`（这是 Docker Desktop 的特性）。需要使用实际的 IP 地址或主机名来访问宿主机上的服务。

## 镜像源配置

### 方案 1: HTTP/HTTPS 源（推荐）

如果镜像文件在宿主机上通过 HTTP 服务器提供：

```yaml
disks:
  - name: system
    size: 5Gi
    storageClassName: local-path  # k3s 默认使用 local-path
    boot: true
    image: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"
```

**配置要点**：
1. **使用实际 IP 地址**：将 `host.docker.internal` 替换为虚拟机的实际 IP（如 `192.168.1.141`）
2. **确保 HTTP 服务器可访问**：Pod 需要能够从集群网络访问宿主机 IP
3. **检查防火墙**：确保宿主机防火墙允许来自 Pod 网络的连接

### 方案 2: Docker Registry 源

如果镜像已推送到 registry：

```yaml
disks:
  - name: system
    size: 5Gi
    storageClassName: local-path
    boot: true
    image: "docker://192.168.1.141:5000/ubuntu-noble:latest"
```

**配置要点**：
1. **Registry 地址**：使用实际的 IP 地址或主机名
2. **网络可达性**：确保 Pod 能够访问 registry
3. **认证配置**：如果 registry 需要认证，需要配置 Secret

### 方案 3: 使用 NodePort/Service（高级）

如果 HTTP 服务器在集群内运行，可以通过 Service 暴露：

```yaml
# 创建 Service 暴露 HTTP 服务器
apiVersion: v1
kind: Service
metadata:
  name: image-server
spec:
  type: NodePort
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080
  selector:
    app: image-server
```

然后在 Wukong 中使用：
```yaml
image: "http://image-server.default.svc.cluster.local:8080/images/noble-server-cloudimg-amd64.img"
```

## 网络访问检查

### 1. 检查 Pod 能否访问宿主机 IP

```bash
# 在 Pod 中测试连接
kubectl run -it --rm test-curl --image=curlimages/curl --restart=Never -- \
  curl -I http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img
```

### 2. 检查宿主机防火墙

```bash
# 在宿主机上检查防火墙状态
sudo ufw status

# 如果需要，允许 8080 端口
sudo ufw allow 8080/tcp

# 或者临时关闭防火墙测试（不推荐生产环境）
sudo ufw disable
```

### 3. 检查 HTTP 服务器是否在监听

```bash
# 在宿主机上检查端口监听
sudo netstat -tlnp | grep 8080
# 或
sudo ss -tlnp | grep 8080

# 检查 HTTP 服务器是否可访问
curl -I http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img
```

## 常见问题

### 问题 1: Pod 无法访问宿主机 IP

**原因**：
- k3s 使用 Flannel CNI，Pod 网络和宿主机网络隔离
- 防火墙阻止了连接
- HTTP 服务器只监听 localhost

**解决**：
```bash
# 1. 确保 HTTP 服务器监听所有接口（0.0.0.0），而不是只监听 localhost
# 例如，使用 Python HTTP 服务器：
python3 -m http.server 8080 --bind 0.0.0.0

# 2. 检查并配置防火墙
sudo ufw allow from 10.42.0.0/16 to any port 8080  # k3s 默认 Pod 网段

# 3. 或者使用 NodePort Service 暴露服务
```

### 问题 2: 如何获取虚拟机 IP 地址

```bash
# 方法 1: 使用 hostname
hostname -I | awk '{print $1}'

# 方法 2: 使用 ip 命令
ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1

# 方法 3: 查看 k3s 节点信息
kubectl get nodes -o wide
```

### 问题 3: 如何确认 Pod 网络网段

```bash
# 查看 k3s 网络配置
sudo cat /var/lib/rancher/k3s/agent/etc/flannel/net-conf.json

# 或查看 Pod IP 范围
kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}'
```

## 完整示例

### 1. 在宿主机上启动 HTTP 服务器

```bash
# 创建镜像目录
mkdir -p ~/images
cd ~/images

# 下载或复制镜像文件
# wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# 启动 HTTP 服务器（监听所有接口）
python3 -m http.server 8080 --bind 0.0.0.0
```

### 2. 获取虚拟机 IP

```bash
VM_IP=$(hostname -I | awk '{print $1}')
echo "虚拟机 IP: $VM_IP"
```

### 3. 配置 Wukong YAML

```yaml
apiVersion: vm.novasphere.dev/v1alpha1
kind: Wukong
metadata:
  name: ubuntu-noble-local
spec:
  cpu: 1
  memory: 1Gi
  disks:
    - name: system
      size: 5Gi
      storageClassName: local-path
      boot: true
      image: "http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img"  # 替换为实际 IP
  startStrategy:
    autoStart: true
```

### 4. 测试连接

```bash
# 在 Pod 中测试
kubectl run -it --rm test-curl --image=curlimages/curl --restart=Never -- \
  curl -I http://192.168.1.141:8080/images/noble-server-cloudimg-amd64.img

# 如果成功，应该看到 HTTP 200 响应
```

### 5. 应用配置

```bash
kubectl apply -f config/samples/vm_v1alpha1_wukong_ubuntu_noble_local.yaml
```

## 总结

在 k3s 环境中：
- ✅ **使用实际 IP 地址**：`http://192.168.1.141:8080/...`
- ❌ **不要使用** `host.docker.internal`（Docker Desktop 特性）
- ✅ **确保 HTTP 服务器监听** `0.0.0.0`，而不是 `127.0.0.1`
- ✅ **检查防火墙**：允许 Pod 网络访问宿主机端口
- ✅ **测试连接**：使用 `kubectl run` 在 Pod 中测试访问


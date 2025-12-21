# 访问 Longhorn UI

## 从宿主机访问

### 方法 1: 绑定到宿主机 IP（推荐）

```bash
# 使用宿主机 IP
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8080:80
```

然后通过浏览器访问: `http://192.168.1.141:8080`

### 方法 2: 绑定到所有接口

```bash
# 使用 0.0.0.0（可以从任何 IP 访问）
kubectl port-forward -n longhorn-system svc/longhorn-frontend --address 0.0.0.0 8088:80
```

然后可以通过以下地址访问:
- `http://localhost:8080`
- `http://127.0.0.1:8080`
- `http://192.168.1.141:8080`

### 方法 3: 使用脚本

```bash
# 绑定到宿主机 IP
./scripts/access-longhorn-ui.sh 192.168.1.141 8080

# 或绑定到所有接口
./scripts/access-longhorn-ui.sh 0.0.0.0 8080
```

## 命令说明

### 基本格式

```bash
kubectl port-forward -n <namespace> svc/<service-name> [local-ip:]local-port:remote-port
```

### 参数说明

- `-n longhorn-system`: 命名空间
- `svc/longhorn-frontend`: Service 名称
- `192.168.1.141:8080:80`: 
  - `192.168.1.141`: 本地绑定 IP（宿主机 IP）
  - `8080`: 本地端口
  - `80`: Service 端口

### 使用 --address 参数（kubectl 1.23+）

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend --address 0.0.0.0 8080:80
```

## 后台运行

如果需要后台运行：

```bash
# 后台运行
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8080:80 > /dev/null 2>&1 &

# 查看进程
ps aux | grep port-forward

# 停止
pkill -f "port-forward.*longhorn-frontend"
```

## 访问 Longhorn UI

### 1. 启动 port-forward

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8080:80
```

### 2. 在浏览器中访问

打开浏览器，访问: `http://192.168.1.141:8080`

### 3. 在 UI 中配置

- **Nodes**: 查看和配置节点
- **Disks**: 配置磁盘路径（修复磁盘配置不一致问题）
- **Volumes**: 查看和管理卷
- **Settings**: 配置 Longhorn 设置（如副本数）

## 修复磁盘配置不一致

在 Longhorn UI 中：

1. 进入 **Nodes** → 选择节点
2. 进入 **Disks** 标签
3. 点击 **Add Disk** 或编辑现有磁盘
4. 配置磁盘路径: `/var/lib/longhorn`
5. 保存配置

## 常见问题

### 问题 1: 端口被占用

```bash
# 检查端口
lsof -i :8080
# 或
netstat -an | grep 8080

# 使用其他端口
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8081:80
```

### 问题 2: 无法访问

- 检查防火墙规则
- 检查 kubectl 是否正常运行
- 检查 Service 是否存在: `kubectl get svc -n longhorn-system longhorn-frontend`

### 问题 3: 连接被拒绝

- 检查 Longhorn UI Pod 是否运行: `kubectl get pods -n longhorn-system -l app=longhorn-ui`
- 检查 Service: `kubectl describe svc -n longhorn-system longhorn-frontend`

## 快速命令

```bash
# 绑定到宿主机 IP
kubectl port-forward -n longhorn-system svc/longhorn-frontend 192.168.1.141:8080:80

# 或使用脚本
./scripts/access-longhorn-ui.sh 192.168.1.141 8080
```

## 总结

| 方法 | 命令 | 访问地址 |
|------|------|---------|
| 绑定宿主机 IP | `kubectl port-forward ... 192.168.1.141:8080:80` | `http://192.168.1.141:8080` |
| 绑定所有接口 | `kubectl port-forward ... --address 0.0.0.0 8080:80` | `http://192.168.1.141:8080` 或 `http://localhost:8080` |
| 使用脚本 | `./scripts/access-longhorn-ui.sh 192.168.1.141 8080` | `http://192.168.1.141:8080` |


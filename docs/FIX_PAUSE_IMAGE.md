# 修复 pause 镜像问题

## 问题

系统已有 pause 镜像，但名称不匹配：
- k3s 需要: `rancher/mirrored-pause:3.6`
- 系统有: `registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6`

## 解决方案

### 方案 1: 使用 ctr tag 镜像（推荐）

```bash
# 使用 ctr 给现有镜像打标签
sudo ctr -n k8s.io images tag \
  registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 \
  rancher/mirrored-pause:3.6

# 验证
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl images | grep pause

# 删除 Pod 重新创建
kubectl delete pod -n kubevirt -l app=virt-operator
kubectl get pods -n kubevirt -w
```

### 方案 2: 配置 k3s 使用系统默认镜像

编辑 k3s 配置，让它使用系统已有的 pause 镜像：

```bash
# 编辑 k3s 服务配置
sudo systemctl edit k3s

# 添加以下内容（如果 k3s 支持）：
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s server --system-default-registry=registry.cn-hangzhou.aliyuncs.com

# 重启 k3s
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

### 方案 3: 直接删除 Pod 让 k3s 重新尝试

有时 k3s 会自动使用系统已有的镜像：

```bash
# 删除 Pod
kubectl delete pod -n kubevirt -l app=virt-operator

# 观察重新创建
kubectl get pods -n kubevirt -w

# 如果还是失败，查看事件
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10
```

## 快速修复

运行修复脚本：
```bash
./scripts/fix-pause-image.sh
```

## 验证

修复后验证：

```bash
# 1. 检查镜像
export CRICTL_CONFIG=~/.config/crictl/crictl.yaml
crictl images | grep pause

# 2. 检查 Pod 状态
kubectl get pods -n kubevirt

# 3. 检查事件（应该没有镜像拉取错误）
kubectl get events -n kubevirt --sort-by='.lastTimestamp' | tail -10
```


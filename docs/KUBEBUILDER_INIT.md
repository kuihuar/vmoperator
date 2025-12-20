# kubebuilder init 参数说明

## 参数详解

### 1. `--domain` 参数

**作用**: 定义 API 组的域名，用于生成 CRD 的 API 组名

**格式**: 域名格式（如 `example.com`）

**影响**:
- 生成的 CRD 的 `apiVersion` 会是 `group.domain/version`
- 例如：`--domain=example.com` + `--group=vm` + `--version=v1alpha1`
- 最终 API 版本为：`vm.example.com/v1alpha1`

**选择建议**:
- **公司/组织域名**: 如果有自己的域名，使用它（如 `yourcompany.com`）
- **GitHub 域名**: 如果项目在 GitHub，可以使用 `github.com`（但通常不推荐）
- **示例域名**: 开发测试时可以使用 `example.com` 或 `local.dev`

**示例**:
```bash
# 使用公司域名
--domain=mycompany.com

# 使用示例域名（开发测试）
--domain=example.com

# 使用本地开发域名
--domain=local.dev
```

---

### 2. `--repo` 参数

**作用**: 定义 Go 模块的路径，对应 `go.mod` 中的 `module` 声明

**格式**: Go 模块路径格式（如 `github.com/user/repo`）

**影响**:
- 设置 `go.mod` 文件中的 `module` 声明
- 影响所有 Go 代码的导入路径
- 应该与实际的代码仓库路径一致

**选择建议**:
- **GitHub 仓库**: `github.com/your-username/vmoperator`
- **GitLab 仓库**: `gitlab.com/your-group/vmoperator`
- **私有仓库**: `git.company.com/team/vmoperator`
- **本地开发**: 可以使用任意路径，但建议与未来仓库路径一致

**示例**:
```bash
# GitHub 公开仓库
--repo=github.com/jianfenliu/vmoperator

# GitHub 组织仓库
--repo=github.com/myorg/vmoperator

# GitLab 仓库
--repo=gitlab.com/mygroup/vmoperator

# 私有 Git 服务器
--repo=git.company.com/platform/vmoperator
```

---

## 实际使用示例

### 场景 1: 个人 GitHub 项目

```bash
kubebuilder init \
  --domain=example.com \
  --repo=github.com/jianfenliu/vmoperator
```

**结果**:
- API 版本: `vm.example.com/v1alpha1`
- Go 模块: `module github.com/jianfenliu/vmoperator`
- CRD 名称: `virtualmachineprofiles.vm.example.com`

---

### 场景 2: 公司内部项目

```bash
kubebuilder init \
  --domain=mycompany.com \
  --repo=git.mycompany.com/platform/vmoperator
```

**结果**:
- API 版本: `vm.mycompany.com/v1alpha1`
- Go 模块: `module git.mycompany.com/platform/vmoperator`
- CRD 名称: `virtualmachineprofiles.vm.mycompany.com`

---

### 场景 3: 本地开发（未确定仓库）

```bash
kubebuilder init \
  --domain=local.dev \
  --repo=github.com/your-org/vmoperator
```

**说明**: 即使暂时不上传到 GitHub，也可以先使用预期的路径，后续可以修改。

---

## 参数关系

```
--domain=example.com
    │
    └─→ 用于生成 API 组名
        └─→ vm.example.com/v1alpha1

--repo=github.com/your-org/vmoperator
    │
    └─→ 用于生成 go.mod
        └─→ module github.com/your-org/vmoperator
```

---

## 如何选择参数

### 1. 确定 `--domain`

**问题**: 我应该使用什么域名？

**答案**:
- ✅ **有公司域名**: 使用公司域名（如 `mycompany.com`）
- ✅ **开源项目**: 可以使用 `example.com` 或项目相关的域名
- ✅ **内部项目**: 使用内部域名或 `local.dev`
- ❌ **避免**: 使用 `github.com`（不符合域名规范）

**示例**:
```bash
# 推荐
--domain=example.com          # 通用示例
--domain=vmoperator.dev       # 项目专用域名（如果拥有）
--domain=mycompany.com        # 公司域名

# 不推荐
--domain=github.com           # 不符合规范
```

---

### 2. 确定 `--repo`

**问题**: 我应该使用什么仓库路径？

**答案**:
- ✅ **已确定仓库**: 使用实际仓库路径
- ✅ **GitHub**: `github.com/username/vmoperator`
- ✅ **GitLab**: `gitlab.com/group/vmoperator`
- ✅ **私有仓库**: 使用私有 Git 服务器路径
- ⚠️ **未确定**: 可以先使用预期路径，后续可修改

**注意**: 
- 这个路径会写入 `go.mod`，后续修改需要更新所有导入
- 建议一开始就使用正确的路径

---

## 推荐配置（针对本项目）

基于当前项目路径 `/Users/jianfenliu/Workspace/vmoperator`，推荐配置：

### 选项 1: 使用示例域名（开发阶段）

```bash
kubebuilder init \
  --domain=example.com \
  --repo=github.com/jianfenliu/vmoperator
```

**适用场景**: 
- 开发测试阶段
- 尚未确定最终仓库位置
- 快速原型开发

---

### 选项 2: 使用项目专用域名（如果有）

```bash
kubebuilder init \
  --domain=vmoperator.dev \
  --repo=github.com/jianfenliu/vmoperator
```

**适用场景**:
- 拥有 `vmoperator.dev` 域名
- 正式项目

---

### 选项 3: 使用公司域名

```bash
kubebuilder init \
  --domain=mycompany.com \
  --repo=git.mycompany.com/platform/vmoperator
```

**适用场景**:
- 公司内部项目
- 有公司域名

---

## 参数修改

如果初始化后需要修改参数：

### 修改 domain

1. 修改 `api/v1alpha1/groupversion_info.go` 中的 `GroupName`
2. 重新生成 CRD: `make manifests`

### 修改 repo

1. 修改 `go.mod` 中的 `module` 声明
2. 更新所有导入路径（可以使用 `find` + `sed` 批量替换）
3. 运行 `go mod tidy`

**注意**: 修改 repo 比较麻烦，建议初始化时就使用正确的路径。

---

## 完整初始化命令示例

```bash
# 进入项目目录
cd /Users/jianfenliu/Workspace/vmoperator

# 初始化项目（使用推荐配置）
kubebuilder init \
  --domain=example.com \
  --repo=github.com/jianfenliu/vmoperator

# 创建 API
kubebuilder create api \
  --group=vm \
  --version=v1alpha1 \
  --kind=VirtualMachineProfile
# 选择: Y (创建 Resource) 和 Y (创建 Controller)
```

---

## 验证参数设置

初始化后，可以验证参数是否正确：

```bash
# 1. 检查 go.mod
cat go.mod
# 应该看到: module github.com/jianfenliu/vmoperator

# 2. 检查 API 组
cat api/v1alpha1/groupversion_info.go
# 应该看到: GroupName = "vm.example.com"

# 3. 检查 CRD（生成后）
kubectl get crd virtualmachineprofiles.vm.example.com -o yaml
# 应该看到: apiVersion: vm.example.com/v1alpha1
```

---

## 常见问题

### Q1: domain 和 repo 可以相同吗？

**A**: 可以，但不推荐。它们有不同的用途：
- `domain`: 用于 API 组名（如 `vm.example.com`）
- `repo`: 用于 Go 模块路径（如 `github.com/user/repo`）

### Q2: 如果后续要修改怎么办？

**A**: 
- 修改 `domain`: 相对容易，只需修改 `groupversion_info.go` 并重新生成
- 修改 `repo`: 较麻烦，需要修改 `go.mod` 和所有导入路径

### Q3: 可以使用中文或特殊字符吗？

**A**: 
- `domain`: 必须符合域名规范（字母、数字、点、连字符）
- `repo`: 必须符合 Go 模块路径规范（通常与 Git 仓库路径一致）

---

**提示**: 如果不确定，建议使用 `example.com` 作为 domain，使用预期的 GitHub 路径作为 repo。


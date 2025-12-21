# 磁盘容量规划指南

## 系统盘容量规划

### 基础建议

| 操作系统 | 最小容量 | 推荐容量 | 说明 |
|---------|---------|---------|------|
| Ubuntu/Debian | 10Gi | 20-30Gi | 基础系统 + 常用软件 |
| CentOS/RHEL | 15Gi | 25-40Gi | 系统较大，需要更多空间 |
| Windows Server | 40Gi | 60-100Gi | Windows 系统占用较大 |

### 详细建议

#### 开发/测试环境

```yaml
disks:
  - name: system
    size: 20Gi    # 足够安装系统和常用开发工具
    storageClassName: longhorn
    boot: true
```

**包含内容**:
- 操作系统: ~5-8Gi
- 系统软件: ~2-3Gi
- 开发工具: ~3-5Gi
- 日志和临时文件: ~2-4Gi
- 预留空间: ~20%

#### 生产环境

```yaml
disks:
  - name: system
    size: 30-50Gi  # 根据实际需求调整
    storageClassName: longhorn
    boot: true
```

**包含内容**:
- 操作系统: ~8-12Gi
- 系统软件和服务: ~5-10Gi
- 应用软件: ~5-15Gi
- 日志文件: ~5-10Gi
- 预留空间: ~30%

#### 容器化环境

```yaml
disks:
  - name: system
    size: 25Gi    # 容器镜像和运行时
    storageClassName: longhorn
    boot: true
```

**包含内容**:
- 操作系统: ~8Gi
- 容器运行时: ~5Gi
- 容器镜像: ~5-10Gi
- 日志: ~2-5Gi

## 数据盘容量规划

### 基础建议

| 应用类型 | 推荐容量 | 说明 |
|---------|---------|------|
| Web 应用 | 50-200Gi | 静态文件、上传文件 |
| 数据库 | 100-500Gi | 根据数据量规划 |
| 日志存储 | 50-500Gi | 根据日志保留策略 |
| 文件存储 | 100Gi-2Ti | 根据文件量规划 |
| 开发环境 | 20-50Gi | 测试数据 |

### 详细建议

#### Web 应用服务器

```yaml
disks:
  - name: system
    size: 30Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 100Gi    # Web 文件、上传文件
    storageClassName: longhorn
    boot: false
  - name: logs
    size: 50Gi     # 应用日志
    storageClassName: longhorn
    boot: false
```

#### 数据库服务器

```yaml
disks:
  - name: system
    size: 40Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 200Gi    # 数据库数据文件
    storageClassName: longhorn
    boot: false
  - name: backup
    size: 500Gi    # 数据库备份
    storageClassName: longhorn
    boot: false
```

#### 应用服务器

```yaml
disks:
  - name: system
    size: 30Gi
    storageClassName: longhorn
    boot: true
  - name: app-data
    size: 100Gi    # 应用数据
    storageClassName: longhorn
    boot: false
  - name: cache
    size: 50Gi     # 缓存数据（可选，可以使用内存）
    storageClassName: longhorn
    boot: false
```

## 容量规划考虑因素

### 1. 操作系统类型

- **Linux 轻量发行版** (Alpine, Ubuntu Minimal): 5-10Gi
- **Linux 标准发行版** (Ubuntu, CentOS): 15-30Gi
- **Linux 完整发行版** (带 GUI): 30-50Gi
- **Windows Server**: 60-100Gi

### 2. 应用类型

- **静态 Web 服务器**: 20-50Gi 系统盘 + 50-200Gi 数据盘
- **动态 Web 应用**: 30Gi 系统盘 + 100-500Gi 数据盘
- **数据库服务器**: 40Gi 系统盘 + 200Gi-2Ti 数据盘
- **文件服务器**: 30Gi 系统盘 + 500Gi-10Ti 数据盘
- **开发环境**: 20Gi 系统盘 + 20-50Gi 数据盘

### 3. 数据增长

考虑数据增长，预留 20-30% 空间：

```yaml
disks:
  - name: data
    size: 150Gi    # 实际需要 100Gi，预留 50Gi
    storageClassName: longhorn
    boot: false
```

### 4. 日志和临时文件

系统盘需要为日志和临时文件预留空间：

```yaml
disks:
  - name: system
    size: 30Gi     # 系统 20Gi + 日志 10Gi
    storageClassName: longhorn
    boot: true
```

## 实际示例

### 示例 1: 小型 Web 应用

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn
    boot: true
  - name: web-data
    size: 50Gi
    storageClassName: longhorn
    boot: false
```

### 示例 2: 中型应用服务器

```yaml
disks:
  - name: system
    size: 30Gi
    storageClassName: longhorn
    boot: true
  - name: app-data
    size: 100Gi
    storageClassName: longhorn
    boot: false
  - name: logs
    size: 50Gi
    storageClassName: longhorn
    boot: false
```

### 示例 3: 数据库服务器

```yaml
disks:
  - name: system
    size: 40Gi
    storageClassName: longhorn
    boot: true
  - name: database
    size: 500Gi
    storageClassName: longhorn
    boot: false
  - name: backup
    size: 1Ti
    storageClassName: longhorn
    boot: false
```

### 示例 4: 开发/测试环境

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 30Gi
    storageClassName: longhorn
    boot: false
```

## 容量扩展策略

### 初始容量

建议初始容量略大于当前需求：

```yaml
disks:
  - name: data
    size: 120Gi    # 当前需要 80Gi，预留 40Gi
    storageClassName: longhorn
    boot: false
```

### 扩展计划

由于 Longhorn 支持卷扩展，可以：
1. 初始设置较小容量
2. 根据实际使用情况扩展
3. 使用监控工具跟踪使用率

```bash
# 扩展数据盘
./scripts/expand-disk.sh <wukong-name> data 200Gi
```

## 监控和告警

### 监控磁盘使用

```bash
# 在 VM 内部
df -h
du -sh /home/*

# 在 Kubernetes 中
kubectl get pvc
kubectl describe pvc <pvc-name>
```

### 设置告警阈值

建议设置告警：
- **警告**: 使用率 > 80%
- **严重**: 使用率 > 90%

## 最佳实践

### 1. 系统盘和数据盘分离

```yaml
disks:
  - name: system
    size: 30Gi    # 系统盘，相对固定
    storageClassName: longhorn
    boot: true
  - name: data
    size: 100Gi   # 数据盘，易于扩展
    storageClassName: longhorn
    boot: false
```

**优势**:
- 系统盘可以快速重建
- 数据盘可以独立扩展和管理
- 便于备份和迁移

### 2. 预留空间

```yaml
disks:
  - name: data
    size: 150Gi   # 实际需要 100Gi，预留 50Gi (33%)
    storageClassName: longhorn
    boot: false
```

### 3. 根据应用规划

- **Web 应用**: 系统盘 20-30Gi，数据盘 50-200Gi
- **数据库**: 系统盘 30-40Gi，数据盘 200Gi-2Ti
- **文件存储**: 系统盘 20-30Gi，数据盘 500Gi-10Ti
- **开发环境**: 系统盘 20Gi，数据盘 20-50Gi

### 4. 考虑扩展性

由于 Longhorn 支持卷扩展，可以：
- 初始设置较小容量
- 根据实际使用情况扩展
- 避免过度分配

## 容量计算公式

### 系统盘

```
系统盘容量 = 操作系统大小 + 系统软件 + 应用软件 + 日志空间 + 预留空间(20-30%)
```

**示例**:
```
系统盘 = 8Gi (OS) + 5Gi (软件) + 5Gi (应用) + 5Gi (日志) + 7Gi (预留) = 30Gi
```

### 数据盘

```
数据盘容量 = 当前数据量 + 预期增长 + 预留空间(20-30%)
```

**示例**:
```
数据盘 = 50Gi (当前) + 30Gi (增长) + 20Gi (预留) = 100Gi
```

## 总结

| 场景 | 系统盘 | 数据盘 | 说明 |
|------|--------|--------|------|
| 开发/测试 | 20Gi | 20-50Gi | 最小配置 |
| 小型应用 | 20-30Gi | 50-100Gi | Web 应用、小型服务 |
| 中型应用 | 30-40Gi | 100-200Gi | 标准应用服务器 |
| 大型应用 | 40-50Gi | 200-500Gi | 数据库、大型服务 |
| 文件存储 | 30Gi | 500Gi-10Ti | 根据文件量规划 |

**关键点**:
- ✅ 系统盘: 20-50Gi（根据操作系统和应用）
- ✅ 数据盘: 根据实际需求，预留 20-30% 空间
- ✅ 系统盘和数据盘分离，便于管理
- ✅ Longhorn 支持扩展，可以从小容量开始

## 推荐配置

### 通用配置（推荐）

```yaml
disks:
  - name: system
    size: 30Gi      # 适合大多数 Linux 系统
    storageClassName: longhorn
    boot: true
  - name: data
    size: 100Gi     # 根据实际需求调整
    storageClassName: longhorn
    boot: false
```

### 最小配置（开发测试）

```yaml
disks:
  - name: system
    size: 20Gi
    storageClassName: longhorn
    boot: true
  - name: data
    size: 30Gi
    storageClassName: longhorn
    boot: false
```

### 生产配置（推荐）

```yaml
disks:
  - name: system
    size: 40Gi      # 预留更多空间
    storageClassName: longhorn
    boot: true
  - name: data
    size: 200Gi     # 根据应用需求
    storageClassName: longhorn
    boot: false
```


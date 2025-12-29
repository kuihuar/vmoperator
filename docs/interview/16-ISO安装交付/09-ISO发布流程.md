# ISO 发布流程

## 1. 构建流程

```
准备阶段
    ↓
下载 Ubuntu ISO
    ↓
定制文件系统
    ↓
打包应用文件
    ↓
制作 ISO
    ↓
验证 ISO
    ↓
发布 ISO
```

## 2. 构建脚本

```bash
#!/bin/bash
# scripts/build-iso.sh

set -e

VERSION=${1:-$(date +%Y%m%d)}
UBUNTU_ISO="ubuntu-22.04.3-live-server-amd64.iso"
OUTPUT_ISO="novasphere-installer-${VERSION}.iso"
BUILD_DIR="iso-build"

echo "开始构建 ISO v${VERSION}..."

# 1. 创建工作目录
mkdir -p ${BUILD_DIR}/{mount,extract,novasphere}

# 2. 准备应用文件
echo "准备应用文件..."
cp -r charts/ ${BUILD_DIR}/novasphere/
cp -r scripts/ ${BUILD_DIR}/novasphere/
cp -r configs/ ${BUILD_DIR}/novasphere/
cp -r packages/ ${BUILD_DIR}/novasphere/

# 3. 提取 Ubuntu ISO
echo "提取 Ubuntu ISO..."
sudo mount -o loop ${UBUNTU_ISO} ${BUILD_DIR}/mount/
cp -r ${BUILD_DIR}/mount/* ${BUILD_DIR}/extract/
sudo umount ${BUILD_DIR}/mount/

# 4. 定制文件系统
echo "定制文件系统..."
./scripts/customize-filesystem.sh ${BUILD_DIR}/extract

# 5. 复制应用文件到 ISO
echo "复制应用文件..."
sudo cp -r ${BUILD_DIR}/novasphere ${BUILD_DIR}/extract/

# 6. 制作 ISO
echo "制作 ISO..."
./scripts/create-iso.sh ${BUILD_DIR}/extract ${OUTPUT_ISO}

# 7. 验证 ISO
echo "验证 ISO..."
./scripts/verify-iso.sh ${OUTPUT_ISO}

echo "ISO 构建完成: ${OUTPUT_ISO}"
```

## 3. CI/CD 集成

### 3.1 GitHub Actions
```yaml
name: Build ISO

on:
  release:
    types: [created]
  workflow_dispatch:

jobs:
  build-iso:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            squashfs-tools \
            genisoimage \
            xorriso \
            isolinux \
            syslinux-utils
      
      - name: Download Ubuntu ISO
        run: |
          wget https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso
      
      - name: Build ISO
        run: |
          ./scripts/build-iso.sh ${GITHUB_REF#refs/tags/v}
      
      - name: Upload ISO
        uses: actions/upload-artifact@v3
        with:
          name: novasphere-installer
          path: novasphere-installer-*.iso
      
      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            novasphere-installer-*.iso
          draft: false
          prerelease: false
```

## 4. 版本管理

### 4.1 版本号规则
- 格式: `YYYYMMDD` 或语义化版本
- 示例: `20240101` 或 `v1.0.0`

### 4.2 版本信息
ISO 中包含版本信息文件：
```
/opt/novasphere/VERSION
```

## 5. 发布检查清单

- [ ] ISO 构建成功
- [ ] ISO 验证通过
- [ ] 功能测试通过
- [ ] 文档更新
- [ ] 版本号更新
- [ ] 发布说明准备

## 6. 发布流程

### 6.1 本地构建
```bash
./scripts/build-iso.sh v1.0.0
```

### 6.2 测试验证
```bash
# 在虚拟机中测试
qemu-system-x86_64 -cdrom novasphere-installer-v1.0.0.iso
```

### 6.3 发布
```bash
# 上传到发布服务器
scp novasphere-installer-v1.0.0.iso user@server:/releases/

# 或创建 GitHub Release
gh release create v1.0.0 novasphere-installer-v1.0.0.iso
```

## 7. 文档更新

发布时更新：
- 安装文档
- 版本说明
- 已知问题
- 升级指南

## 8. 注意事项

- 确保 ISO 完整性（MD5 校验）
- 测试所有功能
- 记录已知问题
- 提供回滚方案


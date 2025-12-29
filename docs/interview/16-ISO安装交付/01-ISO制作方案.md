# ISO 制作方案

## 1. 概述

使用 Ubuntu 官方 ISO 作为基础，定制化制作包含 Novasphere 应用栈的安装 ISO。

## 2. 制作工具

### 2.1 推荐工具

#### Cubic (Custom Ubuntu ISO Creator)
- **官网**: https://launchpad.net/cubic
- **特点**: 图形化界面，易于使用
- **适用**: 快速定制

#### mkisofs/genisoimage
- **特点**: 命令行工具，灵活
- **适用**: 自动化构建

#### Ubuntu Customization Kit (UCK)
- **特点**: 官方工具
- **适用**: 深度定制

### 2.2 选择建议

**开发阶段**: 使用 Cubic（图形化，便于调试）
**生产阶段**: 使用 mkisofs（命令行，适合 CI/CD）

## 3. 制作流程

### 3.1 准备阶段

```bash
# 1. 下载 Ubuntu ISO
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso

# 2. 创建工作目录
mkdir -p iso-build/{mount,extract,novasphere}
cd iso-build

# 3. 挂载 ISO
sudo mount -o loop ubuntu-22.04.3-live-server-amd64.iso mount/

# 4. 提取文件
cp -r mount/* extract/
cp -r mount/.disk extract/
```

### 3.2 定制阶段

```bash
# 1. 挂载文件系统
sudo mount -o loop extract/casper/filesystem.squashfs /mnt

# 2. 复制文件到 chroot
sudo cp -r novasphere/* /mnt/opt/novasphere/

# 3. 配置 chroot 环境
sudo chroot /mnt

# 4. 安装依赖
apt-get update
apt-get install -y k3s kubectl helm

# 5. 退出 chroot
exit

# 6. 卸载文件系统
sudo umount /mnt
```

### 3.3 打包阶段

```bash
# 1. 重新打包文件系统
sudo mksquashfs /mnt extract/casper/filesystem.squashfs

# 2. 更新 manifest
sudo chmod +w extract/casper/filesystem.manifest
sudo chroot /mnt dpkg-query -W --showformat='${Package} ${Version}\n' > extract/casper/filesystem.manifest
sudo chmod -w extract/casper/filesystem.manifest

# 3. 更新文件大小
sudo du -sx --block-size=1 /mnt | cut -f1 > extract/casper/filesystem.size

# 4. 生成 MD5
cd extract
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
cd ..

# 5. 制作 ISO
sudo mkisofs -D -r -V "Novasphere Installer" \
  -cache-inodes -J -l \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -o ../novasphere-installer.iso \
  extract/
```

## 4. 自动化脚本

### 4.1 构建脚本
```bash
#!/bin/bash
# scripts/build-iso.sh

set -e

UBUNTU_ISO="ubuntu-22.04.3-live-server-amd64.iso"
OUTPUT_ISO="novasphere-installer-$(date +%Y%m%d).iso"
BUILD_DIR="iso-build"

echo "开始制作 ISO..."

# 创建工作目录
mkdir -p ${BUILD_DIR}/{mount,extract,novasphere}

# 复制应用文件
cp -r charts/ ${BUILD_DIR}/novasphere/
cp -r scripts/ ${BUILD_DIR}/novasphere/
cp -r configs/ ${BUILD_DIR}/novasphere/

# 提取 ISO
echo "提取 Ubuntu ISO..."
sudo mount -o loop ${UBUNTU_ISO} ${BUILD_DIR}/mount/
cp -r ${BUILD_DIR}/mount/* ${BUILD_DIR}/extract/
sudo umount ${BUILD_DIR}/mount/

# 定制文件系统
echo "定制文件系统..."
./scripts/customize-filesystem.sh ${BUILD_DIR}

# 打包 ISO
echo "打包 ISO..."
./scripts/create-iso.sh ${BUILD_DIR} ${OUTPUT_ISO}

echo "ISO 制作完成: ${OUTPUT_ISO}"
```

## 5. ISO 结构设计

```
novasphere-installer.iso
├── boot/
│   ├── grub/
│   └── efi.img
├── casper/
│   ├── filesystem.squashfs    # 定制文件系统
│   ├── filesystem.manifest     # 包清单
│   └── filesystem.size         # 文件系统大小
├── preseed/
│   └── novasphere.seed         # 自动安装配置
├── novasphere/                 # 应用文件
│   ├── scripts/
│   │   ├── install.sh         # 主安装脚本
│   │   ├── install-k3s.sh
│   │   ├── install-kubevirt.sh
│   │   └── install-novasphere.sh
│   ├── configs/
│   │   ├── k3s-config.yaml
│   │   ├── longhorn-values.yaml
│   │   └── novasphere-values.yaml
│   ├── packages/               # 离线包
│   │   ├── k3s.deb
│   │   └── helm.deb
│   └── charts/                # Helm Charts
│       ├── longhorn/
│       ├── kubevirt/
│       └── novasphere/
├── isolinux/
│   ├── isolinux.bin
│   └── boot.cat
└── md5sum.txt
```

## 6. 引导配置

### 6.1 GRUB 配置
```grub
menuentry "Install Novasphere" {
    set gfxpayload=keep
    linux   /casper/vmlinuz quiet autoinstall ds=nocloud-net\;s=file:///novasphere/preseed/
    initrd  /casper/initrd
}
```

### 6.2 Preseed 配置
```bash
# preseed/novasphere.seed
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string novasphere
d-i netcfg/get_domain string local
d-i mirror/country string manual
d-i mirror/http/hostname string archive.ubuntu.com
d-i mirror/http/directory string /ubuntu
d-i mirror/http/proxy string
d-i time/zone string UTC
d-i clock-setup/utc boolean true
d-i partman-auto/method string lvm
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i passwd/user-fullname string Novasphere Admin
d-i passwd/username string admin
d-i passwd/user-password password novasphere
d-i passwd/user-password-again password novasphere
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false
d-i apt-setup/restricted boolean true
d-i apt-setup/universe boolean true
d-i pkgsel/update-policy select none
d-i pkgsel/upgrade select none
d-i finish-install/reboot_in_progress note
```

## 7. 自动化安装脚本

### 7.1 安装后脚本
```bash
#!/bin/bash
# scripts/install.sh

# 在系统安装完成后自动执行
# 位置: /opt/novasphere/scripts/install.sh

set -e

echo "开始安装 Novasphere 应用栈..."

# 1. 安装 k3s
/opt/novasphere/scripts/install-k3s.sh

# 2. 安装 KubeVirt
/opt/novasphere/scripts/install-kubevirt.sh

# 3. 安装 Longhorn
/opt/novasphere/scripts/install-longhorn.sh

# 4. 安装 Novasphere Operator
/opt/novasphere/scripts/install-novasphere.sh

echo "安装完成！"
```

## 8. 制作环境要求

### 8.1 系统要求
- Ubuntu 22.04+ (推荐)
- 至少 20GB 可用空间
- root 权限

### 8.2 依赖工具
```bash
sudo apt-get install -y \
  squashfs-tools \
  genisoimage \
  xorriso \
  isolinux \
  syslinux-utils
```

## 9. 优化建议

### 9.1 减小 ISO 大小
- 移除不必要的语言包
- 压缩应用文件
- 使用最小化 Ubuntu 镜像

### 9.2 加快安装速度
- 预安装常用包
- 优化文件系统压缩
- 使用本地镜像源

## 10. CI/CD 集成

### 10.1 GitHub Actions
```yaml
name: Build ISO

on:
  release:
    types: [created]

jobs:
  build-iso:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      - name: Build ISO
        run: |
          ./scripts/build-iso.sh
      - name: Upload ISO
        uses: actions/upload-artifact@v3
        with:
          name: novasphere-installer
          path: novasphere-installer-*.iso
```


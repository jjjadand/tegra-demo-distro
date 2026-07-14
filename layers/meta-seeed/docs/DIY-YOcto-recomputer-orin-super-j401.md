# 在 Yocto/OE4T 中 DIY reComputer Jetson BSP

本文以 **Seeed reComputer Super J401 + Jetson Orin NX 16GB** 为完整示例，说明如何把一个基于 NVIDIA Linux for Tegra（L4T）的第三方载板 BSP，移植到 Yocto/OE4T 的 `meta-tegra` 构建体系中。

本文不仅给出最终文件，还解释每类 BSP 文件属于启动链的哪一层、如何从厂商 L4T BSP 提取信息、如何验证生成物，以及如何定位构建和刷写问题。其他 reComputer 或自定义 Jetson 载板可以沿用相同流程。

本示例已经完成以下实机验证：

- Yocto `demo-image-full` 构建成功；
- 自定义 DTB、BPMP DTB、pinmux、pad voltage 和 camera overlay 进入刷写包；
- NVMe A/B rootfs、kernel、DTB 和 ESP 写入成功；
- `initrd-flash` 最终返回 `Final status: SUCCESS`；
- HDMI、USB 等基础外设可用；
- 系统进入 OE4T/Yocto Sato 图形桌面。

> 本文示例基于 `meta-tegra` 的 `wrynose` 分支、L4T R39.2.0 / JetPack 7.2。移植其他版本时，必须使用与目标 L4T 版本匹配的 OE4T 分支和 NVIDIA BSP 文件。

> **验证范围说明：** 目前只有 reComputer Super J401 搭配 Jetson Orin NX 16GB（P3767-0000）完成了构建、刷写和启动实机验证。其他 Seeed reComputer/第三方载板可以复用本文的方法论和 layer 组织方式，但不能直接认为同一 machine、DTB 或刷写包一定可用。每款载板和每种 module SKU 都必须重新核对并验证 DTB、BCT、BPMP DTB、ODMDATA/UPHY、存储布局以及厂商 kernel/OOT 驱动差异。

本地 `Linux_for_Tegra` 中其他 Seeed 板卡的源文件盘点和当前 Yocto 支持状态见：

```text
layers/meta-seeed/docs/board-support-status.md
```

也可以生成详细的 L4T 配置清单：

```bash
./scripts/seeed/discover-l4t-boards.sh \
  --l4t-dir ../Linux_for_Tegra \
  > /tmp/seeed-l4t-board-inventory.md
```

## 0. 准备一个可复现、可分发的工作目录

### 0.1 不要打包已经编译过的工作目录

Yocto 构建目录会包含：

```text
build-*/tmp/
build-*/downloads/
build-*/sstate-cache/
*.ext4
*.tegraflash-tar.zst
解压后的 tegraflash 工具和固件
```

其中单个 A/B rootfs 刷写包就可能包含两个约 28 GiB 的 rootfs 分区镜像。完整工作目录很容易增长到数百 GiB，不适合压缩、上传或交给其他开发者。

正确交付方式是只提交：

```text
Git 主仓库
meta-seeed 源码 layer
machine/recipe/bbappend/class
文档和辅助脚本
锁定的 submodule commit
```

以下内容都应该由使用者重新生成，并且已由仓库 `.gitignore` 排除：

```text
build*/
downloads/
sstate-cache/
tmp/
deploy/
刷写包解压目录
```

### 0.2 主机和磁盘建议

建议使用：

- x86_64 Linux 构建主机；
- 非 root 普通用户；
- 主机本地 SSD；
- 至少 200 GiB 可用空间，推荐预留 300 GiB 以上；
- 16 GiB 以上内存，推荐 32 GiB 以上；
- 稳定网络；
- 刷写时使用主板直连 USB 数据口。

Ubuntu/Debian 主机常用依赖示例：

```bash
sudo apt update
sudo apt install -y \
  gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio \
  python3 python3-pip python3-pexpect python3-git python3-jinja2 \
  xz-utils debianutils iputils-ping libegl1-mesa libsdl1.2-dev \
  pylint xterm zstd liblz4-tool file locales \
  gdisk parted udev udisks2
```

不同 Ubuntu/Yocto 版本的依赖包名可能略有变化。如果主机发行版不在 Yocto 支持列表中，优先使用受支持的构建主机或容器，而不是忽略 BitBake 的 host validation 警告。

### 0.3 从 fork 获取轻量源码

创建一个新的源码目录，不要复制本次已经构建过的目录：

```bash
mkdir -p ~/work/jetson-yocto
cd ~/work/jetson-yocto

git clone \
  --branch wrynose \
  --single-branch \
  https://github.com/jjjadand/tegra-demo-distro.git

cd tegra-demo-distro
```

主仓库只保存 metadata。大型 OE4T/OpenEmbedded 源码由 Git submodule 按锁定 commit 获取，构建产物不会进入 Git。

### 0.4 一键准备 submodule、build 目录和共享缓存

仓库提供：

```text
scripts/seeed/prepare-workspace.sh
```

默认执行：

```bash
./scripts/seeed/prepare-workspace.sh
```

它会：

1. 同步并以 shallow 模式初始化锁定的 submodule；
2. 创建 `build-seeed`；
3. 选择 `recomputer-orin-super-j401` machine；
4. 在用户 cache 目录创建共享 downloads 和 sstate；
5. 生成独立 cache 配置，不把缓存写进 Git。

默认目录：

```text
source:    当前 Git checkout
build:     ./build-seeed
downloads: ~/.cache/yocto-seeed/downloads
sstate:    ~/.cache/yocto-seeed/sstate-cache
```

如果有大容量本地 SSD，可以指定缓存位置：

```bash
./scripts/seeed/prepare-workspace.sh \
  --build-dir /data/yocto/build-seeed \
  --cache-dir /data/yocto/cache
```

以后即使删除 build 目录，downloads 和 sstate 仍然可以复用。

查看全部选项：

```bash
./scripts/seeed/prepare-workspace.sh --help
```

### 0.5 推荐的分阶段编译教程

统一构建入口：

```text
scripts/seeed/build.sh
```

第一步，检查 layer、recipe 和最终变量：

```bash
./scripts/seeed/build.sh metadata
```

第二步，只编译 DTB/DTBO：

```bash
./scripts/seeed/build.sh dtb
```

第三步，安装并检查 Seeed BCT/pinmux 文件：

```bash
./scripts/seeed/build.sh bootfiles
```

第四步，构建完整镜像：

```bash
./scripts/seeed/build.sh image
```

如果只修改了 tegraflash 打包逻辑，可以重建刷写包并发布到 deploy：

```bash
./scripts/seeed/build.sh flash-package
```

生成交叉开发 SDK：

```bash
./scripts/seeed/build.sh sdk
```

构建脚本支持其他 build 目录：

```bash
./scripts/seeed/build.sh image \
  --build-dir /data/yocto/build-seeed
```

### 0.6 校验并解压刷写包

不要在 deploy 目录中直接解压，也不要把刷写目录放在 USB 移动硬盘上。使用：

```bash
./scripts/seeed/prepare-flash.sh \
  --output-dir ~/recomputer-super-flash
```

脚本会：

- 找到 deploy 中稳定软链接指向的 tegraflash archive；
- 要求输出目录为空，避免混入旧文件；
- 解压刷写包；
- 检查 DTB、BPMP DTB、pinmux、GPIO、pad voltage、rootfs 和入口脚本；
- 打印 `flashvars` 与 `.env.initrd-flash`；
- 只输出后续刷写命令，不会自动运行 `sudo`。

准备完成后：

```bash
cd ~/recomputer-super-flash
lsusb -d 0955:
sudo ./initrd-flash
```

### 0.7 推荐目录布局

```text
~/work/jetson-yocto/
└── tegra-demo-distro/              # Git 源码，体积较小

/data/yocto/
├── build-seeed/         # 可删除、可重建
└── cache/
    ├── downloads/                  # 可跨 build 复用
    └── sstate-cache/                # 可跨 build 复用

~/recomputer-super-flash/           # 临时刷写目录，刷完可删除
```

需要备份或分享时，只推送 Git commit。不要归档 `/data/yocto/build-*` 或 `~/recomputer-super-flash`。

## 目录

0. 准备可复现工作目录和配套脚本
1. Yocto BSP 和 Ubuntu BSP 的关系
2. Jetson BSP 的组成
3. 示例范围和版本矩阵
4. 创建自定义 layer
5. 从 L4T flash config 映射到 Yocto machine
6. 移植 kernel DTB 和 overlays
7. 移植 pinmux、GPIO 和 pad voltage BCT
8. 判断是否需要移植 kernel/OOT 驱动
9. 选择和定制 Yocto image
10. 构建流程
11. 构建后的静态验证
12. 刷写流程
13. 启动后验收
14. 故障排查树
15. 从“能启动”到“可量产”
16. 复制到另一款 reComputer
17. BSP 交付物
18. 当前示例的已知边界

## 1. 先理解：Yocto BSP 和 Ubuntu BSP 的关系

Jetson 上常见的两条系统路线是：

```text
NVIDIA/Seeed L4T BSP + Ubuntu rootfs + DEB/apt
NVIDIA/Seeed L4T BSP + OE4T/Yocto rootfs + BitBake recipes
```

二者共享的底层内容包括：

- BootROM/RCM 刷写协议；
- MB1、MB2、UEFI 等启动固件；
- BCT、pinmux、GPIO、pad voltage；
- BPMP firmware 和 BPMP DTB；
- Linux kernel、out-of-tree NVIDIA 驱动；
- kernel DTB 和 DTBO；
- CUDA、TensorRT、VPI 等 NVIDIA runtime。

差异主要发生在 rootfs 和软件交付方式：

| 项目 | Ubuntu/JetPack | Yocto/OE4T |
| --- | --- | --- |
| rootfs | Ubuntu | OpenEmbedded 自定义 rootfs |
| 软件安装 | `apt` / `.deb` | BitBake recipe / image |
| 软件仓库 | Ubuntu/NVIDIA 仓库 | 项目自行构建和维护 |
| 开发方式 | 目标机直接安装和编译 | 交叉 SDK、容器或预集成应用 |
| 产品化 | 通用发行版基础上定制 | 从构建阶段精确控制所有组件 |

因此，移植 Yocto BSP 并不是把 Ubuntu rootfs 打进 Yocto，而是把厂商 L4T BSP 中的**板级启动和硬件描述信息**映射为 Yocto machine、recipe、bbappend 和 image class。

刷入本文的 `demo-image-full` 后看到的是 Sato 桌面，而不是 Ubuntu GNOME。默认镜像也不提供 `apt`，这是设计结果，不是构建失败。

## 2. Jetson BSP 的组成

开始移植前，应把厂商 BSP 拆分为以下几类。

### 2.1 Machine identity

描述具体 SoM、载板和存储组合：

- module board ID/SKU/FAB；
- carrier board；
- boot device；
- rootfs device；
- 是否使用 A/B rootfs；
- 是否存在内部 eMMC、QSPI 或外部 NVMe。

在 Yocto 中主要对应：

```text
conf/machine/<machine>.conf
```

### 2.2 MB1/BCT 配置

包括：

- pinmux；
- GPIO default state；
- pad voltage；
- UPHY lane；
- PMIC；
- SDRAM；
- MB1/MB2 miscellaneous settings。

这些文件在启动内核之前就会生效。仅修改 kernel DTB 不能替代 BCT 配置。

### 2.3 BPMP firmware DTB

BPMP 管理电源、时钟、复位和部分高速 I/O。载板或功耗模式变化可能需要选择不同的 BPMP DTB。

### 2.4 Kernel DTB 和 DTBO

描述进入 Linux 后的硬件：

- USB；
- PCIe/NVMe；
- Ethernet；
- I²C/SPI/UART；
- HDMI/display；
- camera；
- GPIO；
- regulator。

### 2.5 Kernel 和 NVIDIA OOT 驱动

如果厂商 BSP 修改了：

```text
Linux_for_Tegra/source/kernel
Linux_for_Tegra/source/nvidia-oot
Linux_for_Tegra/source/hardware
```

则不能只复制 DTS。必须进一步制作 kernel 或 `nvidia-kernel-oot` bbappend/patch。

### 2.6 Rootfs 软件和服务

包括用户、网络、Docker、应用、systemd service、OTA、安全策略等。这部分应通过 image recipe 或应用 recipe 实现，不应直接复制 Ubuntu rootfs 文件。

## 3. 示例范围和版本矩阵

本示例使用：

```text
Carrier:  Seeed reComputer Super J401
Module:   Jetson Orin NX 16GB
SKU:      P3767-0000
Storage:  NVMe rootfs
L4T:      R39.2.0
OE4T:     wrynose
Machine:  recomputer-orin-super-j401
Image:    demo-image-full
```

源 BSP 位于：

```text
../Linux_for_Tegra
```

关键入口文件是：

```text
../Linux_for_Tegra/recomputer-orin-super-j401.conf
```

该文件继承 NVIDIA 的：

```text
p3768-0000-p3767-0000-a0.conf
```

然后覆盖 Seeed 载板所需的 DTB、BPMP DTB、pinmux、pad voltage、HDMI DCE overlay 和 camera overlay。

### 3.1 不要把多个 module SKU 混成一个静态 machine

Seeed L4T 配置会读取 EEPROM，并根据 `board_sku` 在运行时选择不同文件：

| Module SKU | 示例 DTB/BPMP 选择 |
| --- | --- |
| `0000`/`0002` | Orin NX 16GB Super 配置 |
| `0001` | 对应 P3767-0001 配置 |
| `0003` | 对应 P3767-0003 配置 |
| `0004` | 对应 P3767-0004 配置 |
| `0005` | 对应 P3767-0005 配置 |

Yocto machine 通常是构建时静态确定的。因此建议：

```text
recomputer-super-orin-nx-16gb.conf
recomputer-super-orin-nx-8gb.conf
recomputer-super-orin-nano-8gb.conf
recomputer-super-orin-nano-4gb.conf
```

或者创建公共 include，再由多个 machine conf 覆盖 SKU 相关变量。不要假设一个静态刷写包能安全覆盖所有 module SKU。

## 4. 创建自定义 layer

示例 layer 结构如下：

```text
layers/meta-seeed/
├── classes-recipe/
│   └── seeed-recomputer-super-tegraflash.bbclass
├── conf/
│   ├── layer.conf
│   └── machine/
│       └── recomputer-orin-super-j401.conf
├── docs/
│   └── recomputer-orin-super-j401.md
└── recipes-bsp/
    ├── seeed-devicetree/
    │   ├── seeed-devicetree_1.0.bb
    │   └── seeed-devicetree/
    │       ├── tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dts
    │       ├── tegra234-j401-p3768-0000+p3767-recomputer-super-common.dts
    │       ├── tegra234-super-j401-p3768-0000+p3767-0000.dts
    │       ├── tegra234-p3768-0000+p3767-xxxx-nv-common.dtsi
    │       └── tegra234-p3767-camera-p3768-imx219-quad-seeed.dts
    └── tegra-binaries/
        ├── tegra-bootfiles_39.2.0.bbappend
        └── tegra-bootfiles/
            ├── recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi
            ├── recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi
            └── recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi
```

`conf/layer.conf` 至少需要注册 layer 和兼容分支：

```bitbake
BBPATH .= ":${LAYERDIR}"

BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "seeed"
BBFILE_PATTERN_seeed = "^${LAYERDIR}/"
BBFILE_PRIORITY_seeed = "8"

LAYERSERIES_COMPAT_seeed = "wrynose"
```

再把 layer 加入 `bblayers.conf`。本仓库模板已包含：

```text
##OEROOT##/meta-seeed
```

检查 layer 是否生效：

```bash
. ./setup-env --machine recomputer-orin-super-j401 build-seeed
bitbake-layers show-layers
```

## 5. 从 L4T flash config 映射到 Yocto machine

示例 machine 文件：

```text
layers/meta-seeed/conf/machine/recomputer-orin-super-j401.conf
```

核心内容：

```bitbake
MACHINEOVERRIDES =. "p3768-0000-p3767-0000:"

require conf/machine/p3768-0000-p3767-0000.conf

PREFERRED_PROVIDER_virtual/dtb = "seeed-devicetree"
KERNEL_DEVICETREE = "tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb"

TEGRA_FLASHVAR_BPFDTB_FILE = "tegra234-bpmp-3767-0000-3768-super.dtb"
TEGRA_FLASHVAR_PINMUX_CONFIG = "recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi"
TEGRA_FLASHVAR_PMC_CONFIG = "recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi"
TEGRA_FLASHVAR_DCE_OVERLAY = "tegra234-dcb-p3767-0000-hdmi.dtbo"

TEGRA_PLUGIN_MANAGER_OVERLAYS:append = " \
    tegra234-dcb-p3767-0000-hdmi.dtbo \
    tegra234-p3767-camera-p3768-imx219-quad-seeed.dtbo"

IMAGE_CLASSES:append = " seeed-recomputer-super-tegraflash"
```

### 5.1 为什么先继承 NVIDIA machine

```bitbake
require conf/machine/p3768-0000-p3767-0000.conf
```

可以复用 NVIDIA/OE4T 已定义的：

- SoC family；
- tune；
- kernel provider；
- boot firmware；
- storage layout；
- module defaults；
- CUDA architecture。

自定义载板 layer 只覆盖真正不同的板级内容，避免复制整份 NVIDIA machine 配置。

### 5.2 L4T 变量到 Yocto 变量的映射

| L4T flash config | Yocto/OE4T | 用途 |
| --- | --- | --- |
| `DTB_FILE` | `KERNEL_DEVICETREE` / `TEGRA_FLASHVAR_DTB_FILE` | kernel/boot DTB |
| `BPFDTB_FILE` | `TEGRA_FLASHVAR_BPFDTB_FILE` | BPMP DTB |
| `PINMUX_CONFIG` | `TEGRA_FLASHVAR_PINMUX_CONFIG` | MB1 pinmux |
| `PMC_CONFIG` | `TEGRA_FLASHVAR_PMC_CONFIG` | pad voltage |
| `DCE_OVERLAY_DTB_FILE` | `TEGRA_FLASHVAR_DCE_OVERLAY` | display DCE overlay |
| `OVERLAY_DTB_FILE` | `TEGRA_PLUGIN_MANAGER_OVERLAYS` | boot/runtime overlays |
| `ODMDATA` | `TEGRA_FLASHVAR_ODMDATA` 或基础 machine 默认值 | UPHY/lane 配置 |

不同 `meta-tegra` 版本的变量名可能变化。移植新版本时先执行：

```bash
bitbake -e demo-image-full | grep '^TEGRA_FLASHVAR_'
```

不要直接照搬其他分支的 machine conf。

## 6. 移植 kernel DTB 和 overlays

自定义 device-tree recipe：

```text
layers/meta-seeed/recipes-bsp/seeed-devicetree/seeed-devicetree_1.0.bb
```

示例：

```bitbake
DESCRIPTION = "Seeed reComputer Super J401 device trees"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit tegra-devicetree

COMPATIBLE_MACHINE = "(recomputer-orin-super-j401)"
S = "${UNPACKDIR}"

SRC_URI = " \
    file://tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dts \
    file://tegra234-j401-p3768-0000+p3767-recomputer-super-common.dts \
    file://tegra234-super-j401-p3768-0000+p3767-0000.dts \
    file://tegra234-p3768-0000+p3767-xxxx-nv-common.dtsi \
    file://tegra234-p3767-camera-p3768-imx219-quad-seeed.dts \
"

DT_FILES = " \
    tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb \
    tegra234-p3767-camera-p3768-imx219-quad-seeed.dtbo \
"
```

### 6.1 收集 DTS 时不要漏 include 链

厂商顶层 DTS 往往只包含少量内容，真正定义分散在多个 `.dts/.dtsi` 中。应递归检查：

```bash
grep -R '^#include\|/include/' <vendor-dts-directory>
```

确保 recipe 的 `SRC_URI` 能提供所有非 NVIDIA 标准 include 文件。NVIDIA 已由 `meta-tegra` staged 的公共 DTS 可以复用，不必全部复制。

### 6.2 不要只检查编译成功

DTB 能编译不代表选择正确。至少检查：

```bash
bitbake -e virtual/dtb | grep -E '^(PN|FILE|PROVIDES|PREFERRED_PROVIDER_virtual/dtb)='
bitbake -f -c compile seeed-devicetree
```

预期生成：

```text
tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb
tegra234-p3767-camera-p3768-imx219-quad-seeed.dtbo
```

必要时反编译核对关键节点：

```bash
dtc -I dtb -O dts -o /tmp/board.dts <generated-board.dtb>
grep -nE 'compatible|pcie|nvme|usb|ethernet|display|camera' /tmp/board.dts
```

## 7. 移植 pinmux、GPIO 和 pad voltage BCT

示例通过 `tegra-bootfiles_39.2.0.bbappend` 把 Seeed 文件安装到 tegraflash sysroot：

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

SRC_URI:append:recomputer-orin-super-j401 = " \
    file://recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi \
    file://recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi \
    file://recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi \
"

SEEED_BOOTFILES_DIR := "${THISDIR}/${BPN}"

do_install:append:recomputer-orin-super-j401() {
    install -m 0644 ${SEEED_BOOTFILES_DIR}/recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi ${D}${datadir}/tegraflash/
    install -m 0644 ${SEEED_BOOTFILES_DIR}/recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi ${D}${datadir}/tegraflash/
    install -m 0644 ${SEEED_BOOTFILES_DIR}/recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi ${D}${datadir}/tegraflash/
}
```

验证安装任务：

```bash
bitbake -f -c install tegra-bootfiles
```

然后检查：

```text
build-seeed/tmp/work/<machine-triplet>/tegra-bootfiles/39.2.0/image/usr/share/tegraflash/
```

### 7.1 `do_install` 成功不等于进入刷写包

这是本次移植最重要的实际问题之一。

OE4T 默认 `tegraflash_populate_package()` 对 T234 主要复制：

```text
tegra234-*.dts*
```

Seeed 文件以：

```text
recomputer-super-*
```

开头，因此它们虽然已经：

- 进入 `tegra-bootfiles` image；
- 进入 package；
- 进入 sysroot；

但最初仍未进入 `.tegraflash-tar.zst`。

本 layer 使用 image class 修复：

```bitbake
SEEED_RECOMPUTER_SUPER_BCT_FILES = " \
    recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi \
    recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi \
    recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi \
"

tegraflash_custom_pre() {
    for bctfile in ${SEEED_RECOMPUTER_SUPER_BCT_FILES}; do
        cp "${STAGING_DATADIR}/tegraflash/$bctfile" .
    done
}
```

并在 machine 中启用：

```bitbake
IMAGE_CLASSES:append = " seeed-recomputer-super-tegraflash"
```

其他载板如果自定义 boot 文件不符合 `meta-tegra` 默认通配规则，也必须做相同检查。

## 8. 判断是否需要移植 kernel/OOT 驱动

DTB 和 BCT 只解决硬件描述。如果厂商 BSP 修改了驱动，需要对比源树：

```bash
git diff <nvidia-baseline> -- Linux_for_Tegra/source/kernel
git diff <nvidia-baseline> -- Linux_for_Tegra/source/nvidia-oot
```

常见需要驱动补丁的功能：

- GMSL camera；
- 特殊 MIPI CSI sensor；
- CAN transceiver 控制；
- PCIe endpoint 特殊 reset sequence；
- 定制 fan/tach；
- 特殊 GPIO expander；
- 非主线 Ethernet PHY。

典型做法是创建：

```text
recipes-kernel/linux/linux-*.bbappend
recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot_*.bbappend
```

并通过 `SRC_URI` 添加 patch。不要直接修改 `repos/meta-tegra`，否则难以升级和复用。

本示例当前主要完成板级 DT/BCT 映射。Seeed BSP 中部分 camera/GMSL 驱动变化尚未纳入，因此使用这些功能前需要单独验证。

## 9. 选择和定制 Yocto image

仓库常用镜像：

| Image | 用途 |
| --- | --- |
| `demo-image-base` | 无图形基础系统 |
| `demo-image-egl` | DRM/EGL，无桌面 |
| `demo-image-sato` | X11/Sato 桌面 |
| `demo-image-weston` | Wayland/Weston |
| `demo-image-full` | Sato + Docker + NVIDIA 测试/示例组件 |

本示例使用：

```bash
bitbake demo-image-full
```

`demo-image-full` 包含 Python、OpenSSH、Docker、CUDA runtime、cuDNN、TensorRT、VPI 和示例程序，但它不是 Ubuntu，也不是完整的 SDK Manager 开发环境。

### 9.1 添加应用和开发工具

建议创建自己的 image recipe，不要长期修改 demo image。例如：

```bitbake
DESCRIPTION = "Product image for custom reComputer"

require recipes-demo/images/demo-image-common.inc

IMAGE_FEATURES += "splash x11-base x11-sato hwcodecs"

IMAGE_INSTALL:append = " \
    git \
    cmake \
    python3-pip \
    my-product-app \
"
```

如果需要复用 `demo-image-full` 中的 NVIDIA 测试组件，应把对应 package/packagegroup 明确加入产品 image，而不是 `require` 另一个 `.bb` 文件。这样产品 image 的依赖关系更清晰，也避免两个 image recipe 的变量互相覆盖。

如果确实需要目标机编译：

```bitbake
IMAGE_INSTALL:append = " packagegroup-core-buildessential"
```

但量产镜像通常不应包含完整编译工具链。

### 9.2 软件包管理不是 apt

当前 distro 使用：

```bitbake
PACKAGE_CLASSES ?= "package_rpm"
```

要保留运行时包管理数据库，可加入：

```bitbake
IMAGE_FEATURES += "package-management"
```

这会使用 RPM/DNF 体系，而不是 Ubuntu `apt`。项目仍需要自行构建和发布匹配的 package feed。

不要把 Ubuntu 仓库添加到 Yocto 系统。即使某些包能强行安装，也可能因为 ABI、路径、依赖和构建选项不同而损坏系统。

### 9.3 用户和密码

当前开发配置允许 root 空密码登录：

```bitbake
EXTRA_IMAGE_FEATURES ?= "allow-empty-password empty-root-password allow-root-login"
```

量产前必须移除这些 feature，并使用 `extrausers` 或首次启动 provisioning 创建受控用户。例如：

```bitbake
inherit extrausers

EXTRA_USERS_PARAMS = " \
    useradd -m -G sudo,docker product; \
    usermod -p '<password-hash>' product; \
    usermod -L root; \
"
```

不要在 layer 中保存明文密码。

### 9.4 推荐生成交叉 SDK

```bash
. ./setup-env --machine recomputer-orin-super-j401 build-seeed
bitbake demo-image-full -c populate_sdk
```

输出位于：

```text
build-seeed/tmp/deploy/sdk/
```

应用团队可以安装 SDK 后交叉编译，不必在目标机安装 GCC/CMake。

## 10. 构建流程

如果使用第 0 章提供的脚本，通常不需要手工执行本章命令。本章保留底层 BitBake 命令，便于理解脚本行为和排查失败。

### 10.1 初始化环境

```bash
cd tegra-demo-distro
. ./setup-env --machine recomputer-orin-super-j401 build-seeed
```

确认配置：

```bash
bitbake -e demo-image-full | grep -E '^(MACHINE|DISTRO|PREFERRED_PROVIDER_virtual/dtb|KERNEL_DEVICETREE)='
```

### 10.2 推荐的分阶段构建

先检查 metadata：

```bash
bitbake-layers show-layers
bitbake-layers show-recipes seeed-devicetree
```

再编译 DTB：

```bash
bitbake -f -c compile seeed-devicetree
```

再检查 bootfiles：

```bash
bitbake -f -c install tegra-bootfiles
```

最后构建镜像：

```bash
bitbake demo-image-full
```

成功示例：

```text
Tasks Summary: Attempted 13211 tasks ... all succeeded.
```

### 10.3 下载和 sstate 缓存

大型 Jetson Yocto 构建应共享：

```bitbake
DL_DIR ?= "/path/to/shared/downloads"
SSTATE_DIR ?= "/path/to/shared/sstate-cache"
```

这可以避免重复下载 NVIDIA、kernel、CUDA 等大型组件，也有助于在网络不稳定时复用成功 fetch 的内容。

## 11. 构建后必须进行的静态验证

刷写前不要只看 `bitbake` 是否成功。

### 11.1 检查关键 BitBake 变量

```bash
bitbake -e demo-image-full | grep -E \
'^(MACHINE|PREFERRED_PROVIDER_virtual/dtb|KERNEL_DEVICETREE|TEGRA_FLASHVAR_(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|DCE_OVERLAY))='
```

本示例预期：

```text
MACHINE="recomputer-orin-super-j401"
PREFERRED_PROVIDER_virtual/dtb="seeed-devicetree"
KERNEL_DEVICETREE="tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb"
TEGRA_FLASHVAR_BPFDTB_FILE="tegra234-bpmp-3767-0000-3768-super.dtb"
TEGRA_FLASHVAR_PINMUX_CONFIG="recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi"
TEGRA_FLASHVAR_PMC_CONFIG="recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi"
TEGRA_FLASHVAR_DCE_OVERLAY="tegra234-dcb-p3767-0000-hdmi.dtbo"
```

### 11.2 找到 tegraflash 包

```text
build-seeed/tmp/deploy/images/recomputer-orin-super-j401/
```

使用稳定软链接：

```text
demo-image-full-recomputer-orin-super-j401.rootfs.tegraflash-tar.zst
```

### 11.3 解压到独立目录

不要直接在 deploy 根目录覆盖解压，也不要把解压目录和原始 archive 混在一起：

```bash
mkdir -p /path/on/local-disk/recomputer-super-flash
cd /path/on/local-disk/recomputer-super-flash
tar xf /path/to/demo-image-full-recomputer-orin-super-j401.rootfs.tegraflash-tar.zst
```

建议放在主机本地 SSD，而不是 USB 移动硬盘。刷写期间会同时进行大文件读取和 USB gadget 存储操作，本地磁盘更稳定。

### 11.4 检查刷写变量

```bash
grep -E '^(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|DCE_OVERLAY|PLUGIN_MANAGER_OVERLAYS|BOOTCONTROL_OVERLAYS)=' flashvars
cat .env.initrd-flash
```

预期包含：

```text
BPFDTB_FILE="tegra234-bpmp-3767-0000-3768-super.dtb"
DTB_FILE="tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb"
PINMUX_CONFIG="recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi"
PMC_CONFIG="recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi"
DCE_OVERLAY="tegra234-dcb-p3767-0000-hdmi.dtbo"
ROOTFS_DEVICE="nvme0n1"
ROOTFS_IMAGE="demo-image-full.ext4"
```

### 11.5 检查所有引用文件存在

```bash
for file in \
  recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi \
  recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi \
  recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi \
  tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb \
  tegra234-bpmp-3767-0000-3768-super.dtb; do
    test -s "$file" || echo "MISSING: $file"
done
```

## 12. 刷写流程

### 12.1 主机准备

主机需要：

- Linux x86_64；
- `sudo` 权限；
- `gdisk/sgdisk`；
- `partprobe`；
- `udevadm`；
- `udisksctl`；
- 稳定的 USB 数据线和主板直连端口。

刷写前尽量拔掉其他 USB mass-storage，减少 `/dev/sdX` 变化和 USB 带宽干扰。

### 12.2 进入 Force Recovery

确认：

```bash
lsusb -d 0955:
```

Orin recovery 设备示例：

```text
0955:7323 NVIDIA Corp. APX
```

### 12.3 执行刷写

从独立解压目录运行：

```bash
sudo ./initrd-flash
```

流程大致为：

```text
Step 1: 读取板卡信息并准备/签名固件
Step 2: 通过 RCM 启动 initrd flasher
Step 3: 发送 flash command sequence
Step 4: 将目标 NVMe 作为 USB mass storage 导出并写分区
Step 5: 读取目标端最终状态
```

成功标志：

```text
[OK: /dev/sdX]
Final status: SUCCESS
Successfully finished
```

本次实机成功日志：

```text
log.initrd-flash.2026-07-13-15.20.03
device-logs-2026-07-13-15.20.03/
```

### 12.4 刷写后首次启动

1. 等刷写脚本完全结束；
2. 断开 USB 数据线；
3. 松开 recovery；
4. 完全断电数秒；
5. 重新上电；
6. 通过 HDMI 或串口观察启动。

开发镜像默认可以使用：

```text
user: root
password: empty
```

登录后立即执行 `passwd`，并在量产配置中关闭空密码。

## 13. 启动后验收

### 13.1 系统和 rootfs

```bash
cat /etc/os-release
uname -a
findmnt /
lsblk
```

正常 rootfs 应位于：

```text
/dev/nvme0n1p1
```

系统标识会类似：

```text
OE4Tegra Demonstration Distro
```

### 13.2 板卡、设备树和启动日志

```bash
tr -d '\0' < /proc/device-tree/model; echo
dmesg | grep -Ei 'tegra|nvidia|error|fail' | tail -100
```

### 13.3 网络和 SSH

```bash
ip addr
systemctl status sshd
connmanctl services
```

### 13.4 NVIDIA runtime

```bash
tegrastats
nvidia-smi
trtexec --version
docker --version
systemctl status docker
```

### 13.5 外设 checklist

根据产品逐项测试：

- HDMI/display；
- USB 2.0/3.x host；
- Ethernet；
- Wi-Fi/Bluetooth；
- NVMe；
- RTC；
- fan；
- GPIO；
- UART；
- I²C；
- SPI；
- CAN；
- CSI camera；
- PCIe 扩展设备。

不要因为能进入桌面就认为 BSP 已完成。

## 14. 故障排查树

### 14.1 `linux-*:do_fetch` 失败

症状：kernel 或 NVIDIA 源码 URL 无法下载。

处理：

- 检查网络和代理；
- 使用共享 `DL_DIR`；
- 复用已成功构建目录的 downloads；
- 不要通过手工修改 fetch URL 掩盖版本不匹配。

### 14.2 `tegra-bootfiles:do_install` 找不到自定义文件

检查：

- `FILESEXTRAPATHS`；
- `SRC_URI` override 是否匹配 machine；
- 文件是否位于 `${THISDIR}/${BPN}`；
- `do_install` 使用的路径是否真实存在。

可以查看：

```bash
bitbake -e tegra-bootfiles | grep -E '^(FILESPATH|SRC_URI|UNPACKDIR|WORKDIR)='
```

### 14.3 刷写时报 pinmux `cpp` 失败

典型日志：

```text
Pre-processing config: recomputer-super-...-pinmux-....dtsi
Error: Return value 1
Command cpp ...
```

随后可能出现：

```text
cp: cannot stat 'signed/*'
ParseError: no element found
ERR: RCM boot blob incomplete
```

不要被后续 XML/signed 错误误导。先检查最早的 `cpp` 错误，以及 pinmux 文件是否真正存在于解压后的刷写包。

### 14.4 `could not retrieve board information`

如果日志停在：

```text
Sending bct_br
ERROR: might be timeout in USB write
```

说明 recovery 已识别，但 RCM USB 传输失败。建议：

- 完全断电并重新进入 recovery；
- 使用主板直连 USB；
- 更换可靠数据线；
- 拔掉其他 USB mass-storage/hub；
- 检查 `sudo dmesg --ctime | tail -100`。

### 14.5 `partprobe failed after partitioning /dev/sdX`

先确认 `/dev/sdX` 是否真的是目标端导出的 NVMe，而不是 `flashpkg` 临时盘或主机其他磁盘：

```bash
lsblk -b -o NAME,SIZE,MODEL,SERIAL,TRAN,MOUNTPOINTS
sudo dmesg --ctime | tail -150
```

常见原因：

- 主机桌面自动挂载了目标 NVMe 的旧分区；
- 刷写包从 USB 移动硬盘运行，I/O 和 USB gadget 操作互相干扰；
- 设备重新枚举时 `/dev/sdX` 变化；
- 其他 storage 设备增加识别复杂度。

优先处理：

- 将刷写包解压到主机本地 SSD；
- 拔掉其他移动存储；
- 重新完全启动刷写流程；
- 不要手工假设目标永远是 `/dev/sdb`。

本次实机在本地磁盘运行刷写包后完成成功，因此没有保留针对 `make-sdcard` 的额外修改。

### 14.6 构建成功但启动黑屏

检查顺序：

1. 串口是否启动；
2. kernel DTB 是否正确；
3. DCE overlay 是否进入 flashvars；
4. HDMI connector/status 节点；
5. BPMP DTB 是否匹配 module SKU；
6. display firmware 和 DTB overlay 合并日志；
7. 是否只是图形服务失败而系统可 SSH。

## 15. 从“能启动”到“可量产”

完成基础 BSP 后，还需要处理以下内容。

### 15.1 创建产品 machine 和产品 image

不要长期使用实验名称或 demo image。建议：

```text
conf/machine/<product>-<module-sku>.conf
recipes-core/images/<product>-image.bb
```

### 15.2 固定版本

记录：

- OE4T/meta-tegra commit；
- OpenEmbedded layers commit；
- Seeed BSP source commit/version；
- kernel source revision；
- firmware revision；
- product layer revision；
- toolchain/container version。

### 15.3 安全配置

- 禁止 root 空密码；
- 禁止不需要的 root SSH；
- 配置防火墙；
- 删除测试工具和 demo service；
- 评估 Secure Boot；
- 保护签名密钥；
- 生成 SBOM；
- 规划 CVE 更新。

### 15.4 OTA 和回滚

本示例使用 A/B rootfs layout。产品应进一步定义：

- active slot 管理；
- boot success 标记；
- rollback 条件；
- bootloader 与 rootfs 兼容矩阵；
- 断电恢复；
- OTA 签名；
- 数据分区迁移策略。

本仓库已有 SWUpdate 示例，可作为起点，但不能未经产品验证直接用于量产。

### 15.5 自动化硬件验证

至少建立：

- 开机测试；
- 重启/断电循环；
- NVMe 压力测试；
- 网络吞吐；
- USB 热插拔；
- GPU/CUDA/TensorRT smoke test；
- 温度和功耗测试；
- camera pipeline 测试；
- OTA/回滚测试。

## 16. 复制本示例到另一款 reComputer 的步骤

本章描述的是**移植流程复用**，不是“一个 BSP 通刷所有 Seeed 载板”。通常可以复用：

- `meta-seeed` 的 layer 目录组织；
- 从 L4T config 提取变量的方法；
- devicetree recipe 模式；
- `tegra-bootfiles` bbappend 模式；
- tegraflash archive 静态检查方法；
- 分阶段构建、刷写和验收 checklist。

通常不能直接复用：

- `recomputer-orin-super-j401.conf`；
- J401 pinmux/GPIO/pad voltage；
- J401 kernel DTB；
- 固定的 BPMP DTB；
- camera/display overlays；
- module SKU/FAB 默认值；
- NVMe/eMMC/QSPI storage layout；
- 特定载板驱动 patch。

因此，其他载板的合理目标是“沿用相同流程创建新的 machine 和板级文件”，而不是只修改 machine 名称后直接构建。

可以按以下顺序执行：

1. 确认目标 L4T/JetPack 和对应 OE4T 分支；
2. 找到厂商 `<board>.conf` 及其继承的 NVIDIA config；
3. 记录 board ID、SKU、FAB、boot/rootfs device；
4. 提取 DTB、BPMP DTB、BCT、overlay、ODMDATA；
5. 检查 kernel 和 OOT 驱动差异；
6. 创建新的 machine conf；
7. 创建或复用 devicetree recipe；
8. 用 bbappend 安装自定义 boot files；
9. 检查这些文件是否真正进入 tegraflash archive；
10. 分阶段构建和静态验证；
11. 在本地 SSD 解压刷写包；
12. recovery 刷写；
13. 按外设 checklist 验收；
14. 创建产品 image、用户、安全和 OTA 策略。

## 17. 建议提交的 BSP 交付物

一个可维护的第三方载板 Yocto BSP 至少应包含：

```text
meta-<vendor>/
├── conf/machine/
├── recipes-bsp/device-tree/
├── recipes-bsp/tegra-binaries/
├── recipes-kernel/                 # 如果有驱动差异
├── recipes-core/images/
├── recipes-core/packagegroups/
├── recipes-apps/
├── classes-recipe/                 # 如果打包过程需扩展
├── docs/
└── README.md
```

文档中应明确：

- 支持的 module SKU；
- 支持的载板 revision；
- L4T/OE4T 版本；
- 构建命令；
- 刷写命令；
- 默认用户策略；
- 已验证外设；
- 未支持功能；
- 已知问题；
- OTA 和恢复方式。

## 18. 当前示例的已知边界

- 当前 machine 静态针对 P3767-0000 / Orin NX 16GB；
- 其他 module SKU 应拆分为独立 machine；
- 已完成板级 DT/BCT 和基础刷写验证；
- 部分 Seeed camera/GMSL 驱动差异尚未移植；
- `demo-image-full` 是演示镜像，不是最终产品镜像；
- 默认 root 空密码仅用于开发；
- 未在本文中完成 Secure Boot、量产密钥和完整 OTA 验证。

完成这些边界项后，才应把 BSP 标记为对应产品的正式量产版本。

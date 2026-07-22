# Seeed Jetson 第三方载板 Yocto/OE4T 构建、验证与刷写教程

本文用于实际验证本仓库支持的全部 Seeed Jetson 第三方载板。仓库已经为本地 Seeed Linux for Tegra（L4T）BSP 中的 16 个载板配置建立独立 Yocto machine；每块载板使用独立 build 目录，但共享 downloads 和 sstate 缓存。**第 0 章是建议逐条执行的验证教程**，后续章节用于解释移植原理和排查问题。

本文仍以 **Seeed reComputer Super J401 + Jetson Orin NX 16GB** 记录完整的基础外设实机结果。另有 **reServer J501X GMSL + Jetson AGX Orin SKU 0004** 已完成 Yocto 包刷写和系统启动验证，但尚未声明 GMSL 及其他外设验证完成。验证其他载板时，必须使用对应 machine，并准确区分“构建验证”“刷机/启动验证”和“外设验证”。

本文不仅给出最终文件，还解释每类 BSP 文件属于启动链的哪一层、如何从厂商 L4T BSP 提取信息、如何验证生成物，以及如何定位构建和刷写问题。其他 reComputer 或自定义 Jetson 载板可以沿用相同流程。

本示例已经完成以下实机验证：

- Yocto `demo-image-full` 构建成功；
- 自定义 DTB、BPMP DTB、pinmux、pad voltage 和 camera overlay 进入刷写包；
- NVMe A/B rootfs、kernel、DTB 和 ESP 写入成功；
- `initrd-flash` 最终返回 `Final status: SUCCESS`；
- HDMI、USB 等基础外设可用；
- 系统进入 OE4T/Yocto Sato 图形桌面。

> 本文示例基于 `meta-tegra` 的 `wrynose` 分支、L4T R39.2.0 / JetPack 7.2。移植其他版本时，必须使用与目标 L4T 版本匹配的 OE4T 分支和 NVIDIA BSP 文件。

> **验证范围说明：** 16 个默认 machine 均已完成 BitBake metadata 解析，`tegra234` 与 `tegra264` 板级设备树已完成构建验证，自定义 BCT 文件也已验证进入 tegraflash sysroot。reComputer Super J401 + Jetson Orin NX 16GB（P3767-0000）已完成刷写、启动和基础外设验证；reServer J501X GMSL + Jetson AGX Orin SKU 0004 已完成刷写和启动验证。其余 machine 仍不能直接视为已完成产品级硬件验证。

本地 `Linux_for_Tegra` 中其他 Seeed 板卡的源文件盘点和当前 Yocto 支持状态见：

```text
layers/meta-seeed/docs/board-support-status.md
```

也可以生成详细的 L4T 配置清单：

```bash
L4T_DIR=/path/to/Linux_for_Tegra

./scripts/seeed/discover-l4t-boards.sh \
  --l4t-dir "$L4T_DIR" \
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
  --branch master \
  --single-branch \
  https://github.com/jjjadand/seeed-tegra-demo-distro.git \
  tegra-demo-distro

cd tegra-demo-distro
```

主仓库只保存 metadata。大型 OE4T/OpenEmbedded 源码由 Git submodule 按锁定 commit 获取，构建产物不会进入 Git。

### 0.4 选择要验证的载板

先列出仓库中的全部 Seeed machine：

```bash
./scripts/seeed/build.sh machines
```

完整 machine、Seeed L4T config、SoC 和验证状态见：

```text
layers/meta-seeed/docs/board-support-status.md
```

下面统一以 `recomputer-orin-super-j401` 为主流程示例。按照 NVIDIA 39.2.0
配置，J401 系列支持 P3767 `0000`、`0001`、`0003`、`0004` 四个 Orin NX/Nano
模组，因此主流程也必须明确传入 `--module-sku`。验证其他载板时，替换
`--machine`、`--module-sku` 和 `--build-dir`，并为每个载板/模组组合使用独立
build 目录。

`--module-sku` 对应 NVIDIA 模组完整编号的最后四位：

| 模组系列 | `--module-sku` | 完整模组编号 | 具体模组型号 |
| --- | --- | --- | --- |
| P3767 | `0000` | `P3767-0000` | Jetson Orin NX 16GB |
| P3767 | `0001` | `P3767-0001` | Jetson Orin NX 8GB |
| P3767 | `0003` | `P3767-0003` | Jetson Orin Nano 8GB |
| P3767 | `0004` | `P3767-0004` | Jetson Orin Nano 4GB |
| P3701 | `0000` | `P3701-0000` | Jetson AGX Orin 开发套件模组 |
| P3701 | `0001` | `P3701-0001` | AGX Orin 历史/兼容 SKU，复用 `0000` DTB/BPMP 配置 |
| P3701 | `0002` | `P3701-0002` | AGX Orin 历史/兼容 SKU，复用 `0000` DTB/BPMP 配置 |
| P3701 | `0004` | `P3701-0004` | Jetson AGX Orin 32GB |
| P3701 | `0005` | `P3701-0005` | Jetson AGX Orin 64GB |
| P3834 | 不可选择 | `P3834-0000` | Jetson T4000 |
| P3834 | 不可选择 | `P3834-0008` | Jetson T5000 / AGX Thor 开发套件模组 |

当前 BSP 将 P3701 `0001`、`0002` 作为兼容编号处理，没有给出独立的量产商品
型号名称；使用前应以模组标签或 EEPROM 信息确认。Thor 模组由 `MACHINE` 固定，
不能额外传入 `--module-sku`。

### 0.5 一次 prepare 固定载板、build 目录和共享缓存

建议把多个 machine 共用的下载和 sstate 缓存放在独立目录：

```text
$HOME/.cache/yocto-seeed
```

验证 Super J401 时执行：

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
  --module-sku 0000 \
  --build-dir build-seeed-super-j401 \
  --cache-dir "$HOME/.cache/yocto-seeed"
```

这条命令会：

1. 初始化锁定的 submodule；
2. 创建 `build-seeed-super-j401`；
3. 把 machine 固化到该目录的 `conf/local.conf`；
4. 配置共享 `downloads` 和 `sstate-cache`；
5. 把该 build 目录记录为当前 checkout 的活动工作区。

`--machine` 只影响本次 prepare 及其目标 build 目录，不会导出全局环境变量。**一个 build 目录只能对应一个 machine**；切换载板时必须换一个新的 `--build-dir`。

确认当前活动载板：

```bash
./scripts/seeed/build.sh current
```

Super J401 应显示：

```text
Machine:   recomputer-orin-super-j401
Module SKU: 0000
```

如果这里显示其他 machine，不要继续编译，应重新执行本节 prepare 命令。

Super J401 当前通过 `p3768-0000-p3767-${SEEED_MODULE_SKU}.conf` 选择 P3767
模组。`prepare-workspace.sh` 会校验 `0000`、`0001`、`0003`、`0004`，并把选择
写入 `conf/seeed-machine.conf`；不能只复用当前 machine 并在刷写时临时修改
SKU。

### 0.6 按顺序验证 metadata、DTB、BCT 和完整镜像

后续命令自动使用活动 build 目录，不需要再传 `--machine` 或 `--build-dir`。

第一步，解析 metadata 并检查最终 BSP 变量：

```bash
./scripts/seeed/build.sh metadata
```

输出中的 `MACHINE` 必须和 `build.sh current` 一致，并且应看到：

```text
PREFERRED_PROVIDER_virtual/dtb="seeed-devicetree"
```

第二步，编译该载板的 DTB/DTBO：

```bash
./scripts/seeed/build.sh dtb
```

首次执行会准备 kernel/OOT sysroot，因此可能出现大量 `Setscene tasks`，也可能拉取 `linux-noble-nvidia-tegra`。这是 `tegra-devicetree` 的正常依赖，不表示脚本错误。成功标志为：

```text
Tasks Summary: ... all succeeded.
```

第三步，安装并检查该载板的 BCT、pinmux 和 pad-voltage 文件：

```bash
./scripts/seeed/build.sh bootfiles
```

脚本会对需要进入 tegraflash sysroot 的文件逐一打印 `OK:`；任何缺失文件都会直接返回非零状态。

第四步，构建完整镜像和 tegraflash archive：

```bash
./scripts/seeed/build.sh image
```

只修改 tegraflash 打包逻辑时，可以执行：

```bash
./scripts/seeed/build.sh flash-package
```

可选：只有需要在 x86_64 PC 上交叉编译 Jetson 应用时才生成 SDK。刷写镜像或在
Jetson 上使用 `nvcc`、GCC/CMake 直接编译时不需要执行：

```bash
./scripts/seeed/build.sh sdk
```

上游默认 image `demo-image-full` 是 NVIDIA/OE4T 参考基线，包含 CUDA runtime、
CUDA samples、TensorRT/VPI/MMAPI tests、OpenCV、多媒体和容器运行时，但不包含
目标端 `nvcc` 及完整 CUDA/cuDNN/TensorRT/VPI 开发头文件。

路线 B 已新增：

- `seeed-image-jetson-runtime`：与参考包的 runtime、samples 和 tests 选择对齐，
  不安装目标端完整工具链；
- `seeed-image-jetson-development`：在 runtime 基础上加入 `cuda-toolkit`、目标端
  `nvcc`、CUDA/cuDNN/TensorRT/VPI/OpenCV 开发文件、编译调试工具和测试样例；
- 可选地对 development image 执行 `populate_sdk`：仅供 x86_64 PC 交叉编译，
  生成 CUDA host tools 和匹配的 AArch64 开发 sysroot；板端开发和刷机不需要。

它们仍是 Yocto/OE4T，不是 Ubuntu JetPack SDK Manager 环境。参考包静态审计见
`layers/meta-seeed/docs/nvidia-demo-image-full-reference.md`，实施边界见
`layers/meta-seeed/docs/yocto-route-b-build-plan.md`。

如果希望一次完成本节的 metadata、DTB、BCT 和完整镜像构建，执行：

```bash
./scripts/seeed/build.sh all
```

它会严格按照 `metadata → dtb → bootfiles → image` 顺序运行，任一步失败都会立即停止。`all` 不包含 SDK，也不会自动解压或刷写；完整镜像成功后仍需执行第 0.7 节的 `prepare-flash.sh`。

也可以在一条命令中选择已经 prepare 的载板/模组 build 目录并完成全部阶段：

```bash
./scripts/seeed/build.sh all \
  --machine recomputer-orin-super-j401 \
  --build-dir build-seeed-super-j401
```

这条命令只选择已经 prepare 的目录，不会修改其中的 machine；对于 J401 和
AGX Orin，也不会修改目录中固化的 module SKU。首次构建必须先按第 0.5 节执行
`prepare-workspace.sh`。

### 0.7 校验刷写包并执行实机刷写

完整镜像成功后，使用脚本查找、解压并检查当前 machine 的刷写包：

```bash
./scripts/seeed/prepare-flash.sh
```

脚本会自动读取活动 build 目录和 machine，检查 DTB、BPMP DTB、pinmux、pad voltage、rootfs 和 `initrd-flash`，并打印实际解压目录。不要在 deploy 目录中手工覆盖解压。

将目标板进入 Force Recovery Mode 后，按脚本最后输出的目录执行：

```bash
cd ~/seeed-flash-recomputer-orin-super-j401
lsusb -d 0955:
sudo ./initrd-flash
```

只有出现以下结果，才能标记为“刷写验证通过”：

```text
Final status: SUCCESS
Successfully finished
```

刷写后还必须按第 13 章检查启动、网络、NVIDIA runtime 和载板外设。没有实机的 machine 只能记录为“构建验证/未实机验证”。

### 0.8 切换到另一块载板

例如从主示例 Super J401 切换到 reServer AGX Orin J501x GMSL：

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine reserver-agx-orin-j501x-gmsl \
  --module-sku 0004 \
  --build-dir build-seeed-reserver-j501x-gmsl-sku0004 \
  --cache-dir "$HOME/.cache/yocto-seeed"

./scripts/seeed/build.sh current
./scripts/seeed/build.sh metadata
./scripts/seeed/build.sh dtb
./scripts/seeed/build.sh bootfiles
./scripts/seeed/build.sh image
./scripts/seeed/prepare-flash.sh
```

上例复用 `$HOME/.cache/yocto-seeed`，避免重新
下载和生成全部 sstate。如果以后迁移缓存，只需在 prepare 时替换 `--cache-dir`。
不要复用此前 SKU `0000` 的 build 目录或刷写包。

对于已经 prepare 的 build 目录，也可以直接在任意 `build.sh` 命令中显式选择；成功校验后，它会成为后续命令的活动工作区：

```bash
./scripts/seeed/build.sh metadata \
  --machine recomputer-orin-super-j401 \
  --build-dir build-seeed-super-j401
```

上面的命令成功校验 build 目录中的 machine 后，后续 `dtb`、`bootfiles` 和 `image` 不再需要参数。若只想临时检查而不改变活动工作区，显式增加：

```bash
./scripts/seeed/build.sh current \
  --machine recomputer-orin-super-j401 \
  --build-dir build-seeed-super-j401 \
  --no-activate
```

`build.sh` 不会把一个已有 build 目录改成另一种 machine。J401 和 AGX Orin 的
`prepare-workspace.sh --module-sku` 会写入 `conf/seeed-machine.conf`，同一 build
目录也不能改成另一个 module SKU。载板或模组组合变化时必须使用新的 build 目录。

当前 J401 系列接受 `0000`、`0001`、`0003`、`0004`；reServer J501X/J501X GMSL
和 Seeed AGX Orin Kit 接受
`0000`、`0001`、`0002`、`0004`、`0005`；reComputer Mini/Robo AGX Orin
按提供的 L4T 配置接受 `0004`、`0005`。其中 `0001`、`0002` 复用 `0000`
的 kernel DTB 和 BPMP DTB，但刷写包仍保留实际 `BOARDSKU` 并严格校验。

### 0.9 全 machine 构建矩阵检查

```bash
./scripts/seeed/validate-all-machines.sh
```

该脚本内部遍历全部 machine，因此不指定单一载板参数。它用于 metadata、`tegra234`/`tegra264` DT 和 BCT 安装检查，不能代替每块载板的完整 image 构建和实机刷写。

### 0.10 推荐目录布局

```text
tegra-demo-distro/                    # Git 源码
├── build-seeed-super-j401/          # Super J401 主示例，可重建
├── build-seeed-reserver-j501x-gmsl-sku0004/ # AGX SKU 示例，可重建
└── ...

yocto-seeed-cache/
├── downloads/                       # 所有 machine 共享，删除 build 后保留
└── sstate-cache/                     # 所有 machine 共享，删除 build 后保留

~/seeed-flash-<machine>/              # 临时刷写目录，刷完可删除
```

需要备份或分享时，只推送 Git commit。不要归档 `build-*`、共享缓存或刷写目录。

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
16. 扩展到新的 Seeed 或第三方载板
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

仓库中的 `meta-seeed` 当前覆盖三类 SoC/模块平台：

| 平台 | machine 数量 | 构建状态 | 实机状态 |
| --- | ---: | --- | --- |
| Jetson Orin NX/Nano | 8 | metadata、DTB/BCT 构建验证 | Super J401 已实机验证，其余未实机验证 |
| Jetson AGX Orin | 5 | metadata、DTB/BCT 构建验证 | 未实机验证 |
| Jetson Thor | 3 | metadata、DTB/BCT 构建验证 | 未实机验证 |

完整 machine/config 对照见 `layers/meta-seeed/docs/board-support-status.md`。本文后续代码仍以以下实机案例展开：

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

源 BSP 目录记为：

```text
/path/to/Linux_for_Tegra
```

关键入口文件是：

```text
/path/to/Linux_for_Tegra/recomputer-orin-super-j401.conf
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

当前多板 layer 的主要结构如下。为避免目录树过长，DT/BCT 文件只展示代表项：

```text
layers/meta-seeed/
├── classes-recipe/
│   └── seeed-recomputer-super-tegraflash.bbclass
├── conf/
│   ├── layer.conf
│   └── machine/
│       ├── include/
│       │   ├── seeed-agx-orin.inc
│       │   ├── seeed-orin-j401.inc
│       │   └── seeed-thor.inc
│       ├── recomputer-orin-super-j401.conf
│       ├── recomputer-industrial-orin-j401.conf
│       ├── recomputer-mini-agx-orin-j501x.conf
│       ├── recomputer-thor-carrier-j601.conf
│       └── ...                         # 共 16 个 machine
├── docs/
│   ├── DIY-YOcto-recomputer-orin-super-j401.md
│   └── board-support-status.md
└── recipes-bsp/
    ├── seeed-devicetree/
    │   ├── seeed-devicetree_1.0.bb
    │   └── seeed-devicetree/
    │       ├── tegra234-...-recomputer*.dts
    │       ├── tegra234-...-reserver*.dts
    │       ├── tegra264-...-recomputer-carrier.dts
    │       └── gmsl/
    └── tegra-binaries/
        ├── tegra-bootfiles_39.2.0.bbappend
        └── tegra-bootfiles/
            ├── recomputer-*-pinmux*.dts*
            ├── recomputer-*-padvoltage*.dts*
            ├── reserver-*-pinmux*.dtsi
            └── seeed-agx-orin-kit-*.dtsi
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
./scripts/seeed/build.sh metadata
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

```text
grep -R '^#include\|/include/' <vendor-dts-directory>
```

确保 recipe 的 `SRC_URI` 能提供所有非 NVIDIA 标准 include 文件。NVIDIA 已由 `meta-tegra` staged 的公共 DTS 可以复用，不必全部复制。

### 6.2 不要只检查编译成功

DTB 能编译不代表选择正确。至少检查：

```bash
./scripts/seeed/build.sh metadata
./scripts/seeed/build.sh dtb
```

预期生成：

```text
tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb
tegra234-p3767-camera-p3768-imx219-quad-seeed.dtbo
```

必要时反编译核对关键节点：

```text
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
./scripts/seeed/build.sh bootfiles
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

```text
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
./scripts/seeed/build.sh image
```

`demo-image-full` 包含 Python、OpenSSH、Docker、CUDA runtime、cuDNN、TensorRT、VPI 和示例程序，但它不是 Ubuntu，也不是完整的目标端 SDK。需要目标端 `nvcc` 和开发头文件时，构建 `seeed-image-jetson-development`；只需与参考包能力对齐时，构建 `seeed-image-jetson-runtime`。

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

### 9.4 可选：生成 PC 端交叉 SDK

仅当应用团队需要在 x86_64 PC 上交叉编译时执行。若使用
`seeed-image-jetson-development` 在 Jetson 板端直接编译，或只需要刷机运行，
跳过本节即可。

```bash
./scripts/seeed/build.sh sdk
```

输出位于：

```text
<active-build>/tmp/deploy/sdk/
```

应用团队可以安装 SDK 后交叉编译，不必在目标机安装 GCC/CMake。

## 10. 构建流程

第 0 章的 `scripts/seeed` 入口是本仓库推荐的实际操作方式。本章只说明脚本背后的 BitBake 阶段，不建议在同一个 build 目录中混用两套入口。

### 10.1 初始化环境

确认当前活动 build 和 machine：

```bash
./scripts/seeed/build.sh current
```

### 10.2 推荐的分阶段构建

先检查 metadata：

```bash
./scripts/seeed/build.sh metadata
```

再编译 DTB：

```bash
./scripts/seeed/build.sh dtb
```

再检查 bootfiles：

```bash
./scripts/seeed/build.sh bootfiles
```

最后构建镜像：

```bash
./scripts/seeed/build.sh image
```

成功示例：

```text
Tasks Summary: Attempted 13211 tasks ... all succeeded.
```

### 10.3 下载和 sstate 缓存

大型 Jetson Yocto 构建应通过 `prepare-workspace.sh --cache-dir` 共享：

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
  --module-sku 0000 \
  --build-dir build-seeed-super-j401 \
  --cache-dir "$HOME/.cache/yocto-seeed"
```

脚本会生成 `conf/seeed-cache.conf`，配置 `DL_DIR`、`SSTATE_DIR` 和 hash server。共享缓存可以避免重复下载 NVIDIA、kernel、CUDA 等大型组件，也有助于在网络不稳定时复用成功 fetch 的内容。

## 11. 构建后必须进行的静态验证

刷写前不要只看 `bitbake` 是否成功。

### 11.1 检查关键 BitBake 变量

```bash
./scripts/seeed/build.sh metadata
```

对于 Super J401 实机案例，关键变量预期为：

```text
MACHINE="recomputer-orin-super-j401"
PREFERRED_PROVIDER_virtual/dtb="seeed-devicetree"
KERNEL_DEVICETREE="tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb"
TEGRA_FLASHVAR_BPFDTB_FILE="tegra234-bpmp-3767-0000-3768-super.dtb"
TEGRA_FLASHVAR_PINMUX_CONFIG="recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi"
TEGRA_FLASHVAR_PMC_CONFIG="recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi"
TEGRA_FLASHVAR_DCE_OVERLAY="tegra234-dcb-p3767-0000-hdmi.dtbo"
```

### 11.2 找到、解压并校验 tegraflash 包

```bash
./scripts/seeed/prepare-flash.sh
```

它会从活动 build 的 `tmp/deploy/images/<machine>/` 找到当前 image 的 archive，解压到独立目录，并检查 `flashvars` 引用的关键文件。建议把输出目录放在主机本地 SSD，而不是 USB 移动硬盘。

### 11.3 Super J401 刷写变量参考

`prepare-flash.sh` 会自动打印当前 machine 的 `flashvars` 和 `.env.initrd-flash`。以下内容仅是已经完成实机验证的 Super J401 参考值，其他载板必须以脚本实际输出为准：

```text
BPFDTB_FILE="tegra234-bpmp-3767-0000-3768-super.dtb"
DTB_FILE="tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb"
PINMUX_CONFIG="recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi"
PMC_CONFIG="recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi"
DCE_OVERLAY="tegra234-dcb-p3767-0000-hdmi.dtbo"
ROOTFS_DEVICE="nvme0n1"
ROOTFS_IMAGE="demo-image-full.ext4"
```

### 11.4 检查所有引用文件存在

`prepare-flash.sh` 已经执行这一步。若需要手工复核，应在它打印的独立刷写目录中，根据当前 machine 的 `flashvars` 动态读取文件名，不要复制 Super J401 的固定文件名到其他载板。

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

- 先执行 `./scripts/seeed/build.sh current`，确认当前 build 和 machine；
- 确认 `build.sh current` 显示的 `DL_DIR` 是共享缓存，而不是刚创建的空目录；
- 如果已有成功构建的缓存，重新执行 `prepare-workspace.sh` 并指定同一个 `--cache-dir`；
- 使用 `git ls-remote` 检查目标分支是否可访问，再重试 `./scripts/seeed/build.sh dtb`；
- `Setscene tasks: ...` 是正常缓存恢复进度，不是错误；
- 若日志出现 `early EOF`、`unexpected disconnect`，通常是大型 Git 镜像下载断流，不要修改 machine 或 DTB 文件；
- 不要通过手工修改 fetch URL 掩盖版本不匹配。

本仓库当前 kernel fetch 的直接检查命令为：

```bash
git ls-remote \
  https://gitlab.com/nvidia/nv-tegra/3rdparty/canonical/linux-noble.git \
  refs/heads/l4t/l4t-r39.2-Ubuntu-nvidia-tegra-6.8.0-1021.21
```

### 14.2 `tegra-bootfiles:do_install` 找不到自定义文件

检查：

- `FILESEXTRAPATHS`；
- `SRC_URI` override 是否匹配 machine；
- 文件是否位于 `${THISDIR}/${BPN}`；
- `do_install` 使用的路径是否真实存在。

可以查看：

```bash
./scripts/seeed/build.sh bootfiles
```

脚本失败时再进入对应 BitBake task 日志检查 `FILESPATH`、`SRC_URI`、`UNPACKDIR` 和 `WORKDIR`，不要在未初始化的普通 shell 中直接运行 `bitbake -e`。

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

## 16. 将通用框架扩展到新的 Seeed 或第三方载板

本仓库已经为当前 L4T BSP 中的 16 个 Seeed config 建立默认 machine。本章适用于新增 module SKU、载板 revision，或继续接入 L4T 树中尚未出现的新载板；它描述的是**移植流程复用**，不是“一个 BSP 通刷所有载板”。通常可以复用：

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

开始新增移植前，先确认仓库中是否已有对应 machine：

```bash
./scripts/seeed/build.sh machines
```

如果已经存在，应优先验证或扩展该 machine，而不是重复创建。对于真正的新载板，合理目标是“沿用相同流程创建新的 machine 和板级文件”，而不是只修改 machine 名称后直接构建。

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

- 当前 16 个 machine 对应各 Seeed L4T config 的默认 module/SKU 组合；动态 EEPROM SKU 分支尚未全部拆分为独立 Yocto machine；
- 16 个 machine 已完成 metadata 解析，`tegra234`/`tegra264` DT 构建以及 BCT 安装验证；
- 只有 reComputer Super J401 + Orin NX 16GB 完成刷写、启动和基础外设实机验证；
- 本地 L4T 的双 IMX219 overlay 缺少 `tegra234-camera-rbpcv2-imx219.dtsi`，受影响 machine 暂不声明该 overlay 可构建；
- camera/GMSL、工业 I/O、网络、存储和电源模式仍需按具体硬件执行回归测试；
- `demo-image-full` 是演示镜像，不是最终产品镜像；
- 默认 root 空密码仅用于开发；
- 未在本文中完成 Secure Boot、量产密钥和完整 OTA 验证。

完成这些边界项后，才应把 BSP 标记为对应产品的正式量产版本。

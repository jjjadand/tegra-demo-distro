# Seeed Jetson Yocto 路线 B 构建任务规划

## 1. 目标

本任务以 Yocto/OE4T 作为唯一产品构建与发布入口，为仓库中全部 Seeed
Jetson 第三方载板生成可复现、可刷写、可验证的 Jetson Linux 产品包。

最终目标不是复制 NVIDIA Ubuntu/JetPack rootfs，也不是只为 NVIDIA
开发套件重新构建 `demo-image-full`，而是建立以下产品链：

```text
NVIDIA Jetson Linux / meta-tegra
                +
Seeed machine、DTB、DTBO、BCT、pinmux、flash variables
                +
Seeed JetPack runtime/development packagegroups
                +
Seeed runtime/development/production images
                ↓
按 Seeed MACHINE 生成 tegraflash、SDK、manifest、SBOM 和校验文件
```

完成后，每个 Seeed `MACHINE` 都应拥有独立的构建目录、镜像、刷写包和验证记录。
没有实机的载板只能标记为“构建验证/未实机验证”，不能声明硬件支持已验证。

> **当前状态：** 本文是路线 B 的产品化实施规划，不是已完成清单。当前仓库仍以
> `demo-image-full` 为默认 image；它已有 CUDA runtime/libraries、CUDA samples、
> TensorRT/VPI/MMAPI tests，并可通过 `populate_sdk` 生成包含 CUDA host tools 的
> OE4T 标准 SDK。本文规划的 Seeed runtime/development/production images、产品
> packagegroups 和发布 SDK 尚待实现，状态以第 10 节任务清单为准。

## 2. 参考输入及使用边界

### 2.1 NVIDIA/OE4T 参考包

当前参考输入是 NVIDIA/OE4T 生成的 tegraflash Zstandard 归档：

```text
$WORKSPACE_ROOT/demo-image-full-jetson-orin-nano-devkit-nvme.rootfs.tegraflash-tar.zst
```

分析前将其解压到独立的只读目录，例如：

```text
$WORKSPACE_ROOT/demo-image-full-jetson-orin-nano-devkit-nvme.rootfs.tegraflash
```

它是 `jetson-orin-nano-devkit-nvme` 的 OE4T `tegrademo/wrynose`
参考镜像，使用 Jetson Linux R39.2。该包用于建立以下基线：

- Jetson Linux 固件、UEFI、BPMP、OP-TEE 和 initrd-flash 归档结构。
- CUDA、cuDNN、TensorRT、VPI、OpenCV 和多媒体运行时组件集合。
- Docker、NVIDIA Container Toolkit 和 NVIDIA Container Runtime 集成方式。
- X11/Sato 演示环境和 NVIDIA 测试程序的镜像组织方式。
- tegraflash archive 的文件完整性和发布形式。

该包不能直接作为 Seeed 产品包，以下内容必须由对应 Seeed `MACHINE` 重新生成：

- carrier DTB、DTBO 和 camera/GMSL overlays。
- BPMP DTB、BCT、pinmux、pad-voltage 和 ODMDATA。
- `flashvars`、`.env.initrd-flash`、分区 XML 和 board identity。
- `boot.img`、initrd、rootfs、tegraflash archive 和 SDK。

参考包只用于比较组件和归档结构，不提交进 Git，也不从中复制 NVIDIA
开发套件的板级二进制文件覆盖 Seeed machine 输出。

### 2.2 Seeed BSP 源

Seeed 板级文件的源 BSP 为：

```text
$WORKSPACE_ROOT/Linux_for_Tegra
```

仓库中的 `meta-seeed` 是产品构建时的实际输入。每项导入文件都必须能够追溯到：

1. 原始 Seeed L4T board config。
2. 原始 DT/DTSI、overlay、BCT 或 pinmux 文件。
3. 对应 Yocto `MACHINE` 和 BitBake 变量。
4. 构建验证及实机验证状态。

## 3. 支持范围

当前计划覆盖 `layers/meta-seeed/conf/machine` 中的全部 16 个 machine：

### 3.1 Orin NX/Nano

- `recomputer-industrial-orin-j401`
- `recomputer-orin-j401`
- `recomputer-orin-j40mini`
- `recomputer-orin-robotics-j401`
- `recomputer-orin-robotics-j401-gmsl`
- `recomputer-orin-super-j401`
- `recomputer-rugged-orin-j401`
- `reserver-industrial-orin-j401`

### 3.2 AGX Orin

- `recomputer-mini-agx-orin-j501x`
- `recomputer-robo-agx-orin-j501x`
- `reserver-agx-orin-j501x`
- `reserver-agx-orin-j501x-gmsl`
- `seeed-agx-orin-kit`

### 3.3 Thor

- `recomputer-thor-carrier-j601`
- `recomputer-thor-carrier-j6014`
- `recomputer-thor-carrier-j6015`

不同 module SKU 只有在 DTB、BCT、flash variables 和刷写流程均完成映射后，
才能新增为独立 machine 或经过验证的 machine override。不得使用一个默认 SKU
输出冒充同一载板的全部 module SKU。

## 4. 工作目录规划

### 4.1 源码目录

```bash
WORKSPACE_ROOT=/path/to/jetson-workspace
REPO_ROOT=$WORKSPACE_ROOT/seeed-tegra-demo-distro/tegra-demo-distro
L4T_ROOT=$WORKSPACE_ROOT/Linux_for_Tegra
REFERENCE_TEGRAFLASH_ZST=$WORKSPACE_ROOT/demo-image-full-jetson-orin-nano-devkit-nvme.rootfs.tegraflash-tar.zst
REFERENCE_TEGRAFLASH_DIR=$WORKSPACE_ROOT/demo-image-full-jetson-orin-nano-devkit-nvme.rootfs.tegraflash
CACHE_ROOT=$HOME/.cache/yocto-seeed
RELEASE_ROOT=$WORKSPACE_ROOT/yocto-seeed-release
```

`REPO_ROOT` 是唯一允许修改和提交 Yocto metadata 的目录。`L4T_ROOT`、
`REFERENCE_TEGRAFLASH_ZST` 与 `REFERENCE_TEGRAFLASH_DIR` 作为只读输入使用。

### 4.2 每 machine 独立构建目录

禁止不同 machine 共用同一个 `TMPDIR`。构建目录统一命名为：

```text
$REPO_ROOT/build-seeed-<machine-short-name>
```

例如：

```text
build-seeed-super-j401
build-seeed-industrial-j401
build-seeed-robotics-j401
build-seeed-reserver-j501x-gmsl
```

下载缓存和 sstate 缓存可以共享：

```text
$CACHE_ROOT/downloads
$CACHE_ROOT/sstate-cache
```

准备一个 machine：

```bash
cd "$REPO_ROOT"

./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
  --module-sku 0000 \
  --build-dir build-seeed-super-j401 \
  --cache-dir "$CACHE_ROOT"

./scripts/seeed/build.sh current
```

`prepare-workspace.sh` 成功后，该 build 目录成为活动目录。J401 machine 支持
P3767 `0000`、`0001`、`0003`、`0004` 四个 Orin NX/Nano module SKU；AGX Orin
machine 也支持多个 module SKU。准备 build 目录时必须传 `--module-sku`，并把
选择固化到该目录。后续命令默认使用该 machine 和 module SKU，不需要反复传递
参数。临时操作其他 build 目录时使用
`--build-dir` 和 `--no-activate`，不能修改原 build 目录中的 `MACHINE`。

### 4.3 磁盘规划

建议预留：

- 共享 downloads：至少 80 GiB。
- 共享 sstate：至少 200 GiB，并定期按发布周期清理。
- 单个 Orin machine 完整构建：至少 150 GiB 可用空间。
- Thor 和并行 machine 构建：根据实际构建峰值额外预留空间。
- release 目录：至少能保存当前版本及上一个版本的全部刷写包和 SDK。

已验证且不再需要的旧 build 目录可以删除；保留 downloads、sstate 和最终 release
产物即可。删除前必须确认所需 tegraflash archive、SDK、manifest 和日志已经发布。

## 5. 需要加入 Yocto 的产品 metadata

本阶段不修改 `meta-tegra` 上游内容。Seeed 产品相关内容进入
`layers/meta-seeed`，通用演示内容继续由 `meta-tegrademo` 提供。

建议目标结构：

```text
layers/meta-seeed/
├── conf/
│   ├── layer.conf
│   └── machine/
├── classes-recipe/
├── recipes-bsp/
│   ├── seeed-devicetree/
│   └── tegra-binaries/
├── recipes-core/
│   ├── images/
│   └── packagegroups/
├── recipes-containers/
├── recipes-support/
├── recipes-tests/
└── docs/
```

### 5.1 BSP 层产物

每个 machine 必须具备：

- machine `.conf`。
- SoC/module 公共 include。
- carrier DTB 和必要 DTBO。
- BPMP DTB/BPMP firmware 选择。
- pinmux、pad-voltage、GPIO 和必要 BCT 文件。
- ODMDATA、board ID、SKU、FAB 和默认 flash variables。
- 内置存储或 NVMe/external-device 分区及 initrd-flash 配置。
- tegraflash image class 集成。

现有 BSP metadata 继续保留，后续任务重点是逐 machine 复核完整性，不用为不同
产品镜像复制 machine 文件。

### 5.2 Packagegroup 规划

新增 packagegroup 时应按能力拆分，避免一个不可裁剪的超大包组。

#### `packagegroup-seeed-jetson-runtime`

目标运行时基础：

- Jetson Linux 用户态驱动和 Tegra 配置。
- CUDA runtime libraries。
- cuDNN runtime。
- TensorRT runtime、plugins 和 `trtexec`。
- VPI runtime。
- OpenCV runtime。
- GStreamer 及 NVIDIA 硬件编解码插件。
- Argus、Jetson Multimedia API 和必要摄像头服务。
- Vulkan、EGL、OpenGL ES 和显示运行时。

#### `packagegroup-seeed-jetson-containers`

- Docker/Moby runtime。
- NVIDIA Container Toolkit。
- NVIDIA Container Runtime。
- 默认 daemon/runtime 配置。
- 容器运行 smoke test。

#### `packagegroup-seeed-jetson-development`

- `cuda-toolkit` 和 `nvcc`。
- CUDA、cuDNN、TensorRT、VPI 和 OpenCV 开发头文件。
- `packagegroup-core-buildessential`。
- CMake、Ninja、pkg-config、Git 和调试工具。
- Python 3、pip、开发头文件及基础科学计算工具。
- NVIDIA 示例和诊断程序。

开发包名称必须通过当前 wrynose/meta-tegra recipe 实际解析确认，不照搬 Ubuntu
中的 DEB 包名。

#### `packagegroup-seeed-jetson-tests`

- CUDA runtime 测试。
- TensorRT tests。
- VPI tests。
- Tegra Multimedia API tests。
- OpenCV/GStreamer/NVIDIA container smoke tests。
- Seeed carrier 外设检查脚本。

#### 可选高层组件

DeepStream、Holoscan、PyTorch、Triton 等组件单独放入可选 packagegroup，不能让
基础 BSP 镜像因高层框架失败而无法构建。每个组件必须记录许可证、下载源、版本、
构建时间、磁盘占用和是否完成实机验证。

### 5.3 Image 规划

#### `seeed-image-jetson-runtime`

用于功能验证和一般产品运行：

- 基础系统、SSH、systemd 和网络。
- `packagegroup-seeed-jetson-runtime`。
- `packagegroup-seeed-jetson-containers`。
- 轻量诊断工具。
- 默认不包含目标机编译器和完整 CUDA toolkit。

#### `seeed-image-jetson-development`

用于板上开发和 BSP/AI 调试：

- 继承 runtime image。
- `packagegroup-seeed-jetson-development`。
- `packagegroup-seeed-jetson-tests`。
- 可选 X11/Sato 或 Wayland/Weston 图形环境。
- 保留日志、调试、性能分析和示例程序。

它应比当前 `demo-image-full` 更适合目标机开发，但仍然是 Yocto，不提供 Ubuntu
APT 软件仓库，也不声明与 Ubuntu JetPack rootfs 完全一致。

#### `seeed-image-jetson-production`

用于正式产品发布：

- 从 runtime image 裁剪，不继承 development image。
- 只加入产品需要的 AI、多媒体、容器和应用组件。
- 删除编译器、测试程序、示例、无用服务和默认调试账号。
- 启用产品用户、密钥、日志策略和必要的安全配置。
- 后续接入 secure boot、磁盘加密、A/B 和 OTA。

第一阶段先完成 runtime 和 development；production 在组件及实机矩阵稳定后进入。

### 5.4 SDK 规划

每个发布 machine 至少生成 development image 对应的标准 SDK：

```bash
./scripts/seeed/build.sh sdk --image seeed-image-jetson-development
```

SDK 应包含：

- AArch64 交叉编译工具链。
- CMake/pkg-config toolchain environment。
- CUDA host tools。
- CUDA、cuDNN、TensorRT、VPI、OpenCV 和 GStreamer sysroot headers/libs。
- 与目标 image 一致的版本信息。

后续根据应用团队需求评估 eSDK。标准 SDK 验证通过前，不把 eSDK 作为发布阻塞项。

## 6. 构建任务阶段

### 阶段 0：冻结参考基线

- 记录 tegra-demo-distro、meta-tegra、meta-openembedded 和 BitBake commit。
- 记录 Jetson Linux、kernel、CUDA、cuDNN、TensorRT、VPI 版本。
- 保存参考 `demo-image-full` 的文件树和组件报告，不保存完整 rootfs 副本到 Git。
- 输出参考包与计划 image 的组件差异表。

完成条件：所有后续 packagegroup 均能说明来自参考包、产品需求或显式新增需求。

### 阶段 1：创建产品 packagegroup 和 image

- 新增 runtime、containers、development 和 tests packagegroup。
- 新增 runtime 与 development image。
- 复用 `meta-tegra` recipe，不复制 CUDA/TensorRT recipe 到 `meta-seeed`。
- 使用 `RRECOMMENDS` 处理可选功能，核心启动和驱动依赖使用明确依赖。

完成条件：NVIDIA devkit machine 可解析两个新 image，用于隔离 image metadata
错误；该结果只作为通用组件验证，不代表 Seeed 板卡发布完成。

### 阶段 2：接入全部 Seeed machine

对每个 Seeed machine 执行：

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine <seeed-machine> \
  --module-sku <module-sku> \
  --build-dir build-seeed-<short-name> \
  --cache-dir "$CACHE_ROOT"

./scripts/seeed/build.sh metadata --image seeed-image-jetson-runtime
./scripts/seeed/build.sh dtb --image seeed-image-jetson-runtime
./scripts/seeed/build.sh bootfiles --image seeed-image-jetson-runtime
```

完成条件：最终 metadata 中的 `MACHINE`、DTB、BPMP、pinmux、PMC、ODMDATA、
overlays 和 flash image class 均来自当前 Seeed machine。

### 阶段 3：构建 runtime image

```bash
./scripts/seeed/build.sh image --image seeed-image-jetson-runtime
```

检查：

- rootfs 发行版身份为 Yocto/OE4T 产品发行版。
- CUDA、cuDNN、TensorRT、VPI、OpenCV 和 GStreamer runtime 存在。
- Docker 和 NVIDIA Container Runtime 可按镜像设计启用。
- rootfs 中没有意外安装完整编译工具链。
- tegraflash archive 使用当前 Seeed machine 的 flash variables。

### 阶段 4：构建 development image 和 SDK

```bash
./scripts/seeed/build.sh image --image seeed-image-jetson-development
./scripts/seeed/build.sh sdk --image seeed-image-jetson-development
```

检查：

- 目标机存在 `nvcc`、编译器、CMake、headers 和调试工具。
- SDK 能在干净 shell 中编译 CUDA、TensorRT、VPI 和 GStreamer 示例。
- SDK 生成程序能够在相同 machine 的 runtime/development image 上运行。

### 阶段 5：生成并检查刷写包

```bash
./scripts/seeed/build.sh flash-package --image seeed-image-jetson-runtime

./scripts/seeed/prepare-flash.sh \
  --machine <seeed-machine> \
  --build-dir build-seeed-<short-name> \
  --image seeed-image-jetson-runtime
```

每个 tegraflash archive 至少检查：

- `.env.initrd-flash` 中的 `MACHINE` 和 rootfs image。
- `flashvars` 中的 DTB、BPMP、BCT、pinmux 和 pad-voltage。
- `boot.img`、rootfs ext4、initrd-flash 和分区 XML。
- 所有 flashvars 引用文件均存在且非空。
- archive 文件名中包含 image 和 Seeed machine。

### 阶段 6：静态和实机验证

静态验证：

```bash
./scripts/seeed/validate-all-machines.sh
```

逐 machine 记录：

- metadata parse。
- DTB/DTBO compile。
- bootfiles install。
- runtime image build。
- development image build。
- SDK build。
- tegraflash archive integrity。

实机验证至少包括：

- initrd-flash 和首次启动。
- NVMe/eMMC/rootfs 挂载。
- Ethernet、USB、PCIe、HDMI/DP、RTC、风扇和 GPIO。
- 对应载板的 CSI、GMSL、CAN、串口及其他特有接口。
- CUDA、TensorRT、VPI、多媒体和容器 smoke tests。
- 冷启动、重启和连续运行稳定性。

没有实机的 machine 保持“构建验证/未实机验证”。

### 阶段 7：生产镜像和发布

runtime/development 稳定后，建立 production image，并生成正式发布目录：

```text
$RELEASE_ROOT/<release-id>/<machine>/
├── images/
│   ├── seeed-image-jetson-runtime-<machine>.rootfs.tegraflash-tar.zst
│   ├── seeed-image-jetson-development-<machine>.rootfs.tegraflash-tar.zst
│   └── seeed-image-jetson-production-<machine>.rootfs.tegraflash-tar.zst
├── sdk/
│   └── seeed-image-jetson-development-<machine>-toolchain.sh
├── manifests/
│   ├── image.manifest
│   ├── image.spdx.json
│   ├── build-versions.txt
│   └── flashvars.txt
├── checksums/
│   └── SHA256SUMS
├── logs/
│   └── validation-summary.md
└── RELEASE_NOTES.md
```

只有成功发布到 `RELEASE_ROOT` 的文件才属于交付产物。`tmp/deploy` 是构建输出，
不能作为长期归档或对外发布目录。

## 7. 最终交付包

每个已发布 Seeed machine 至少交付：

1. runtime tegraflash archive。
2. development tegraflash archive。
3. 对应 development SDK installer。
4. package manifest。
5. SPDX/SBOM 输出。
6. SHA-256 校验文件。
7. BSP、Yocto layers 和 NVIDIA 组件版本清单。
8. machine 的 DTB/BCT/flashvars 摘要。
9. 构建验证与实机验证状态。
10. 刷写及首次启动说明。

production image 在安全、账号、升级和产品应用策略确认后加入必选交付项。

## 8. 验收门槛

### 8.1 通用门槛

- 产品 image 不依赖修改后的 `meta-tegra` 工作树。
- 所有产品差异均位于 `meta-seeed` 或明确的产品 layer。
- clean build 能使用固定 commits 和共享下载缓存重新生成。
- 相同 machine 和配置重复构建具有可解释的一致性。
- tegraflash archive 内不存在 NVIDIA devkit carrier DTB 冒充 Seeed DTB。

### 8.2 Runtime 门槛

- 可启动并进入 systemd userspace。
- NVIDIA 驱动、CUDA、TensorRT、VPI 和多媒体 smoke tests 通过。
- container runtime 能调用 NVIDIA runtime。
- rootfs 未意外包含开发镜像专用工具。

### 8.3 Development 门槛

- `nvcc`、C/C++ 编译器和 CMake 可用。
- 设备端可以编译并运行最小 CUDA 程序。
- Yocto SDK 可以交叉编译并部署最小 CUDA/TensorRT 程序。
- SDK 与目标 rootfs 的 headers、libraries 和 ABI 匹配。

### 8.4 板级门槛

- metadata 中所有 flash variables 与当前 Seeed machine 匹配。
- DTB/DTBO 和 BCT 文件来自 `meta-seeed` 的对应板级配置。
- 刷写包完整性检查通过。
- 支持状态文档明确区分构建验证与实机验证。

## 9. 实施顺序

建议按以下顺序执行，避免同时扩大板级和软件栈风险：

1. 以已实机启动的 `recomputer-orin-super-j401` 验证 runtime image。
2. 在同一 machine 上验证 development image 和 SDK。
3. 已用 `reserver-agx-orin-j501x-gmsl` + AGX Orin SKU `0004` 完成刷机和启动验证；继续补齐 GMSL 与其他外设验证。
4. 用一个 Thor machine 验证 tegra264 软件和刷写路径。
5. 对全部 16 个 machine 执行静态构建矩阵。
6. 根据可获得实机逐板完成外设验证。
7. 建立 production image、SBOM、checksums 和 release 目录。

## 10. 当前任务清单

- [ ] 生成参考 `demo-image-full` 组件清单和差异报告。
- [ ] 新增 runtime、containers、development、tests packagegroups。
- [ ] 新增 runtime 和 development image recipes。
- [ ] 为新 image 补充 SDK host/target task。
- [ ] 扩展构建脚本的 image/SDK/发布产物检查。
- [ ] 在 `recomputer-orin-super-j401` 完成 runtime 构建。
- [ ] 在 `recomputer-orin-super-j401` 完成 development 和 SDK 构建。
- [ ] 在 AGX Orin 和 Thor 各选一个 machine 完成构建验证。
- [ ] 全量解析和构建 16 个 Seeed machine。
- [ ] 生成逐 machine tegraflash archive 完整性报告。
- [ ] 建立 release 目录、manifest、SBOM 和 SHA-256 发布流程。
- [ ] 更新板级支持状态和用户构建/刷写教程。

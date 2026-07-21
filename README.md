# tegra-demo-distro

Reference/demo distribution for NVIDIA Jetson platforms
using Yocto Project tools and the [meta-tegra](https://github.com/OE4T/meta-tegra) BSP layer.

## Seeed Carrier BSP Support

This workspace includes `meta-seeed` machine definitions for all 16 Seeed
carrier configurations in the matching L4T BSP. The reComputer Super J401 has
completed physical flash and basic peripheral validation; the reServer J501X
GMSL with AGX Orin SKU 0004 has completed physical flash and boot validation.
See the
[support matrix](layers/meta-seeed/docs/board-support-status.md) and the
[end-to-end Chinese BSP guide](layers/meta-seeed/docs/DIY-YOcto-recomputer-orin-super-j401.md).

### Carrier and module parameters

The current Seeed helper supports the following carrier-board `MACHINE`
values. J401 carrier machines accept the four NVIDIA Orin NX/Nano module SKUs
listed below; AGX Orin machines accept their listed SKUs. Use one build
directory for each carrier and module combination. Thor carrier machines are
currently fixed to the module shown in their machine file.

| Carrier board | `MACHINE` | Module configuration | `--module-sku` |
| --- | --- | --- | --- |
| reComputer Industrial J401 | `recomputer-industrial-orin-j401` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Mini AGX Orin J501X | `recomputer-mini-agx-orin-j501x` | AGX Orin `P3701-0004`/`P3701-0005` | `0004` or `0005` |
| reComputer Orin J401 | `recomputer-orin-j401` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Orin J40mini | `recomputer-orin-j40mini` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Robotics J401 | `recomputer-orin-robotics-j401` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Robotics J401 GMSL | `recomputer-orin-robotics-j401-gmsl` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Super J401 | `recomputer-orin-super-j401` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Robo AGX Orin J501X | `recomputer-robo-agx-orin-j501x` | AGX Orin `P3701-0004`/`P3701-0005` | `0004` or `0005` |
| reComputer Rugged Orin J401 | `recomputer-rugged-orin-j401` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| reComputer Thor Carrier J601 | `recomputer-thor-carrier-j601` | AGX Thor, `P3834-0008` | 不传 |
| reComputer Thor Carrier J6014 | `recomputer-thor-carrier-j6014` | AGX Thor, `P3834-0000` | 不传 |
| reComputer Thor Carrier J6015 | `recomputer-thor-carrier-j6015` | AGX Thor, `P3834-0008` | 不传 |
| reServer AGX Orin J501X | `reserver-agx-orin-j501x` | AGX Orin | `0000`, `0001`, `0002`, `0004`, or `0005` |
| reServer AGX Orin J501X GMSL | `reserver-agx-orin-j501x-gmsl` | AGX Orin | `0000`, `0001`, `0002`, `0004`, or `0005` |
| reServer Industrial Orin J401 | `reserver-industrial-orin-j401` | Orin NX/Nano `P3767-0000`/`0001`/`0003`/`0004` | `0000`, `0001`, `0003`, or `0004` |
| Seeed AGX Orin Kit | `seeed-agx-orin-kit` | AGX Orin | `0000`, `0001`, `0002`, `0004`, or `0005` |

For example, Super J401 must select the module explicitly. NVIDIA's 39.2.0
configuration maps the P3768 carrier to P3767 module SKUs `0000`, `0001`,
`0003`, and `0004`. Select the SKU explicitly and use a separate build
directory for each choice:

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
  --module-sku 0000 \
  --build-dir build-seeed-super-j401-sku0000
```

Quick start from a clean checkout:

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
  --module-sku 0000 \
  --build-dir build-seeed-super-j401
./scripts/seeed/build.sh metadata --build-dir build-seeed-super-j401
./scripts/seeed/build.sh dtb --build-dir build-seeed-super-j401
./scripts/seeed/build.sh image --build-dir build-seeed-super-j401
./scripts/seeed/prepare-flash.sh \
  --build-dir build-seeed-super-j401 \
  --output-dir ~/seeed-flash-recomputer-orin-super-j401
```

For the complete Chinese build, flash, validation, and troubleshooting guide,
see [DIY-YOcto-recomputer-orin-super-j401.md](layers/meta-seeed/docs/DIY-YOcto-recomputer-orin-super-j401.md).
The shorter script reference is [scripts/seeed/README.md](scripts/seeed/README.md).

The Super J401 example currently targets the Jetson Orin NX 16GB module
(`P3767-0000`) through the selected module SKU. J401 machines accept
`0000`, `0001`, `0003`, and `0004`; AGX Orin carrier configurations support
their machine-specific SKU sets. Always select the module while preparing a
separate build directory, for example:

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine reserver-agx-orin-j501x-gmsl \
  --module-sku 0004 \
  --build-dir build-seeed-reserver-j501x-gmsl-sku0004
```

The upstream `demo-image-full` remains the NVIDIA/OE4T reference baseline. It
includes CUDA runtime libraries, samples, TensorRT/VPI/MMAPI tests, OpenCV,
multimedia, and container support, but it does not contain target-side `nvcc`
or the complete CUDA/cuDNN/TensorRT/VPI development headers.

Route B now provides two Seeed images:

- `seeed-image-jetson-runtime` aligns with the reference runtime, sample, and
  test package selections without installing the target compiler toolchain.
- `seeed-image-jetson-development` adds `cuda-toolkit`, target-side `nvcc`,
  CUDA/cuDNN/TensorRT/VPI/OpenCV development files, build/debug tools, samples,
  and tests. Its `populate_sdk` output also contains CUDA host tools and the
  matching AArch64 development sysroot.

These remain Yocto/OE4T images, not Ubuntu JetPack SDK Manager root filesystems.
See the [reference audit](layers/meta-seeed/docs/nvidia-demo-image-full-reference.md)
and [Route B document](layers/meta-seeed/docs/yocto-route-b-build-plan.md).

For the generic upstream tegrademo workflow, continue with:

```bash
./scripts/seeed/prepare-workspace.sh
./scripts/seeed/build.sh metadata
./scripts/seeed/build.sh dtb
./scripts/seeed/build.sh image
./scripts/seeed/prepare-flash.sh
```

Build output, downloads, sstate, rootfs images, and extracted flash packages are intentionally not stored in Git.

![Build status](https://builder.madison.systems/badges/tegrademo-wrynose.svg)

Metadata layers are brought in as git submodules:

| Layer Repo            | Branch                  | Description                                         |
| --------------------- | ------------------------|---------------------------------------------------- |
| bitbake               | wrynose                 | bitbake tool                                        |
| openembedded-core     | wrynose                 | OE-Core                                             |
| meta-tegra            | wrynose                 | L4T BSP layer - L4T R39.2.0/JetPack 7.2             |
| meta-tegra-community  | wrynose                 | OE4T layer with additions from the community        |
| meta-openembedded     | wrynose                 | OpenEmbedded layers                                 |
| meta-virtualization   | wrynose                 | Virtualization layer for docker support             |

## Prerequisites

See the [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html)
documentation for information on setting up your build host.

See the [Flashing Basics](https://oe4t.github.io/wrynose/Flashing.html) page for information on
packages needed for flashing.

## Setting up

1. Clone this repository:

        $ git clone https://github.com/jjjadand/seeed-tegra-demo-distro.git
        $ cd seeed-tegra-demo-distro

2. Use the `master` branch for the Seeed carrier-board extensions:

        $ git switch master

3. Prepare the default Seeed build workspace. This initializes the required
   submodules and configures the Super J401 machine for Jetson Orin NX 16GB:

        $ ./scripts/seeed/prepare-workspace.sh \
              --machine recomputer-orin-super-j401 \
              --module-sku 0000 \
              --build-dir build-seeed-super-j401

   The script defaults to this machine, so the explicit options can be omitted
   when using the standard Super J401 example.

4. Build the metadata, DTB, image, and flash package:

        $ ./scripts/seeed/build.sh all --build-dir build-seeed-super-j401
        $ ./scripts/seeed/prepare-flash.sh \
              --build-dir build-seeed-super-j401 \
              --output-dir ~/seeed-flash-recomputer-orin-super-j401

   For J401 and AGX Orin machines with multiple module SKUs, pass
   `--module-sku` while preparing a separate build directory. See the quick
   start above and the
   [complete BSP guide](layers/meta-seeed/docs/DIY-YOcto-recomputer-orin-super-j401.md)
   for the module-selection rules.

5. Optional: Install pre-commit hook for commit autosigning using

        $ ./scripts-setup/setup-git-hooks

## Distributions

The Seeed helper scripts use the `tegrademo` distribution by default. For an
advanced generic Yocto build, customize the `DISTRO` setting in your
`$BUILDDIR/conf/local.conf`, or pass the corresponding options directly to
`setup-env`.

Currently supported distributions are listed below:


| Distribution name | Description                                                   |
| ----------------- | ------------------------------------------------------------- |
| tegrademo         | Default distro used to demonstrate/test meta-tegra features   |

## Images

The `tegrademo` distro includes the following image recipes, which
are dervied from the `core-image-XXX` recipes in OE-Core but configured
for Jetson platforms. They include some additional test tools and
demo applications.

| Recipe name       | Description                                                   |
| ----------------- | ------------------------------------------------------------- |
| demo-image-base   | Basic image with no graphics                                  |
| demo-image-egl    | Base with DRM/EGL graphics, no window manager                 |
| demo-image-sato   | X11 image with Sato UI                                        |
| demo-image-weston | Wayland with Weston compositor                                |
| demo-image-full   | Sato image plus nvidia-docker, openCV, multimedia API samples |
| seeed-image-jetson-runtime | Seeed runtime aligned with the OE4T/NVIDIA reference stack |
| seeed-image-jetson-development | Runtime plus complete target CUDA development SDK and tests |

### Update image demo

A [swupdate](https://sbabic.github.io/swupdate/) demo image is also available which supports
A/B rootfs updates to any of the supported images.  For details refer to
[layers/meta-tegrademo/dynamic-layers/meta-swupdate/README.md](layers/meta-tegrademo/dynamic-layers/meta-swupdate/README.md).

# Contributing

Please see the [contributing guide in our documentation](https://oe4t.github.io/master/CONTRIBUTING.html).

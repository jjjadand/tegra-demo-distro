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

Quick start from a clean checkout:

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
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
(`P3767-0000`) through its machine configuration, so it does not accept or
need `--module-sku`. AGX Orin carrier configurations that support multiple
module SKUs must select the module while preparing a separate build directory,
for example:

```bash
./scripts/seeed/prepare-workspace.sh \
  --machine reserver-agx-orin-j501x-gmsl \
  --module-sku 0004 \
  --build-dir build-seeed-reserver-j501x-gmsl-sku0004
```

The default `demo-image-full` includes CUDA runtime libraries and samples,
TensorRT/VPI components, and Tegra multimedia API tests. `build.sh sdk`
generates the standard OE4T/Yocto cross-development SDK with CUDA host tools;
it is not an Ubuntu JetPack SDK Manager environment. The productized Route B
images, package groups, and per-machine release SDK are documented as a plan
in [yocto-route-b-build-plan.md](layers/meta-seeed/docs/yocto-route-b-build-plan.md)
and are not all implemented yet.

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
              --build-dir build-seeed-super-j401

   The script defaults to this machine, so the explicit options can be omitted
   when using the standard Super J401 example.

4. Build the metadata, DTB, image, and flash package:

        $ ./scripts/seeed/build.sh all --build-dir build-seeed-super-j401
        $ ./scripts/seeed/prepare-flash.sh \
              --build-dir build-seeed-super-j401 \
              --output-dir ~/seeed-flash-recomputer-orin-super-j401

   For AGX Orin machines with multiple module SKUs, pass `--module-sku` while
   preparing a separate build directory. See the quick start above and the
   [complete BSP guide](layers/meta-seeed/docs/DIY-YOcto-recomputer-orin-super-j401.md)
   for the module-selection rules.

5. Optional: Install pre-commit hook for commit autosigning using

        $ ./scripts-setup/setup-git-hooks

## Distributions

Use the `--distro` option with `setup-env` to specify a distribution for your build,
or customize the DISTRO setting in your `$BUILDDIR/conf/local.conf` to reference one
of the supported distributions.

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

### Update image demo

A [swupdate](https://sbabic.github.io/swupdate/) demo image is also available which supports
A/B rootfs updates to any of the supported images.  For details refer to
[layers/meta-tegrademo/dynamic-layers/meta-swupdate/README.md](layers/meta-tegrademo/dynamic-layers/meta-swupdate/README.md).

# Contributing

Please see the [contributing guide in our documentation](https://oe4t.github.io/master/CONTRIBUTING.html).

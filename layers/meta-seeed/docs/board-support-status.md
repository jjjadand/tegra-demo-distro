# Seeed Jetson board support status

All 16 Seeed `Linux_for_Tegra` board configurations have a dedicated Yocto
machine, carrier DTB selection, flash-variable mapping, and imported BCT files.
The status below deliberately separates build validation from hardware claims.

## Hardware validated

| Yocto MACHINE | Seeed L4T config | Validation |
| --- | --- | --- |
| `recomputer-orin-super-j401` | `recomputer-orin-super-j401.conf` | Build, initrd-flash, NVMe boot, HDMI and basic USB validated |

## Build validated, not hardware validated

| Yocto MACHINE | Seeed L4T config | SoC family |
| --- | --- | --- |
| `recomputer-industrial-orin-j401` | `recomputer-industrial-orin-j401.conf` | Orin NX/Nano |
| `recomputer-orin-j401` | `recomputer-orin-j401.conf` | Orin NX/Nano |
| `recomputer-orin-j40mini` | `recomputer-orin-j40mini.conf` | Orin NX/Nano |
| `recomputer-orin-robotics-j401` | `recomputer-orin-robotics-j401.conf` | Orin NX/Nano |
| `recomputer-orin-robotics-j401-gmsl` | `recomputer-orin-robotics-j401-gmsl.conf` | Orin NX/Nano |
| `recomputer-rugged-orin-j401` | `recomputer-rugged-orin-j401.conf` | Orin NX/Nano |
| `reserver-industrial-orin-j401` | `reserver-industrial-orin-j401.conf` | Orin NX/Nano |
| `recomputer-mini-agx-orin-j501x` | `recomputer-mini-agx-orin-j501x.conf` | AGX Orin |
| `recomputer-robo-agx-orin-j501x` | `recomputer-robo-agx-orin-j501x.conf` | AGX Orin |
| `reserver-agx-orin-j501x` | `reserver-agx-orin-j501x.conf` | AGX Orin |
| `reserver-agx-orin-j501x-gmsl` | `reserver-agx-orin-j501x-gmsl.conf` | AGX Orin |
| `seeed-agx-orin-kit` | `seeed-agx-orin-kit.conf` | AGX Orin |
| `recomputer-thor-carrier-j601` | `recomputer-thor-carrier-j601.conf` | Thor T5000 |
| `recomputer-thor-carrier-j6014` | `recomputer-thor-carrier-j6014.conf` | Thor T4000 |
| `recomputer-thor-carrier-j6015` | `recomputer-thor-carrier-j6015.conf` | Thor T5000 |

Validation performed:

1. BitBake metadata parses for every machine.
2. The full `tegra234` Seeed DTB/DTBO set compiles.
3. The full `tegra264` Seeed DTB set compiles.
4. Custom pinmux/pad-voltage files install into the tegraflash sysroot.

Known source limitation: the local L4T dual-IMX219 Seeed overlay includes
`tegra234-camera-rbpcv2-imx219.dtsi`, but that dependency is absent from the
provided BSP tree. The two affected machines therefore keep their carrier DTB
and HDMI overlay but do not advertise the unbuildable dual-camera overlay.

Run the matrix check with:

```bash
./scripts/seeed/validate-all-machines.sh
```

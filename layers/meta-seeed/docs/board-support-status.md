# Seeed Jetson board support status

This table distinguishes files available in the local Seeed
`Linux_for_Tegra` BSP from boards actually ported and validated in
`meta-seeed`.

## Validated

| Yocto MACHINE | Seeed L4T config | Module | Status |
| --- | --- | --- | --- |
| `recomputer-orin-super-j401` | `recomputer-orin-super-j401.conf` | Jetson Orin NX 16GB / P3767-0000 | Build, initrd-flash, NVMe boot, HDMI and basic USB validated |

## Source available, Yocto port not yet validated

| Family | Seeed L4T config |
| --- | --- |
| Orin NX/Nano carrier | `recomputer-orin-j401.conf` |
| Orin NX/Nano mini | `recomputer-orin-j40mini.conf` |
| Orin NX/Nano industrial | `recomputer-industrial-orin-j401.conf` |
| Orin NX/Nano industrial | `reserver-industrial-orin-j401.conf` |
| Orin NX/Nano rugged | `recomputer-rugged-orin-j401.conf` |
| Orin NX/Nano robotics | `recomputer-orin-robotics-j401.conf` |
| Orin NX/Nano robotics GMSL | `recomputer-orin-robotics-j401-gmsl.conf` |
| AGX Orin mini | `recomputer-mini-agx-orin-j501x.conf` |
| AGX Orin robotics | `recomputer-robo-agx-orin-j501x.conf` |
| AGX Orin reServer | `reserver-agx-orin-j501x.conf` |
| AGX Orin reServer GMSL | `reserver-agx-orin-j501x-gmsl.conf` |
| AGX Orin kit | `seeed-agx-orin-kit.conf` |
| Jetson Thor carrier | `recomputer-thor-carrier-j601.conf` |
| Jetson Thor carrier | `recomputer-thor-carrier-j6014.conf` |
| Jetson Thor carrier | `recomputer-thor-carrier-j6015.conf` |

“Source available” means a vendor flash config and related files are present in
the Seeed L4T tree. Before claiming support, each target still needs:

1. A dedicated Yocto machine/SKU mapping.
2. DTB, BPMP DTB, BCT, overlay and storage-layout verification.
3. Kernel and NVIDIA OOT driver-diff review.
4. A successful tegraflash package inspection.
5. Physical flashing and peripheral regression tests.

Generate a detailed inventory from a local L4T tree with:

```bash
./scripts/recomputer-super/discover-l4t-boards.sh \
  --l4t-dir /path/to/Linux_for_Tegra \
  > /tmp/seeed-l4t-board-inventory.md
```

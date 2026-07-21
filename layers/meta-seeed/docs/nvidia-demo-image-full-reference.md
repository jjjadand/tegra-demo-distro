# NVIDIA/OE4T `demo-image-full` reference audit

The reference archive audited for Route B is:

```text
demo-image-full-jetson-orin-nano-devkit-nvme.rootfs.tegraflash-tar.zst
```

The archive contains a 14 GiB logical ext4 root filesystem. Static inspection
found the same runtime-oriented stack used by the upstream `demo-image-full`:

- CUDA 13.2 runtime libraries under `/usr/local/cuda-13.2/lib`;
- cuDNN 9 and TensorRT 10 runtime libraries under `/usr/lib`;
- TensorRT samples and `trtexec` under `/usr/src/tensorrt`;
- VPI 4 runtime files and samples under `/opt/nvidia/vpi4`;
- OpenCV, multimedia, graphics, container, and demo/test components supplied by
  the OE4T packagegroups.

The reference root filesystem does **not** contain `/usr/local/cuda-13.2/bin/nvcc`,
CUDA headers, cuDNN/TensorRT development headers, or VPI development headers.
It is therefore a runtime and sample image, not a complete on-target CUDA SDK.

Route B keeps that boundary explicit:

| Image | Purpose | CUDA development content |
| --- | --- | --- |
| `demo-image-full` | Unmodified upstream demo baseline | Runtime, samples, tests; no target `nvcc` |
| `seeed-image-jetson-runtime` | Seeed product runtime aligned with the reference package selections | Runtime libraries, samples, tests, and `trtexec`; no target `nvcc` |
| `seeed-image-jetson-development` | On-target development and BSP/AI debugging | `cuda-toolkit`, `nvcc`, CUDA/cuDNN/TensorRT/VPI/OpenCV headers, build tools, samples, and tests |

The SDK generated from `seeed-image-jetson-development` adds the standard
AArch64 cross-toolchain and CUDA host tools, while its target sysroot is
populated from the same runtime and development packagegroups as the image.

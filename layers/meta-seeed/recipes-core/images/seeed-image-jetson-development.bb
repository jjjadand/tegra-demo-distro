SUMMARY = "Seeed Jetson image with complete on-target CUDA development SDK"

require seeed-image-jetson-runtime.inc

IMAGE_FEATURES += "dev-pkgs tools-debug tools-sdk"

CORE_IMAGE_BASE_INSTALL += " \
    packagegroup-seeed-jetson-development \
    packagegroup-seeed-jetson-tests \
"

SDKIMAGE_FEATURES += "dev-pkgs staticdev-pkgs"
TOOLCHAIN_TARGET_TASK:append = " packagegroup-seeed-jetson-runtime packagegroup-seeed-jetson-development"

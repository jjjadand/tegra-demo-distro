LICENSE = "MIT"

inherit core-image features_check nopackages

REQUIRED_DISTRO_FEATURES = "x11 opengl virtualization"

IMAGE_FEATURES += "splash x11-base x11-sato hwcodecs ssh-server-openssh container-registry"

CORE_IMAGE_BASE_INSTALL += " \
    packagegroup-demo-base \
    packagegroup-demo-x11tests \
    packagegroup-seeed-jetson-runtime \
    packagegroup-seeed-jetson-containers \
    ${@'packagegroup-demo-systemd' if d.getVar('VIRTUAL-RUNTIME_init_manager') == 'systemd' else ''} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'vulkan', 'packagegroup-demo-vulkantests', '', d)} \
    tegra-mmapi-tests \
    vpi4-tests \
    tensorrt-tests \
"

TOOLCHAIN_HOST_TASK += "nativesdk-packagegroup-cuda-sdk-host"

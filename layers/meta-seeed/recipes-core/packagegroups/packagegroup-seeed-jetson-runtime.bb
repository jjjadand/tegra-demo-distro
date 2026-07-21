SUMMARY = "Seeed Jetson AI and multimedia runtime"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    cuda-libraries \
    cudnn \
    tensorrt-core \
    tensorrt-plugins \
    tensorrt-trtexec \
    libnvvpi4 \
    opencv \
"

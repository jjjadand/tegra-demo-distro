SUMMARY = "Seeed Jetson target development SDK"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    packagegroup-core-buildessential \
    cuda-toolkit \
    cudnn-dev \
    tensorrt-core-dev \
    tensorrt-plugins-dev \
    libnvvpi4-dev \
    opencv-dev \
    gstreamer1.0-dev \
    cmake \
    ninja \
    pkgconfig \
    git \
    gdb \
    strace \
    python3 \
    python3-dev \
    python3-pip \
    python3-numpy \
"

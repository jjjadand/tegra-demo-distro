SUMMARY = "Seeed Jetson container runtime"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    docker \
    docker-registry-config \
    nvidia-container-toolkit \
"

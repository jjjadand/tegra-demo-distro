SUMMARY = "Seeed Jetson NVIDIA samples and validation tools"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    packagegroup-demo-x11tests \
    cuda-samples \
    tegra-mmapi-tests \
    vpi4-tests \
    tensorrt-tests \
    tensorrt-samples \
"

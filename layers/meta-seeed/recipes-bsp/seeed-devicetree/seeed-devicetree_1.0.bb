DESCRIPTION = "Seeed reComputer Super J401 device trees"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit tegra-devicetree

COMPATIBLE_MACHINE = "(recomputer-orin-super-j401)"

S = "${UNPACKDIR}"

SRC_URI = " \
    file://tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dts \
    file://tegra234-j401-p3768-0000+p3767-recomputer-super-common.dts \
    file://tegra234-super-j401-p3768-0000+p3767-0000.dts \
    file://tegra234-p3768-0000+p3767-xxxx-nv-common.dtsi \
    file://tegra234-p3767-camera-p3768-imx219-quad-seeed.dts \
"

DT_FILES = " \
    tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb \
    tegra234-p3767-camera-p3768-imx219-quad-seeed.dtbo \
"

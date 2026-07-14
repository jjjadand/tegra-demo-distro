FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

SRC_URI:append:recomputer-orin-super-j401 = " \
    file://recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi \
    file://recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi \
    file://recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi \
"

SEEED_BOOTFILES_DIR := "${THISDIR}/${BPN}"

do_install:append:recomputer-orin-super-j401() {
    install -m 0644 ${SEEED_BOOTFILES_DIR}/recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi ${D}${datadir}/tegraflash/
    install -m 0644 ${SEEED_BOOTFILES_DIR}/recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi ${D}${datadir}/tegraflash/
    install -m 0644 ${SEEED_BOOTFILES_DIR}/recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi ${D}${datadir}/tegraflash/
}

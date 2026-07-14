SEEED_RECOMPUTER_SUPER_BCT_FILES = " \
    recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi \
    recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi \
    recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi \
"

tegraflash_custom_pre() {
    for bctfile in ${SEEED_RECOMPUTER_SUPER_BCT_FILES}; do
        cp "${STAGING_DATADIR}/tegraflash/$bctfile" .
    done
}

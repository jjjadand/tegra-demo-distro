DESCRIPTION = "Seeed carrier board device trees"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit tegra-devicetree

COMPATIBLE_MACHINE = "(recomputer|reserver|seeed-agx-orin-kit)"

S = "${UNPACKDIR}"

# Import the required Seeed-modified platform and overlay DTS dependency closure.
SRC_URI = " \
    ${@' '.join('file://' + f for f in sorted(os.listdir(d.getVar('THISDIR') + '/seeed-devicetree')) if f.endswith('.dts') or f.endswith('.dtsi'))} \
    file://gmsl \
"

DT_FILES:tegra234 = " \
    ${SEEED_DTB} \
    tegra234-j201-p3768-0000+p3767-0000-recomputer-indu.dtb \
    tegra234-j401-p3768-0000+p3767-0000-recomputer.dtb \
    tegra234-j401-p3768-0000+p3767-0000-recomputer-robo.dtb \
    tegra234-j401-p3768-0000+p3767-0000-recomputer-robo-gmsl.dtb \
    tegra234-j401-p3768-0000+p3767-0000-recomputer-rugged.dtb \
    tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb \
    tegra234-j401-p3768-0000+p3767-0000-reserver-indu.dtb \
    tegra234-j40mini-p3768-0000+p3767-0000-recomputer.dtb \
    tegra234-j501x-0000+p3701-0000-recomputer-mini.dtb \
    tegra234-j501x-0000+p3701-0004-recomputer-mini.dtb \
    tegra234-j501x-0000+p3701-0005-recomputer-mini.dtb \
    tegra234-j501x-0000+p3701-0000-recomputer-robo.dtb \
    tegra234-j501x-0000+p3701-0004-recomputer-robo.dtb \
    tegra234-j501x-0000+p3701-0005-recomputer-robo.dtb \
    tegra234-j501x-0000+p3701-0000-reserver-gmsl.dtb \
    tegra234-j501x-0000+p3701-0004-reserver-gmsl.dtb \
    tegra234-j501x-0000+p3701-0005-reserver-gmsl.dtb \
    tegra234-j501x-0000+p3701-0000-reserver.dtb \
    tegra234-j501x-0000+p3701-0004-reserver.dtb \
    tegra234-j501x-0000+p3701-0005-reserver.dtb \
    tegra234-dcb-p3701-0000-hdmi.dtbo \
    tegra234-p3737-0000+p3701-0000-seeed.dtb \
    tegra234-p3737-0000+p3701-0004-seeed.dtb \
    tegra234-p3737-0000+p3701-0005-seeed.dtb \
    tegra234-p3767-camera-p3768-imx219-quad-seeed.dtbo \
    tegra234-seeed-gmsl-recomputer-robo-3g-overlay.dtbo \
    tegra234-seeed-gmsl-recomputer-robo-6g-overlay.dtbo \
"

python do_compile:prepend:tegra234() {
    import os
    import shutil

    template = d.getVar("SEEED_DTS_TEMPLATE")
    if template:
        generated = d.getVar("SEEED_DTB").removesuffix(".dtb") + ".dts"
        if generated != template:
            shutil.copyfile(
                os.path.join(d.getVar("S"), template),
                os.path.join(d.getVar("S"), generated),
            )
}

DT_FILES:tegra264 = " \
    tegra264-p4071-0000+p3834-0000-recomputer-carrier.dtb \
    tegra264-p4071-0000+p3834-0008-recomputer-carrier.dtb \
"

do_compile:append:tegra234() {
    import glob
    import os
    import subprocess

    fdtget = os.path.join(d.getVar("STAGING_BINDIR_NATIVE"), "fdtget")
    nodes = (
        "/bus@0/padctl@3520000/pads/usb2/lanes/usb2-0",
        "/bus@0/padctl@3520000/ports/usb2-0",
        "/bus@0/usb@3550000",
    )
    for dtbf in glob.glob(os.path.join(d.getVar("B"), "tegra234-*.dtb")):
        for node in nodes:
            result = subprocess.run(
                [fdtget, "-t", "s", dtbf, node, "status"],
                capture_output=True,
                text=True,
            )
            status = result.stdout.strip() if result.returncode == 0 else "missing"
            if status != "okay":
                bb.fatal(
                    "%s: %s must be okay for initrd flash USB device mode (got %s)"
                    % (os.path.basename(dtbf), node, status)
                )
}

do_compile:append:tegra264() {
    import glob
    import os
    import subprocess

    fdtget = os.path.join(d.getVar("STAGING_BINDIR_NATIVE"), "fdtget")
    nodes = (
        "/bus@0/padctl@a808680000/pads/usb2/lanes/usb2-0",
        "/bus@0/padctl@a808680000/ports/usb2-0",
        "/bus@0/usb@a808670000",
    )
    for dtbf in glob.glob(os.path.join(d.getVar("B"), "tegra264-*.dtb")):
        for node in nodes:
            result = subprocess.run(
                [fdtget, "-t", "s", dtbf, node, "status"],
                capture_output=True,
                text=True,
            )
            status = result.stdout.strip() if result.returncode == 0 else "missing"
            if status != "okay":
                bb.fatal(
                    "%s: %s must be okay for initrd flash USB device mode (got %s)"
                    % (os.path.basename(dtbf), node, status)
                )
}

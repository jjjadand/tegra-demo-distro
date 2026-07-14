#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

BUILD_DIR=${BUILD_DIR:-build-recomputer-super}
MACHINE=${MACHINE:-recomputer-orin-super-j401}
IMAGE=${IMAGE:-demo-image-full}
OUTPUT_DIR=${OUTPUT_DIR:-$HOME/recomputer-super-flash}
ARCHIVE=

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Verify and extract the reComputer Super tegraflash package into a clean,
separate directory. This script does not run sudo or flash the target.

Options:
  --archive FILE    Explicit .tegraflash-tar.zst archive
  --output-dir DIR  Extraction directory (default: $OUTPUT_DIR)
  --build-dir DIR   Build directory (default: $BUILD_DIR)
  --machine NAME    Machine name (default: $MACHINE)
  --image NAME      Image name (default: $IMAGE)
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            ARCHIVE=$2
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR=$2
            shift 2
            ;;
        --build-dir)
            BUILD_DIR=$2
            shift 2
            ;;
        --machine)
            MACHINE=$2
            shift 2
            ;;
        --image)
            IMAGE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ $BUILD_DIR != /* ]]; then
    BUILD_DIR="$REPO_ROOT/$BUILD_DIR"
fi

if [[ -z $ARCHIVE ]]; then
    ARCHIVE="$BUILD_DIR/tmp/deploy/images/$MACHINE/$IMAGE-$MACHINE.rootfs.tegraflash-tar.zst"
fi

if [[ ! -e $ARCHIVE ]]; then
    echo "ERROR: flash archive not found: $ARCHIVE" >&2
    exit 1
fi

ARCHIVE=$(readlink -f "$ARCHIVE")
OUTPUT_DIR=$(readlink -m "$OUTPUT_DIR")

if mount_source=$(findmnt -n -T "$OUTPUT_DIR" -o SOURCE 2>/dev/null); then
    case "$mount_source" in
        /dev/sd*|/dev/disk/by-*|/dev/mapper/*)
            echo "NOTE: extraction target is on $mount_source. A host-local SSD is recommended." >&2
            ;;
    esac
fi

if [[ -e $OUTPUT_DIR && -n $(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
    echo "ERROR: output directory is not empty: $OUTPUT_DIR" >&2
    echo "Use a new directory or remove the old extraction manually." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
echo "==> Extracting $ARCHIVE"
tar xf "$ARCHIVE" -C "$OUTPUT_DIR"

required_files=(
    initrd-flash
    flashvars
    .env.initrd-flash
    "$IMAGE.ext4"
    recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi
    recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi
    recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi
    tegra234-j401-p3768-0000+p3767-0000-recomputer-super.dtb
    tegra234-bpmp-3767-0000-3768-super.dtb
)

for file in "${required_files[@]}"; do
    if [[ ! -s "$OUTPUT_DIR/$file" ]]; then
        echo "ERROR: required flash-package file missing or empty: $file" >&2
        exit 1
    fi
    echo "OK: $file"
done

echo
grep -E '^(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|DCE_OVERLAY|PLUGIN_MANAGER_OVERLAYS|BOOTCONTROL_OVERLAYS)=' \
    "$OUTPUT_DIR/flashvars"
cat "$OUTPUT_DIR/.env.initrd-flash"

cat <<EOF

Flash directory is ready:
  $OUTPUT_DIR

Next steps:
  1. Put the Jetson into Force Recovery Mode.
  2. Confirm it with: lsusb -d 0955:
  3. Run from the prepared directory:

       cd "$OUTPUT_DIR"
       sudo ./initrd-flash

Do not assume the temporary host block device is always /dev/sdb or /dev/sdc.
EOF

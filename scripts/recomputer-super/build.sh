#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

MACHINE=${MACHINE:-recomputer-orin-super-j401}
BUILD_DIR=${BUILD_DIR:-build-recomputer-super}
IMAGE=${IMAGE:-demo-image-full}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  metadata       Parse metadata and print the key BSP selections
  dtb            Compile the Seeed DTB/DTBO provider
  bootfiles      Install and verify custom BCT/pinmux files
  image          Build the complete image and tegraflash archive
  flash-package  Rebuild only the tegraflash archive, then publish it
  sdk            Build the cross-development SDK
  clean          Clean the image recipe work directory

Options:
  --build-dir DIR  Build directory (default: $BUILD_DIR)
  --machine NAME   Yocto MACHINE (default: $MACHINE)
  --image NAME     Image recipe (default: $IMAGE)
  -h, --help       Show this help
EOF
}

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
fi

if [[ $1 == -h || $1 == --help ]]; then
    usage
    exit 0
fi

action=$1
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
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

case "$action" in
    metadata|dtb|bootfiles|image|flash-package|sdk|clean)
        ;;
    *)
        echo "Unknown command: $action" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ $BUILD_DIR != /* ]]; then
    BUILD_DIR="$REPO_ROOT/$BUILD_DIR"
fi

cd "$REPO_ROOT"
# shellcheck disable=SC1091
set +u
. ./setup-env --machine "$MACHINE" "$BUILD_DIR"
set -u

case "$action" in
    metadata)
        bitbake-layers show-layers
        bitbake-layers show-recipes seeed-devicetree
        bitbake -e "$IMAGE" | grep -E \
            '^(MACHINE|DISTRO|PREFERRED_PROVIDER_virtual/dtb|KERNEL_DEVICETREE|TEGRA_FLASHVAR_(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|DCE_OVERLAY))='
        ;;
    dtb)
        bitbake -f -c compile seeed-devicetree
        ;;
    bootfiles)
        bitbake -f -c install tegra-bootfiles
        workdir=$(bitbake -e tegra-bootfiles | sed -n 's/^WORKDIR="\(.*\)"$/\1/p')
        for file in \
            recomputer-super-orin-j401-gpio-p3767-hdmi-a03.dtsi \
            recomputer-super-orin-j401-padvoltage-p3767-hdmi-a03.dtsi \
            recomputer-super-orin-j401-pinmux-p3767-hdmi-a03.dtsi; do
            test -s "$workdir/image/usr/share/tegraflash/$file" || {
                echo "ERROR: tegra-bootfiles did not install $file" >&2
                exit 1
            }
            echo "OK: $file"
        done
        ;;
    image)
        bitbake "$IMAGE"
        ;;
    flash-package)
        bitbake -f -c image_tegraflash_tar "$IMAGE"
        bitbake "$IMAGE"
        ;;
    sdk)
        bitbake -c populate_sdk "$IMAGE"
        ;;
    clean)
        bitbake -c clean "$IMAGE"
        ;;
esac

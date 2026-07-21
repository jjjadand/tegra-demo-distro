#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

EXPECTED_MACHINE=${MACHINE:-}
BUILD_DIR=${BUILD_DIR:-}
IMAGE=${IMAGE:-demo-image-full}
BUILD_DIR_FROM_CLI=no
ACTIVATE_WORKSPACE=yes

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  machines       List all Seeed MACHINE names
  current        Show the active build directory and configured MACHINE
  all            Run metadata, DTB, bootfiles, and image in order
  metadata       Parse metadata and print the key BSP selections
  dtb            Compile the Seeed DTB/DTBO provider
  bootfiles      Install and verify custom BCT/pinmux files
  image          Build the complete image and tegraflash archive
  flash-package  Rebuild only the tegraflash archive, then publish it
  sdk            Build the cross-development SDK
  clean          Clean the image recipe work directory

Options:
  --build-dir DIR  Use and activate this prepared build directory
  --machine NAME   Verify that the prepared build uses this MACHINE
  --no-activate    Do not change the active workspace for this command
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
            BUILD_DIR_FROM_CLI=yes
            shift 2
            ;;
        --machine)
            EXPECTED_MACHINE=$2
            shift 2
            ;;
        --image)
            IMAGE=$2
            shift 2
            ;;
        --no-activate)
            ACTIVATE_WORKSPACE=no
            shift
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
    machines|current|all|metadata|dtb|bootfiles|image|flash-package|sdk|clean)
        ;;
    *)
        echo "Unknown command: $action" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ $action == machines ]]; then
    find "$REPO_ROOT/layers/meta-seeed/conf/machine" -maxdepth 1 -name '*.conf' \
        -printf '%f\n' | sed 's/\.conf$//' | sort
    exit 0
fi

active_file=$(git -C "$REPO_ROOT" rev-parse --git-path seeed-active-build)
if [[ $active_file != /* ]]; then
    active_file="$REPO_ROOT/$active_file"
fi

if [[ -z $BUILD_DIR ]]; then
    if [[ -s $active_file ]]; then
        BUILD_DIR=$(<"$active_file")
    else
        BUILD_DIR=build-seeed
    fi
fi

if [[ $BUILD_DIR != /* ]]; then
    BUILD_DIR="$REPO_ROOT/$BUILD_DIR"
fi
BUILD_DIR=$(readlink -m "$BUILD_DIR")

local_conf="$BUILD_DIR/conf/local.conf"
if [[ ! -f $local_conf ]]; then
    cat >&2 <<EOF
ERROR: $BUILD_DIR is not a prepared Yocto build directory.

Run scripts/seeed/prepare-workspace.sh with --machine and --build-dir first.
EOF
    exit 1
fi

configured_machine=$(sed -n 's/^[[:space:]]*MACHINE[[:space:]]*?=[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$local_conf" | head -n 1)
if [[ -z $configured_machine ]]; then
    echo "ERROR: cannot determine MACHINE from $local_conf" >&2
    exit 1
fi
if [[ -n $EXPECTED_MACHINE && $EXPECTED_MACHINE != "$configured_machine" ]]; then
    cat >&2 <<EOF
ERROR: requested MACHINE does not match the prepared build directory.
  Build dir:  $BUILD_DIR
  Configured: $configured_machine
  Requested:  $EXPECTED_MACHINE
EOF
    exit 1
fi

if [[ $BUILD_DIR_FROM_CLI == yes && $ACTIVATE_WORKSPACE == yes ]]; then
    mkdir -p "$(dirname "$active_file")"
    printf '%s\n' "$BUILD_DIR" > "$active_file"
    echo "==> Activated Seeed workspace: $configured_machine ($BUILD_DIR)"
fi

if [[ $action == current ]]; then
    configured_module_sku=$(sed -n \
        's/^[[:space:]]*SEEED_MODULE_SKU[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$BUILD_DIR/conf/seeed-machine.conf" 2>/dev/null | head -n 1)
    echo "Build dir: $BUILD_DIR"
    echo "Machine:   $configured_machine"
    echo "Module SKU: ${configured_module_sku:-machine-default}"
    sed -n 's/^[[:space:]]*\(DL_DIR\|SSTATE_DIR\)[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1: \2/p' \
        "$BUILD_DIR/conf/seeed-cache.conf" 2>/dev/null || true
    exit 0
fi

echo "==> Seeed build: $configured_machine ($BUILD_DIR)"

cd "$REPO_ROOT"
unset MACHINE
# shellcheck disable=SC1091
set +u
. ./setup-env "$BUILD_DIR"
set -u

run_metadata() {
    bitbake-layers show-layers
    bitbake-layers show-recipes seeed-devicetree
    bitbake -e "$IMAGE" | grep -E \
        '^(MACHINE|DISTRO|SEEED_MODULE_SKU|PREFERRED_PROVIDER_virtual/dtb|KERNEL_DEVICETREE|TEGRA_BOARDSKU|TEGRA_FLASHVAR_(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|DCE_OVERLAY))='
}

run_dtb() {
    bitbake -f -c compile seeed-devicetree
}

run_bootfiles() {
    bitbake -f -c install tegra-bootfiles
    local workdir
    workdir=$(bitbake -e tegra-bootfiles | sed -n 's/^WORKDIR="\(.*\)"$/\1/p')
    local files=()
    mapfile -t files < <(bitbake -e tegra-bootfiles | sed -n \
        's/^TEGRA_FLASHVAR_\(PINMUX_CONFIG\|PMC_CONFIG\)="\(.*\)"$/\2/p')
    local file
    for file in "${files[@]}"; do
        [[ -n $file ]] || continue
        test -s "$workdir/image/usr/share/tegraflash/$file" || {
            echo "ERROR: tegra-bootfiles did not install $file" >&2
            return 1
        }
        echo "OK: $file"
    done
}

print_image_outputs() {
    local deploy_dir
    deploy_dir=$(bitbake -e "$IMAGE" | sed -n 's/^DEPLOY_DIR_IMAGE="\(.*\)"$/\1/p')
    echo "==> Image outputs: $deploy_dir"
    find "$deploy_dir" -maxdepth 1 \( -type f -o -type l \) \
        -name "$IMAGE-$configured_machine.rootfs.*" -printf '  %p\n' | sort
}

print_sdk_outputs() {
    local deploy_dir
    deploy_dir=$(bitbake -e "$IMAGE" | sed -n 's/^DEPLOY_DIR_SDK="\(.*\)"$/\1/p')
    echo "==> SDK outputs: $deploy_dir"
    find "$deploy_dir" -maxdepth 1 -type f -printf '  %p\n' | sort
}

run_image() {
    bitbake "$IMAGE"
    print_image_outputs
}

case "$action" in
    all)
        echo "==> [1/4] Validating metadata"
        run_metadata
        echo "==> [2/4] Compiling DTB/DTBO"
        run_dtb
        echo "==> [3/4] Installing and checking bootfiles"
        run_bootfiles
        echo "==> [4/4] Building $IMAGE"
        run_image
        echo "==> Seeed validation and image build completed: $configured_machine"
        ;;
    metadata)
        run_metadata
        ;;
    dtb)
        run_dtb
        ;;
    bootfiles)
        run_bootfiles
        ;;
    image)
        run_image
        ;;
    flash-package)
        bitbake -f -c image_tegraflash_tar "$IMAGE"
        bitbake "$IMAGE"
        print_image_outputs
        ;;
    sdk)
        bitbake -c populate_sdk "$IMAGE"
        print_sdk_outputs
        ;;
    clean)
        bitbake -c clean "$IMAGE"
        ;;
esac

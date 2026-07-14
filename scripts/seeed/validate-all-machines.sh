#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
BUILD_DIR=${BUILD_DIR:-build-seeed-validation}

usage() {
    cat <<EOF
Usage: $(basename "$0") [--build-dir DIR]

Parse every Seeed machine and compile the tegra234 and tegra264 device-tree
families. This validates builds only; it does not claim hardware validation.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-dir)
            BUILD_DIR=$2
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

mapfile -t machines < <(
    find "$REPO_ROOT/layers/meta-seeed/conf/machine" -maxdepth 1 -name '*.conf' \
        -printf '%f\n' | sed 's/\.conf$//' | sort
)

cd "$REPO_ROOT"
set +u
. ./setup-env --machine "${machines[0]}" "$BUILD_DIR"
set -u

for machine in "${machines[@]}"; do
    echo "==> Parsing $machine"
    BB_ENV_PASSTHROUGH_ADDITIONS=MACHINE MACHINE="$machine" \
        bitbake -e seeed-devicetree >/dev/null
done

for machine in recomputer-orin-super-j401 recomputer-thor-carrier-j601; do
    echo "==> Compiling the ${machine} device-tree family"
    BB_ENV_PASSTHROUGH_ADDITIONS=MACHINE MACHINE="$machine" \
        bitbake -c compile seeed-devicetree
done

echo "Validated ${#machines[@]} Seeed machines. Hardware validation is separate."

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

MACHINE=${MACHINE:-recomputer-orin-super-j401}
MODULE_SKU=${MODULE_SKU:-}
BUILD_DIR=${BUILD_DIR:-build-seeed}
CACHE_DIR=${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/yocto-seeed}

is_agx_orin_machine() {
    case "$1" in
        recomputer-mini-agx-orin-j501x|recomputer-robo-agx-orin-j501x|\
        reserver-agx-orin-j501x|reserver-agx-orin-j501x-gmsl|seeed-agx-orin-kit)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_j401_machine() {
    case "$1" in
        recomputer-industrial-orin-j401|recomputer-orin-j401|recomputer-orin-j40mini|\
        recomputer-orin-robotics-j401|recomputer-orin-robotics-j401-gmsl|\
        recomputer-orin-super-j401|recomputer-rugged-orin-j401|reserver-industrial-orin-j401)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_module_selectable_machine() {
    is_agx_orin_machine "$1" || is_j401_machine "$1"
}

supported_module_skus() {
    case "$1" in
    recomputer-mini-agx-orin-j501x|recomputer-robo-agx-orin-j501x)
            echo "0004 0005"
            ;;
        recomputer-industrial-orin-j401|recomputer-orin-j401|recomputer-orin-j40mini|\
        recomputer-orin-robotics-j401|recomputer-orin-robotics-j401-gmsl|\
        recomputer-orin-super-j401|recomputer-rugged-orin-j401|reserver-industrial-orin-j401)
            echo "0000 0001 0003 0004"
            ;;
        reserver-agx-orin-j501x|reserver-agx-orin-j501x-gmsl|seeed-agx-orin-kit)
            echo "0000 0001 0002 0004 0005"
            ;;
    esac
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Prepare a lightweight Seeed carrier-board Yocto build workspace.

Options:
  --build-dir DIR   Build directory relative to the repository or absolute
                    (default: $BUILD_DIR)
  --cache-dir DIR   Shared downloads/sstate directory
                    (default: $CACHE_DIR)
  --machine NAME    Yocto MACHINE (default: $MACHINE)
  --module-sku SKU  Select the module SKU for a configurable carrier
  --no-activate     Do not make this the active Seeed build workspace
  --no-submodules   Do not initialize/update git submodules
  --full-history    Fetch full submodule history instead of shallow clones
  -h, --help        Show this help

Environment variables MACHINE, MODULE_SKU, BUILD_DIR, and CACHE_DIR provide
the same settings as the command-line options.
EOF
}

update_submodules=yes
shallow_submodules=yes
activate_workspace=yes
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-dir)
            BUILD_DIR=$2
            shift 2
            ;;
        --cache-dir)
            CACHE_DIR=$2
            shift 2
            ;;
        --machine)
            MACHINE=$2
            shift 2
            ;;
        --module-sku)
            MODULE_SKU=$2
            shift 2
            ;;
        --no-activate)
            activate_workspace=no
            shift
            ;;
        --no-submodules)
            update_submodules=no
            shift
            ;;
        --full-history)
            shallow_submodules=no
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

if is_module_selectable_machine "$MACHINE"; then
    supported_skus=$(supported_module_skus "$MACHINE")
    if [[ -z $MODULE_SKU ]]; then
        cat >&2 <<EOF
ERROR: --module-sku is required for configurable machine $MACHINE.
Supported module SKUs: $supported_skus

Use a separate --build-dir for each MACHINE and module SKU combination.
EOF
        exit 2
    fi
    if [[ ! " $supported_skus " =~ " $MODULE_SKU " ]]; then
        echo "ERROR: unsupported module SKU $MODULE_SKU for $MACHINE" >&2
        echo "Supported module SKUs: $supported_skus" >&2
        exit 2
    fi
elif [[ -n $MODULE_SKU ]]; then
    echo "ERROR: --module-sku is not supported for this machine." >&2
    exit 2
fi

for command in git bash awk sed readlink; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $command" >&2
        exit 1
    fi
done

if [[ ! -f "$REPO_ROOT/setup-env" || ! -f "$REPO_ROOT/.gitmodules" ]]; then
    echo "ERROR: run this script from a tegra-demo-distro source checkout." >&2
    exit 1
fi

if [[ $update_submodules == yes ]]; then
    echo "==> Initializing pinned source submodules"
    git -C "$REPO_ROOT" submodule sync --recursive
    if [[ $shallow_submodules == yes ]]; then
        git -C "$REPO_ROOT" submodule update --init --recursive --depth 1
    else
        git -C "$REPO_ROOT" submodule update --init --recursive
    fi
fi

mkdir -p "$CACHE_DIR/downloads" "$CACHE_DIR/sstate-cache"
CACHE_DIR=$(readlink -f "$CACHE_DIR")

if [[ $BUILD_DIR != /* ]]; then
    BUILD_DIR="$REPO_ROOT/$BUILD_DIR"
fi
BUILD_DIR=$(readlink -m "$BUILD_DIR")

if [[ -f $BUILD_DIR/conf/local.conf ]]; then
    configured_machine=$(awk -F'"' \
        '/^[[:space:]]*MACHINE[[:space:]]*(\?|\+|:)?=/{print $2; exit}' \
        "$BUILD_DIR/conf/local.conf")
    if [[ -n $configured_machine && $configured_machine != "$MACHINE" ]]; then
        echo "ERROR: build directory is configured for $configured_machine, not $MACHINE" >&2
        echo "Use a separate --build-dir for each machine." >&2
        exit 1
    fi
    if is_module_selectable_machine "$MACHINE"; then
        machine_conf="$BUILD_DIR/conf/seeed-machine.conf"
        configured_module_sku=
        if [[ -f $machine_conf ]]; then
            configured_module_sku=$(sed -n \
                's/^[[:space:]]*SEEED_MODULE_SKU[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
                "$machine_conf" | head -n 1)
        fi
        if [[ -z $configured_module_sku ]]; then
            cat >&2 <<EOF
ERROR: existing configurable build directory has no explicit module SKU.
  Build dir: $BUILD_DIR
  Machine:   $MACHINE

Use a new --build-dir for module SKU $MODULE_SKU. This prevents mixing
artifacts generated for different modules.
EOF
            exit 1
        fi
        if [[ $configured_module_sku != "$MODULE_SKU" ]]; then
            cat >&2 <<EOF
ERROR: build directory is configured for a different module SKU.
  Build dir:  $BUILD_DIR
  Configured: $configured_module_sku
  Requested:  $MODULE_SKU

Use a separate --build-dir for each MACHINE and module SKU combination.
EOF
            exit 1
        fi
    fi
fi

echo "==> Creating/updating build configuration"
(
    cd "$REPO_ROOT"
    # setup-env is intentionally sourced because it exports the BitBake/OE
    # environment and changes into the selected build directory.
    # shellcheck disable=SC1091
    set +u
    . ./setup-env --machine "$MACHINE" "$BUILD_DIR"
    set -u

    configured_machine=$(sed -n 's/^[[:space:]]*MACHINE[[:space:]]*?=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$BUILDDIR/conf/local.conf" | head -n 1)
    if [[ -z $configured_machine ]]; then
        echo "ERROR: cannot determine MACHINE from $BUILDDIR/conf/local.conf" >&2
        exit 1
    fi
    if [[ $configured_machine != "$MACHINE" ]]; then
        cat >&2 <<EOF
ERROR: build directory is already configured for a different machine.
  Build dir:  $BUILDDIR
  Configured: $configured_machine
  Requested:  $MACHINE

Use a separate --build-dir for each Seeed carrier board.
EOF
        exit 1
    fi

    if is_module_selectable_machine "$MACHINE"; then
        machine_conf="$BUILDDIR/conf/seeed-machine.conf"
        cat > "$machine_conf" <<EOF
# Generated by scripts/seeed/prepare-workspace.sh
SEEED_MODULE_SKU = "$MODULE_SKU"
EOF

        machine_include='require conf/seeed-machine.conf'
        if ! grep -Fxq "$machine_include" "$BUILDDIR/conf/local.conf"; then
            printf '\n# Seeed module selection\n%s\n' "$machine_include" >> "$BUILDDIR/conf/local.conf"
        fi
    fi

    cache_conf="$BUILDDIR/conf/seeed-cache.conf"
    cat > "$cache_conf" <<EOF
# Generated by scripts/seeed/prepare-workspace.sh
DL_DIR = "$CACHE_DIR/downloads"
SSTATE_DIR = "$CACHE_DIR/sstate-cache"
BB_HASHSERVE_DB_DIR = "\${SSTATE_DIR}"
EOF

    include_line='require conf/seeed-cache.conf'
    if ! grep -Fxq "$include_line" "$BUILDDIR/conf/local.conf"; then
        printf '\n# Shared cache for Seeed carrier builds\n%s\n' "$include_line" >> "$BUILDDIR/conf/local.conf"
    fi
)

if [[ $activate_workspace == yes ]]; then
    active_file=$(git -C "$REPO_ROOT" rev-parse --git-path seeed-active-build)
    if [[ $active_file != /* ]]; then
        active_file="$REPO_ROOT/$active_file"
    fi
    mkdir -p "$(dirname "$active_file")"
    printf '%s\n' "$BUILD_DIR" > "$active_file"
fi

if [[ $activate_workspace == yes ]]; then
    next_build_args=
else
    printf -v next_build_args ' --build-dir %q' "$BUILD_DIR"
fi

cat <<EOF

Workspace prepared successfully.

  Repository: $REPO_ROOT
  Machine:    $MACHINE
  Module SKU: ${MODULE_SKU:-machine-default}
  Build dir:  $BUILD_DIR
  Downloads:  $CACHE_DIR/downloads
  Sstate:     $CACHE_DIR/sstate-cache
  Active:     $activate_workspace

Next steps:
  $REPO_ROOT/scripts/seeed/build.sh current$next_build_args
  $REPO_ROOT/scripts/seeed/build.sh metadata$next_build_args
  $REPO_ROOT/scripts/seeed/build.sh dtb$next_build_args
  $REPO_ROOT/scripts/seeed/build.sh image$next_build_args
EOF

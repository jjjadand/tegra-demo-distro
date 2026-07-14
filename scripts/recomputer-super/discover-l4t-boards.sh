#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
L4T_DIR=${L4T_DIR:-$(readlink -m "$REPO_ROOT/../Linux_for_Tegra")}

usage() {
    cat <<EOF
Usage: $(basename "$0") [--l4t-dir DIR]

Inventory Seeed/reComputer board configurations in an NVIDIA/Seeed
Linux_for_Tegra BSP tree. The script parses configuration text only; it does
not execute vendor shell functions or claim that a board is supported by the
Yocto layer.

Default L4T directory:
  $L4T_DIR
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --l4t-dir)
            L4T_DIR=$2
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

L4T_DIR=$(readlink -m "$L4T_DIR")
if [[ ! -d $L4T_DIR || ! -f $L4T_DIR/nv_public_common_board.conf ]]; then
    echo "ERROR: not a Linux_for_Tegra BSP directory: $L4T_DIR" >&2
    exit 1
fi

mapfile -t configs < <(
    find "$L4T_DIR" -maxdepth 1 -type f \
        \( -name 'recomputer-*.conf' -o -name 'reserver-*.conf' -o -name 'seeed-*.conf' \) \
        -printf '%f\n' | sort
)

echo "# Seeed Linux_for_Tegra board configuration inventory"
echo
echo "Source: \`$L4T_DIR\`"
echo
echo "> Inventory only. A source config is not automatically a validated Yocto MACHINE."
echo

for config_name in "${configs[@]}"; do
    config="$L4T_DIR/$config_name"
    echo "## $config_name"
    echo

    sources=$(sed -n 's/^[[:space:]]*source[[:space:]]*"${LDK_DIR}\/\([^";]*\)";.*/\1/p' "$config" | sort -u)
    if [[ -n $sources ]]; then
        echo "Base config:"
        while IFS= read -r source_name; do
            [[ -n $source_name ]] && echo "- \`$source_name\`"
        done <<<"$sources"
        echo
    fi

    echo "Board variables:"
    matches=$(grep -E '^[[:space:]]*(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|ODMDATA|OVERLAY_DTB_FILE|DCE_OVERLAY_DTB_FILE)\+?=' "$config" || true)
    if [[ -n $matches ]]; then
        while IFS= read -r line; do
            echo "- \`${line//\`/}\`"
        done <<<"$matches"
    else
        echo "- No direct static assignment found; inspect vendor shell functions."
    fi
    echo

    mapfile -t referenced_files < <(
        grep -E '^[[:space:]]*(DTB_FILE|BPFDTB_FILE|PINMUX_CONFIG|PMC_CONFIG|OVERLAY_DTB_FILE|DCE_OVERLAY_DTB_FILE)\+?=' "$config" \
            | grep -Eo '[A-Za-z0-9_+.-]+\.(dtb|dtbo|dts|dtsi)' \
            | sort -u || true
    )

    if [[ ${#referenced_files[@]} -gt 0 ]]; then
        echo "Referenced file lookup:"
        for referenced in "${referenced_files[@]}"; do
            location=$(find "$L4T_DIR" -type f -name "$referenced" -printf '%P\n' -quit)
            if [[ -n $location ]]; then
                echo "- OK \`$referenced\` → \`$location\`"
            else
                echo "- DYNAMIC/MISSING \`$referenced\`"
            fi
        done
        echo
    fi
done

echo "Total board configs: ${#configs[@]}"

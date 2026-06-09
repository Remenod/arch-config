#!/usr/bin/env bash
#
# Requirement: fzf, openrgb, kbd-openrgb.sh
#
# Author:  Remenod <remenod@gmail.com>
# Date:    February 1, 2026
# License: MIT

set -euo pipefail

KBD_SCRIPT="${KBD_OPENRGB_SCRIPT:-$HOME/.config/waybar/scripts/kbd_backlight.sh}"
LOW_COLOR="${KBD_OPENRGB_LOW_COLOR:-808080}"

main() {
    if [[ ! -x "$KBD_SCRIPT" ]]; then
        echo "Error: keyboard OpenRGB script is not executable or not found: $KBD_SCRIPT" >&2
        echo "Set KBD_OPENRGB_SCRIPT=/path/to/kbd-openrgb.sh if it is located elsewhere." >&2
        exit 1
    fi

    local list=(
        "󰹏  Off"
        "󰌵  Low"
        "󰛨  High"
    )

    local options=(
        "--border=sharp"
        "--border-label= Keyboard Backlight "
        "--height=~100%"
        "--highlight-line"
        "--no-input"
        "--pointer="
        "--reverse"
    )

    local selected
    selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}")

    case "$selected" in
        "󰹏"* )
            "$KBD_SCRIPT" off
            ;;
        "󰌵"* )
            "$KBD_SCRIPT" low "$LOW_COLOR"
            ;;
        "󰛨"* )
            "$KBD_SCRIPT" high
            ;;
        * )
            exit 1
            ;;
    esac
}

main

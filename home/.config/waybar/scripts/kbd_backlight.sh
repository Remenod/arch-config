#!/usr/bin/env bash
set -euo pipefail

OPENRGB_BIN="${OPENRGB_BIN:-openrgb}"

# Можна перевизначити ззовні:
# OPENRGB_DEVICE=0
# OPENRGB_ZONE=0
# OPENRGB_MODE=static
DEVICE="${OPENRGB_DEVICE:-0}"
ZONE="${OPENRGB_ZONE:-}"
MODE="${OPENRGB_MODE:-static}"

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/keyboard-openrgb-color"

set_color() {
    local color
    color="$(echo "$1" | tr '[:lower:]' '[:upper:]')"

    local args=(--device "$DEVICE")

    if [[ -n "$ZONE" ]]; then
        args+=(--zone "$ZONE")
    fi

    args+=(--mode "$MODE" --color "$color")

    "$OPENRGB_BIN" "${args[@]}" >/dev/null 2>&1
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$color" > "$STATE_FILE"
}

read_color() {
    if [[ -f "$STATE_FILE" ]]; then
        tr '[:lower:]' '[:upper:]' < "$STATE_FILE" | tr -dc '0-9A-F' | head -c 6
    else
        echo "000000"
    fi
}

classify_color() {
    local color="$1"

    case "$color" in
        000000)
            emoji="󰹏"
            txt_profile="Off"
            ;;
        FFFFFF)
            emoji="󰛨"
            txt_profile="High"
            ;;
        *)
            local r="${color:0:2}"
            local g="${color:2:2}"
            local b="${color:4:2}"

            if [[ "$r" == "$g" && "$g" == "$b" ]]; then
                emoji="󰌵"
                txt_profile="Low"
            else
                emoji="❓"
                txt_profile="Custom"
            fi
            ;;
    esac
}

case "${1:-status}" in
    status)
        color="$(read_color)"
        classify_color "$color"
        echo "$emoji "
        echo "Keyboard Backlight Profile: $txt_profile"
        ;;

    off)
        set_color "000000"
        ;;

    low)
        set_color "${2:-808080}"
        ;;

    high)
        set_color "FFFFFF"
        ;;

    toggle)
        color="$(read_color)"

        case "$color" in
            000000)
                set_color "808080"
                ;;
            FFFFFF)
                set_color "000000"
                ;;
            *)
                set_color "FFFFFF"
                ;;
        esac
        ;;

    *)
        echo "Usage: $0 [status|off|low [HEX_GRAY]|high|toggle]" >&2
        exit 1
        ;;
esac

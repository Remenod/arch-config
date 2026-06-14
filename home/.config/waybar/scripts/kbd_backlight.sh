#!/usr/bin/env bash
set -euo pipefail

OPENRGB_BIN="${OPENRGB_BIN:-openrgb}"
OPENRGB_SERVER="${OPENRGB_SERVER:-127.0.0.1:6742}"

# Можна перевизначити ззовні:
# OPENRGB_DEVICE=0
# OPENRGB_ZONE=0
# OPENRGB_MODE=Static
DEVICE="${OPENRGB_DEVICE:-0}"
ZONE="${OPENRGB_ZONE:-}"
MODE="${OPENRGB_MODE:-Static}"

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/keyboard-openrgb-color"

notify() {
    notify-send "$1" "$2" -i "$3" \
        -h string:x-canonical-private-synchronous:keyboard-openrgb 2>/dev/null || true
}

normalize_color() {
    local color="$1"
    color="$(printf "%s" "$color" | tr '[:lower:]' '[:upper:]' | tr -dc '0-9A-F' | head -c 6)"

    if [[ ${#color} -ne 6 ]]; then
        return 1
    fi

    printf "%s" "$color"
}

openrgb_client() {
    "$OPENRGB_BIN" --client "$OPENRGB_SERVER" "$@"
}

set_color() {
    local color
    color="$(normalize_color "$1")" || {
        notify "Keyboard Backlight" "Invalid color: $1" "dialog-error"
        return 1
    }

    local args=(--device "$DEVICE")

    if [[ -n "$ZONE" ]]; then
        args+=(--zone "$ZONE")
    fi

    args+=(--mode "$MODE" --color "$color")

    if ! openrgb_client "${args[@]}" >/dev/null 2>&1; then
        notify "Keyboard Backlight" "OpenRGB client failed. Is openrgb.service running?" "dialog-error"
        return 1
    fi

    mkdir -p "$(dirname "$STATE_FILE")"
    printf "%s\n" "$color" > "$STATE_FILE"
}

read_color() {
    local color

    if [[ -f "$STATE_FILE" ]]; then
        color="$(normalize_color "$(cat "$STATE_FILE")" 2>/dev/null || true)"
        [[ -n "${color:-}" ]] && {
            printf "%s\n" "$color"
            return 0
        }
    fi

    printf "000000\n"
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
        808080)
            emoji="󰌵"
            txt_profile="Low"
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
        printf "%s\n" "$emoji "
        printf "Keyboard Backlight Profile: %s\n" "$txt_profile"
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

    toggle|cycle)
        color="$(read_color)"

        case "$color" in
            000000)
                set_color "808080"
                notify "Keyboard Backlight" "Low" "keyboard-brightness"
                ;;
            808080)
                set_color "FFFFFF"
                notify "Keyboard Backlight" "High" "keyboard-brightness"
                ;;
            FFFFFF)
                set_color "000000"
                notify "Keyboard Backlight" "Off" "keyboard-brightness"
                ;;
            *)
                set_color "FFFFFF"
                notify "Keyboard Backlight" "High" "keyboard-brightness"
                ;;
        esac
        ;;

    restore)
        color="$(read_color)"
        set_color "$color"
        ;;

    *)
        printf 'Usage: %s [status|off|low [HEX_GRAY]|high|toggle|cycle|restore]\n' "${0##*/}" >&2
        exit 1
        ;;
esac

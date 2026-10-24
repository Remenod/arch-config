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
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/keyboard-openrgb.lock"
WATCH_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/keyboard-openrgb-watch.pid"
WAYBAR_SIGNAL=5

notify() {
    notify-send "$1" "$2" -i "$3" "${@:4}" \
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

# The Waybar module has no interval: it redraws on this signal only.
refresh_waybar() {
    pkill -x -RTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true
}

# Runs "$@" holding the lock. Without it two quick presses of the backlight
# key both read the same saved colour and both step to the same next one.
with_lock() {
    local fd rc=0

    exec {fd}> "$LOCK_FILE"
    flock "$fd"
    "$@" || rc=$?
    exec {fd}>&-
    return "$rc"
}

# Sends a normalized colour to the keyboard and saves it. Quiet on failure,
# so that restore_color can retry.
apply_color() {
    local args=(--device "$DEVICE")

    if [[ -n "$ZONE" ]]; then
        args+=(--zone "$ZONE")
    fi

    args+=(--mode "$MODE" --color "$1")

    openrgb_client "${args[@]}" >/dev/null 2>&1 || return 1

    mkdir -p "$(dirname "$STATE_FILE")"
    printf "%s\n" "$1" > "$STATE_FILE"
    refresh_waybar
}

set_color() {
    local color
    color="$(normalize_color "$1")" || {
        notify "Keyboard Backlight" "Invalid color: $1" "dialog-error"
        return 1
    }

    if ! apply_color "$color"; then
        notify "Keyboard Backlight" "OpenRGB client failed. Is openrgb.service running?" "dialog-error"
        return 1
    fi
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

cycle_color() {
    case "$(read_color)" in
        000000)
            set_color "808080" && notify "Keyboard Backlight" "Low" "keyboard-brightness" -e
            ;;
        808080)
            set_color "FFFFFF" && notify "Keyboard Backlight" "High" "keyboard-brightness" -e
            ;;
        FFFFFF)
            set_color "000000" && notify "Keyboard Backlight" "Off" "keyboard-brightness" -e
            ;;
        *)
            set_color "FFFFFF" && notify "Keyboard Backlight" "High" "keyboard-brightness" -e
            ;;
    esac
}

# Puts the saved colour back on the keyboard. Retries quietly first: right
# after a resume the OpenRGB server may need a moment.
restore_color() {
    local color attempt

    color="$(read_color)"
    for attempt in 1 2 3; do
        apply_color "$color" && return 0
        sleep 2
    done

    notify "Keyboard Backlight" "OpenRGB client failed. Is openrgb.service running?" "dialog-error"
    return 1
}

# Re-applies the saved colour after every resume. Hibernation cuts power to
# the USB lighting controller, which comes back in its own default colour
# while the saved one - and so the Waybar module - still says otherwise.
# Started from Hyprland's autostart; a new instance replaces the old one.
watch_sleep() {
    local old="" args=() fd line

    if [[ -r $WATCH_PID_FILE ]]; then
        read -r old < "$WATCH_PID_FILE" || true
    fi
    # Only if that pid still is a watcher, not a process that reused it.
    if [[ -n $old && $old != "$$" ]] && mapfile -d '' args 2>/dev/null < "/proc/$old/cmdline" &&
        [[ "${args[*]}" == *kbd_backlight.sh\ watch* ]]; then
        pkill -P "$old" 2>/dev/null || true
        kill "$old" 2>/dev/null || true
    fi
    printf '%s\n' "$$" > "$WATCH_PID_FILE"

    while true; do
        exec {fd}< <(exec gdbus monitor --system --dest org.freedesktop.login1 \
            --object-path /org/freedesktop/login1 2>/dev/null)

        while IFS= read -r line <&"$fd"; do
            [[ $line == *"PrepareForSleep (false,)"* ]] || continue
            sleep 2
            with_lock restore_color || true
        done

        # The system bus went away; try again.
        exec {fd}<&-
        sleep 5
    done
}

case "${1:-status}" in
    status)
        color="$(read_color)"
        classify_color "$color"
        printf "%s\n" "$emoji "
        printf "Keyboard Backlight Profile: %s\n" "$txt_profile"
        ;;

    off)
        with_lock set_color "000000"
        ;;

    low)
        with_lock set_color "${2:-808080}"
        ;;

    high)
        with_lock set_color "FFFFFF"
        ;;

    toggle|cycle)
        with_lock cycle_color
        ;;

    restore)
        with_lock restore_color
        ;;

    watch)
        watch_sleep
        ;;

    *)
        printf 'Usage: %s [status|off|low [HEX_GRAY]|high|toggle|cycle|restore|watch]\n' "${0##*/}" >&2
        exit 1
        ;;
esac

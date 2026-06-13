#!/usr/bin/env sh
set -eu

DEVICE="${1:-pnp0c50:0e-06cb:7e7e-touchpad}"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-touchpad-enabled"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "$@" || true
}

if [ -z "$DEVICE" ]; then
    DEVICE="$(hyprctl -j devices | jq -r '.mice[]?.name | select(test("touchpad"; "i"))' | head -n1)"
fi

if [ -z "$DEVICE" ]; then
    notify "Touchpad" "Touchpad device not found"
    exit 1
fi

[ -f "$STATE_FILE" ] || echo 1 > "$STATE_FILE"

STATE="$(cat "$STATE_FILE")"

if [ "$STATE" = "1" ]; then
    hyprctl -r -- keyword "device[$DEVICE]:enabled" false >/dev/null
    echo 0 > "$STATE_FILE"
    notify "Touchpad" "disabled"
else
    hyprctl -r -- keyword "device[$DEVICE]:enabled" true >/dev/null
    echo 1 > "$STATE_FILE"
    notify "Touchpad" "enabled"
fi

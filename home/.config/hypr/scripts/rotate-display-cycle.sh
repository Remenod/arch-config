#!/usr/bin/env bash
set -euo pipefail

notify() {
    notify-send "$1" "$2" -i video-display \
        -h string:x-canonical-private-synchronous:rotate-display 2>/dev/null || true
}

command -v jq >/dev/null 2>&1 || {
    notify "Display rotation" "jq is not installed"
    exit 1
}

monitor_json="$(
    hyprctl -j monitors | jq -c '
        (map(select(.focused == true))[0] // .[0])
    '
)"

if [[ -z "$monitor_json" || "$monitor_json" == "null" ]]; then
    notify "Display rotation" "No monitor found"
    exit 1
fi

name="$(jq -r '.name' <<< "$monitor_json")"
x="$(jq -r '.x' <<< "$monitor_json")"
y="$(jq -r '.y' <<< "$monitor_json")"
scale="$(jq -r '.scale' <<< "$monitor_json")"
current="$(jq -r '.transform // 0' <<< "$monitor_json")"

case "$current" in
    0) next=1; label="90°" ;;
    1) next=2; label="180°" ;;
    2) next=3; label="270°" ;;
    3) next=0; label="Normal" ;;
    *) next=0; label="Normal" ;;
esac

# preferred = не хардкодимо resolution/refresh
# ${x}x${y} = залишаємо поточну позицію монітора в layout
# scale = залишаємо поточний scale
hyprctl keyword monitor "$name, preferred, ${x}x${y}, $scale, transform, $next" >/dev/null

notify "Display rotation" "$name: $label"

if [[ -x "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/waybar-adaptive.sh" ]]; then
    sleep 0.2
    "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/waybar-adaptive.sh" reload
fi

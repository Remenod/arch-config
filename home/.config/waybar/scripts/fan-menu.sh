#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=msi-ec.sh
source "$script_dir/msi-ec.sh"

pause_on_error() {
    local message="$1"

    notify-send "MSI EC" "$message" -i "dialog-error" 2>/dev/null || true
    printf '\n%s\n' "$message" >&2
    printf 'Press Enter to close...' >&2
    read -r _ || true
}

write_or_pause() {
    local rel="$1"
    local value="$2"

    if ! msi_ec_write "$rel" "$value"; then
        pause_on_error "Failed to set $rel=$value"
        exit 1
    fi
}

if ! msi_ec_available; then
    pause_on_error "msi-ec is not available"
    exit 1
fi

fan_mode="$(msi_ec_read fan_mode unknown || true)"
cooler="$(msi_ec_read cooler_boost unknown || true)"
fan_modes="$(msi_ec_read_words available_fan_modes "auto silent advanced" || true)"

list=()
if [[ "$cooler" == "on" ]]; then
    list+=("boost:off"$'\t'"󱑯  Turn Cooler Boost off")
else
    list+=("boost:on"$'\t'"󱑯  Turn Cooler Boost on")
fi

list+=("noop:"$'\t'"── fan mode ──")

for mode in $fan_modes; do
    case "$mode" in
        auto) icon="󱜝"; label="Auto" ;;
        silent) icon="󱑭"; label="Silent" ;;
        advanced) icon="󱑮"; label="Advanced" ;;
        *) icon="󰿈"; label="$mode" ;;
    esac

    prefix=""
    [[ "$mode" == "$fan_mode" ]] && prefix="* "
    list+=("fan:$mode"$'\t'"$icon  $prefix$label fan mode")
done

options=(
    "--border=sharp"
    "--border-label= Fan Control "
    "--height=~100%"
    "--highlight-line"
    "--no-input"
    "--pointer="
    "--reverse"
    "--delimiter=\t"
    "--with-nth=2.."
)

selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}") || exit 0
action="${selected%%$'\t'*}"
kind="${action%%:*}"
value="${action#*:}"

case "$kind" in
    fan)
        write_or_pause fan_mode "$value"
        notify-send "MSI EC" "Fan mode: $value" -i "dialog-ok" 2>/dev/null || true
        ;;
    boost)
        write_or_pause cooler_boost "$value"
        notify-send "MSI EC" "Cooler Boost: $value" -i "dialog-ok" 2>/dev/null || true
        ;;
    *)
        exit 0
        ;;
esac

#!/usr/bin/env bash
set -euo pipefail

SHADER="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/fast-spin.frag"
DURATION="${SPIN_SHADER_DURATION:-1.20}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-fast-spin-shader.lock"

notify() {
    notify-send "$1" "$2" -i video-display \
        -h string:x-canonical-private-synchronous:fast-spin-shader 2>/dev/null || true
}

get_option_json() {
    local opt="$1"

    hyprctl -j getoption "$opt" 2>/dev/null || \
    hyprctl -j getoption "${opt/:/.}" 2>/dev/null || \
    return 1
}

get_int_option() {
    local opt="$1"
    local fallback="$2"

    get_option_json "$opt" | jq -r '.int // .value // empty' 2>/dev/null | grep -E '^[0-9-]+$' || {
        printf "%s\n" "$fallback"
    }
}

get_bool_option() {
    local opt="$1"
    local fallback="$2"
    local value

    value="$(get_option_json "$opt" | jq -r '.bool // .int // .value // empty' 2>/dev/null || true)"

    case "$value" in
        true|1)  printf "true\n" ;;
        false|0) printf "false\n" ;;
        *)       printf "%s\n" "$fallback" ;;
    esac
}

if [[ ! -f "$SHADER" ]]; then
    notify "Spin shader" "Shader file not found: $SHADER"
    exit 1
fi

command -v jq >/dev/null 2>&1 || {
    notify "Spin shader" "jq is not installed"
    exit 1
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

old_damage="$(get_int_option "debug:damage_tracking" "2")"
old_vfr="$(get_bool_option "debug:vfr" "true")"

cleanup() {
    hyprctl eval "hl.config({ decoration = { screen_shader = \"\" }, debug = { damage_tracking = $old_damage, vfr = $old_vfr } })" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

# hyprctl синхронний; краще один eval, ніж кілька keyword-викликів.
hyprctl eval "hl.config({ debug = { damage_tracking = 0, vfr = false }, decoration = { screen_shader = \"$SHADER\" } })" >/dev/null

sleep "$DURATION"

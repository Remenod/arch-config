#!/usr/bin/env bash
set -euo pipefail

TEMPLATE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/spin-frame-template.frag"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-spin-shader"
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-screen-shader-effect.lock"
PID_FILE="$LOCK_DIR/pid"

# Налаштування ефекту.
# 1.0 = один повний оберт.
# 1.5 = півтора оберти.
TURNS="${SPIN_TURNS:-1.0}"

# Тривалість у секундах.
DURATION="${SPIN_DURATION:-0.30}"

# Кількість кадрів. 36 або 45 достатньо.
# Не став 120: hyprctl буде спамити compositor.
FRAMES="${SPIN_FRAMES:-45}"

notify() {
    notify-send "$1" "$2" -i video-display \
        -h string:x-canonical-private-synchronous:spin-shader 2>/dev/null || true
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

get_str_option() {
    local opt="$1"
    local fallback="$2"

    get_option_json "$opt" | jq -r '.str // .value // empty' 2>/dev/null || {
        printf "%s\n" "$fallback"
    }
}

acquire_lock() {
    local owner

    mkdir -p "$RUNTIME_DIR"

    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        owner="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
            rm -rf "$LOCK_DIR"
            continue
        fi

        exit 0
    done

    printf '%s\n' "$$" > "$PID_FILE"
}

restore_shader() {
    if [[ -n "${old_shader:-}" ]]; then
        hyprctl eval "hl.config({ decoration = { screen_shader = \"$old_shader\" } })" >/dev/null 2>&1 || true
    else
        hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' >/dev/null 2>&1 || true
    fi
}

if [[ ! -f "$TEMPLATE" ]]; then
    notify "Spin shader" "Template not found: $TEMPLATE"
    exit 1
fi

command -v jq >/dev/null 2>&1 || {
    notify "Spin shader" "jq is not installed"
    exit 1
}

command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || {
    notify "Spin shader" "python/python3 is not installed"
    exit 1
}

PYTHON_BIN="$(command -v python || command -v python3)"

acquire_lock

old_damage="$(get_int_option "debug:damage_tracking" "2")"
old_vfr="$(get_bool_option "debug:vfr" "true")"
old_shader="$(get_str_option "decoration:screen_shader" "")"

cleanup() {
    restore_shader
    hyprctl eval "hl.config({ debug = { damage_tracking = $old_damage, vfr = $old_vfr } })" >/dev/null 2>&1 || true
    rm -f "$RUNTIME_DIR"/frame-*.frag 2>/dev/null || true

    if [[ -r "$PID_FILE" ]] && [[ "$(<"$PID_FILE")" == "$$" ]]; then
        rm -rf "$LOCK_DIR"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

hyprctl eval 'hl.config({ debug = { damage_tracking = 0, vfr = false } })' >/dev/null

frame_sleep="$("$PYTHON_BIN" - <<PY
duration = float("$DURATION")
frames = int("$FRAMES")
print(max(duration / max(frames, 1), 0.001))
PY
)"

for ((i = 0; i <= FRAMES; i++)); do
    angle="$("$PYTHON_BIN" - <<PY
import math

i = int("$i")
frames = int("$FRAMES")
turns = float("$TURNS")

x = i / frames if frames > 0 else 1.0

# smoothstep: 0 на старті, 1 у кінці, плавне прискорення/сповільнення
ease = x * x * (3.0 - 2.0 * x)

angle = ease * turns * 2.0 * math.pi
print(f"{angle:.9f}")
PY
)"

    shader="$RUNTIME_DIR/frame-$i.frag"
    sed "s/__ANGLE__/$angle/g" "$TEMPLATE" > "$shader"

    hyprctl eval "hl.config({ decoration = { screen_shader = \"$shader\" } })" >/dev/null
    sleep "$frame_sleep"
done

#!/usr/bin/env bash
set -euo pipefail

TEMPLATE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/spin-frame-template.frag"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-hold-spin-shader"
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-screen-shader-effect.lock"
PID_FILE="$LOCK_DIR/pid"
STOP_FILE="$RUNTIME_DIR/stop"

FPS="${SPIN_HOLD_FPS:-36}"
MAX_RPS="${SPIN_HOLD_MAX_RPS:-1.35}"
ACCEL_TIME="${SPIN_HOLD_ACCEL_TIME:-1.10}"
DECEL_TIME="${SPIN_HOLD_DECEL_TIME:-0.65}"
RETURN_TIME="${SPIN_HOLD_RETURN_TIME:-0.55}"

notify() {
    notify-send "$1" "$2" -i video-display \
        -h string:x-canonical-private-synchronous:hold-spin-shader 2>/dev/null || true
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
        hyprctl keyword decoration:screen_shader "$old_shader" >/dev/null 2>&1 || true
    else
        hyprctl keyword decoration:screen_shader "" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    restore_shader
    hyprctl keyword debug:damage_tracking "${old_damage:-2}" >/dev/null 2>&1 || true
    hyprctl keyword debug:vfr "${old_vfr:-true}" >/dev/null 2>&1 || true
    rm -f "$STOP_FILE" "$RUNTIME_DIR"/frame-*.frag 2>/dev/null || true

    if [[ -r "$PID_FILE" ]] && [[ "$(<"$PID_FILE")" == "$$" ]]; then
        rm -rf "$LOCK_DIR"
    fi
}

stop_effect() {
    mkdir -p "$RUNTIME_DIR"
    touch "$STOP_FILE"
}

start_effect() {
    local python_bin

    [[ -f "$TEMPLATE" ]] || {
        notify "Spin shader" "Template not found: $TEMPLATE"
        exit 1
    }

    command -v jq >/dev/null 2>&1 || {
        notify "Spin shader" "jq is not installed"
        exit 1
    }

    python_bin="$(command -v python || command -v python3 || true)"
    [[ -n "$python_bin" ]] || {
        notify "Spin shader" "python/python3 is not installed"
        exit 1
    }

    acquire_lock
    rm -f "$STOP_FILE"

    old_damage="$(get_int_option "debug:damage_tracking" "2")"
    old_vfr="$(get_bool_option "debug:vfr" "true")"
    old_shader="$(get_str_option "decoration:screen_shader" "")"

    trap cleanup EXIT
    trap 'exit 130' INT TERM HUP

    hyprctl --batch "\
keyword debug:damage_tracking 0 ; \
keyword debug:vfr false" >/dev/null

    "$python_bin" - "$TEMPLATE" "$RUNTIME_DIR" "$STOP_FILE" "$FPS" "$MAX_RPS" "$ACCEL_TIME" "$DECEL_TIME" "$RETURN_TIME" <<'PY'
import math
import os
import subprocess
import sys
import time
from pathlib import Path

template_path, runtime_dir, stop_file = sys.argv[1:4]
fps, max_rps, accel_time, decel_time, return_time = map(float, sys.argv[4:9])

fps = max(fps, 1.0)
max_rps = max(max_rps, 0.05)
accel = max_rps / max(accel_time, 0.05)
decel = max_rps / max(decel_time, 0.05)
interval = 1.0 / fps
tau = math.tau

template = Path(template_path).read_text()
runtime = Path(runtime_dir)
stop = Path(stop_file)
runtime.mkdir(parents=True, exist_ok=True)

frame_index = 0

def smoothstep(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)

def normalized_angle(angle: float) -> float:
    return (angle + math.pi) % tau - math.pi

def render(angle: float) -> None:
    global frame_index

    shader = runtime / f"frame-{frame_index % 4}.frag"
    frame_index += 1
    shader.write_text(template.replace("__ANGLE__", f"{normalized_angle(angle):.9f}"))
    subprocess.run(
        ["hyprctl", "keyword", "decoration:screen_shader", str(shader)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

def frame_sleep(started: float) -> None:
    elapsed = time.monotonic() - started
    time.sleep(max(interval - elapsed, 0.001))

angle = 0.0
speed = 0.0
last = time.monotonic()

while not stop.exists():
    frame_started = time.monotonic()
    dt = max(frame_started - last, interval)
    last = frame_started

    speed = min(max_rps, speed + accel * dt)
    angle += speed * tau * dt
    render(angle)
    frame_sleep(frame_started)

while speed > 0.001:
    frame_started = time.monotonic()
    dt = max(frame_started - last, interval)
    last = frame_started

    speed = max(0.0, speed - decel * dt)
    angle += speed * tau * dt
    render(angle)
    frame_sleep(frame_started)

start_angle = normalized_angle(angle)
frames = max(int(return_time * fps), 1)
for frame in range(frames + 1):
    frame_started = time.monotonic()
    ease = smoothstep(frame / frames)
    render(start_angle * (1.0 - ease))
    frame_sleep(frame_started)
PY
}

case "${1:-start}" in
    start)
        start_effect
        ;;
    stop)
        stop_effect
        ;;
    *)
        printf 'Usage: %s [start|stop]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

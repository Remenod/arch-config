#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-adaptive"
LANDSCAPE_CONFIG="$CONFIG_DIR/config.jsonc"
PORTRAIT_CONFIG="$CONFIG_DIR/config-portrait.jsonc"
ADAPTIVE_STYLE="$CONFIG_DIR/style-adaptive.css"
LOCK_DIR="$RUNTIME_DIR/lock"

with_lock() {
	local wait_count=0 owner

	mkdir -p "$RUNTIME_DIR"

	while ! mkdir "$LOCK_DIR" 2>/dev/null; do
		owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"

		if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
			rm -rf "$LOCK_DIR"
			continue
		fi

		if [[ -z "$owner" ]] && (( wait_count > 20 )); then
			rm -rf "$LOCK_DIR"
			wait_count=0
			continue
		fi

		(( wait_count += 1 ))
		sleep 0.05
	done

	printf '%s\n' "$$" > "$LOCK_DIR/pid"
	trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM
	"$@"
}

monitors_json() {
	if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
		return 1
	fi

	hyprctl -j monitors 2>/dev/null | jq -c '.[]'
}

monitor_mode() {
	local monitor="$1"
	local width height transform effective_width effective_height

	width="$(jq -r '.width // 0' <<< "$monitor")"
	height="$(jq -r '.height // 0' <<< "$monitor")"
	transform="$(jq -r '.transform // 0' <<< "$monitor")"

	effective_width="$width"
	effective_height="$height"
	case "$transform" in
		1|3|5|7)
			effective_width="$height"
			effective_height="$width"
			;;
	esac

	if (( effective_height > effective_width )); then
		printf 'portrait\n'
	else
		printf 'landscape\n'
	fi
}

runtime_config() {
	local target="$RUNTIME_DIR/config.json"
	local monitors

	mkdir -p "$RUNTIME_DIR"
	monitors="$(hyprctl -j monitors 2>/dev/null || printf '[]')"

	MONITORS_JSON="$monitors" python - "$LANDSCAPE_CONFIG" "$PORTRAIT_CONFIG" "$target" <<'PY'
import copy
import json
import os
import sys
from pathlib import Path

landscape_source, portrait_source, target = sys.argv[1:]
monitors = json.loads(os.environ.get("MONITORS_JSON") or "[]")

def strip_jsonc(value: str) -> str:
    result = []
    i = 0
    in_string = False
    escaped = False
    while i < len(value):
        char = value[i]
        nxt = value[i + 1] if i + 1 < len(value) else ""

        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
            continue

        if char == '"':
            in_string = True
            result.append(char)
            i += 1
            continue

        if char == "/" and nxt == "/":
            i += 2
            while i < len(value) and value[i] not in "\r\n":
                i += 1
            continue

        if char == "/" and nxt == "*":
            i += 2
            while i + 1 < len(value) and not (value[i] == "*" and value[i + 1] == "/"):
                i += 1
            i += 2
            continue

        result.append(char)
        i += 1

    return "".join(result)

def read_config(path: str) -> dict:
    return json.loads(strip_jsonc(Path(path).read_text()))

landscape_config = read_config(landscape_source)
portrait_config = read_config(portrait_source)

def monitor_mode(monitor: dict) -> str:
    width = int(monitor.get("width") or 0)
    height = int(monitor.get("height") or 0)
    transform = int(monitor.get("transform") or 0)
    if transform in (1, 3, 5, 7):
        width, height = height, width
    return "portrait" if height > width else "landscape"

bars = []
for monitor in monitors:
    output = monitor.get("name")
    if not output:
        continue

    mode = monitor_mode(monitor)
    source = portrait_config if mode == "portrait" else landscape_config
    bar = copy.deepcopy(source)
    bar["output"] = output
    bar["name"] = mode
    bars.append(bar)

if not bars:
    bar = copy.deepcopy(landscape_config)
    bar["name"] = "landscape"
    bars.append(bar)

Path(target).write_text(json.dumps(bars, ensure_ascii=False, indent="\t") + "\n")
PY

	printf '%s\n' "$target"
}

start_all() {
	local config

	config="$(runtime_config)"
	setsid -f waybar -c "$config" -s "$ADAPTIVE_STYLE" >/dev/null 2>&1
}

stop_all() {
	local count

	pkill -x waybar 2>/dev/null || true

	for count in {1..60}; do
		if ! pgrep -x waybar >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.05
	done

	pkill -KILL -x waybar 2>/dev/null || true

	for count in {1..20}; do
		if ! pgrep -x waybar >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.05
	done
}

restart_all() {
	stop_all
	start_all
}

print_modes() {
	local monitor output mode

	while IFS= read -r monitor; do
		[[ -n "$monitor" ]] || continue
		output="$(jq -r '.name' <<< "$monitor")"
		mode="$(monitor_mode "$monitor")"
		printf '%s:%s\n' "$output" "$mode"
	done < <(monitors_json || true)
}

case "${1:-run}" in
	run)
		with_lock restart_all
		;;
	reload)
		with_lock restart_all
		;;
	mode)
		print_modes
		;;
	*)
		printf 'Usage: %s [run|reload|mode]\n' "${0##*/}" >&2
		exit 2
		;;
esac

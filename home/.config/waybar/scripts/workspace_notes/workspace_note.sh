#!/bin/bash

set -u

FILE="$HOME/.config/waybar/modules/custom/workspace_notes/workspace_notes.json"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-workspace-note"
OUTPUT_NAME="${WAYBAR_OUTPUT_NAME:-global}"
SAFE_OUTPUT="${OUTPUT_NAME//[^A-Za-z0-9_.-]/_}"
PID_FILE="$RUNTIME_DIR/$SAFE_OUTPUT.pid"
nc_pid=""

mkdir -p "$RUNTIME_DIR"

if [ -r "$PID_FILE" ]; then
    old_pid="$(<"$PID_FILE")"
    if [ -n "$old_pid" ] && [ "$old_pid" != "$$" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
    fi
fi

printf '%s\n' "$$" > "$PID_FILE"

cleanup() {
    if [ -n "$nc_pid" ]; then
        kill "$nc_pid" 2>/dev/null || true
    fi

    if [ -r "$PID_FILE" ] && [ "$(<"$PID_FILE")" = "$$" ]; then
        rm -f "$PID_FILE"
    fi
}
trap cleanup EXIT INT TERM HUP

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | jq -r '.[0].instance' 2>/dev/null)
fi
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

print_note() {
    if [ -n "$WAYBAR_OUTPUT_NAME" ]; then
        current=$(hyprctl monitors -j | jq -r --arg mon "$WAYBAR_OUTPUT_NAME" '.[] | select(.name == $mon) | .activeWorkspace.id' 2>/dev/null)
    else
        current=$(hyprctl activeworkspace -j | jq -r '.id' 2>/dev/null)
    fi

    if [ -f "$FILE" ] && [ -s "$FILE" ]; then
        note=$(jq -r --arg ws "$current" '.[$ws] // "Workspace \($ws)"' "$FILE" 2>/dev/null)
    else
        note="Workspace $current"
    fi

    jq -n --unbuffered --compact-output --arg text "$note" --arg tooltip "Workspace $current" \
        '{text: $text, tooltip: $tooltip}'
}

print_note

while true; do
    coproc NC { nc -U "$SOCK"; }
    nc_pid="$NC_PID"

    while IFS= read -r line <&"${NC[0]}"; do
        case "$line" in
            "workspace>>"*|"focusedmon>>"*)
                print_note
                ;;
        esac
    done

    wait "$nc_pid" 2>/dev/null || true
    nc_pid=""
    sleep 1
done

#!/bin/bash

FILE="$HOME/.config/waybar/modules/custom/workspace_notes/workspace_notes.json"

if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
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

nc -U "$SOCK" | while read -r line; do
    case "$line" in
        "workspace>>"*|"focusedmon>>"*)
            print_note
            ;;
    esac
done

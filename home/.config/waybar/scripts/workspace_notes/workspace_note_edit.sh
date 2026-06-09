#!/usr/bin/env bash

FILE="$HOME/.config/waybar/modules/custom/workspace_notes/workspace_notes.json"

if [ ! -f "$FILE" ]; then
    mkdir -p "$(dirname "$FILE")"
    echo "{}" > "$FILE"
fi

current=$(hyprctl activeworkspace -j | jq -r '.id')
current_note=$(jq -r --arg ws "$current" '.[$ws] // ""' "$FILE")

clear
printf "\e[32mEditing note for Workspace %s\e[39m\n" "$current"

read -e -i "$current_note" -p "> " new_note

if [ -z "$new_note" ] || [ "$new_note" = "$current_note" ]; then
    exit 0
fi

tmp=$(mktemp)
jq --arg ws "$current" --arg note "$new_note" \
    '.[$ws]=$note' "$FILE" > "$tmp"

# CRITICAL FIX: Use cat to overwrite content, preserving the symlink structure
cat "$tmp" > "$FILE"
rm "$tmp"

pkill -f "workspace_note.sh"

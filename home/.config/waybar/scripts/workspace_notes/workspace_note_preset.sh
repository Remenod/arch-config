#!/usr/bin/env bash

CONFIG_DIR="$HOME/.config/waybar/modules/custom/workspace_notes"
PRESETS_DIR="$CONFIG_DIR/presets"
ACTIVE_FILE="$CONFIG_DIR/workspace_notes.json"

CREATE_PRESET="  Create preset"
RENAME_PRESET="󰑕  Rename preset"
DELETE_PRESET="󰆴  Delete preset"

cprintf() {
    printf "\e[32m%b\e[39m\n" "$@"
}

get_presets() {
    mkdir -p "$PRESETS_DIR"

    LIST=$(ls -1 "$PRESETS_DIR" 2>/dev/null | grep '\.json$' | sed 's/\.json$//')
}

select_preset() {
    local formatted_list="$CREATE_PRESET"
    formatted_list+=$'\n'"$RENAME_PRESET"
    formatted_list+=$'\n'"$DELETE_PRESET"

    # Add emoji to each existing preset for aesthetics
    for preset in $LIST; do
        formatted_list+=$'\n'"$preset"
    done

    local options=(
        "--border=sharp"
        "--border-label= Choose preset "
        "--height=~100%"
        "--highlight-line"
        "--no-input"
        "--pointer="
        "--reverse"
    )

    SELECTION=$(fzf "${options[@]}" <<< "$formatted_list")

    if [[ -z $SELECTION ]]; then
        notify-send "Workspace Notes" "No preset selected" -i "dialog-error"
        exit 1
    fi

    if [[ "$SELECTION" == "$CREATE_NEW" ]]; then
        ACTION="create"
    elif [[ "$SELECTION" == "$RENAME_PRESET" ]]; then
        ACTION="rename"
    elif [[ "$SELECTION" == "$DELETE_PRESET" ]]; then
        ACTION="delete"
    else
        ACTION="switch"
        PROFILE="${SELECTION#📝 }"
    fi
}

create_preset() {
    clear
    cprintf "Enter name for the new preset:"

    read -r -p "> " NEW_NAME

    if [[ -z "$NEW_NAME" ]]; then
        notify-send "Workspace Notes" "Creation cancelled" -i "dialog-error"
        exit 1
    fi

    echo "{}" > "$PRESETS_DIR/$NEW_NAME.json"

    PROFILE="$NEW_NAME"
    notify-send "Workspace Notes" "Created new preset: $PROFILE"
}

rename_preset() {
	local options=(
	    "--border=sharp"
    	"--border-label= Select preset to rename "
	    "--height=~100%"
    	"--highlight-line"
	    "--no-input"
    	"--pointer="
	    "--reverse"
	)

    local target=$(fzf "${options[@]}" <<< "$LIST")

    if [[ -z "$target" ]]; then
        notify-send "Workspace Notes" "Rename cancelled" -i "dialog-error"
        exit 1
    fi

    clear
    cprintf "Enter new name for $target:"
    read -r -p "> " NEW_NAME

    if [[ -z "$NEW_NAME" ]]; then
        notify-send "Workspace Notes" "Rename cancelled" -i "dialog-error"
        exit 1
    fi

    mv "$PRESETS_DIR/$target.json" "$PRESETS_DIR/$NEW_NAME.json"
    PROFILE="$NEW_NAME"
    notify-send "Workspace Notes" "Renamed preset to: $PROFILE"
}

delete_preset() {

	local options=(
    	"--border=sharp"
	    "--border-label= Select preset to delete "
    	"--height=~100%"
	    "--highlight-line"
    	"--no-input"
	    "--pointer="
    	"--reverse"
	)

    local target=$(fzf "${options[@]}" <<< "$LIST")

    if [[ -z "$target" ]]; then
        notify-send "Workspace Notes" "Deletion cancelled" -i "dialog-error"
        exit 1
    fi

    rm "$PRESETS_DIR/$target.json"
    notify-send "Workspace Notes" "Deleted preset: $target"
    exit 0
}

switch_preset() {
    cprintf "Switching to preset: $PROFILE"

    if [[ -f "$PRESETS_DIR/$PROFILE.json" ]]; then
        # CRITICAL FIX: Use symbolic link instead of copying
        ln -sf "$PRESETS_DIR/$PROFILE.json" "$ACTIVE_FILE"

        pkill -f "workspace_note.sh"

        notify-send "Workspace Notes" "Activated preset: $PROFILE" -i "dialog-ok"
    else
        notify-send "Workspace Notes" "Failed to switch preset" -i "dialog-error"
        exit 1
    fi
}

main() {
    printf "\e[?25l"
    get_presets
    printf "\e[?25h"
    select_preset
    
    if [[ "$ACTION" == "create" ]]; then
        create_preset
    elif [[ "$ACTION" == "rename" ]]; then
        rename_preset
    elif [[ "$ACTION" == "delete" ]]; then
        delete_preset
    fi

    switch_preset
}

main

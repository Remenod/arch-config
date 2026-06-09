#!/usr/bin/env bash
#
# Select and switch power profile with fzf
#
# Requirements:
# - fzf
# - notify-send
# - powerprofilesctl

TIMEOUT=10

cprintf() {
    printf "\e[32m%b\e[39m\n" "$@"
}

get_profiles() {
    if ! command -v powerprofilesctl >/dev/null 2>&1; then
        notify-send "PowerProfiles" "powerprofilesctl not found" -i "dialog-error"
        exit 1
    fi

    LIST=$(powerprofilesctl list \
        | grep -E '^\s*\*?\s*[a-zA-Z0-9-]+:$' \
        | sed 's/^[ *]*//;s/:$//')

    if [[ -z $LIST ]]; then
        notify-send "PowerProfiles" "No profiles found" -i "dialog-error"
        exit 1
    fi
}

select_profile() {
    local formatted_list=""
    first=1

    for profile in $LIST; do
        case "$profile" in
            power-saver)  emoji="  " ;;
            performance)  emoji="  " ;;
            balanced)     emoji="  " ;;
            *)            emoji="❓ " ;;
        esac

    if [[ $first -eq 1 ]]; then
        formatted_list+="$emoji$profile"
        first=0
    else
        formatted_list+=$'\n'"$emoji$profile"
    fi
done
     

    local options=(
        "--border=sharp"
        "--border-label= Power Profile "
        "--height=~100%"
        "--highlight-line"
        "--no-input"
        "--pointer="
        "--reverse"
    )

    SELECTION=$(fzf "${options[@]}" <<< "$formatted_list")
    if [[ -z $SELECTION ]]; then
        notify-send "PowerProfiles" "No profile selected" -i "dialog-error"
        exit 1
    fi

    # Витягуємо тільки назву профілю без emoji
    PROFILE=$(awk '{print $2}' <<< "$SELECTION")
}

switch_profile() {
    cprintf "Switching to profile: $PROFILE"

    if ! timeout $TIMEOUT powerprofilesctl set "$PROFILE"; then
        notify-send "PowerProfiles" "Failed to switch profile" -i "dialog-error"
        exit 1
    fi

    notify-send "PowerProfiles" "Switched to $PROFILE" -i "dialog-ok"
}

main() {
    printf "\e[?25l"  # hide cursor
    get_profiles
    printf "\e[?25h"  # unhide cursor
    select_profile
    switch_profile
}

main

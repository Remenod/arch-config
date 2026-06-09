#!/usr/bin/env bash

STATUS_FILE="$HOME/.config/waybar/.fan_control_status"

# Лише дві опції: Турбо та Звичайний
list=(
    "󱜝  Normal"
    "󱑯  Turbo"
)

options=(
    "--border=sharp"
    "--border-label= Fan Control "
    "--height=~100%"
    "--highlight-line"
    "--no-input"
    "--pointer="
    "--reverse"
)

selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}") || exit 0

case "$selected" in
    "󱑯"*)  # Turbo
        # Використовуємо команду, яку ви вказали. 
        # Додано -n, щоб уникнути блокування меню запитом пароля
        sudo -n /usr/bin/isw -cb on
        echo "Turbo" > "$STATUS_FILE"
        ;;
    "󱜝"*)  # Normal
        sudo -n /usr/bin/isw -cb off
        echo "Normal" > "$STATUS_FILE"
        ;;
esac

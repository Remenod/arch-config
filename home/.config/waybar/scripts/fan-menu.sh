#!/usr/bin/env bash

HWMON=/sys/class/hwmon/hwmon*
PWMS=($HWMON/pwm1 $HWMON/pwm2)
ENABLES=($HWMON/pwm1_enable $HWMON/pwm2_enable)
STATUS_FILE="$HOME/.config/waybar/.fan_control_status"

set_pwm() {
    local v=$1
    for e in "${ENABLES[@]}"; do echo 1 | sudo tee "$e" > /dev/null; done
    for p in "${PWMS[@]}"; do echo "$v" | sudo tee "$p" > /dev/null; done
}

list=(
    "󱜝  Auto"
    "󰠝  Off"
    "󱑲  Medium"
    "󱑳  Full"
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
    "󱜝"*)  # Auto
        sudo dell-bios-fan-control 1
	echo "Auto" > "$STATUS_FILE"
        ;;
    "󰠝"*)  # Off
        sudo dell-bios-fan-control 0
        set_pwm 0
	echo "Off" > "$STATUS_FILE"
        ;;
    "󱑲"*)  # Medium
        sudo dell-bios-fan-control 0
        set_pwm 128
	echo "Medium" > "$STATUS_FILE"
        ;;
    "󱑳"*)  # Full
        sudo dell-bios-fan-control 0
        set_pwm 255
	echo "Full" > "$STATUS_FILE"
        ;;
esac

#!/usr/bin/env bash
#
# Requirement: fzf
#
# Author:  Remenod <remenod@gmail.com>
# Date:    February 1, 2026
# License: MIT

LED=/sys/class/leds/dell::kbd_backlight/brightness

main() {
	local list=(
	    "󰹏  Off"
	    "󰌵  Low"
	    "󰛨  High"
	)

	local options=(
		"--border=sharp"
		"--border-label= Keyboard Backlight "
		"--height=~100%"
		"--highlight-line"
		"--no-input"
		"--pointer="
		"--reverse"
	)

	local selected
	selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}")

	case $selected in
	    "󰹏"* )      echo 0 | sudo tee $LED ;;
	    "󰌵"* )      echo 1 | sudo tee $LED ;;
	    "󰛨"* )      echo 2 | sudo tee $LED ;;
	    * )          exit 1 ;;
	esac
}

main

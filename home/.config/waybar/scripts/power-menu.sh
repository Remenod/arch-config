#!/usr/bin/env bash
#
# Launch a power menu
#
# Requirement: fzf
#
# Author:  Jesse Mirabel <sejjymvm@gmail.com>
# Date:    August 19, 2025
# License: MIT

main() {
	local list=(
	    "  Lock"
	    "  Shutdown"
	    "  Reboot"
	    "󰍃  Logout"
	    "󰒲  Hibernate"
	    "  Suspend"
	)

	local options=(
		"--border=sharp"
		"--border-label= Power Menu "
		"--height=~100%"
		"--highlight-line"
		"--no-input"
		"--pointer="
		"--reverse"
	)

	local selected
	selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}")

	case $selected in
	    ""* )      loginctl lock-session ;;
	    ""* )      systemctl poweroff ;;
	    ""* )      systemctl reboot ;;
	    "󰍃"* )      loginctl terminate-session "$XDG_SESSION_ID" ;;
	    "󰒲"* )      systemctl hibernate ;;
	    ""* )      systemctl suspend ;;
	    * )          exit 1 ;;
	esac
}

main

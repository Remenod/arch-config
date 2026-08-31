#!/usr/bin/env bash
#
# Launch a power menu
#
# Requirement: fzf
#
# The icons come from the Material Design range (U+F0xxx) on purpose. The
# legacy Font Awesome range (U+F000-U+F0FF) is also claimed by Courier New,
# so fontconfig hands those codepoints to Courier New instead of a Nerd Font
# and they render as blank boxes or stray dots in this popup - the popup
# terminal uses Ubuntu Mono, not a Nerd Font, so it relies on fallback.
#
# Author:  Jesse Mirabel <sejjymvm@gmail.com>
# Date:    August 19, 2025
# License: MIT

ICON_LOCK=󰌾       # md-lock
ICON_SHUTDOWN=󰐥   # md-power
ICON_REBOOT=󰜉     # md-restart
ICON_LOGOUT=󰍃     # md-logout
ICON_HIBERNATE=󰜗  # md-snowflake
ICON_SUSPEND=󰒲    # md-sleep

main() {
	local list=(
	    "$ICON_LOCK  Lock"
	    "$ICON_SHUTDOWN  Shutdown"
	    "$ICON_REBOOT  Reboot"
	    "$ICON_LOGOUT  Logout"
	    "$ICON_HIBERNATE  Hibernate"
	    "$ICON_SUSPEND  Suspend"
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
	    "$ICON_LOCK"* )       loginctl lock-session ;;
	    "$ICON_SHUTDOWN"* )   systemctl poweroff ;;
	    "$ICON_REBOOT"* )     systemctl reboot ;;
	    "$ICON_LOGOUT"* )     loginctl terminate-session "$XDG_SESSION_ID" ;;
	    "$ICON_HIBERNATE"* )  systemctl hibernate ;;
	    "$ICON_SUSPEND"* )    systemctl suspend ;;
	    * )                   exit 1 ;;
	esac
}

main

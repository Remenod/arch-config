#!/usr/bin/env bash

profile=$(cat /sys/class/leds/dell::kbd_backlight/brightness)

case "$profile" in
    0)
        emoji="󰹏"
	txt_profile="Off"
        ;;
    1)
        emoji="󰌵"
	txt_profile="Low"
        ;;
    2)
        emoji="󰛨"
	txt_profile="High"
        ;;
    *)
        emoji="❓"
        ;;
esac

echo "$emoji "
echo "Keyboard Backlight Profile: $txt_profile"

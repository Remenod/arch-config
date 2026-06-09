#!/bin/sh

hyprctl devices -j \
| jq -r '.keyboards[] | select(.main == true) | .active_keymap' \
| sed -e 's/English.*/EN/' -e 's/Ukrainian.*/UA/'

#!/usr/bin/env bash

profile=$(powerprofilesctl get)

case "$profile" in
    power-saver)
        emoji=""
        ;;
    performance)
        emoji=""
        ;;
    balanced)
        emoji=""
        ;;
    *)
        emoji="❓"
        ;;
esac

echo "$emoji"
echo "Profile: $profile"

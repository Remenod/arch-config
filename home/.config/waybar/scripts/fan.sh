PWM1="/sys/class/hwmon/hwmon*/fan1_input"
PWM2="/sys/class/hwmon/hwmon*/fan2_input"
STATUS_FILE="$HOME/.config/waybar/.fan_control_status"

profile=$(cat $STATUS_FILE)

case "$profile" in
    Auto)
        emoji="󱜝"
        ;;
    Off)
        emoji="󰠝"
        ;;
    Medium)
        emoji="󱑲"
        ;;
    Full)
        emoji="󱑳"
        ;;
    *)
        emoji="❓"
        ;;
esac

PWM1_RPM=$(cat $PWM1)
PWM2_RPM=$(cat $PWM2)

avg=$(( (PWM1_RPM + PWM2_RPM)/2 ))

tooltip="Mode: $profile\nFan1: $PWM1_RPM RPM\nFan2: $PWM2_RPM RPM"

escaped_tooltip=${tooltip//\"/\\\"}

echo "{\"text\": \"$emoji $avg\", \"tooltip\": \"$escaped_tooltip\"}"

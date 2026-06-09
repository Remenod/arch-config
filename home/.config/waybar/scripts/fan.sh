#!/bin/bash

STATUS_FILE="$HOME/.config/waybar/.fan_control_status"
profile=$(cat "$STATUS_FILE" 2>/dev/null || echo "Normal")

TMP_FILE="/tmp/waybar_fan_isw.txt"

# Отримуємо дані з isw (наш стабільний метод)
env TERM=xterm script -q "$TMP_FILE" -c "timeout 0.8 sudo -n /usr/bin/isw -r E15CKAMS" < /dev/null > /dev/null 2>&1

# Витягуємо числа
rpm_values=$(grep -oP '\d+(?=RPM)' "$TMP_FILE")
CPU_RPM=$(echo "$rpm_values" | sed -n '1p')
GPU_RPM=$(echo "$rpm_values" | sed -n '2p')

# Якщо порожньо - ставимо 0
CPU_RPM=${CPU_RPM:-0}
GPU_RPM=${GPU_RPM:-0}

# Рахуємо, скільки кулерів зараз працюють (RPM > 0)
active_fans=0
total_rpm=0

if [ "$CPU_RPM" -gt 0 ]; then
    active_fans=$((active_fans + 1))
    total_rpm=$((total_rpm + CPU_RPM))
fi

if [ "$GPU_RPM" -gt 0 ]; then
    active_fans=$((active_fans + 1))
    total_rpm=$((total_rpm + GPU_RPM))
fi

# Визначаємо, що показувати на панелі
if [ "$active_fans" -eq 2 ]; then
    display_rpm=$((total_rpm / 2)) # Середнє, якщо крутяться обидва
elif [ "$active_fans" -eq 1 ]; then
    display_rpm=$total_rpm         # Точні оберти, якщо крутиться лише один
else
    display_rpm=0                  # Обидва стоять
fi

# Логіка іконок для режиму Normal та Turbo
if [ "$profile" = "Turbo" ]; then
    emoji="󱑯"
else
    # Режим "Не турбо" (Normal)
    if [ "$active_fans" -eq 2 ]; then
        emoji="󱑳"  # Обидва крутяться
    elif [ "$active_fans" -eq 1 ]; then
        emoji="󱑲"  # Один крутиться
    else
        emoji="󰠝"  # Жоден не крутиться
    fi
fi

# Формуємо підказку
tooltip="Mode: $profile\nCPU Fan: $CPU_RPM RPM\nGPU Fan: $GPU_RPM RPM"
escaped_tooltip=${tooltip//\"/\\\"}

# Відправляємо JSON у Waybar
echo "{\"text\": \"$emoji $display_rpm\", \"tooltip\": \"$escaped_tooltip\"}"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=msi-ec.sh
source "$HOME/.config/waybar/scripts/msi-ec.sh"

notify() {
    notify-send "$1" "$2" -i "$3" \
        -h string:x-canonical-private-synchronous:msi-shift 2>/dev/null || true
}

label_for() {
    case "$1" in
        turbo)   printf "Efficiency" ;;
        comfort) printf "Balance" ;;
        eco)     printf "Powersafe" ;;
        *)       printf "%s" "$1" ;;
    esac
}

icon_for() {
    case "$1" in
        turbo)   printf "" ;;
        comfort) printf "" ;;
        eco)     printf "" ;;
        *)       printf "" ;;
    esac
}

if ! msi_ec_available; then
    notify "MSI EC" "msi-ec unavailable" "dialog-error"
    exit 1
fi

current="$(msi_ec_profile || true)"
read -r -a available_profiles <<< "$(msi_ec_available_profiles || true)"

# Порядок перемикання:
# eco -> comfort -> turbo -> eco
# Якщо хочеш навпаки — зміни порядок у цьому масиві.
preferred_order=(eco comfort turbo)

profiles=()
for profile in "${preferred_order[@]}"; do
    if msi_ec_contains_word "$profile" "${available_profiles[@]}"; then
        profiles+=("$profile")
    fi
done

if ((${#profiles[@]} == 0)); then
    notify "MSI EC" "No available shift profiles" "dialog-error"
    exit 1
fi

next="${profiles[0]}"

for i in "${!profiles[@]}"; do
    if [[ "${profiles[$i]}" == "$current" ]]; then
        next="${profiles[$(((i + 1) % ${#profiles[@]}))]}"
        break
    fi
done

if ! msi_ec_main set-profile "$next"; then
    notify "MSI EC" "Failed to set MSI shift to $next" "dialog-error"
    exit 1
fi

notify "MSI EC" "$(icon_for "$next")  MSI shift: $(label_for "$next")" "dialog-ok"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=msi-ec.sh
source "$script_dir/msi-ec.sh"

pause_on_error() {
    local title="$1"
    local message="$2"

    notify-send "$title" "$message" -i "dialog-error" 2>/dev/null || true
    printf '\n%s: %s\n' "$title" "$message" >&2
    printf 'Press Enter to close...' >&2
    read -r _ || true
}

power_current="$(powerprofiles_current || true)"
shift_current="$(msi_ec_profile || true)"

list=()
if powerprofiles_available; then
    mapfile -t power_profiles < <(powerprofiles_list || true)

    list+=("noop:"$'\t'"── powerprofilesctl ──")

    while IFS= read -r profile; do
        [[ -z "$profile" ]] && continue

        case "$profile" in
            performance) icon=""; label="Efficiency" ;;
            balanced) icon=""; label="Balance" ;;
            power-saver) icon=""; label="Powersafe" ;;
            *) icon=""; label="$profile" ;;
        esac

        prefix=""
        [[ "$profile" == "$power_current" ]] && prefix="* "
        list+=("power:$profile"$'\t'"$icon  $prefix$label power profile")
    done < <(powerprofiles_ordered "${power_profiles[@]}")
else
    list+=("noop:"$'\t'"  powerprofilesctl unavailable")
fi

if msi_ec_available; then
    read -r -a shift_profiles <<< "$(msi_ec_available_profiles)"

    list+=("noop:"$'\t'"── MSI EC shift ──")

    for shift in turbo comfort eco; do
        msi_ec_contains_word "$shift" "${shift_profiles[@]}" || continue
        case "$shift" in
            turbo) icon=""; label="Efficiency" ;;
            comfort) icon=""; label="Balance" ;;
            eco) icon=""; label="Powersafe" ;;
            *) icon=""; label="$shift" ;;
        esac

        prefix=""
        [[ "$shift" == "$shift_current" ]] && prefix="* "
        list+=("shift:$shift"$'\t'"$icon  $prefix$label MSI shift")
    done
else
    list+=("noop:"$'\t'"  msi-ec unavailable")
fi

options=(
    "--border=sharp"
    "--border-label= Power Profiles "
    "--height=~100%"
    "--highlight-line"
    "--no-input"
    "--pointer="
    "--reverse"
    "--delimiter=\t"
    "--with-nth=2.."
)

selection=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}") || exit 0
action="${selection%%$'\t'*}"
kind="${action%%:*}"
value="${action#*:}"

case "$kind" in
    power)
        if ! powerprofiles_set "$value"; then
            pause_on_error "Power Profiles" "Failed to switch to $value"
            exit 1
        fi
        notify-send "Power Profiles" "Power profile: $value" -i "dialog-ok" 2>/dev/null || true
        ;;
    shift)
        if ! msi_ec_main set-profile "$value"; then
            pause_on_error "MSI EC" "Failed to set MSI shift to $value"
            exit 1
        fi
        notify-send "MSI EC" "MSI shift: $value" -i "dialog-ok" 2>/dev/null || true
        ;;
    *)
        exit 0
        ;;
esac

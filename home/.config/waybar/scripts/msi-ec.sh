#!/usr/bin/env bash
set -euo pipefail

MSI_EC_BASE="${MSI_EC_BASE:-/sys/devices/platform/msi-ec}"
MSI_EC_PROFILE_ATTR="${MSI_EC_PROFILE_ATTR:-}"
ISW_BIN="${ISW_BIN:-/usr/bin/isw}"
ISW_EC="${ISW_EC:-E15CKAMS}"
ISW_TIMEOUT="${ISW_TIMEOUT:-0.8}"

msi_ec_available() {
    [[ -d "$MSI_EC_BASE" ]]
}

msi_ec_file() {
    printf '%s/%s\n' "$MSI_EC_BASE" "$1"
}

msi_ec_read() {
    local rel="$1"
    local fallback="${2:-unknown}"
    local file

    file="$(msi_ec_file "$rel")"
    if [[ ! -r "$file" ]]; then
        printf '%s\n' "$fallback"
        return 1
    fi

    sed -n '1{s/\r$//;p;q}' "$file"
}

msi_ec_read_words() {
    local rel="$1"
    local fallback="${2:-}"
    local file

    file="$(msi_ec_file "$rel")"
    if [[ ! -r "$file" ]]; then
        printf '%s\n' "$fallback"
        return 1
    fi

    tr '\r\n' '  ' < "$file" | xargs
}

msi_ec_write() {
    local rel="$1"
    local value="$2"
    local file

    file="$(msi_ec_file "$rel")"
    if [[ ! -e "$file" ]]; then
        notify-send "MSI EC" "Missing sysfs node: $file" -i "dialog-error" 2>/dev/null || true
        return 1
    fi

    if [[ -w "$file" ]]; then
        if ! printf '%s\n' "$value" > "$file"; then
            notify-send "MSI EC" "Failed to write $rel=$value" -i "dialog-error" 2>/dev/null || true
            return 1
        fi
    else
        notify-send "MSI EC" "No write access to $rel" -i "dialog-error" 2>/dev/null || true
        return 1
    fi
}

msi_ec_profile_attr() {
    if [[ -n "$MSI_EC_PROFILE_ATTR" ]]; then
        printf '%s\n' "$MSI_EC_PROFILE_ATTR"
    # Newer/custom msi-ec builds may expose the profile switch as "gp".
    elif [[ -r "$MSI_EC_BASE/gp" && ! -d "$MSI_EC_BASE/gp" ]]; then
        printf 'gp\n'
    else
        printf 'shift_mode\n'
    fi
}

msi_ec_available_profiles() {
    local rel

    for rel in available_gp_modes available_profiles available_shift_modes; do
        if [[ -r "$MSI_EC_BASE/$rel" ]]; then
            msi_ec_read_words "$rel"
            return 0
        fi
    done

    printf 'eco comfort turbo\n'
}

msi_ec_profile() {
    local attr

    attr="$(msi_ec_profile_attr)"
    msi_ec_read "$attr" "unknown"
}

msi_ec_contains_word() {
    local needle="$1"
    shift

    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done

    return 1
}

msi_ec_json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

powerprofiles_available() {
    command -v powerprofilesctl >/dev/null 2>&1
}

powerprofiles_current() {
    if powerprofiles_available; then
        powerprofilesctl get 2>/dev/null || printf 'unknown\n'
    else
        printf 'unknown\n'
        return 1
    fi
}

powerprofiles_list() {
    if ! powerprofiles_available; then
        return 1
    fi

    powerprofilesctl list 2>/dev/null \
        | sed -n 's/^[[:space:]*]*\([[:alnum:]-]\+\):$/\1/p'
}

powerprofiles_ordered() {
    local available=("$@")
    local profile

    for profile in performance balanced power-saver; do
        if msi_ec_contains_word "$profile" "${available[@]}"; then
            printf '%s\n' "$profile"
        fi
    done
}

powerprofiles_set() {
    local profile="$1"

    if ! powerprofiles_available; then
        notify-send "Power Profiles" "powerprofilesctl not found" -i "dialog-error" 2>/dev/null || true
        return 1
    fi

    if ! powerprofilesctl set "$profile"; then
        notify-send "Power Profiles" "Failed to switch to $profile" -i "dialog-error" 2>/dev/null || true
        return 1
    fi
}

msi_ec_is_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

msi_ec_display_speed() {
    local value="$1"

    if msi_ec_is_int "$value" && (( value > 0 )); then
        printf '%s\n' "$value"
    else
        printf '0\n'
    fi
}

msi_ec_fan_speed_label() {
    local value="$1"

    if msi_ec_is_int "$value"; then
        printf '%s RPM' "$value"
    else
        printf '%s' "$value"
    fi
}

isw_fan_rpms() {
    local tmp command rpm_values cpu_rpm gpu_rpm

    if [[ ! -x "$ISW_BIN" ]]; then
        return 1
    fi

    tmp="$(mktemp)"
    printf -v command 'timeout %q sudo -n %q -r %q' "$ISW_TIMEOUT" "$ISW_BIN" "$ISW_EC"

    env TERM=xterm script -q "$tmp" -c "$command" </dev/null >/dev/null 2>&1 || true
    rpm_values="$(grep -oE '[0-9]+[[:space:]]*RPM' "$tmp" | grep -oE '[0-9]+' || true)"
    rm -f "$tmp"

    cpu_rpm="$(sed -n '1p' <<< "$rpm_values")"
    gpu_rpm="$(sed -n '2p' <<< "$rpm_values")"

    if [[ -z "$cpu_rpm" || -z "$gpu_rpm" ]]; then
        return 1
    fi

    printf '%s %s\n' "$cpu_rpm" "$gpu_rpm"
}

msi_ec_fan_icon() {
    local cooler="$1"
    local fan_mode="$2"
    local active_fans="$3"

    if [[ "$fan_mode" == "silent" && "$active_fans" -eq 0 ]]; then
        printf '󰠝'
    elif [[ "$active_fans" -ge 2 ]]; then
        printf '󱑳'
    elif [[ "$active_fans" -eq 1 ]]; then
        printf '󱑲'
    else
        printf '󰠝'
    fi
}

msi_ec_profile_icon() {
    case "$1" in
        eco|power-saver)
            printf ''
            ;;
        comfort|balanced)
            printf ''
            ;;
        sport|turbo|performance)
            printf ''
            ;;
        *)
            printf ''
            ;;
    esac
}

powerprofiles_icon() {
    case "$1" in
        power-saver)
            printf ''
            ;;
        balanced)
            printf ''
            ;;
        performance)
            printf ''
            ;;
        *)
            printf ''
            ;;
    esac
}

msi_ec_fan_json() {
    if ! msi_ec_available; then
        printf '{"text":"󰠝 n/a","tooltip":"msi-ec is not available","class":"missing"}\n'
        return 0
    fi

    local cpu_rpm gpu_rpm cpu_display gpu_display cpu_temp gpu_temp fan_mode cooler active_fans total_rpm display_rpm icon tooltip class rpm_pair rpm_note

    cpu_temp="$(msi_ec_read cpu/realtime_temperature '?' || true)"
    gpu_temp="$(msi_ec_read gpu/realtime_temperature '?' || true)"
    fan_mode="$(msi_ec_read fan_mode unknown || true)"
    cooler="$(msi_ec_read cooler_boost unknown || true)"

    if rpm_pair="$(isw_fan_rpms)"; then
        read -r cpu_rpm gpu_rpm <<< "$rpm_pair"
        rpm_note="isw"
    else
        cpu_rpm=0
        gpu_rpm=0
        rpm_note="isw unavailable"
    fi

    msi_ec_is_int "$cpu_rpm" || cpu_rpm=0
    msi_ec_is_int "$gpu_rpm" || gpu_rpm=0
    cpu_display="$(msi_ec_display_speed "$cpu_rpm")"
    gpu_display="$(msi_ec_display_speed "$gpu_rpm")"

    active_fans=0
    total_rpm=0

    if (( cpu_display > 0 )); then
        active_fans=$((active_fans + 1))
        total_rpm=$((total_rpm + cpu_display))
    fi

    if (( gpu_display > 0 )); then
        active_fans=$((active_fans + 1))
        total_rpm=$((total_rpm + gpu_display))
    fi

    if (( active_fans > 1 )); then
        display_rpm=$((total_rpm / active_fans))
    else
        display_rpm="$total_rpm"
    fi

    icon="$(msi_ec_fan_icon "$cooler" "$fan_mode" "$active_fans")"
    printf -v tooltip 'Fan mode: %s\nCooler Boost: %s\nCPU: %sC / %s\nGPU: %sC / %s' \
        "$fan_mode" \
        "$cooler" \
        "$cpu_temp" \
        "$(msi_ec_fan_speed_label "$cpu_rpm")" \
        "$gpu_temp" \
        "$(msi_ec_fan_speed_label "$gpu_rpm")"

    if [[ "$rpm_note" != "isw" ]]; then
        tooltip+=$'\n'"RPM source: $rpm_note"
    fi
    class="$fan_mode"
    [[ "$cooler" == "on" ]] && class="boost"

    printf '{"text":"%s %s","tooltip":"%s","class":"%s"}\n' \
        "$icon" "$display_rpm" "$(msi_ec_json_escape "$tooltip")" "$(msi_ec_json_escape "$class")"
}

msi_ec_profile_json() {
    local pp_profile pp_icon msi_profile tooltip class

    pp_profile="$(powerprofiles_current || true)"
    pp_icon="$(powerprofiles_icon "$pp_profile")"

    if msi_ec_available; then
        msi_profile="$(msi_ec_profile || true)"
    else
        msi_profile="unavailable"
    fi

    printf -v tooltip 'Power profile: %s\nMSI shift: %s' \
        "$pp_profile" \
        "$msi_profile"
    class="$pp_profile"

    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
        "$pp_icon" "$(msi_ec_json_escape "$tooltip")" "$(msi_ec_json_escape "$class")"
}

msi_ec_main() {
    local attr

    case "${1:-}" in
        read)
            msi_ec_read "${2:?missing attr}"
            ;;
        write)
            msi_ec_write "${2:?missing attr}" "${3:?missing value}"
            ;;
        fan-json)
            msi_ec_fan_json
            ;;
        profile-json)
            msi_ec_profile_json
            ;;
        profile)
            msi_ec_profile
            ;;
        profile-attr)
            msi_ec_profile_attr
            ;;
        profiles)
            msi_ec_available_profiles
            ;;
        set-profile)
            attr="$(msi_ec_profile_attr)"
            msi_ec_write "$attr" "${2:?missing profile}"
            ;;
        powerprofiles)
            powerprofiles_list
            ;;
        set-powerprofile)
            powerprofiles_set "${2:?missing power profile}"
            ;;
        *)
            printf 'Usage: %s {read ATTR|write ATTR VALUE|fan-json|profile-json|profile|profile-attr|profiles|set-profile PROFILE|powerprofiles|set-powerprofile PROFILE}\n' "$0" >&2
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    msi_ec_main "$@"
fi

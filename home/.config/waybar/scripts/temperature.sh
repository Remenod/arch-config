#!/usr/bin/env bash
#
# Temperature module with a selectable sensor.
#
# Modes:
#   temperature.sh module   JSON for Waybar
#   temperature.sh next     select the next sensor
#   temperature.sh prev     select the previous sensor
#   temperature.sh menu     pick a sensor from an fzf popup
#   temperature.sh list     print the detected sensors
#
# Sensors are rediscovered on every run, because hwmon numbering is not stable
# across boots - they are matched by driver name and label instead.

set -euo pipefail

STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/.temperature_sensor"
SIGNAL=3
WARN=${WARN:-80}
CRIT=${CRIT:-90}

ICON_CRIT=󰀦

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

pango_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    printf '%s' "$value"
}

# rank|key|icon|label|path for one hwmon input, or nothing if it is not
# something worth showing.
classify() {
    local name="$1" label="$2" file="$3" dir="$4"

    case "$name" in
        k10temp|zenpower|coretemp)
            case "$label" in
                Tctl|"Package id 0"|"") printf '10|cpu|󰻠|CPU|%s\n' "$file" ;;
                Tccd*) printf '11|cpu-%s|󰻠|CPU %s|%s\n' "${label,,}" "$label" "$file" ;;
            esac
            ;;
        amdgpu)
            # A discrete Navi exposes junction/mem as well; the APU only edge.
            if [[ -e $dir/temp2_input ]]; then
                case "$label" in
                    edge) printf '20|gpu|󰢮|GPU|%s\n' "$file" ;;
                    junction) printf '21|gpu-hotspot|󰈸|GPU hotspot|%s\n' "$file" ;;
                    mem) printf '22|vram|󰍹|VRAM|%s\n' "$file" ;;
                esac
            else
                printf '30|igpu|󰡁|iGPU|%s\n' "$file"
            fi
            ;;
        nvme)
            case "$label" in
                Composite | "") printf '40|nvme|󰋊|NVMe|%s\n' "$file" ;;
            esac
            ;;
        iwlwifi*|ath*|mt79*)
            printf '50|wifi|󰖩|Wi-Fi|%s\n' "$file"
            ;;
        acpitz*)
            printf '60|board|󰰌|Board|%s\n' "$file"
            ;;
        *)
            printf '90|%s|󰔏|%s|%s\n' "${name,,}" "$name" "$file"
            ;;
    esac
}

# All sensors as "key|icon|label|path", in a stable, sensible order.
scan_sensors() {
    local dir name file label base

    for dir in /sys/class/hwmon/hwmon*; do
        [[ -r $dir/name ]] || continue
        name="$(< "$dir/name")"

        for file in "$dir"/temp*_input; do
            [[ -r $file ]] || continue
            base="${file%_input}"
            label=""
            [[ -r ${base}_label ]] && label="$(< "${base}_label")"
            classify "$name" "$label" "$file" "$dir"
        done
    done | sort -t'|' -k1,1n -k2,2 | cut -d'|' -f2-
}

read_temp() {
    local raw

    [[ -r $1 ]] || { printf '?'; return 1; }
    raw="$(< "$1")"
    [[ $raw =~ ^-?[0-9]+$ ]] || { printf '?'; return 1; }

    printf '%s' $(((raw + 500) / 1000))
}

selected_key() {
    [[ -r $STATE_FILE ]] && head -n1 "$STATE_FILE" || true
}

# Echoes the currently selected line, falling back to the first sensor when
# the stored key no longer exists (hardware or driver changed).
current_line() {
    local sensors="$1" want line

    want="$(selected_key)"

    if [[ -n $want ]]; then
        while IFS= read -r line; do
            [[ ${line%%|*} == "$want" ]] && { printf '%s' "$line"; return 0; }
        done <<< "$sensors"
    fi

    head -n1 <<< "$sensors"
}

cycle() {
    local step="$1" sensors keys count i want
    sensors="$(scan_sensors)"
    [[ -n $sensors ]] || return 0

    mapfile -t keys < <(cut -d'|' -f1 <<< "$sensors")
    count=${#keys[@]}
    want="$(selected_key)"

    for ((i = 0; i < count; i++)); do
        [[ ${keys[i]} == "$want" ]] && break
    done
    ((i == count)) && i=0

    i=$(((i + step + count) % count))
    printf '%s\n' "${keys[i]}" > "$STATE_FILE"

    pkill -RTMIN+$SIGNAL waybar 2> /dev/null || true
}

build_tooltip() {
    local sensors="$1" active="$2" line key icon label path temp out=""

    while IFS='|' read -r key icon label path; do
        [[ -n $key ]] || continue
        temp="$(read_temp "$path" || true)"

        if [[ $key == "$active" ]]; then
            line="$(printf '%s  <b>%-12s %3s °C</b>' "$icon" "$(pango_escape "$label")" "$temp")"
        else
            line="$(printf '%s  %-12s %3s °C' "$icon" "$(pango_escape "$label")" "$temp")"
        fi

        out+="$line"$'\n'
    done <<< "$sensors"

    out+="<span alpha='55%'>scroll to switch · click to pick</span>"
    printf '%s' "$out"
}

module() {
    local sensors line key icon label path temp class tooltip

    sensors="$(scan_sensors)"

    if [[ -z $sensors ]]; then
        printf '{"text":"%s n/a","tooltip":"No temperature sensors found","class":"missing"}\n' "$ICON_CRIT"
        return 0
    fi

    line="$(current_line "$sensors")"
    IFS='|' read -r key icon label path <<< "$line"
    temp="$(read_temp "$path" || true)"

    class=""
    if [[ $temp =~ ^[0-9]+$ ]]; then
        if ((temp >= CRIT)); then
            class="critical"
            icon="$ICON_CRIT"
        elif ((temp >= WARN)); then
            class="warning"
        fi
    fi

    tooltip="$(build_tooltip "$sensors" "$key")"

    printf '{"text":"%s %s°C","tooltip":"%s","class":"%s"}\n' \
        "$icon" "$temp" "$(json_escape "$tooltip")" "$class"
}

menu() {
    local sensors list=() key icon label path temp active selected

    sensors="$(scan_sensors)"
    active="$(cut -d'|' -f1 <<< "$(current_line "$sensors")")"

    while IFS='|' read -r key icon label path; do
        [[ -n $key ]] || continue
        temp="$(read_temp "$path" || true)"
        [[ $key == "$active" ]] && prefix="* " || prefix="  "
        list+=("$key"$'\t'"$icon  $prefix$(printf '%-12s %3s °C' "$label" "$temp")")
    done <<< "$sensors"

    selected="$(printf '%s\n' "${list[@]}" | fzf \
        --border=sharp \
        --border-label=' Temperature Sensor ' \
        --height=~100% \
        --highlight-line \
        --no-input \
        --pointer= \
        --reverse \
        --delimiter=$'\t' \
        --with-nth=2..)" || exit 0

    printf '%s\n' "${selected%%$'\t'*}" > "$STATE_FILE"
    pkill -RTMIN+$SIGNAL waybar 2> /dev/null || true
}

case "${1:-module}" in
    module) module ;;
    next) cycle 1 ;;
    prev) cycle -1 ;;
    menu) menu ;;
    list) scan_sensors ;;
    *)
        printf 'Usage: %s {module|next|prev|menu|list}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

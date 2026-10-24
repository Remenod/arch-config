#!/usr/bin/env bash
#
# Temperature module with a selectable sensor.
#
# Modes:
#   temperature.sh module   long-running daemon, one JSON line per tick (no "interval")
#   temperature.sh once     print a single JSON line and exit (handy for debugging)
#   temperature.sh next     select the next sensor
#   temperature.sh prev     select the previous sensor
#   temperature.sh menu     pick a sensor from an fzf popup
#   temperature.sh list     print the detected sensors
#
# Sensors are matched by driver name and label instead of hwmon number,
# which is not stable across boots. The daemon rediscovers them every
# RESCAN_EVERY ticks, and on the next tick when a sensor file disappears.
#
# Ahead of the sensors sits "auto": it follows whichever sensor is hottest at
# the moment and shows that sensor's icon. It is also the fallback when
# nothing is selected yet.
#
# A tick reads sysfs with builtins and forks nothing. Between ticks the daemon
# waits on a fifo of its own; next, prev and menu write to every such fifo, so
# a new choice shows at once rather than on the next tick.

set -euo pipefail

STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/.temperature_sensor"
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-temperature"
INTERVAL=${INTERVAL:-2}            # seconds between ticks
RESCAN_EVERY=${RESCAN_EVERY:-30}   # rediscover the sensors every N ticks
WARN=${WARN:-80}
CRIT=${CRIT:-90}

ICON_AUTO=󱃂
ICON_NONE=󰔏

# The sensors as parallel arrays, in display order. TEMPS holds the last
# reading of each: whole degrees, or the bare word "off" or "?".
declare -a KEYS=() ICONS=() LABELS=() PATHS=() TEMPS=() MENU=()
HOT=-1          # index of the hottest sensor, -1 while none has a reading
ACTIVE=auto     # the selected key ...
ACTIVE_I=-1     # ... and its index, -1 for auto
RESCAN=0        # set when a sensor file vanished
TEMP=""
TOOLTIP=""
WAKE_FD=""

# json_escape VAR VALUE sets VAR to VALUE escaped for a JSON string.
json_escape() {
    local _value="$2"
    _value="${_value//\\/\\\\}"
    _value="${_value//\"/\\\"}"
    _value="${_value//$'\n'/\\n}"
    printf -v "$1" '%s' "$_value"
}

# pango_escape VAR VALUE sets VAR to VALUE escaped for Pango markup.
pango_escape() {
    local _value="$2"
    _value="${_value//&/&amp;}"
    _value="${_value//</&lt;}"
    _value="${_value//>/&gt;}"
    printf -v "$1" '%s' "$_value"
}

# with_unit VAR READING UNIT sets VAR to "45 °C" for a reading, to the bare
# word ("off", "?") otherwise.
with_unit() {
    if [[ $2 =~ ^-?[0-9]+$ ]]; then
        printf -v "$1" '%s%s' "$2" "$3"
    else
        printf -v "$1" '%s' "$2"
    fi
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
        name=""
        read -r name < "$dir/name" || true
        [[ -n $name ]] || continue

        for file in "$dir"/temp*_input; do
            [[ -r $file ]] || continue
            base="${file%_input}"
            label=""
            [[ -r ${base}_label ]] && { read -r label < "${base}_label" || true; }
            classify "$name" "$label" "$file" "$dir"
        done
    done | sort -t'|' -k1,1n -k2,2 | cut -d'|' -f2-
}

# Fills KEYS, ICONS, LABELS and PATHS from scan_sensors.
load_sensors() {
    local key icon label path

    KEYS=() ICONS=() LABELS=() PATHS=()

    while IFS='|' read -r key icon label path; do
        [[ -n $key ]] || continue
        KEYS+=("$key")
        ICONS+=("$icon")
        LABELS+=("$label")
        PATHS+=("$path")
    done < <(scan_sensors)
}

# Sets TEMP to the temp*_input at $1 in whole degrees. A powered-off device
# has no reading: amdgpu refuses temp*_input while the dGPU sits in D3cold
# (and does not wake it for that), so that reads "off" instead of "?".
read_temp() {
    local raw="" state="" state_file="${1%/*}/device/power_state"

    TEMP="?"
    if [[ -r $state_file ]]; then
        read -r state < "$state_file" || true
        if [[ $state == D3cold ]]; then
            TEMP="off"
            return 0
        fi
    fi

    { read -r raw < "$1"; } 2> /dev/null || true
    [[ $raw =~ ^-?[0-9]+$ ]] && TEMP=$(((raw + 500) / 1000))
    return 0
}

# Reads every sensor into TEMPS and finds the hottest; on a tie the sensor
# listed first wins.
read_all() {
    local i best=0

    TEMPS=()
    HOT=-1

    for i in "${!PATHS[@]}"; do
        [[ -e ${PATHS[i]} ]] || RESCAN=1
        read_temp "${PATHS[i]}"
        TEMPS[i]=$TEMP
        [[ $TEMP =~ ^-?[0-9]+$ ]] || continue

        if ((HOT < 0 || TEMP > best)); then
            HOT=$i
            best=$TEMP
        fi
    done
}

# Sets ACTIVE and ACTIVE_I to the selected sensor, falling back to "auto" when
# nothing is stored or the stored sensor no longer exists (hardware or driver
# changed).
find_active() {
    local want="" i

    ACTIVE=auto
    ACTIVE_I=-1
    [[ -r $STATE_FILE ]] && { read -r want < "$STATE_FILE" || true; }

    for i in "${!KEYS[@]}"; do
        if [[ ${KEYS[i]} == "$want" ]]; then
            ACTIVE="$want"
            ACTIVE_I=$i
            return 0
        fi
    done
}

# Appends a tooltip row to TOOLTIP: key, icon, label, reading. The selected
# row is bold; while auto is selected, an arrow marks the sensor it follows.
tooltip_row() {
    local shown name row

    with_unit shown "$4" ' °C'
    pango_escape name "$3"

    if [[ $1 == "$ACTIVE" ]]; then
        printf -v row '%s  <b>%-12s %6s</b>' "$2" "$name" "$shown"
    else
        printf -v row '%s  %-12s %6s' "$2" "$name" "$shown"
    fi
    [[ $ACTIVE == auto ]] && ((HOT >= 0)) && [[ $1 == "${KEYS[HOT]}" ]] && row+=" ←"

    TOOLTIP+="$row"$'\n'
}

emit() {
    local i icon temp shown class="" auto_temp="?" tooltip_json

    if ((${#KEYS[@]} == 0)); then
        printf '{"text":"%s n/a","tooltip":"No temperature sensors found","class":"missing"}\n' "$ICON_NONE"
        return 0
    fi

    # Auto shows the hottest sensor as if it were the selected one.
    i=$ACTIVE_I
    [[ $ACTIVE == auto ]] && i=$HOT

    if ((i >= 0)); then
        icon="${ICONS[i]}"
        temp="${TEMPS[i]}"
    else
        icon="$ICON_AUTO"
        temp="?"
    fi

    if [[ $temp =~ ^[0-9]+$ ]]; then
        if ((temp >= CRIT)); then
            class="critical"
        elif ((temp >= WARN)); then
            class="warning"
        fi
    fi

    ((HOT >= 0)) && auto_temp="${TEMPS[HOT]}"
    TOOLTIP=""
    tooltip_row auto "$ICON_AUTO" Auto "$auto_temp"
    for i in "${!KEYS[@]}"; do
        tooltip_row "${KEYS[i]}" "${ICONS[i]}" "${LABELS[i]}" "${TEMPS[i]}"
    done
    TOOLTIP+="<span alpha='55%'>scroll to switch · click to pick</span>"

    with_unit shown "$temp" '°C'
    json_escape tooltip_json "$TOOLTIP"
    printf '{"text":"%s %s","tooltip":"%s","class":"%s"}\n' \
        "$icon" "$shown" "$tooltip_json" "$class"
}

# The fifo next, prev and menu poke. Held open read-write, so the timed read
# on it waits out the whole interval without a sleep child.
open_wake() {
    local fifo="$RUNDIR/wake.$$"

    mkdir -p "$RUNDIR"
    rm -f "$fifo"
    mkfifo "$fifo" 2> /dev/null || return 1
    exec {WAKE_FD}<> "$fifo"
}

naptime() {
    if [[ -n $WAKE_FD ]]; then
        read -r -t "$INTERVAL" -u "$WAKE_FD" _ || true
    else
        sleep "$INTERVAL"
    fi
}

# Pokes every running daemon. Opening a fifo read-write never blocks, so one
# left behind by a daemon that died without cleaning up cannot hang this;
# such fifos are removed.
wake() {
    local fifo

    for fifo in "$RUNDIR"/wake.*; do
        [[ -p $fifo ]] || continue
        if kill -0 "${fifo##*.}" 2> /dev/null; then
            printf '\n' 1<> "$fifo" || true
        else
            rm -f "$fifo"
        fi
    done
}

module() {
    local tick=0

    trap 'rm -f "$RUNDIR/wake.$$"' EXIT
    # Exiting from the handler rather than falling through it stops the shell
    # from announcing the interrupted read on Waybar's stderr at shutdown.
    trap 'exit 0' INT TERM HUP
    open_wake || true

    while true; do
        if ((tick % RESCAN_EVERY == 0 || RESCAN)); then
            load_sensors
            RESCAN=0
        fi

        read_all
        find_active
        emit
        tick=$((tick + 1))
        naptime
    done
}

once() {
    load_sensors
    read_all
    find_active
    emit
}

cycle() {
    local step="$1" keys count i

    load_sensors
    ((${#KEYS[@]} > 0)) || return 0
    find_active

    # Auto sits in front, and ACTIVE_I is -1 for it.
    keys=(auto "${KEYS[@]}")
    count=${#keys[@]}
    i=$(((ACTIVE_I + 1 + step + count) % count))

    printf '%s\n' "${keys[i]}" > "$STATE_FILE"
    wake
}

# Appends an fzf line to MENU: the key, a tab, then what is shown.
menu_row() {
    local prefix="  " shown row

    [[ $1 == "$ACTIVE" ]] && prefix="* "
    with_unit shown "$4" ' °C'
    printf -v row '%s\t%s  %s%-12s %6s' "$1" "$2" "$prefix" "$3" "$shown"
    MENU+=("$row")
}

menu() {
    local i auto_temp="?" selected

    load_sensors
    read_all
    find_active

    MENU=()
    ((HOT >= 0)) && auto_temp="${TEMPS[HOT]}"
    menu_row auto "$ICON_AUTO" Auto "$auto_temp"
    for i in "${!KEYS[@]}"; do
        menu_row "${KEYS[i]}" "${ICONS[i]}" "${LABELS[i]}" "${TEMPS[i]}"
    done

    selected="$(printf '%s\n' "${MENU[@]}" | fzf \
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
    wake
}

case "${1:-module}" in
    module) module ;;
    once) once ;;
    next) cycle 1 ;;
    prev) cycle -1 ;;
    menu) menu ;;
    list) scan_sensors ;;
    *)
        printf 'Usage: %s {module|once|next|prev|menu|list}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

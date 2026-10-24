#!/usr/bin/env bash
#
# Bluetooth menu for Waybar.
#
#   bluetooth.sh          the menu, meant for a terminal popup
#   bluetooth.sh toggle   turn Bluetooth on or off
#
# Opens at once with the known devices - no scan to sit through. r scans for
# new ones, for SCAN_SECONDS at most and never past closing the menu. Every
# refresh reads the whole state from BlueZ in one D-Bus call.
#
# Keys, also shown in the footer: enter connects or disconnects (a new device
# is paired and trusted first), r scans, t trusts or untrusts, f forgets
# (press twice), b turns Bluetooth off and on, a also lists devices without
# a name, / filters, i hides the details, q quits. Disconnecting and turning
# Bluetooth off with a device connected take a second press.
#
# Grew out of the scanner by Jesse Mirabel (MIT).

set -euo pipefail

MENU_NAME=bluetooth
LETTERS=(r t f b a)
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib/connect-menu.sh"

SCAN_SECONDS=30
SCAN_PID_FILE="$STATE_DIR/scan.pid"
SNAPSHOT="$STATE_DIR/snapshot"

ICON_ON=󰂯
ICON_OFF=󰂲
ICON_SCAN=󰐷
ICON_BATTERY=󰁹

# One GetManagedObjects reply turned into lines: the first adapter, then its
# devices. Booleans come out as "true"/"false", absent numbers as "". Fields
# are split by \x1f, not tabs: IFS whitespace would merge empty fields.
BLUEZ_JQ='
def text: tostring | gsub("[\u0000-\u001f\u007f]"; "");
def line: map(text) | join("\u001f");
.data[0] as $objects
| ($objects | to_entries | map(select(.value["org.bluez.Adapter1"])) | sort_by(.key) | first) as $adapter
| if $adapter == null then empty else
    ($adapter.value["org.bluez.Adapter1"] as $a
     | ["adapter", $adapter.key, $a.Powered.data, ($a.PowerState.data // ""), $a.Discovering.data] | line),
    ($objects | to_entries[]
     | select(.key | startswith($adapter.key + "/dev_"))
     | .value as $v
     | ($v["org.bluez.Device1"] // empty) as $d
     | ["device", $d.Address.data, (if $d.Name then "1" else "0" end), ($d.Alias.data // ""),
        ($d.Icon.data // ""), $d.Paired.data, $d.Connected.data, $d.Trusted.data, ($d.RSSI.data // ""),
        ($v["org.bluez.Battery1"].Percentage.data // ""), (($d.UUIDs.data // []) | join(","))] | line)
  end'

# What BlueZ reported, filled by read_snapshot. rows rebuilds the snapshot
# every second; the other callbacks only read it.
ADAPTER=""
POWERED=false
POWER_STATE=""
DISCOVERING=false
declare -a DEV_ORDER=()
declare -A DEV_NAMED=() DEV_ALIAS=() DEV_ICON=() DEV_PAIRED=() DEV_CONNECTED=() DEV_TRUSTED=() \
    DEV_RSSI=() DEV_BATTERY=() DEV_UUIDS=()

build_snapshot() {
    busctl --system --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects 2> /dev/null |
        jq -r "$BLUEZ_JQ" > "$SNAPSHOT.$$" 2> /dev/null || true
    mv -f "$SNAPSHOT.$$" "$SNAPSHOT"
}

read_snapshot() {
    local kind a b c d e f g h i j

    [[ -r $SNAPSHOT ]] || build_snapshot

    while IFS=$'\037' read -r kind a b c d e f g h i j; do
        case $kind in
            adapter) ADAPTER=$a POWERED=$b POWER_STATE=$c DISCOVERING=$d ;;
            device)
                [[ $a =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || continue
                DEV_ORDER+=("$a")
                DEV_NAMED[$a]=$b
                DEV_ALIAS[$a]=$c
                DEV_ICON[$a]=$d
                DEV_PAIRED[$a]=$e
                DEV_CONNECTED[$a]=$f
                DEV_TRUSTED[$a]=$g
                [[ $h =~ ^-?[0-9]+$ ]] && DEV_RSSI[$a]=$h
                [[ $i =~ ^[0-9]+$ ]] && DEV_BATTERY[$a]=$i
                DEV_UUIDS[$a]=$j
                ;;
        esac
    done < "$SNAPSHOT"

    return 0
}

dev_path() {
    printf '%s/dev_%s' "$ADAPTER" "${1//:/_}"
}

device_icon() {
    case $1 in
        audio-headset | audio-headphones) printf '󰋋' ;;
        audio-card) printf '󰓃' ;;
        input-mouse) printf '󰍽' ;;
        input-keyboard) printf '󰌌' ;;
        input-gaming) printf '󰊗' ;;
        input-tablet) printf '󰓶' ;;
        phone) printf '󰄜' ;;
        computer) printf '󰌢' ;;
        video-display) printf '󰍹' ;;
        printer) printf '󰐪' ;;
        *) printf '%s' "$ICON_ON" ;;
    esac
}

device_kind() {
    case $1 in
        audio-headset | audio-headphones) printf 'headphones' ;;
        audio-card) printf 'speaker' ;;
        input-mouse) printf 'mouse' ;;
        input-keyboard) printf 'keyboard' ;;
        input-gaming) printf 'game controller' ;;
        input-tablet) printf 'tablet' ;;
        phone) printf 'phone' ;;
        computer) printf 'computer' ;;
        video-display) printf 'display' ;;
        printer) printf 'printer' ;;
        *) printf 'device' ;;
    esac
}

# What a device can do, from its service UUIDs.
device_profiles() {
    local uuid short out=""

    for uuid in ${1//,/ }; do
        short="${uuid:4:4}"
        case $short in
            110b) short=audio ;;
            110a) short='audio source' ;;
            110c | 110e | 110f) short='media keys' ;;
            1108 | 111e) short=calls ;;
            1124 | 1812) short=input ;;
            180f) short=battery ;;
            1101) short=serial ;;
            1105 | 1106) short=files ;;
            1115 | 1116) short=network ;;
            *) continue ;;
        esac
        [[ ", $out, " == *", $short, "* ]] || out+="${out:+, }$short"
    done

    printf '%s' "$out"
}

battery_label() {
    [[ -z ${DEV_BATTERY[$1]-} ]] || printf '%s %s%%' "$ICON_BATTERY" "${DEV_BATTERY[$1]}"
}

connected_names() {
    local addr out=""

    for addr in "${DEV_ORDER[@]}"; do
        [[ ${DEV_CONNECTED[$addr]} == true ]] && out+="${out:+, }${DEV_ALIAS[$addr]}"
    done

    printf '%s' "$out"
}

scan_running() {
    local pid cmdline

    [[ -r $SCAN_PID_FILE ]] || return 1
    pid="$(< "$SCAN_PID_FILE")"
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    # The pid file outlives a scan that timed out; make sure the pid is still
    # our scanner before trusting - or killing - it.
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null)" || return 1
    [[ $cmdline == *bluetoothctl*' scan on '* ]]
}

# The scanner gets a session of its own, so closing the terminal cannot
# hang it up mid-scan, and a timeout of its own, so it ends even if nothing
# stops it.
scan_start() {
    scan_running && return 0

    setsid -f bash -c 'printf "%s\n" "$$" > "$1"; exec bluetoothctl --timeout "$2" scan on' \
        _ "$SCAN_PID_FILE" "$SCAN_SECONDS" > /dev/null 2>&1 < /dev/null
    printf '%s\n' "$EPOCHSECONDS" > "$STATE_DIR/scan.start"
}

# Ends the scan. If the scanning client is killed abruptly - by closing the
# terminal, say - BlueZ can keep the discovery session with no owner. The
# adapter then keeps hopping the 2.4GHz band, which starves A2DP audio until
# it is power-cycled, and no later "bluetoothctl scan off" can clear it. So
# the scanner always gets a SIGTERM, which bluetoothctl handles cleanly, and
# a "scan off" after it.
scan_stop() {
    local pid i

    if scan_running; then
        pid="$(< "$SCAN_PID_FILE")"
        kill "$pid" 2> /dev/null || true
        for ((i = 0; i < 40; i++)); do
            kill -0 "$pid" 2> /dev/null || break
            sleep 0.05
        done
        bluetoothctl scan off > /dev/null 2>&1 || true
    fi

    rm -f "$SCAN_PID_FILE" "$STATE_DIR/scan.start"
}

scan_left() {
    local start

    [[ -r $STATE_DIR/scan.start ]] || return 0
    start="$(< "$STATE_DIR/scan.start")"
    [[ $start =~ ^[0-9]+$ ]] || return 0
    printf '%s' $((SCAN_SECONDS - (EPOCHSECONDS - start)))
}

rows() {
    local addr alias rank order rssi status nameless=0 signal lines=()

    build_snapshot
    read_snapshot

    if [[ -z $ADAPTER ]]; then
        printf 'none\t%s  %sNo Bluetooth adapter found%s\n' "$ICON_OFF" "$RED" "$RESET"
        return 0
    fi

    if [[ $POWERED != true ]]; then
        if [[ $POWER_STATE == off-blocked ]]; then
            printf 'power\t%s  Bluetooth is blocked   %senter unblocks it%s\n' "$ICON_OFF" "$DIM" "$RESET"
        else
            printf 'power\t%s  Bluetooth is off   %senter turns it on%s\n' "$ICON_OFF" "$DIM" "$RESET"
        fi
        return 0
    fi

    for addr in "${DEV_ORDER[@]}"; do
        alias="${DEV_ALIAS[$addr]}"
        order=0
        signal=""

        if [[ ${DEV_CONNECTED[$addr]} == true ]]; then
            rank=0
            alias="$BOLD$(pad "$alias" 24)$RESET"
            status="$GREEN$ICON_OK connected$RESET"
        elif [[ ${DEV_PAIRED[$addr]} == true ]]; then
            rank=1
            alias="$(pad "$alias" 24)"
            status="${DIM}paired$RESET"
        else
            # Nameless devices are mostly BLE beacons and trackers.
            if [[ ${DEV_NAMED[$addr]} != 1 && ! -e $STATE_DIR/all ]]; then
                nameless=$((nameless + 1))
                continue
            fi
            rank=2
            alias="$(pad "$alias" 24)"
            rssi="${DEV_RSSI[$addr]-}"
            if [[ -n $rssi ]]; then
                order=$((200 + rssi))
                signal=" $rssi dBm"
            fi
            status="${DIM}new$signal$RESET"
        fi
        [[ -n ${PENDING["dev:$addr"]-} ]] && status="$YELLOW$ICON_BUSY ${PENDING["dev:$addr"]}…$RESET"

        lines+=("$(printf '%s\t%03d\t%s\tdev:%s\t%s  %s %7s  %s' "$rank" "$order" "${DEV_ALIAS[$addr],,}" "$addr" \
            "$(device_icon "${DEV_ICON[$addr]}")" "$alias" "$(battery_label "$addr")" "$status")")
    done

    printf '%s\n' "$nameless" > "$STATE_DIR/nameless"

    if ((${#lines[@]})); then
        printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1n -k2,2nr -k3,3 | cut -f4-
    elif ! scan_running; then
        printf 'scan\t%s  No devices yet   %senter or r looks for some%s\n' "$ICON_SCAN" "$DIM" "$RESET"
    fi
}

header() {
    local message names left nameless=0

    message="$(said)"
    if [[ -n $message ]]; then
        printf '%s' "$message"
        return 0
    fi

    read_snapshot

    if [[ -z $ADAPTER ]]; then
        printf '%s  %sno adapter%s' "$ICON_OFF" "$RED" "$RESET"
        return 0
    elif [[ $POWERED != true ]]; then
        printf '%s  %sBluetooth is off%s' "$ICON_OFF" "$DIM" "$RESET"
        return 0
    fi

    names="$(connected_names)"
    if [[ -n $names ]]; then
        printf '%s  %s%s%s' "$ICON_ON" "$GREEN" "$names" "$RESET"
    else
        printf '%s  %sno device connected%s' "$ICON_ON" "$DIM" "$RESET"
    fi

    if scan_running; then
        left="$(scan_left)"
        printf '   %s%s scanning%s…%s' "$YELLOW" "$ICON_SCAN" "${left:+ ${left}s}" "$RESET"
    elif [[ $DISCOVERING == true ]]; then
        printf '   %s%s another app is scanning%s' "$DIM" "$ICON_SCAN" "$RESET"
    fi

    [[ -r $STATE_DIR/nameless ]] && nameless="$(< "$STATE_DIR/nameless")"
    if [[ $nameless =~ ^[0-9]+$ ]] && ((nameless > 0)); then
        printf '   %s%s without a name hidden%s' "$DIM" "$nameless" "$RESET"
    fi

    return 0
}

footer() {
    local key="$1" addr item="" trust scan

    read_snapshot

    case $key in
        power) item="$(hints enter "turn Bluetooth on")" ;;
        scan) item="$(hints enter 'scan for devices')" ;;
        dev:*)
            addr="${key#dev:}"
            [[ ${DEV_TRUSTED[$addr]-} == true ]] && trust=untrust || trust=trust
            if [[ ${DEV_CONNECTED[$addr]-} == true ]]; then
                item="$(hints enter×2 disconnect t "$trust" f×2 forget)"
            elif [[ ${DEV_PAIRED[$addr]-} == true ]]; then
                item="$(hints enter connect t "$trust" f×2 forget)"
            else
                item="$(hints enter 'pair and connect')"
            fi
            ;;
    esac

    scan_running && scan='stop scan' || scan=scan

    printf '%s\n%s' "$item" "$(hints r "$scan" b power a nameless / find i info q quit)"
}

field() {
    printf '%s%-10s%s %s\n' "$DIM" "$1" "$RESET" "$2"
}

preview() {
    local key="$1" addr status profiles

    read_snapshot

    case $key in
        none)
            printf '%sNo adapter%s\n\nBlueZ reports no Bluetooth controller. Is bluetooth.service running?\n' "$BOLD" "$RESET"
            ;;
        power)
            printf '%sBluetooth is off%s\n\nEnter or b turns it on.\n' "$BOLD" "$RESET"
            ;;
        scan)
            printf '%sNo devices yet%s\n\nPut the device in pairing mode, then scan.\n' "$BOLD" "$RESET"
            ;;
        dev:*)
            addr="${key#dev:}"
            [[ -n ${DEV_ALIAS[$addr]+x} ]] || return 0

            printf '%s%s%s\n' "$BOLD" "${DEV_ALIAS[$addr]}" "$RESET"
            printf '%s %s  %s%s%s\n\n' "$(device_icon "${DEV_ICON[$addr]}")" "$(device_kind "${DEV_ICON[$addr]}")" \
                "$DIM" "$addr" "$RESET"

            if [[ ${DEV_CONNECTED[$addr]} == true ]]; then
                status="${GREEN}connected$RESET"
            elif [[ ${DEV_PAIRED[$addr]} == true ]]; then
                status=paired
            else
                status='not paired'
            fi
            [[ ${DEV_TRUSTED[$addr]} == true ]] && status+=' · trusted'
            field Status "$status"

            [[ -z ${DEV_BATTERY[$addr]-} ]] || field Battery "${DEV_BATTERY[$addr]}%"
            [[ -z ${DEV_RSSI[$addr]-} ]] || field Signal "${DEV_RSSI[$addr]} dBm"
            profiles="$(device_profiles "${DEV_UUIDS[$addr]}")"
            [[ -z $profiles ]] || field Profiles "$profiles"

            if [[ ${DEV_TRUSTED[$addr]} == true ]]; then
                printf '\n%sTrusted: it may connect by itself.%s\n' "$DIM" "$RESET"
            elif [[ ${DEV_PAIRED[$addr]} == true ]]; then
                printf '\n%sNot trusted: it connects only from here. t trusts it.%s\n' "$DIM" "$RESET"
            fi
            ;;
    esac
}

# Turns a busctl failure into something short enough for the status line.
bz_error() {
    case $1 in
        *page-timeout* | *'Host is down'* | *'Page Timeout'*) printf 'not responding - is it on and nearby?' ;;
        *profile-unavailable* | *'Protocol not available'*) printf 'no usable profile - is the audio server running?' ;;
        *'In Progress'* | *'InProgress'*) printf 'already connecting' ;;
        *'AuthenticationFailed'* | *'Authentication Failed'*) printf 'pairing rejected' ;;
        *'Timeout was reached'* | *'Connection timed out'*) printf 'timed out' ;;
        *)
            local line="${1%%$'\n'*}"
            line="${line#Call failed: }"
            printf '%s' "${line:-failed}"
            ;;
    esac
}

on_enter() {
    local key="$1" addr

    read_snapshot
    load_pending

    if [[ -n ${PENDING[$key]-} ]]; then
        say info "Still ${PENDING[$key]}…"
        refreshed
        return 0
    fi

    case $key in
        power) spawn power 'turning on' power on ;;
        scan)
            scan_start
            say info "Scanning for ${SCAN_SECONDS}s - put the device in pairing mode"
            ;;
        dev:*)
            addr="${key#dev:}"
            if [[ ${DEV_CONNECTED[$addr]-} == true ]]; then
                if confirmed "enter:$key"; then
                    spawn "$key" disconnecting disconnect "$addr"
                else
                    say info "Press enter again to disconnect ${DEV_ALIAS[$addr]}"
                fi
            elif [[ ${DEV_PAIRED[$addr]-} == true ]]; then
                spawn "$key" connecting connect "$addr"
            else
                # Pairing may ask to confirm a code: in the terminal.
                printf 'execute(%s pair {1})+%s' "$SELF_Q" "$REFRESH"
                return 0
            fi
            ;;
    esac

    refreshed
}

on_key() {
    local letter="$1" key="$2" addr="${2#dev:}" names

    read_snapshot

    case $letter in
        r)
            if scan_running; then
                scan_stop
                say info 'Scan stopped'
            elif [[ $POWERED != true ]]; then
                say info 'Bluetooth is off - b turns it on'
            else
                scan_start
                say info "Scanning for ${SCAN_SECONDS}s - put the device in pairing mode"
            fi
            ;;
        t)
            if [[ $key != dev:* || ${DEV_PAIRED[$addr]-} != true ]]; then
                say info 'Only paired devices can be trusted'
            elif [[ ${DEV_TRUSTED[$addr]} == true ]]; then
                spawn "$key" untrusting trust "$addr" false
            else
                spawn "$key" trusting trust "$addr" true
            fi
            ;;
        f)
            if [[ $key != dev:* || -z ${DEV_ALIAS[$addr]+x} ]]; then
                say info 'Nothing to forget here'
            elif confirmed "f:$key"; then
                spawn "$key" forgetting forget "$addr"
            else
                say info "Press f again to forget ${DEV_ALIAS[$addr]}"
            fi
            ;;
        b)
            names="$(connected_names)"
            if [[ $POWERED != true ]]; then
                spawn power 'turning on' power on
            elif [[ -n $names ]] && ! confirmed b; then
                say info "Press b again to turn Bluetooth off and drop $names"
            else
                scan_stop
                spawn power 'turning off' power off
            fi
            ;;
        a)
            if [[ -e $STATE_DIR/all ]]; then
                rm -f "$STATE_DIR/all"
                say info 'Devices without a name hidden'
            else
                : > "$STATE_DIR/all"
                say info 'Devices without a name shown'
            fi
            ;;
    esac

    refreshed
}

job_connect() {
    local addr="$1" name out

    read_snapshot
    name="${DEV_ALIAS[$addr]:-$addr}"

    if out="$(busctl --system --timeout=40 call org.bluez "$(dev_path "$addr")" org.bluez.Device1 Connect 2>&1)"; then
        say ok "Connected to $name"
        notify Bluetooth "Connected to $name" network-bluetooth-activated
    else
        say error "$name: $(bz_error "$out")"
        notify Bluetooth "Could not connect to $name: $(bz_error "$out")" network-bluetooth-inactive
    fi
}

job_disconnect() {
    local addr="$1" name out

    read_snapshot
    name="${DEV_ALIAS[$addr]:-$addr}"

    if out="$(busctl --system --timeout=20 call org.bluez "$(dev_path "$addr")" org.bluez.Device1 Disconnect 2>&1)"; then
        say ok "Disconnected $name"
    else
        say error "$name: $(bz_error "$out")"
    fi
}

job_trust() {
    local addr="$1" value="$2"

    read_snapshot

    if busctl --system set-property org.bluez "$(dev_path "$addr")" org.bluez.Device1 Trusted b "$value" > /dev/null 2>&1; then
        [[ $value == true ]] && say ok "Trusted ${DEV_ALIAS[$addr]}" || say ok "Untrusted ${DEV_ALIAS[$addr]}"
    else
        say error "Could not change trust for ${DEV_ALIAS[$addr]}"
    fi
}

job_forget() {
    local addr="$1" name out

    read_snapshot
    name="${DEV_ALIAS[$addr]:-$addr}"

    if out="$(busctl --system call org.bluez "$ADAPTER" org.bluez.Adapter1 RemoveDevice o "$(dev_path "$addr")" 2>&1)"; then
        say ok "Forgot $name"
    else
        say error "$name: $(bz_error "$out")"
    fi
}

# rfkill first if the adapter is blocked; the adapter shows up powered a
# moment after the unblock.
power_on() {
    local i

    if [[ $(bluetoothctl show 2> /dev/null | awk '/PowerState/ {print $2}') == off-blocked ]]; then
        rfkill unblock bluetooth || return 1
        for ((i = 0; i < 20; i++)); do
            [[ $(bluetoothctl show 2> /dev/null | awk '/PowerState/ {print $2}') != off-blocked ]] && break
            sleep 0.25
        done
    fi

    bluetoothctl power on > /dev/null 2>&1
}

job_power() {
    if [[ $1 == on ]]; then
        if power_on; then
            say ok 'Bluetooth on'
        else
            say error 'Could not turn Bluetooth on'
        fi
    elif bluetoothctl power off > /dev/null 2>&1; then
        say ok 'Bluetooth off'
    else
        say error 'Could not turn Bluetooth off'
    fi
}

# Pairing in the terminal: some devices show a code to confirm. Trusted
# afterwards, so the device may reconnect by itself.
cmd_pair() {
    local addr="${1#dev:}" name out rc=0

    read_snapshot
    name="${DEV_ALIAS[$addr]:-$addr}"

    printf '\e[H\e[2J\e[?25h'
    printf '%s%s  %s%s\n\n' "$BOLD" "$(device_icon "${DEV_ICON[$addr]-}")" "$name" "$RESET"

    # Discovery makes pairing flaky, and the new device is already known.
    scan_stop

    printf 'Pairing - confirm on the device if it asks.\n\n'
    # --foreground: the agent may read a yes/no from the terminal, which a
    # background process group cannot.
    timeout --foreground 45 bluetoothctl pair "$addr" || rc=$?

    if ((rc == 0)); then
        bluetoothctl trust "$addr" > /dev/null 2>&1 || true
        printf '\nConnecting…\n'
        if out="$(busctl --system --timeout=40 call org.bluez "$(dev_path "$addr")" org.bluez.Device1 Connect 2>&1)"; then
            say ok "Paired and connected $name"
            refresh_rows
            return 0
        fi
        say error "Paired $name, but: $(bz_error "$out")"
    else
        say error "Could not pair with $name"
    fi

    refresh_rows
    printf '\n%sPress any key to go back%s' "$DIM" "$RESET"
    read -rsn1 || true
}

# Right click on the bar icon.
cmd_toggle() {
    if [[ $(bluetoothctl show 2> /dev/null | awk '/PowerState/ {print $2}') == on ]]; then
        bluetoothctl power off > /dev/null
        notify-send -e 'Bluetooth Off' -i network-bluetooth-inactive -h string:x-canonical-private-synchronous:bluetooth
    elif power_on; then
        notify-send -e 'Bluetooth On' -i network-bluetooth-activated -h string:x-canonical-private-synchronous:bluetooth
    else
        notify-send 'Bluetooth' 'Could not turn it on' -i network-bluetooth-inactive -h string:x-canonical-private-synchronous:bluetooth
    fi
}

menu_closing() {
    scan_stop
}

main() {
    local addr known=0

    read_snapshot
    for addr in "${DEV_ORDER[@]}"; do
        [[ ${DEV_PAIRED[$addr]} == true ]] && known=1
    done

    # Nothing paired yet: the only thing to do here is to find something.
    if ((!known)) && [[ $POWERED == true ]]; then
        scan_start
    fi

    menu_run "$ICON_ON Bluetooth"
}

menu_dispatch "$@"

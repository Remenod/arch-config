#!/usr/bin/env bash
#
# Wi-Fi menu for Waybar.
#
#   network.sh          the menu, meant for a terminal popup
#   network.sh toggle   turn the Wi-Fi radio on or off
#
# The list opens at once from NetworkManager's last scan and keeps updating
# while a fresh scan runs. Access points that share a name are merged into
# one row; the details pane lists them one by one.
#
# Keys, also shown in the footer: enter connects or disconnects, s shows a QR
# code for joining from a phone, f forgets a saved network, r rescans, w turns
# Wi-Fi off and on, a also lists saved networks that are out of range,
# / filters, i hides the details, q quits. Whatever drops the connection -
# disconnecting, forgetting, Wi-Fi off, the hotspot - takes a second press.
#
# Grew out of the scanner by Jesse Mirabel (MIT).

set -euo pipefail

MENU_NAME=wifi
LETTERS=(r f s w a)
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib/connect-menu.sh"

SIGNAL_OPEN=(󰤟 󰤢 󰤥 󰤨)
SIGNAL_LOCKED=(󰤡 󰤤 󰤧 󰤪)
ICON_WIFI=󰖩
ICON_OFF=󰖪
ICON_HIDDEN=󰈉
ICON_HOTSPOT=󰀂
ICON_SAVED=󰤯
ICON_SCAN=󰐷

SNAPSHOT="$STATE_DIR/snapshot"
# Snapshot field separator. Not a tab: IFS whitespace would merge the empty
# fields of a saved network that is out of range.
US=$'\037'

# What one look at NetworkManager found. build_snapshot fills it and saves it
# for the header, footer and key callbacks, which run as separate processes
# every second and read it back with read_snapshot instead of asking again.
RADIO=off
IFACE=""
DEV_STATE=""
DEV_CONN=""
DEV_UUID=""
DEV_IP=""
HOTSPOT_UUID=""
HOTSPOT_SSID=""
declare -a NET_ORDER=()
# Per SSID. Flags: a active, v visible, s saved, l locked, e 802.1X.
declare -A NET_FLAGS=() NET_LEVEL=() NET_BANDS=() NET_SECURITY=() NET_UUIDS=() NET_USED=()

add_flag() {
    [[ ${NET_FLAGS[$1]-} == *"$2"* ]] || NET_FLAGS["$1"]+=$2
}

load_device() {
    local iface type

    while IFS=: read -r iface type; do
        [[ $type == wifi ]] && { IFACE=$iface; break; }
    done < <(nmcli -g DEVICE,TYPE device 2> /dev/null)

    [[ -n $IFACE ]] || return 0

    {
        IFS= read -r DEV_STATE
        IFS= read -r DEV_CONN
        IFS= read -r DEV_UUID
        IFS= read -r DEV_IP
    } < <(nmcli -g GENERAL.STATE,GENERAL.CONNECTION,GENERAL.CON-UUID,IP4.ADDRESS device show "$IFACE" 2> /dev/null) || true

    DEV_STATE="${DEV_STATE#* (}"
    DEV_STATE="${DEV_STATE%)}"
    DEV_CONN="${DEV_CONN//[[:cntrl:]]/}"
    DEV_IP="${DEV_IP%% | *}"
}

load_saved() {
    local uuids uuid mode stamp ssid

    mapfile -t uuids < <(nmcli -g UUID,TYPE connection show 2> /dev/null | awk -F: '$2 == "802-11-wireless" {print $1}')
    ((${#uuids[@]})) || return 0

    # One block of four lines per profile, blocks separated by a blank line.
    while IFS= read -r uuid && IFS= read -r mode && IFS= read -r stamp && IFS= read -r ssid; do
        IFS= read -r _ || true
        ssid="${ssid//[[:cntrl:]]/}"
        [[ $stamp =~ ^[0-9]+$ ]] || stamp=0

        if [[ $mode == ap ]]; then
            [[ -n $HOTSPOT_UUID ]] || { HOTSPOT_UUID=$uuid; HOTSPOT_SSID=$ssid; }
            continue
        fi
        [[ -n $ssid ]] || continue

        add_flag "$ssid" s
        NET_UUIDS["$ssid"]+="${NET_UUIDS[$ssid]:+ }$uuid"
        if ((stamp > ${NET_USED[$ssid]:-0})); then
            NET_USED["$ssid"]=$stamp
        fi
    done < <(nmcli --escape no -g connection.uuid,802-11-wireless.mode,connection.timestamp,802-11-wireless.ssid \
        connection show "${uuids[@]}" 2> /dev/null)

    return 0
}

load_visible() {
    local inuse freq level security ssid current band

    # SSID goes last: with escaping off it is the only field that may hold ":".
    while IFS=: read -r inuse freq level security ssid; do
        ssid="${ssid//[[:cntrl:]]/}"
        [[ -n $ssid && $level =~ ^[0-9]+$ ]] || continue

        current="${NET_LEVEL[$ssid]-}"
        if [[ -z $current ]]; then
            NET_ORDER+=("$ssid")
            NET_LEVEL["$ssid"]=$level
            NET_SECURITY["$ssid"]=$security
        elif ((level > current)); then
            NET_LEVEL["$ssid"]=$level
            NET_SECURITY["$ssid"]=$security
        fi

        add_flag "$ssid" v
        [[ $inuse == '*' ]] && add_flag "$ssid" a
        [[ -n $security && $security != -- ]] && add_flag "$ssid" l
        [[ $security == *802.1X* ]] && add_flag "$ssid" e

        freq="${freq%% *}"
        if [[ $freq =~ ^[0-9]+$ ]]; then
            if ((freq < 3000)); then band=2.4; elif ((freq < 5925)); then band=5; else band=6; fi
            [[ " ${NET_BANDS[$ssid]-} " == *" $band "* ]] || NET_BANDS["$ssid"]+=" $band"
        fi
    done < <(nmcli --escape no -t -f IN-USE,FREQ,SIGNAL,SECURITY,SSID device wifi list --rescan no 2> /dev/null)

    return 0
}

build_snapshot() {
    local ssid

    [[ $(nmcli radio wifi 2> /dev/null) == enabled ]] && RADIO=on
    load_device
    load_saved
    [[ $RADIO == on ]] && load_visible

    {
        printf 'radio%s%s\n' "$US" "$RADIO"
        printf 'device%s%s%s%s%s%s%s%s%s%s\n' "$US" "$IFACE" "$US" "$DEV_STATE" "$US" "$DEV_CONN" "$US" "$DEV_UUID" "$US" "$DEV_IP"
        printf 'hotspot%s%s%s%s\n' "$US" "$HOTSPOT_UUID" "$US" "$HOTSPOT_SSID"
        for ssid in "${NET_ORDER[@]}"; do
            printf 'net%s%s\n' "$US" "$ssid"
        done
        for ssid in "${!NET_FLAGS[@]}"; do
            printf 'info%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$US" "$ssid" "$US" "${NET_FLAGS[$ssid]}" "$US" "${NET_LEVEL[$ssid]-}" \
                "$US" "${NET_BANDS[$ssid]-}" "$US" "${NET_SECURITY[$ssid]-}" "$US" "${NET_UUIDS[$ssid]-}" "$US" "${NET_USED[$ssid]-}"
        done
    } > "$SNAPSHOT.$$"
    mv -f "$SNAPSHOT.$$" "$SNAPSHOT"
}

read_snapshot() {
    local kind a b c d e f g

    [[ -r $SNAPSHOT ]] || { build_snapshot; return 0; }

    while IFS=$US read -r kind a b c d e f g; do
        case $kind in
            radio) RADIO=$a ;;
            device) IFACE=$a DEV_STATE=$b DEV_CONN=$c DEV_UUID=$d DEV_IP=$e ;;
            hotspot) HOTSPOT_UUID=$a HOTSPOT_SSID=$b ;;
            net) NET_ORDER+=("$a") ;;
            info)
                NET_FLAGS["$a"]=$b
                [[ -n $c ]] && NET_LEVEL["$a"]=$c
                [[ -n $d ]] && NET_BANDS["$a"]=$d
                [[ -n $e ]] && NET_SECURITY["$a"]=$e
                [[ -n $f ]] && NET_UUIDS["$a"]=$f
                [[ -n $g ]] && NET_USED["$a"]=$g
                ;;
        esac
    done < "$SNAPSHOT"

    return 0
}

hotspot_on() {
    [[ -n $HOTSPOT_UUID && $DEV_UUID == "$HOTSPOT_UUID" ]]
}

# "2.4/5G" from " 5 2.4".
bands_label() {
    local list="" band

    for band in 2.4 5 6; do
        [[ " $1 " == *" $band "* ]] && list+="${list:+/}$band"
    done

    [[ -z $list ]] || printf '%sG' "$list"
}

signal_icon() {
    local level="$1" locked="$2" i=0

    if ((level >= 75)); then i=3; elif ((level >= 50)); then i=2; elif ((level >= 25)); then i=1; fi

    if [[ $locked == *l* ]]; then
        printf '%s' "${SIGNAL_LOCKED[i]}"
    else
        printf '%s' "${SIGNAL_OPEN[i]}"
    fi
}

rows() {
    local ssid flags level rank status name

    build_snapshot

    if [[ $RADIO != on ]]; then
        printf 'radio\t%s  Wi-Fi is off   %senter turns it on%s\n' "$ICON_OFF" "$DIM" "$RESET"
        return 0
    fi

    for ssid in "${NET_ORDER[@]}"; do
        flags="${NET_FLAGS[$ssid]}"
        level="${NET_LEVEL[$ssid]}"
        name="$(pad "$ssid" 23)"

        if [[ $flags == *a* ]]; then
            rank=0
            name="$BOLD$name$RESET"
            status="$GREEN$ICON_OK connected$RESET"
        elif [[ $flags == *s* ]]; then
            rank=1
            status="${DIM}saved$RESET"
        else
            rank=2
            status=""
        fi
        [[ -n ${PENDING["ssid:$ssid"]-} ]] && status="$YELLOW$ICON_BUSY ${PENDING["ssid:$ssid"]}…$RESET"

        printf '%s\t%03d\tssid:%s\t%s  %s %6s %4s  %s\n' "$rank" "$level" "$ssid" \
            "$(signal_icon "$level" "$flags")" "$name" "$(bands_label "${NET_BANDS[$ssid]-}")" "$level%" "$status"
    done | sort -t$'\t' -k1,1n -k2,2r | cut -f3-

    # Saved networks that are not around, most recently used first.
    if [[ -e $STATE_DIR/all ]]; then
        for ssid in "${!NET_FLAGS[@]}"; do
            [[ ${NET_FLAGS[$ssid]} == *v* ]] && continue
            printf '%010d\tssid:%s\t%s%s  %s %6s %4s  %s%s\n' "${NET_USED[$ssid]:-0}" "$ssid" \
                "$DIM" "$ICON_SAVED" "$(pad "$ssid" 23)" "" "" "out of range" "$RESET"
        done | sort -r | cut -f2-
    fi

    if [[ -n $HOTSPOT_UUID ]]; then
        if hotspot_on; then
            status="$GREEN$ICON_OK on$RESET"
        else
            status="${DIM}off$RESET"
        fi
        [[ -n ${PENDING[hotspot]-} ]] && status="$YELLOW$ICON_BUSY ${PENDING[hotspot]}…$RESET"
        printf 'hotspot\t%s  %s %6s %4s  %s\n' "$ICON_HOTSPOT" "$(pad Hotspot 23)" "" "" "$status"
    fi

    printf 'hidden\t%s  %sHidden network…%s\n' "$ICON_HIDDEN" "$DIM" "$RESET"
}

header() {
    local message

    message="$(said)"
    if [[ -n $message ]]; then
        printf '%s' "$message"
        return 0
    fi

    read_snapshot
    load_pending

    if [[ $RADIO != on ]]; then
        printf '%s  %sWi-Fi is off%s' "$ICON_OFF" "$DIM" "$RESET"
    elif hotspot_on; then
        printf '%s  %sHotspot %s is on%s' "$ICON_HOTSPOT" "$GREEN" "$HOTSPOT_SSID" "$RESET"
    elif [[ $DEV_STATE == connected ]]; then
        printf '%s  %s%s%s%s' "$ICON_WIFI" "$GREEN" "$DEV_CONN" "$RESET" "${DEV_IP:+$DIM · ${DEV_IP%/*}$RESET}"
    elif [[ $DEV_STATE == connecting* || $DEV_STATE == *config* ]]; then
        printf '%s  %sconnecting to %s…%s' "$ICON_WIFI" "$YELLOW" "$DEV_CONN" "$RESET"
    elif [[ $DEV_STATE == unavailable || -z $IFACE ]]; then
        printf '%s  %sno Wi-Fi device available%s' "$ICON_OFF" "$RED" "$RESET"
    else
        printf '%s  %snot connected%s' "$ICON_WIFI" "$DIM" "$RESET"
    fi

    [[ -n ${PENDING[scan]-} ]] && printf '   %s%s scanning…%s' "$DIM" "$ICON_SCAN" "$RESET"
    return 0
}

footer() {
    local key="$1" ssid flags item=""

    read_snapshot

    case $key in
        radio) item="$(hints enter 'turn Wi-Fi on')" ;;
        hidden) item="$(hints enter 'join a network that hides its name')" ;;
        hotspot)
            if hotspot_on; then
                item="$(hints enter 'stop the hotspot' s 'share (QR)')"
            else
                item="$(hints enter 'start the hotspot' s 'share (QR)')"
            fi
            ;;
        ssid:*)
            ssid="${key#ssid:}"
            flags="${NET_FLAGS[$ssid]-}"
            if [[ $flags == *a* ]]; then
                item="$(hints enter×2 disconnect s 'share (QR)' f×2 forget)"
            elif [[ $flags == *s* ]]; then
                item="$(hints enter connect s 'share (QR)' f×2 forget)"
            elif [[ $flags == *e* ]]; then
                item="$(hints enter '802.1X: set up in nmtui')"
            elif [[ $flags == *l* ]]; then
                item="$(hints enter 'connect (asks for the password)')"
            else
                item="$(hints enter 'connect (open network)')"
            fi
            ;;
    esac

    printf '%s\n%s' "$item" "$(hints r scan w "Wi-Fi $([[ $RADIO == on ]] && echo off || echo on)" a saved / find i info q quit)"
}

# Escapes text for a WIFI: QR payload.
qr_escape() {
    local value="$1" char out=""
    local i

    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        [[ $char == [\\\;,:\"] ]] && out+='\'
        out+="$char"
    done

    printf '%s' "$out"
}

# A QR code phones scan to join $1, from the password in profile $2. The
# security type comes from the profile, not the scan: a network out of range
# has no scan entry to tell.
share_qr() {
    local ssid="$1" uuid="$2" mgmt type psk="" payload

    if ! command -v qrencode > /dev/null; then
        printf '%sqrencode is not installed%s\n' "$RED" "$RESET"
        return 0
    fi

    mgmt="$(nmcli -g 802-11-wireless-security.key-mgmt connection show uuid "$uuid" 2> /dev/null || true)"

    case $mgmt in
        '') type=nopass ;;
        wpa-psk) type=WPA ;;
        sae) type=SAE ;;
        none) type=WEP ;;
        *)
            printf '%s%s networks cannot be shared as a QR code.%s\n' "$RED" "$mgmt" "$RESET"
            return 0
            ;;
    esac

    if [[ $type != nopass ]]; then
        if [[ $type == WEP ]]; then
            psk="$(nmcli -s -g 802-11-wireless-security.wep-key0 connection show uuid "$uuid" 2> /dev/null || true)"
        else
            psk="$(nmcli -s -g 802-11-wireless-security.psk connection show uuid "$uuid" 2> /dev/null || true)"
        fi
        if [[ -z $psk ]]; then
            printf '%sThe password is not stored in this profile.%s\n' "$RED" "$RESET"
            return 0
        fi
        payload="WIFI:T:$type;S:$(qr_escape "$ssid");P:$(qr_escape "$psk");;"
    else
        payload="WIFI:T:nopass;S:$(qr_escape "$ssid");;"
    fi

    printf '%s' "$payload" | qrencode -t ansiutf8 -m 2
    [[ -z $psk ]] || field Password "$psk"
}

field() {
    printf '%s%-10s%s %s\n' "$DIM" "$1" "$RESET" "$2"
}

preview_network() {
    local ssid="$1" flags uuid inuse b1 b2 b3 b4 b5 b6 chan freq level rate security name auto

    flags="${NET_FLAGS[$ssid]-}"
    uuid="${NET_UUIDS[$ssid]-}"
    uuid="${uuid%% *}"

    printf '%s%s%s\n' "$BOLD" "$ssid" "$RESET"
    if [[ $flags == *v* ]]; then
        printf '%s %s%%  %s  %s\n\n' "$(signal_icon "${NET_LEVEL[$ssid]}" "$flags")" "${NET_LEVEL[$ssid]}" \
            "${NET_SECURITY[$ssid]:-open}" "$(bands_label "${NET_BANDS[$ssid]-}")"
    else
        printf '%sout of range%s\n\n' "$DIM" "$RESET"
    fi

    if [[ $flags == *a* ]]; then
        field Status "${GREEN}connected$RESET"
        field Address "${DEV_IP:-…}"
        while IFS=: read -r name auto; do
            case $name in
                IP4.GATEWAY) [[ -n $auto ]] && field Gateway "$auto" ;;
                IP4.DNS*) field DNS "$auto" ;;
            esac
        done < <(nmcli -t -f IP4.GATEWAY,IP4.DNS device show "$IFACE" 2> /dev/null)
    elif [[ $flags == *s* ]]; then
        field Status saved
    else
        field Status 'not saved'
    fi

    if [[ -n $uuid ]]; then
        auto="$(nmcli -g connection.autoconnect connection show uuid "$uuid" 2> /dev/null || true)"
        [[ $auto == yes ]] && auto='connects by itself' || auto='only on request'
        field Saved "$auto"
        if [[ ${NET_USED[$ssid]:-0} != 0 ]]; then
            field 'Last used' "$(printf '%(%Y-%m-%d %H:%M)T' "${NET_USED[$ssid]}")"
        fi
    fi

    [[ $flags == *v* ]] || return 0

    printf '\n%sAccess points%s\n' "$BOLD" "$RESET"
    # BSSID is the six fields after IN-USE; SSID last takes whatever is left.
    while IFS=: read -r inuse b1 b2 b3 b4 b5 b6 chan freq level rate security name; do
        [[ ${name//[[:cntrl:]]/} == "$ssid" ]] || continue
        printf '%s %s:%s:%s:%s:%s:%s  ch %-3s %3s%%%s\n' "$([[ $inuse == '*' ]] && echo "$GREEN$ICON_OK" || echo ' ')" \
            "$b1" "$b2" "$b3" "$b4" "$b5" "$b6" "$chan" "$level" "$RESET"
    done < <(nmcli --escape no -t -f IN-USE,BSSID,CHAN,FREQ,SIGNAL,RATE,SECURITY,SSID device wifi list --rescan no 2> /dev/null | sort -t: -k10,10nr)
}

preview() {
    local key="$1"

    read_snapshot

    case $key in
        radio)
            printf '%sWi-Fi is off%s\n\n' "$BOLD" "$RESET"
            printf 'Enter or w turns it back on.\n'
            ;;
        hidden)
            printf '%sHidden network%s\n\n' "$BOLD" "$RESET"
            printf 'For a network that does not broadcast its name. Enter asks for the name and then the password.\n'
            ;;
        hotspot)
            printf '%sHotspot%s\n\n' "$BOLD" "$RESET"
            field Name "$HOTSPOT_SSID"
            if hotspot_on; then
                field Status "${GREEN}on$RESET"
            else
                field Status off
            fi
            printf '\n%sShares this laptop'"'"'s connection over Wi-Fi. Starting it drops the Wi-Fi network you are on. s shows a QR code for phones.%s\n' "$DIM" "$RESET"
            ;;
        ssid:*)
            preview_network "${key#ssid:}"
            ;;
    esac
}

# Turns an nmcli failure into something short enough for the status line.
nm_error() {
    local out="$1" line

    case $out in
        *'Secrets were required'* | *'secrets'*) printf 'wrong password' ; return 0 ;;
        *'No network with SSID'*) printf 'network not found' ; return 0 ;;
        *'timeout'* | *'Timeout'*) printf 'timed out' ; return 0 ;;
    esac

    line="$(grep -m1 '^Error' <<< "$out" || true)"
    line="${line#Error: }"
    line="${line#Connection activation failed: }"
    printf '%s' "${line:-failed}"
}

on_enter() {
    local key="$1" ssid flags uuid

    read_snapshot
    load_pending

    if [[ -n ${PENDING[$key]-} ]]; then
        say info "Still ${PENDING[$key]}…"
        refreshed
        return 0
    fi

    case $key in
        radio) spawn radio 'turning on' radio on ;;
        hidden)
            printf 'execute(%s join)+%s' "$SELF_Q" "$REFRESH"
            return 0
            ;;
        hotspot)
            if hotspot_on; then
                spawn hotspot stopping hotspot down
            elif [[ $DEV_STATE == connected ]] && ! confirmed "enter:hotspot"; then
                say info "Press enter again: the hotspot drops $DEV_CONN"
            else
                spawn hotspot starting hotspot up
            fi
            ;;
        ssid:*)
            ssid="${key#ssid:}"
            flags="${NET_FLAGS[$ssid]-}"
            if [[ $flags == *a* ]]; then
                # The connected network is the row the menu opens on - one
                # stray enter must not drop it.
                if confirmed "enter:$key"; then
                    spawn "$key" disconnecting disconnect "$ssid"
                else
                    say info "Press enter again to disconnect from $ssid"
                fi
            elif [[ $flags == *s* && ! ( -e $STATE_DIR/repass && $(< "$STATE_DIR/repass") == "$ssid" ) ]]; then
                uuid="${NET_UUIDS[$ssid]}"
                spawn "$key" connecting connect "$ssid" "${uuid%% *}"
            elif [[ $flags == *e* && $flags != *s* ]]; then
                say error "$ssid uses 802.1X - set it up in nmtui first"
            elif [[ $flags == *l* || $flags == *s* ]]; then
                # A password to type: in the terminal, outside fzf.
                printf 'execute(%s join {1})+%s' "$SELF_Q" "$REFRESH"
                return 0
            else
                spawn "$key" connecting connect "$ssid" ""
            fi
            ;;
    esac

    refreshed
}

on_key() {
    local letter="$1" key="$2" ssid="${2#ssid:}" flags

    read_snapshot
    flags="${NET_FLAGS[$ssid]-}"

    case $letter in
        r)
            # NetworkManager spaces scans out; a second one would only queue.
            load_pending
            [[ -n ${PENDING[scan]-} ]] || spawn scan scanning rescan
            ;;
        w)
            if [[ $RADIO != on ]]; then
                spawn radio 'turning on' radio on
            elif [[ $DEV_STATE == connected ]] && ! confirmed w; then
                say info "Press w again to turn Wi-Fi off and drop $DEV_CONN"
            else
                spawn radio 'turning off' radio off
            fi
            ;;
        a)
            if [[ -e $STATE_DIR/all ]]; then
                rm -f "$STATE_DIR/all"
                say info 'Saved networks out of range hidden'
            else
                : > "$STATE_DIR/all"
                say info 'Saved networks out of range shown at the bottom'
            fi
            ;;
        s)
            if [[ $key == hotspot || ( $key == ssid:* && $flags == *s* ) ]]; then
                printf 'execute(%s share {1})+' "$SELF_Q"
            else
                say info 'Only saved networks can be shared'
            fi
            ;;
        f)
            if [[ $key != ssid:* || $flags != *s* ]]; then
                say info 'Nothing to forget - this network is not saved'
            elif confirmed "f:$key"; then
                spawn "$key" forgetting forget "$ssid" ${NET_UUIDS[$ssid]}
            else
                say info "Press f again to forget $ssid"
            fi
            ;;
    esac

    refreshed
}

connected() {
    rm -f "$STATE_DIR/repass"
    say ok "Connected to $1"
    notify 'Wi-Fi' "Connected to $1" network-wireless
}

job_connect() {
    local ssid="$1" uuid="${2-}" out why

    if [[ -n $uuid ]]; then
        out="$(nmcli -w 30 connection up uuid "$uuid" 2>&1)" && { connected "$ssid"; return 0; }
    else
        out="$(nmcli -w 30 device wifi connect "$ssid" 2>&1)" && { connected "$ssid"; return 0; }
    fi

    why="$(nm_error "$out")"
    # A saved password that stopped working: the next enter asks for a new one.
    if [[ $why == 'wrong password' ]]; then
        printf '%s\n' "$ssid" > "$STATE_DIR/repass"
        why='wrong password - enter asks for it'
    fi

    say error "$ssid: $why"
    notify 'Wi-Fi' "Could not connect to $ssid: $why" network-wireless-offline
}

# "connection down", not "device disconnect": the latter also stops the
# adapter from joining any saved network by itself until a manual connect.
# This keeps only the network left behind from coming straight back; w is
# for going offline altogether.
job_disconnect() {
    read_snapshot

    if nmcli connection down uuid "$DEV_UUID" > /dev/null 2>&1; then
        say ok "Disconnected from $1"
    else
        say error "Could not disconnect from $1"
    fi
}

job_forget() {
    local ssid="$1" uuid args=()

    shift

    for uuid in "$@"; do
        args+=(uuid "$uuid")
    done

    if nmcli connection delete "${args[@]}" > /dev/null 2>&1; then
        say ok "Forgot $ssid"
    else
        say error "Could not forget $ssid"
    fi
}

job_rescan() {
    pending scan scanning
    # Unlike "nmcli device wifi rescan", this waits for the scan to finish.
    nmcli -f SSID device wifi list --rescan yes > /dev/null 2>&1 || true
}

job_radio() {
    if nmcli radio wifi "$1" > /dev/null 2>&1; then
        say ok "Wi-Fi $1"
        if [[ $1 == on ]]; then
            job_rescan
        fi
    else
        say error "Could not turn Wi-Fi $1"
    fi
}

job_hotspot() {
    local out

    read_snapshot

    if [[ $1 == up ]]; then
        if out="$(nmcli -w 30 connection up uuid "$HOTSPOT_UUID" 2>&1)"; then
            say ok "Hotspot $HOTSPOT_SSID is on"
            notify 'Hotspot' "$HOTSPOT_SSID is on" network-wireless-hotspot
        else
            say error "Hotspot: $(nm_error "$out")"
            notify 'Hotspot' "Could not start: $(nm_error "$out")" network-wireless-offline
        fi
    else
        nmcli connection down uuid "$HOTSPOT_UUID" > /dev/null 2>&1 || true
        say ok 'Hotspot stopped'
    fi
}

# Joining a network that needs a password, in the terminal: nmcli asks for
# it itself, without echo. No argument means a hidden network.
cmd_join() {
    local ssid="${1-}" hidden=() uuid rc=0

    ssid="${ssid#ssid:}"

    read_snapshot
    printf '\e[H\e[2J\e[?25h'

    if [[ -z $ssid ]]; then
        printf '%s%s  Join a hidden network%s\n\n' "$BOLD" "$ICON_HIDDEN" "$RESET"
        read -rp 'Network name: ' ssid || return 0
        [[ -n $ssid ]] || return 0
        hidden=(hidden yes)
    else
        printf '%s%s  %s%s\n\n' "$BOLD" "$ICON_WIFI" "$ssid" "$RESET"
    fi

    uuid="${NET_UUIDS[$ssid]-}"
    uuid="${uuid%% *}"

    if [[ -n $uuid ]]; then
        nmcli -a -w 45 connection up uuid "$uuid" || rc=$?
    else
        nmcli -a -w 45 device wifi connect "$ssid" "${hidden[@]}" || rc=$?
    fi

    if ((rc == 0)); then
        connected "$ssid"
        refresh_rows
        return 0
    fi

    # The failed first try leaves its new profile behind, holding the wrong
    # password - drop it so the next try asks again.
    if [[ -z $uuid ]]; then
        NET_UUIDS=()
        load_saved
        for uuid in ${NET_UUIDS[$ssid]-}; do
            nmcli connection delete uuid "$uuid" > /dev/null 2>&1 || true
        done
    fi

    say error "Could not connect to $ssid"
    refresh_rows
    printf '\n%sPress any key to go back%s' "$DIM" "$RESET"
    read -rsn1 || true
}

# Full screen, so a long password still fits the QR code.
cmd_share() {
    local key="$1" ssid uuid

    read_snapshot

    if [[ $key == hotspot ]]; then
        ssid="$HOTSPOT_SSID"
        uuid="$HOTSPOT_UUID"
    else
        ssid="${key#ssid:}"
        uuid="${NET_UUIDS[$ssid]-}"
        uuid="${uuid%% *}"
    fi

    printf '\e[H\e[2J'
    printf '%s%s  %s%s\n\n' "$BOLD" "$ICON_WIFI" "$ssid" "$RESET"
    share_qr "$ssid" "$uuid"
    printf '\n%sPoint a phone camera at the code to join. Any key goes back.%s' "$DIM" "$RESET"
    read -rsn1 || true
}

# Right click on the bar icon.
cmd_toggle() {
    if [[ $(nmcli radio wifi) == enabled ]]; then
        nmcli radio wifi off
        notify-send -e 'Wi-Fi Disabled' -i network-wireless-off -h string:x-canonical-private-synchronous:network
    else
        nmcli radio wifi on
        notify-send -e 'Wi-Fi Enabled' -i network-wireless-on -h string:x-canonical-private-synchronous:network
    fi
}

main() {
    spawn scan scanning rescan
    menu_run "$ICON_WIFI Wi-Fi"
}

menu_dispatch "$@"

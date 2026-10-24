#!/usr/bin/env bash
#
# Fan module: fan mode, Cooler Boost and the speed of both fans.
#
# Modes:
#   fan.sh          long-running daemon, one JSON line per reading (no "interval")
#   fan.sh wake     make the running daemons redraw now, e.g. after a boost toggle
#
# msi-ec reports fan speed as a percentage only; the RPM comes from "isw -r",
# which needs root. "isw -r" never exits by itself, so starting it for every
# reading meant killing it by timeout 0.8 s later - some forty processes and
# three sudo lines in the journal every two seconds. Instead the daemon keeps
# one running for as long as it lives: isw prints a reading every two seconds,
# and that paces the module. It gets a terminal from "script", as without one
# Python holds its output back in a buffer.
#
# isw and the wake-ups both write to one fifo, so a single timed read waits
# for either.

set -euo pipefail

shared_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shared/scripts"
# shellcheck source=../../shared/scripts/msi-ec.sh
source "$shared_dir/msi-ec.sh"

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-fan"
FEED_PATH="$RUNDIR/feed.$$"
TICK=${TICK:-2}                # redraw at least this often, with or without isw
STALE=${STALE:-6}              # seconds without a reading before RPM counts as lost
ISW_RETRY=${ISW_RETRY:-60}     # wait before restarting an isw that exited

FEED=""
ISW_PID=""
ISW_STARTED=$((-ISW_RETRY))
CPU_RPM=0
GPU_RPM=0

# Starts "isw -r" writing into the feed. isw runs as root, so the user could
# not kill a stray one: whatever way the daemon dies, the kernel signals
# "script" (pdeathsig), and the hangup of its terminal ends sudo and isw.
# "script" blocks SIGPIPE, so a feed nobody reads would not stop it.
start_isw() {
    local cmd

    printf -v cmd 'sudo -n %q -r %q' "$ISW_BIN" "$ISW_EC"
    TERM=xterm setpriv --pdeathsig TERM script -qfc "$cmd" /dev/null \
        < /dev/null > "$FEED_PATH" 2> /dev/null {FEED}>&- &
    ISW_PID=$!
    ISW_STARTED=$SECONDS
}

# (Re)starts isw when it is not running, at most once a minute: when sudo
# refuses, every attempt costs a journal line.
keep_isw() {
    [[ -x $ISW_BIN ]] || return 0
    [[ -n $ISW_PID ]] && kill -0 "$ISW_PID" 2> /dev/null && return 0
    ((SECONDS - ISW_STARTED >= ISW_RETRY)) || return 0
    start_isw
}

# Sets CPU_RPM and GPU_RPM from an isw row such as
# "│ 79°C │ 80%   6459RPM  │      │ 92°C │ 80%   5975RPM  │".
parse_rpms() {
    local rest="$1" found=()

    while [[ $rest =~ ([0-9]+)[[:space:]]*RPM(.*) ]]; do
        found+=("${BASH_REMATCH[1]}")
        rest="${BASH_REMATCH[2]}"
    done

    ((${#found[@]} >= 2)) || return 1
    CPU_RPM=${found[0]}
    GPU_RPM=${found[1]}
}

# Pokes every running daemon with an empty line. Opening a fifo read-write
# never blocks, so one left behind by a daemon that died without cleaning up
# cannot hang this; such fifos are removed.
wake() {
    local fifo

    for fifo in "$RUNDIR"/feed.*; do
        [[ -p $fifo ]] || continue
        if kill -0 "${fifo##*.}" 2> /dev/null; then
            printf '\n' 1<> "$fifo" || true
        else
            rm -f "$fifo"
        fi
    done
}

cleanup() {
    if [[ -n $ISW_PID ]]; then
        kill "$ISW_PID" 2> /dev/null || true
    fi
    rm -f "$FEED_PATH"
}

module() {
    local line cpu_rpm=0 gpu_rpm=0 rpm_note seen=$((-STALE - 1))

    mkdir -p "$RUNDIR"
    rm -f "$FEED_PATH"
    mkfifo "$FEED_PATH"
    exec {FEED}<> "$FEED_PATH"

    trap cleanup EXIT
    # Exiting from the handler rather than falling through it stops the shell
    # from announcing the interrupted read on Waybar's stderr at shutdown.
    trap 'exit 0' INT TERM HUP

    while true; do
        keep_isw

        if read -r -t "$TICK" -u "$FEED" line; then
            if parse_rpms "$line"; then
                cpu_rpm=$CPU_RPM
                gpu_rpm=$GPU_RPM
                seen=$SECONDS
            elif [[ -n $line ]]; then
                continue # isw's table borders and headings
            fi           # an empty line is a wake-up
        fi

        if ((SECONDS - seen <= STALE)); then
            rpm_note="isw"
        else
            cpu_rpm=0
            gpu_rpm=0
            rpm_note="isw unavailable"
        fi

        msi_ec_fan_render "$cpu_rpm" "$gpu_rpm" "$rpm_note"
    done
}

case "${1:-module}" in
    module) module ;;
    wake) wake ;;
    *)
        printf 'Usage: %s [module|wake]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

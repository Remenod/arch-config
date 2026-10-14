#!/usr/bin/env bash
#
# Discrete GPU power mode for the Waybar power menu.
#
# amdgpu already powers the RX 6700M off completely when it is idle (BOCO:
# the GPU and its PCIe switch go to D3cold), after power/autosuspend_delay_ms.
# "off" keeps that same state but shortens the delay, so the dGPU drops again
# 0.1 s after anything touches it - a compositor rescan, an app enumerating
# GPUs, a sensor read - instead of 0.9 s. An app that keeps rendering on it
# still keeps it up, and external monitors (wired to the dGPU) still work.
#
# /etc/udev/rules.d/80-dgpu-runtime-pm.rules sets the 0.9 s default and lets
# wheel write the delay. It lives in sysfs, so a reboot returns to auto.
#
# Usage: dgpu.sh {status|mode|state|set auto|off}

set -euo pipefail

DGPU_AUTO_DELAY_MS="${DGPU_AUTO_DELAY_MS:-900}"   # keep in sync with the udev rule
DGPU_OFF_DELAY_MS="${DGPU_OFF_DELAY_MS:-100}"

# PCI sysfs directory of the dGPU: the amdgpu device that is not the boot VGA.
dgpu_dev() {
    local dev

    for dev in /sys/bus/pci/drivers/amdgpu/0000:*; do
        [[ -e $dev ]] || continue
        [[ -r $dev/boot_vga && $(< "$dev/boot_vga") == 1 ]] && continue
        printf '%s\n' "$dev"
        return 0
    done

    return 1
}

dgpu_available() {
    dgpu_dev >/dev/null
}

# "active" or "suspended"; reading it never wakes the device.
dgpu_state() {
    local dev

    dev="$(dgpu_dev)" || { printf 'missing\n'; return 1; }
    printf '%s\n' "$(< "$dev/power/runtime_status")"
}

dgpu_delay() {
    local dev

    dev="$(dgpu_dev)" || return 1
    printf '%s\n' "$(< "$dev/power/autosuspend_delay_ms")"
}

dgpu_mode() {
    local delay

    delay="$(dgpu_delay)" || { printf 'missing\n'; return 1; }
    if ((delay <= DGPU_OFF_DELAY_MS)); then
        printf 'off\n'
    else
        printf 'auto\n'
    fi
}

# The delay is root-only until the udev rule hands it to wheel.
dgpu_writable() {
    local dev

    dev="$(dgpu_dev)" || return 1
    [[ -w $dev/power/autosuspend_delay_ms ]]
}

# Report on stderr as well: the power menu runs in a terminal popup, which
# shows it above its own "Failed to ..." line.
dgpu_error() {
    notify-send "dGPU" "$1" -i "dialog-error" 2>/dev/null || true
    printf 'dgpu: %s\n' "$1" >&2
}

dgpu_set_mode() {
    local mode="$1" delay dev file

    case "$mode" in
        auto) delay="$DGPU_AUTO_DELAY_MS" ;;
        off) delay="$DGPU_OFF_DELAY_MS" ;;
        *)
            printf 'dgpu: unknown mode: %s\n' "$mode" >&2
            return 2
            ;;
    esac

    if ! dev="$(dgpu_dev)"; then
        dgpu_error "No discrete amdgpu device found"
        return 1
    fi

    file="$dev/power/autosuspend_delay_ms"
    if ! dgpu_writable; then
        dgpu_error "No write access to $file - install /etc/udev/rules.d/80-dgpu-runtime-pm.rules"
        return 1
    fi

    printf '%s\n' "$delay" > "$file"
}

dgpu_main() {
    case "${1:-status}" in
        status)
            printf 'mode=%s state=%s delay_ms=%s\n' \
                "$(dgpu_mode || true)" "$(dgpu_state || true)" "$(dgpu_delay || printf '?')"
            ;;
        mode)
            dgpu_mode
            ;;
        state)
            dgpu_state
            ;;
        set)
            dgpu_set_mode "${2:?missing mode}"
            ;;
        *)
            printf 'Usage: %s {status|mode|state|set auto|off}\n' "$0" >&2
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    dgpu_main "$@"
fi

#!/usr/bin/env bash
# Notification archive behind swaync, which itself keeps notifications only
# in memory.
#
#   archive.sh log      swaync runs this for every notification it receives
#                       ("scripts" in config.json); it appends one JSON line
#                       to this month's file
#   archive.sh open     closes the control center and opens the archive
#                       panel in its place, or closes the panel if it is open
#
# Transient notifications (notify-send -e: volume, brightness and the other
# feedback on a key press) are not archived, just as swaync keeps them out of
# the control center. When a new month's file starts, files older than
# KEEP_MONTHS months are deleted.

set -euo pipefail

ARCHIVE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/notifications"
KEEP_MONTHS=3

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

prune() {
    local cutoff file name

    cutoff="$(date -d "$1-01 -$KEEP_MONTHS months" +%Y-%m)"
    for file in "$ARCHIVE_DIR"/*.jsonl; do
        name="${file##*/}"
        name="${name%.jsonl}"
        if [[ -e $file && $name < $cutoff ]]; then
            rm -f -- "$file"
        fi
    done
}

log() {
    local month file

    [[ ${SWAYNC_HINT_TRANSIENT-} == true ]] && return 0

    printf -v month '%(%Y-%m)T' -1
    file="$ARCHIVE_DIR/$month.jsonl"
    if [[ ! -e $file ]]; then
        mkdir -p "$ARCHIVE_DIR"
        prune "$month"
    fi

    # swaync passes a missing field as "" or as the string "(null)".
    jq -nc 'def field($name): env["SWAYNC_" + $name] | if . == "" or . == "(null)" then null end;
    {
        time: (now | strflocaltime("%Y-%m-%dT%H:%M:%S%z")),
        app: field("APP_NAME"),
        desktop_entry: field("DESKTOP_ENTRY"),
        summary: field("SUMMARY"),
        body: field("BODY"),
        urgency: field("URGENCY"),
        category: field("CATEGORY")
    }' >> "$file"
}

# The panel is a single-instance GTK application: a second start reaches the
# running one, which closes. gtk4-layer-shell must load before Wayland.
open_panel() {
    swaync-client --close-panel --skip-wait > /dev/null 2>&1 || true
    setsid -f env LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so \
        python3 "$SCRIPT_DIR/archive-panel.py" > /dev/null 2>&1
}

case "${1-}" in
    log) log ;;
    open) open_panel ;;
    *)
        printf 'usage: %s log|open\n' "${0##*/}" >&2
        exit 2
        ;;
esac

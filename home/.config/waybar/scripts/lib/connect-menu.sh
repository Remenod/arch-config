# Shared by network.sh and bluetooth.sh: an fzf menu that refreshes itself
# every second, acts on single keys, and has a status line that detached
# background jobs report to.
#
# The sourcing script sets MENU_NAME and LETTERS (its action keys), defines
# the callbacks below, and ends with `menu_dispatch "$@"`:
#
#   rows          the items, one "key<TAB>text" line each
#   header        the status line above the list
#   footer KEY    key hints for the focused item
#   preview KEY   details of the focused item
#   on_enter KEY  fzf actions for enter and double click, via `refreshed`
#   on_key L KEY  the same for letter L of LETTERS
#   job_NAME      the work behind an action, started detached by spawn
#   cmd_NAME      any other "script NAME" mode, e.g. cmd_toggle
#   menu_closing  optional, runs when the menu exits
#
# fzf calls back into "$SELF <mode>" for everything, so the callbacks keep no
# state except the files under STATE_DIR.
#
# Everything shown comes from the air - SSIDs and Bluetooth names are picked
# by whoever runs the transmitter - so it is printed with %s only, stripped
# of control characters, and never used inside arithmetic.

SELF="$(realpath "$0")"
printf -v SELF_Q '%q' "$SELF"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-$MENU_NAME"
ROWS="$STATE_DIR/rows"
printf -v ROWS_Q '%q' "$ROWS"
STATUS_TTL=6
CONFIRM_TTL=3

BOLD=$'\e[1m'
DIM=$'\e[2m'
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RESET=$'\e[0m'

ICON_OK=󰄬
ICON_ERROR=󰅖
ICON_BUSY=󰔟

# fzf only ever reloads the list from the ROWS file, which a background loop
# keeps current: with --track, fzf drops keys pressed while a reload runs, so
# the reload itself has to be instant. The reload also goes last in a chain -
# fzf skips whatever follows it.
RELOAD="reload-sync(cat $ROWS_Q)"
REFRESH="transform-header($SELF_Q header)+transform-footer($SELF_Q footer {1})+refresh-preview+$RELOAD"

declare -A PENDING=()

mkdir -p "$STATE_DIR/pending"

# $1 cut or padded to $2 columns. Counts characters - bash's printf widths
# count bytes and would misalign Cyrillic names.
pad() {
    local text="$1" width="$2"

    ((${#text} > width)) && text="${text:0:width-1}…"
    printf '%s%*s' "$text" $((width - ${#text})) ''
}

# Escapes text for a notification body, which mako renders as markup.
markup_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    printf '%s' "$value"
}

# "key action" pairs as one line, the keys bold and the rest dim.
hints() {
    local out=""

    while (($# >= 2)); do
        out+="$BOLD$1$RESET $DIM$2$RESET  "
        shift 2
    done

    printf '%s' "${out%  }"
}

# Puts a message in the status line for STATUS_TTL seconds. $1 is ok, error
# or info.
say() {
    printf '%s\t%s\t%s\n' "$EPOCHSECONDS" "$1" "$2" > "$STATE_DIR/status"
}

# The current message, colored, or nothing once it has expired.
said() {
    local when kind text

    [[ -r $STATE_DIR/status ]] || return 0
    IFS=$'\t' read -r when kind text < "$STATE_DIR/status" || return 0
    [[ $when =~ ^[0-9]+$ ]] && ((EPOCHSECONDS - when < STATUS_TTL)) || return 0

    case $kind in
        ok) printf '%s%s %s%s' "$GREEN" "$ICON_OK" "$text" "$RESET" ;;
        error) printf '%s%s %s%s' "$RED" "$ICON_ERROR" "$text" "$RESET" ;;
        *) printf '%s%s%s' "$YELLOW" "$text" "$RESET" ;;
    esac
}

# Marks item $1 as being worked on ("connecting", ...) until this process
# exits, so its row can say so.
pending() {
    printf '%s\t%s\n' "$1" "$2" > "$STATE_DIR/pending/$BASHPID"
    trap 'rm -f "$STATE_DIR/pending/$BASHPID"' EXIT
}

# Fills PENDING[key]=what from the jobs still alive.
load_pending() {
    local file key text

    for file in "$STATE_DIR"/pending/*; do
        [[ -r $file ]] || continue
        if ! kill -0 "${file##*/}" 2> /dev/null; then
            rm -f "$file"
            continue
        fi
        IFS=$'\t' read -r key text < "$file" && PENDING["$key"]=$text
    done

    return 0
}

# True on the second press of the same key on the same item within
# CONFIRM_TTL seconds; the first press only arms it.
confirmed() {
    local id="$1" when="" armed=""

    [[ -r $STATE_DIR/confirm ]] && IFS=$'\t' read -r when armed < "$STATE_DIR/confirm"

    if [[ $armed == "$id" && $when =~ ^[0-9]+$ ]] && ((EPOCHSECONDS - when < CONFIRM_TTL)); then
        rm -f "$STATE_DIR/confirm"
        return 0
    fi

    printf '%s\t%s\n' "$EPOCHSECONDS" "$id" > "$STATE_DIR/confirm"
    return 1
}

# spawn ITEM WHAT JOB ARGS... runs job_JOB detached - it finishes and reports
# even if the menu is closed meanwhile - with ITEM marked as WHAT
# ("connecting") while it runs. Waits for the mark, so the refresh that
# follows already shows it.
spawn() {
    local item="$1" what="$2" i

    PENDING_ITEM="$item" PENDING_WHAT="$what" setsid -f "$SELF" job "${@:3}" > /dev/null 2>&1 < /dev/null

    for ((i = 0; i < 50; i++)); do
        grep -qsxF -- "$item"$'\t'"$what" "$STATE_DIR"/pending/* && break
        sleep 0.01
    done
}

menu_open() {
    local pid
    [[ -r $STATE_DIR/menu.pid ]] && pid="$(< "$STATE_DIR/menu.pid")" && kill -0 "$pid" 2> /dev/null
}

# A desktop notification for a job that ends after the menu was closed; while
# it is open the status line says the same.
notify() {
    menu_open && return 0
    notify-send "$1" "$(markup_escape "$2")" -i "$3" \
        -h "string:x-canonical-private-synchronous:$MENU_NAME" 2> /dev/null || true
}

refresh_rows() {
    # Named up front: in a redirection of an external command, $BASHPID
    # expands in the forked child.
    local tmp="$ROWS.$BASHPID"

    "$SELF" rows > "$tmp" && mv -f "$tmp" "$ROWS"
}

# What an action handler prints last: the list rebuilt now, then fzf told to
# show it along with the new header and footer.
refreshed() {
    refresh_rows
    printf '%s' "$REFRESH"
}

menu_run() {
    local label="$1" letter letters binds=() first

    rm -f "$STATE_DIR/status" "$STATE_DIR/confirm"
    printf '%s\n' "$$" > "$STATE_DIR/menu.pid"
    refresh_rows

    # Stops by itself if this shell dies without running its traps.
    while sleep 1 && kill -0 $$ 2> /dev/null; do
        refresh_rows
    done &
    REFRESHER=$!

    # set +e: on a hangup the refresher is already dead, and a failing kill
    # must not cut the cleanup short.
    trap 'set +e; kill "$REFRESHER" 2> /dev/null; rm -f "$STATE_DIR/menu.pid"; declare -F menu_closing > /dev/null && menu_closing' EXIT
    trap 'exit 0' HUP INT TERM

    for letter in "${LETTERS[@]}"; do
        binds+=(--bind "$letter:transform($SELF_Q key $letter {1})")
    done

    # Letter keys act while the filter is hidden. "/" opens the filter and
    # lets them type; esc clears and closes it and gives them back. The
    # explicit search() is needed - with the input hidden, clear-query alone
    # leaves the old matches up.
    letters="$(IFS=,; printf '%s' "${LETTERS[*]},j,k,g,G,q,i")"
    first="$(head -n1 "$ROWS")"

    fzf "${binds[@]}" \
        --ansi \
        --no-sort \
        --reverse \
        --track \
        --id-nth=1 \
        --delimiter='\t' \
        --with-nth=2.. \
        --with-shell='bash -c' \
        --no-input \
        --prompt='/ ' \
        --info=inline-right \
        --border=sharp \
        --border-label=" $label " \
        --header="$(header)" \
        --header-border=line \
        --footer="$(footer "${first%%$'\t'*}")" \
        --footer-border=line \
        --highlight-line \
        --pointer= \
        --preview="$SELF_Q preview {1}" \
        --preview-window=right,40%,border-left,wrap \
        --bind="every(1):bg-transform-header($SELF_Q header)+bg-transform-footer($SELF_Q footer {1})+refresh-preview+$RELOAD" \
        --bind="focus:bg-transform-footer($SELF_Q footer {1})" \
        --bind="enter,double-click:transform($SELF_Q enter {1})" \
        --bind='j:down,k:up,g:first,G:last,q:abort,i:toggle-preview' \
        --bind="/:show-input+unbind($letters)" \
        --bind="esc:transform:[[ \$FZF_INPUT_STATE == hidden ]] && echo abort || echo 'clear-query+search()+hide-input+rebind($letters)'" \
        < "$ROWS" > /dev/null || true
}

menu_dispatch() {
    local mode="${1-}"
    (($#)) && shift

    case $mode in
        '') main ;;
        rows) load_pending; rows ;;
        header) header ;;
        footer) footer "${1-}" ;;
        preview) preview "${1-}" ;;
        enter) on_enter "${1-}" ;;
        key) on_key "$@" ;;
        job)
            declare -F "job_${1-}" > /dev/null || exit 2
            [[ -z ${PENDING_ITEM-} ]] || pending "$PENDING_ITEM" "$PENDING_WHAT"
            "job_$1" "${@:2}"
            ;;
        *)
            if ! declare -F "cmd_$mode" > /dev/null; then
                printf 'Unknown mode: %s\n' "$mode" >&2
                exit 2
            fi
            "cmd_$mode" "$@"
            ;;
    esac
}

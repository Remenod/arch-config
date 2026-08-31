#!/usr/bin/env bash
#
# Memory module: usage in the bar, where it actually went in the tooltip.
#
# Modes:
#   memory.sh module   JSON for Waybar
#   memory.sh top      open a process viewer in a terminal
#
# Waybar's built-in "memory" can only put {used}/{total} on a tooltip line.
# What that leaves out is everything worth knowing when the number climbs:
# how much of it is reclaimable cache, what has been pushed into swap and how
# far zram squeezed it, whether anything is stalling on memory, and which
# processes are holding the rest.
#
# Unlike the cpu module this needs no deltas - /proc/meminfo is absolute - so
# it stays a plain interval script rather than a daemon.

set -euo pipefail

#--------------------------------------------------------------------
# configuration
#--------------------------------------------------------------------

WARN=${WARN:-75}                   # used share that turns the bar amber
CRIT=${CRIT:-90}
STALL_WARN=${STALL_WARN:-5}        # PSI "some avg10" that counts as pressure
TOP_N=${TOP_N:-6}                  # process groups listed in the tooltip
BAR=${BAR:-20}                     # bar width, in cells
PAGE_KIB=${PAGE_KIB:-4}            # /proc/<pid>/stat counts rss in pages

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
THEME_FILE=${THEME_FILE:-"$CONFIG_DIR/theme.css"}

TERM_CMD=(alacritty)
VIEWERS=(btop htop btm top)

ICON=󰘚                             # md-memory
ICON_ALERT=󰀧                       # md-alert-octagon
ICON_CHIP=󰍛                        # md-chip

BLOCK=█

declare -A MI=()                   # /proc/meminfo, in kB
declare -A THEME=()

C_OK="#a6e3a1"
C_MID="#f9e2af"
C_HOT="#f38ba8"
C_DIM="#6c7086"
C_CACHE="#89b4fa"

NL='\n'
ESC=""
BARBUF=""
VIEWER=""

#--------------------------------------------------------------------
# helpers
#--------------------------------------------------------------------

# Makes a short foreign string safe for both JSON and Pango, in that order.
# Everything else in the tooltip is markup this script wrote, and NL is the
# two-character escape, so nothing else needs escaping.
esc_field() {
    ESC="$1"
    ESC="${ESC//\\/\\\\}"
    ESC="${ESC//\"/\\\"}"
    ESC="${ESC//$'\n'/ }"
    ESC="${ESC//&/&amp;}"
    ESC="${ESC//</&lt;}"
    ESC="${ESC//>/&gt;}"
}

# Follow the active Catppuccin flavour so the bars match the rest of the bar.
load_theme() {
    local directive key value

    if [[ -r $THEME_FILE ]]; then
        while read -r directive key value; do
            [[ $directive == @define-color ]] || continue
            value="${value%;}"
            # Skip the aliases - "@define-color warning @yellow" and friends
            # only matter to GTK, this wants the literal hex.
            [[ $value == \#* ]] && THEME[$key]="$value"
        done < "$THEME_FILE"
    fi

    C_OK="${THEME[green]:-#a6e3a1}"
    C_MID="${THEME[yellow]:-#f9e2af}"
    C_HOT="${THEME[red]:-#f38ba8}"
    C_DIM="${THEME[overlay0]:-#6c7086}"
    C_CACHE="${THEME[blue]:-#89b4fa}"
}

# bar <pct> [color]
bar() {
    local pct="$1" color="${2:-}" fill i filled="" empty=""

    fill=$(((pct * BAR + 50) / 100))
    ((fill < 0)) && fill=0
    ((fill > BAR)) && fill=$BAR

    if [[ -z $color ]]; then
        if ((pct >= 85)); then
            color="$C_HOT"
        elif ((pct >= 50)); then
            color="$C_MID"
        else
            color="$C_OK"
        fi
    fi

    for ((i = 0; i < fill; i++)); do filled+="$BLOCK"; done
    for ((i = fill; i < BAR; i++)); do empty+="$BLOCK"; done

    printf -v BARBUF "<span color='%s'>%s</span><span color='%s' alpha='35%%'>%s</span>" \
        "$color" "$filled" "$C_DIM" "$empty"
}

# bar_stacked <used pct> <cache pct>
#
# One bar, two fills: what is committed in the load colour, what is cache
# behind it in the accent, the rest dim. The interesting question about RAM is
# how full the chip physically is, not two unrelated fractions - and the split
# shows at a glance how much of "full" is instantly reclaimable.
#
# The two shares are very slightly optimistic: "used" is MemTotal-MemAvailable,
# and MemAvailable already writes off most of the cache as reclaimable, so the
# segments overlap by whatever the kernel thinks it cannot reclaim. On a
# twenty-cell bar that is well under one cell.
bar_stacked() {
    local a="$1" b="$2" fa fb rest color i sa="" sb="" sr=""

    fa=$(((a * BAR + 50) / 100))
    ((fa < 0)) && fa=0
    ((fa > BAR)) && fa=$BAR

    fb=$(((((a + b)) * BAR + 50) / 100 - fa))
    ((fb < 0)) && fb=0
    ((fa + fb > BAR)) && fb=$((BAR - fa))

    rest=$((BAR - fa - fb))

    if ((a >= 85)); then
        color="$C_HOT"
    elif ((a >= 50)); then
        color="$C_MID"
    else
        color="$C_OK"
    fi

    for ((i = 0; i < fa; i++)); do sa+="$BLOCK"; done
    for ((i = 0; i < fb; i++)); do sb+="$BLOCK"; done
    for ((i = 0; i < rest; i++)); do sr+="$BLOCK"; done

    printf -v BARBUF "%s%s%s" \
        "<span color='$color'>$sa</span>" \
        "<span color='$C_CACHE' alpha='60%'>$sb</span>" \
        "<span color='$C_DIM' alpha='30%'>$sr</span>"
}

# gib <varname> <kib>
#
# Rounded to a tenth rather than truncated. 48 GiB of swap is really 47.999
# once the per-device header pages come off, and truncating that to "47.9"
# reads as a wrong number instead of a rounded one.
gib() {
    local tenths=$((($2 * 10 + 524288) / 1048576))
    printf -v "$1" '%d.%d' $((tenths / 10)) $((tenths % 10))
}

# gib_b <varname> <bytes>
gib_b() {
    local tenths=$((($2 * 10 + 536870912) / 1073741824))
    printf -v "$1" '%d.%d' $((tenths / 10)) $((tenths % 10))
}

pct_of() { # pct_of <varname> <part> <whole>
    if (($3 > 0)); then
        printf -v "$1" '%d' $((($2 * 100 + $3 / 2) / $3))
    else
        printf -v "$1" '%d' 0
    fi
}

#--------------------------------------------------------------------
# sampling
#--------------------------------------------------------------------

read_meminfo() {
    local key value

    while read -r key value _; do
        MI[${key%:}]="$value"
    done < /proc/meminfo
}

# Memory pressure: the share of the last ten seconds in which at least one
# task was stalled waiting for memory. Zero on a healthy system, and the only
# number here that says "this is actually hurting" rather than "this is full".
read_pressure() {
    local kind rest

    STALL=0
    [[ -r /proc/pressure/memory ]] || return 0

    while read -r kind rest; do
        [[ $kind == some ]] || continue
        rest="${rest#avg10=}"
        STALL="${rest%% *}"
        return 0
    done < /proc/pressure/memory
}

# Swap devices that hold anything, split into zram and everything else - the
# distinction matters, because falling through to a disk swap is the slow one.
read_swaps() {
    local dev type size used prio

    ZRAM_USED=0
    DISK_USED=0
    DISK_NAME=""

    [[ -r /proc/swaps ]] || return 0

    { read -r _; while read -r dev type size used prio; do
        [[ $used =~ ^[0-9]+$ ]] || continue
        if [[ $dev == /dev/zram* ]]; then
            ZRAM_USED=$((ZRAM_USED + used))
        else
            DISK_USED=$((DISK_USED + used))
            ((used > 0)) && DISK_NAME="${dev##*/}"
        fi
    done; } < /proc/swaps

    # The loop body ends on a test that is false for an unused device, and
    # that status would otherwise become the function's under set -e.
    return 0
}

# How much RAM the compressed pages actually occupy, and with which algorithm.
read_zram() {
    local dev orig compr used algo word

    ZRAM_ORIG=0
    ZRAM_PHYS=0
    ZRAM_ALGO=""

    for dev in /sys/block/zram*; do
        [[ -r $dev/mm_stat ]] || continue
        read -r orig compr used _ < "$dev/mm_stat" || continue
        [[ $orig =~ ^[0-9]+$ ]] || continue

        ZRAM_ORIG=$((ZRAM_ORIG + orig))
        ZRAM_PHYS=$((ZRAM_PHYS + used))

        if [[ -z $ZRAM_ALGO && -r $dev/comp_algorithm ]]; then
            read -r -a algo < "$dev/comp_algorithm"
            for word in "${algo[@]}"; do
                [[ $word == \[*\] ]] && { ZRAM_ALGO="${word:1:-1}"; break; }
            done
        fi
    done

    return 0
}

# Resident set summed per process name, because a browser is thirty processes
# and one row. RSS counts shared pages once per process, so the total is an
# upper bound - good enough to answer "what is eating my RAM".
read_top() {
    TOP_LIST="$(head -q -n1 /proc/[0-9]*/stat 2> /dev/null | awk -v topn="$TOP_N" '
        {
            open = index($0, "(")
            if (open == 0 || !match($0, /\)[^)]*$/)) next

            comm = substr($0, open + 1, RSTART - open - 1)
            if (length(comm) > 17) comm = substr(comm, 1, 17)
            split(substr($0, RSTART + 2), f, " ")

            if (f[22] + 0 <= 0) next
            pages[comm] += f[22]
            procs[comm]++
        }
        END {
            n = 0
            for (k in pages) idx[++n] = k

            for (i = 1; i <= topn && i <= n; i++) {
                best = i
                for (j = i + 1; j <= n; j++)
                    if (pages[idx[j]] > pages[idx[best]]) best = j
                k = idx[i]; idx[i] = idx[best]; idx[best] = k
                printf "%s\t%d\t%d\n", idx[i], pages[idx[i]], procs[idx[i]]
            }
        }' || true)"
}

find_viewer() {
    local v
    for v in "${VIEWERS[@]}"; do
        command -v "$v" > /dev/null 2>&1 && { VIEWER="$v"; return 0; }
    done
    return 0
}

#--------------------------------------------------------------------
# rendering
#--------------------------------------------------------------------

build_tooltip() {
    local out line used cache total swap_total swap_used
    local used_pct cache_pct swap_pct ratio
    local g_used g_total g_cache g_avail g_swap g_swaptotal g_orig g_phys g_disk
    local name pages procs g_proc suffix i hint

    total=${MI[MemTotal]:-0}
    used=$((total - ${MI[MemAvailable]:-0}))
    cache=$((${MI[Buffers]:-0} + ${MI[Cached]:-0} + ${MI[SReclaimable]:-0}))
    swap_total=${MI[SwapTotal]:-0}
    swap_used=$((swap_total - ${MI[SwapFree]:-0}))

    pct_of used_pct "$used" "$total"
    pct_of cache_pct "$cache" "$total"
    pct_of swap_pct "$swap_used" "$swap_total"

    gib g_used "$used"
    gib g_total "$total"
    gib g_cache "$cache"
    gib g_avail "${MI[MemAvailable]:-0}"
    gib g_swap "$swap_used"
    gib g_swaptotal "$swap_total"

    out="$ICON_CHIP  <b>Memory</b>   <span alpha='60%'>$g_total GiB</span>$NL$NL"

    bar_stacked "$used_pct" "$cache_pct"
    printf -v line 'Used     %s %3s%%' "$BARBUF" "$used_pct"
    out+="$line   $g_used GiB$NL"

    # Cache is why "free" looks small and why that is fine. Colouring the word
    # the same as its slice of the bar is what makes the stack self-explaining.
    printf -v line "         <span color='%s'>%s GiB cache</span>, reclaimable · %s GiB available" \
        "$C_CACHE" "$g_cache" "$g_avail"
    out+="<span alpha='70%'>$line</span>$NL"

    if ((swap_total > 0)); then
        bar "$swap_pct"
        printf -v line 'Swap     %s %3s%%' "$BARBUF" "$swap_pct"
        out+="$line   $g_swap / $g_swaptotal GiB$NL"

        if ((ZRAM_ORIG > 0 && ZRAM_PHYS > 0)); then
            gib_b g_orig "$ZRAM_ORIG"
            gib_b g_phys "$ZRAM_PHYS"
            ratio=$(((ZRAM_ORIG * 10 + ZRAM_PHYS / 2) / ZRAM_PHYS))
            printf -v line '         zram %s → %s GiB in RAM  (%s, %d.%d×)' \
                "$g_orig" "$g_phys" "${ZRAM_ALGO:-compressed}" $((ratio / 10)) $((ratio % 10))
            out+="<span alpha='55%'>$line</span>$NL"
        fi

        if ((DISK_USED > 0)); then
            gib g_disk "$DISK_USED"
            esc_field "$DISK_NAME"
            out+="<span color='$C_HOT'>         $g_disk GiB on $ESC - disk swap, not zram</span>$NL"
        fi
    fi

    # Only worth a line when it is not zero, which on a healthy system it is.
    if [[ $STALL != 0 && $STALL != 0.00 ]]; then
        printf -v line 'Stalled  %s%%' "$STALL"
        out+="<span color='$C_HOT'>$line</span>   <span alpha='55%'>of the last 10 s waiting on memory</span>$NL"
    fi

    if [[ -n $TOP_LIST ]]; then
        out+="$NL"
        i=0
        while IFS=$'\t' read -r name pages procs; do
            [[ -n $name ]] || continue
            esc_field "$name"
            gib g_proc $((pages * PAGE_KIB))
            suffix=""
            ((procs > 1)) && printf -v suffix "  <span alpha='55%%'>×%s</span>" "$procs"
            ((i == 0)) && printf -v line 'Top      %-17s %5s GiB' "$ESC" "$g_proc" ||
                printf -v line '         %-17s %5s GiB' "$ESC" "$g_proc"
            out+="$line$suffix$NL"
            i=$((i + 1))
        done <<< "$TOP_LIST"
    fi

    [[ -n $VIEWER ]] && hint="click to open $VIEWER" || hint="resident set per process name"
    out+="$NL<span alpha='55%'>$hint</span>"

    TOOLTIP="$out"
}

module() {
    local used total used_pct icon class stalled

    load_theme
    read_meminfo
    read_pressure
    read_swaps
    read_zram
    find_viewer
    ((TOP_N > 0)) && read_top || TOP_LIST=""

    total=${MI[MemTotal]:-0}
    used=$((total - ${MI[MemAvailable]:-0}))
    pct_of used_pct "$used" "$total"

    # Integer share of the PSI figure, which is printed as "12.34".
    stalled="${STALL%%.*}"
    [[ $stalled =~ ^[0-9]+$ ]] || stalled=0

    icon="$ICON"
    class=""
    if ((used_pct >= CRIT)); then
        class="critical"
        icon="$ICON_ALERT"
    elif ((used_pct >= WARN)); then
        class="warning"
        icon="$ICON_ALERT"
    elif ((stalled >= STALL_WARN)); then
        class="pressure"
    fi

    build_tooltip
    esc_field "$icon $used_pct%"

    printf '{"text":"%s","tooltip":"%s","class":"%s","percentage":%d}\n' \
        "$ESC" "$TOOLTIP" "$class" "$used_pct"
}

open_viewer() {
    find_viewer
    [[ -n $VIEWER ]] || exit 0
    exec "${TERM_CMD[@]}" -e "$VIEWER"
}

case "${1:-module}" in
    module) module ;;
    top) open_viewer ;;
    *)
        printf 'Usage: %s {module|top}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

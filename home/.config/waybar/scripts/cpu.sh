#!/usr/bin/env bash
#
# CPU module: package load in the bar, the whole picture in the tooltip.
#
# Modes:
#   cpu.sh module   long-running daemon, one JSON line per tick (no "interval")
#   cpu.sh once     print a single JSON line and exit (handy for debugging)
#   cpu.sh top      open a process viewer in a terminal
#
# Why this replaces Waybar's built-in "cpu": {usage} is the average over every
# thread, so one saturated thread reads as 100/nproc - about 6% on a 16-thread
# part - while the package still clocks up and heats up. The bar therefore
# carries a second gauge for the *busiest* thread, and the tooltip breaks the
# load down per physical core next to the processes actually burning it.

set -euo pipefail

#--------------------------------------------------------------------
# configuration
#--------------------------------------------------------------------

INTERVAL=${INTERVAL:-1}            # seconds between samples
WARN=${WARN:-75}                   # package usage that turns the bar amber
CRIT=${CRIT:-90}
THREAD_BUSY=${THREAD_BUSY:-90}     # a single thread this busy ...
THREAD_TICKS=${THREAD_TICKS:-3}    # ... for this many samples counts as pegged
TOP_N=${TOP_N:-5}                  # processes listed in the tooltip
TOP_EVERY=${TOP_EVERY:-3}          # resample the process table every N ticks
PKG_BAR=${PKG_BAR:-20}             # width of the package bar, in cells
THREAD_BAR=${THREAD_BAR:-8}        # width of a per-thread bar
SPLIT_AT=${SPLIT_AT:-12}           # more cores than this, list them in 2 columns
THEME_EVERY=${THEME_EVERY:-30}     # re-read the palette every N ticks

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
THEME_FILE=${THEME_FILE:-"$CONFIG_DIR/theme.css"}
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-cpu"
PROC_PREV="$RUNDIR/proc-$$.tsv"

# A process viewer wants a real window, not the small centred popup Hyprland
# floats for the fzf menus, so this uses the plain terminal.
TERM_CMD=(alacritty)
VIEWERS=(btop htop btm top)

ICON=󰍛                             # md-memory, the chip shown in the bar
ICON_ALERT=󰀨                       # md-alert
ICON_CHIP=󰻠                        # md-cpu-64-bit

BLOCK=█
GAUGE=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)            # one-glyph readout for the busiest thread

#--------------------------------------------------------------------
# state
#--------------------------------------------------------------------

declare -a PREV_BUSY=() PREV_TOTAL=()
declare -a CUR_BUSY=() CUR_TOTAL=()
declare -a USAGE=()                # 0 = package, 1..N = cpu0..cpuN-1
declare -a CORE_KEYS=()            # "package:core", in enumeration order
declare -A CORE_THREADS=()         # "package:core" -> thread indices
declare -a FILL=()                 # FILL[n] = n block glyphs
declare -a CORE_ROWS_OUT=()        # one rendered line per physical core
declare -A THEME=()

CPU_MODEL="CPU"
NTHREADS=0
NCORES=0
MULTI_PKG=false
AGG_DT=0
PROC_WINDOW=0
PEG_TICKS=0
TICK=0
TOP_LIST=""
VIEWER=""
TICK_FD=""
TOOLTIP=""
BARBUF=""
ESC=""
FREQ_AVG=0
FREQ_MAX=0
PKG_PCT=0
PEAK_PCT=0
PEAK_CPU=0

C_OK="#a6e3a1"
C_MID="#f9e2af"
C_HOT="#f38ba8"
C_DIM="#6c7086"

#--------------------------------------------------------------------
# helpers
#--------------------------------------------------------------------

# The escapes and the renderers below all publish through globals rather than
# echoing into $(...). At one tick per second a command substitution per bar
# cell is the single biggest cost in the module - roughly forty forks a second
# on a 16-thread part - and printf -v removes all of them.
#
# The tooltip is assembled already JSON-safe: NL is the two-character escape
# rather than a real newline, and every span attribute is single-quoted, so
# only the strings that come from outside - the model string and process
# names - have to be run through esc_field. Escaping the finished 2 kB tooltip
# instead costs about 5 ms a tick.

NL='\n'

# Makes a short foreign string safe for both JSON and Pango, in that order.
esc_field() {
    ESC="$1"
    ESC="${ESC//\\/\\\\}"
    ESC="${ESC//\"/\\\"}"
    ESC="${ESC//$'\n'/ }"
    ESC="${ESC//&/&amp;}"
    ESC="${ESC//</&lt;}"
    ESC="${ESC//>/&gt;}"
}

# Every block run the bars can need, rendered once at startup.
precompute_blocks() {
    local i max=$PKG_BAR s=""
    ((THREAD_BAR > max)) && max=$THREAD_BAR
    for ((i = 0; i <= max; i++)); do
        FILL[i]="$s"
        s+="$BLOCK"
    done
}

# Follow the active Catppuccin flavour so the tooltip bars match the bar.
load_theme() {
    local key value
    THEME=()

    if [[ -r $THEME_FILE ]]; then
        while read -r _ key value; do
            value="${value%;}"
            [[ $value == \#* ]] && THEME[$key]="$value"
        done < <(grep -E '^@define-color[[:space:]]' "$THEME_FILE" 2> /dev/null || true)
    fi

    C_OK="${THEME[green]:-#a6e3a1}"
    C_MID="${THEME[yellow]:-#f9e2af}"
    C_HOT="${THEME[red]:-#f38ba8}"
    C_DIM="${THEME[overlay0]:-#6c7086}"
}

bar() {
    local pct="$1" width="$2" fill color

    fill=$(((pct * width + 50) / 100))
    ((fill < 0)) && fill=0
    ((fill > width)) && fill=$width

    if ((pct >= 85)); then
        color="$C_HOT"
    elif ((pct >= 50)); then
        color="$C_MID"
    else
        color="$C_OK"
    fi

    printf -v BARBUF "<span color='%s'>%s</span><span color='%s' alpha='35%%'>%s</span>" \
        "$color" "${FILL[fill]}" "$C_DIM" "${FILL[width - fill]}"
}

# A read from a fifo nobody ever writes to blocks for the whole interval
# without forking a sleep every second, and leaves no killed child for the
# shell to announce as "Terminated" on Waybar's stderr at shutdown.
open_timer() {
    local fifo="$RUNDIR/tick-$$"

    rm -f "$fifo"
    mkfifo "$fifo" 2> /dev/null || return 1
    exec {TICK_FD}<> "$fifo"
    rm -f "$fifo"
}

naptime() {
    if [[ -n $TICK_FD ]]; then
        read -r -t "$INTERVAL" -u "$TICK_FD" _ || true
    else
        sleep "$INTERVAL"
    fi
}

#--------------------------------------------------------------------
# sampling
#--------------------------------------------------------------------

# CUR_BUSY/CUR_TOTAL[0] is the package, [n+1] is cpu<n>.
sample_stat() {
    local name user nice sys idle_j io irq sirq steal total idle

    CUR_BUSY=()
    CUR_TOTAL=()

    # guest and guest_nice are already counted inside user/nice, so the sum
    # deliberately stops at steal.
    while read -r name user nice sys idle_j io irq sirq steal _; do
        [[ $name == cpu* ]] || break

        total=$((user + nice + sys + idle_j + io + irq + sirq + steal))
        idle=$((idle_j + io))

        CUR_BUSY+=($((total - idle)))
        CUR_TOTAL+=("$total")
    done < /proc/stat
}

compute_usage() {
    local i db dt

    USAGE=()
    for i in "${!CUR_BUSY[@]}"; do
        db=$((CUR_BUSY[i] - ${PREV_BUSY[i]:-0}))
        dt=$((CUR_TOTAL[i] - ${PREV_TOTAL[i]:-0}))

        if ((dt > 0)); then
            USAGE[i]=$(((db * 100 + dt / 2) / dt))
        else
            USAGE[i]=0
        fi

        ((USAGE[i] > 100)) && USAGE[i]=100
        ((USAGE[i] < 0)) && USAGE[i]=0
    done

    AGG_DT=$((CUR_TOTAL[0] - ${PREV_TOTAL[0]:-0}))
    ((AGG_DT < 0)) && AGG_DT=0

    PREV_BUSY=("${CUR_BUSY[@]}")
    PREV_TOTAL=("${CUR_TOTAL[@]}")
}

detect_topology() {
    local n core pkg key
    local -A packages=()

    NTHREADS=$((${#CUR_BUSY[@]} - 1))
    ((NTHREADS < 1)) && NTHREADS=1

    CORE_KEYS=()
    CORE_THREADS=()

    for ((n = 0; n < NTHREADS; n++)); do
        core="$n"
        pkg=0
        [[ -r /sys/devices/system/cpu/cpu$n/topology/core_id ]] &&
            read -r core < "/sys/devices/system/cpu/cpu$n/topology/core_id"
        [[ -r /sys/devices/system/cpu/cpu$n/topology/physical_package_id ]] &&
            read -r pkg < "/sys/devices/system/cpu/cpu$n/topology/physical_package_id"

        packages[$pkg]=1
        key="$pkg:$core"

        if [[ -z ${CORE_THREADS[$key]:-} ]]; then
            CORE_KEYS+=("$key")
            CORE_THREADS[$key]="$n"
        else
            CORE_THREADS[$key]+=" $n"
        fi
    done

    NCORES=${#CORE_KEYS[@]}
    ((${#packages[@]} > 1)) && MULTI_PKG=true || MULTI_PKG=false
}

detect_model() {
    local line

    while IFS= read -r line; do
        case $line in
            "model name"* | "Model name"*)
                CPU_MODEL="${line#*: }"
                break
                ;;
        esac
    done < /proc/cpuinfo

    CPU_MODEL="${CPU_MODEL//"(R)"/}"
    CPU_MODEL="${CPU_MODEL//"(TM)"/}"
    CPU_MODEL="${CPU_MODEL//" CPU"/}"
    while [[ $CPU_MODEL == *"  "* ]]; do CPU_MODEL="${CPU_MODEL//"  "/ }"; done
}

# -> $FREQ_AVG, $FREQ_MAX in kHz; fails when cpufreq is not exposed.
read_freq() {
    local file cur sum=0 max=0 n=0

    for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        [[ -r $file ]] || continue
        read -r cur < "$file" 2> /dev/null || continue
        [[ $cur =~ ^[0-9]+$ ]] || continue

        sum=$((sum + cur))
        n=$((n + 1))
        ((cur > max)) && max=$cur
    done

    ((n == 0)) && return 1

    FREQ_AVG=$((sum / n))
    FREQ_MAX=$max
}

# ghz <varname> <kHz>
ghz() { printf -v "$1" '%d.%02d' $(($2 / 1000000)) $((($2 % 1000000) / 10000)); }

# Per-process CPU time deltas, i.e. what htop shows - a single-threaded hog
# reads as ~100% of one core even while the package sits at 6%. Done with one
# head and one awk rather than 400 bash reads, which costs ~10 ms per sample.
sample_top() {
    local out

    out="$(head -q -n1 /proc/[0-9]*/stat 2> /dev/null | awk \
        -v prev="$PROC_PREV" -v nthreads="$NTHREADS" -v window="$PROC_WINDOW" \
        -v topn="$TOP_N" '
        BEGIN {
            while ((getline line < prev) > 0) {
                split(line, a, "\t")
                p[a[1]] = a[2]
            }
            close(prev)
            scale = (window > 0) ? 100.0 * nthreads / window : 0
        }
        {
            open = index($0, "(")
            if (open == 0 || !match($0, /\)[^)]*$/)) next

            comm = substr($0, open + 1, RSTART - open - 1)
            if (length(comm) > 17) comm = substr(comm, 1, 17)
            split(substr($0, RSTART + 2), f, " ")
            ticks = f[12] + f[13]

            cur[$1] = ticks
            if ($1 in p) {
                d = ticks - p[$1]
                if (d > 0 && scale > 0) {
                    pct[$1] = d * scale
                    name[$1] = comm
                }
            }
        }
        END {
            snapshot = ""
            for (k in cur) snapshot = snapshot k "\t" cur[k] "\n"
            printf "%s", snapshot > prev
            close(prev)

            n = 0
            for (k in pct) if (pct[k] >= 0.5) idx[++n] = k

            for (i = 1; i <= topn && i <= n; i++) {
                best = i
                for (j = i + 1; j <= n; j++)
                    if (pct[idx[j]] > pct[idx[best]]) best = j
                k = idx[i]; idx[i] = idx[best]; idx[best] = k
                printf "%s\t%d\n", name[idx[i]], int(pct[idx[i]] + 0.5)
            }
        }' || true)"

    TOP_LIST="$out"
    PROC_WINDOW=0
}

#--------------------------------------------------------------------
# rendering
#--------------------------------------------------------------------

# Package average, busiest thread and where it sits. Both the bar text and the
# tooltip need all three, so they are computed once into globals per tick.
compute_peak() {
    local i

    PKG_PCT=${USAGE[0]:-0}
    PEAK_PCT=0
    PEAK_CPU=0

    for ((i = 0; i < NTHREADS; i++)); do
        if ((${USAGE[i + 1]:-0} > PEAK_PCT)); then
            PEAK_PCT=${USAGE[i + 1]}
            PEAK_CPU=$i
        fi
    done

    if ((PEAK_PCT >= THREAD_BUSY)); then
        PEG_TICKS=$((PEG_TICKS + 1))
    else
        PEG_TICKS=0
    fi
}

# One line per physical core, its SMT siblings side by side.
build_core_rows() {
    local key core threads t row cell pct

    CORE_ROWS_OUT=()

    for key in "${CORE_KEYS[@]}"; do
        core="${key#*:}"
        if $MULTI_PKG; then
            printf -v row 'P%s C%-3s' "${key%%:*}" "$core"
        else
            printf -v row 'Core %-3s' "$core"
        fi

        threads="${CORE_THREADS[$key]}"
        for t in $threads; do
            pct=${USAGE[t + 1]:-0}
            bar "$pct" "$THREAD_BAR"
            printf -v cell ' %s %3s%%' "$BARBUF" "$pct"
            row+="$cell"
        done

        CORE_ROWS_OUT+=("$row")
    done
}

# -> $TOOLTIP
build_tooltip() {
    local out line favg fmax l1 l5 l15 rows half i a b name pct hint

    esc_field "$CPU_MODEL"
    out="$ICON_CHIP  <b>$ESC</b>$NL"
    out+="<span alpha='60%'>   $NCORES cores · $NTHREADS threads</span>$NL$NL"

    # Both bars are the full width: the whole point of the pair is comparing
    # them at a glance, so the thread name goes after the number rather than
    # eating cells out of the second bar.
    bar "$PKG_PCT" "$PKG_BAR"
    printf -v line 'Average  %s %3s%%' "$BARBUF" "$PKG_PCT"
    out+="$line$NL"

    bar "$PEAK_PCT" "$PKG_BAR"
    printf -v line 'Busiest  %s %3s%%' "$BARBUF" "$PEAK_PCT"
    out+="$line  <span alpha='55%'>cpu$PEAK_CPU</span>"
    ((PEG_TICKS >= THREAD_TICKS)) &&
        out+="<span color='$C_HOT'> · pegged $((PEG_TICKS * INTERVAL))s</span>"
    out+="$NL"

    if read_freq; then
        ghz favg "$FREQ_AVG"
        ghz fmax "$FREQ_MAX"
        printf -v line 'Clock    %s GHz avg · %s GHz peak' "$favg" "$fmax"
        out+="$line$NL"
    fi

    # Load average is a task count, not a percentage: how many tasks wanted a
    # thread on average. Printing "of $NTHREADS" next to it is what makes it
    # readable - at 16 every thread has work queued, below that there is slack.
    if read -r l1 l5 l15 _ < /proc/loadavg; then
        printf -v line 'Load     %s · %s · %s of %s' "$l1" "$l5" "$l15" "$NTHREADS"
        out+="$line   <span alpha='55%'>1 · 5 · 15 min</span>$NL"
    fi

    build_core_rows
    out+="$NL"

    rows=${#CORE_ROWS_OUT[@]}
    if ((rows > SPLIT_AT)); then
        half=$(((rows + 1) / 2))
        for ((i = 0; i < half; i++)); do
            a="${CORE_ROWS_OUT[i]}"
            b="${CORE_ROWS_OUT[i + half]:-}"
            [[ -n $b ]] && out+="$a   $b$NL" || out+="$a$NL"
        done
    else
        for ((i = 0; i < rows; i++)); do
            out+="${CORE_ROWS_OUT[i]}$NL"
        done
    fi

    if [[ -n $TOP_LIST ]]; then
        out+="$NL"
        i=0
        while IFS=$'\t' read -r name pct; do
            [[ -n $name ]] || continue
            esc_field "$name"
            if ((i == 0)); then
                printf -v line 'Top      %-17s %3s%%' "$ESC" "$pct"
            else
                printf -v line '         %-17s %3s%%' "$ESC" "$pct"
            fi
            out+="$line$NL"
            i=$((i + 1))
        done <<< "$TOP_LIST"
    fi

    [[ -n $VIEWER ]] && hint="click to open $VIEWER" || hint="per-thread load · % of one core"
    out+="$NL<span alpha='55%'>$hint</span>"

    TOOLTIP="$out"
}

emit() {
    local idx icon class

    compute_peak

    idx=$((PEAK_PCT * 8 / 100))
    ((idx > 7)) && idx=7
    ((idx < 0)) && idx=0

    icon="$ICON"
    class=""
    if ((PKG_PCT >= CRIT)); then
        class="critical"
        icon="$ICON_ALERT"
    elif ((PKG_PCT >= WARN)); then
        class="warning"
        icon="$ICON_ALERT"
    elif ((PEG_TICKS >= THREAD_TICKS)); then
        class="pegged"
    fi

    build_tooltip

    esc_field "$icon $PKG_PCT% ${GAUGE[idx]}"

    printf '{"text":"%s","tooltip":"%s","class":"%s","percentage":%d}\n' \
        "$ESC" "$TOOLTIP" "$class" "$PKG_PCT"
}

#--------------------------------------------------------------------
# modes
#--------------------------------------------------------------------

find_viewer() {
    local v
    for v in "${VIEWERS[@]}"; do
        if command -v "$v" > /dev/null 2>&1; then
            VIEWER="$v"
            return 0
        fi
    done
    return 0
}

cleanup() {
    rm -f "$PROC_PREV" "$RUNDIR/tick-$$"
}

setup() {
    mkdir -p "$RUNDIR"
    trap cleanup EXIT
    # Exiting from the handler rather than falling through it stops the shell
    # from announcing the interrupted wait on Waybar's stderr at shutdown.
    trap 'cleanup; exit 0' INT TERM HUP

    open_timer || true
    precompute_blocks
    load_theme
    detect_model
    find_viewer

    sample_stat
    PREV_BUSY=("${CUR_BUSY[@]}")
    PREV_TOTAL=("${CUR_TOTAL[@]}")
    detect_topology
}

tick() {
    sample_stat
    compute_usage
    PROC_WINDOW=$((PROC_WINDOW + AGG_DT))

    if ((TOP_N > 0)) && ((TICK % TOP_EVERY == 0)); then
        sample_top
    fi

    ((THEME_EVERY > 0)) && ((TICK % THEME_EVERY == 0)) && load_theme

    emit
    TICK=$((TICK + 1))
}

module() {
    setup

    # Prime the process table so the first tooltip already has a top list.
    sample_top
    PROC_WINDOW=0

    while true; do
        naptime
        tick
    done
}

once() {
    setup
    sample_top
    PROC_WINDOW=0
    naptime
    tick
}

open_viewer() {
    find_viewer
    [[ -n $VIEWER ]] || exit 0
    exec "${TERM_CMD[@]}" -e "$VIEWER"
}

case "${1:-module}" in
    module) module ;;
    once) once ;;
    top) open_viewer ;;
    *)
        printf 'Usage: %s {module|once|top}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

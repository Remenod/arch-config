#!/usr/bin/env bash
#
# Check for official and AUR package updates and upgrade them.
#
# Modes:
#   system-update.sh module    long-running daemon, prints one JSON line per
#                              state change for a *continuous* Waybar module
#                              (no "interval" in the module config)
#   system-update.sh refresh   ask the running daemon to re-check right now
#   system-update.sh click     what the Waybar left click runs: an upgrade
#                              normally, a reboot prompt once a kernel
#                              upgrade has made a restart necessary
#   system-update.sh list      show the pending updates in a pager
#   system-update.sh           interactive upgrade (run inside a terminal)
#
# The daemon animates a spinner while it is actually fetching, so the bar shows
# live feedback both on the automatic interval and after a manual refresh.
#
# Requirements:
# - checkupdates (pacman-contrib)
# - notify-send (libnotify)
# - fzf (reboot prompt)
# - Optional: An AUR helper
#
# Author:  Jesse Mirabel <sejjymvm@gmail.com>
# Date:    August 16, 2025
# License: MIT

#--------------------------------------------------------------------
# configuration
#--------------------------------------------------------------------

INTERVAL=${INTERVAL:-3600}        # seconds between automatic checks
RETRY_INTERVAL=${RETRY_INTERVAL:-300}  # retry sooner after a failed check
TIMEOUT=${TIMEOUT:-20}            # per-backend fetch timeout
SPIN_DELAY=${SPIN_DELAY:-0.1}     # seconds per animation frame
TOOLTIP_MAX=${TOOLTIP_MAX:-12}    # packages listed per section in the tooltip
NOTIFY=${NOTIFY:-true}            # notify when new updates show up
UPGRADE_GUARD=${UPGRADE_GUARD:-1800}  # give up on a stuck "upgrading" state
CACHE_TTL=${CACHE_TTL:-30}        # share a fetch between bars for this long

HELPERS=(paru yay aura pikaur trizen)

# Terminals spawned by the click actions. The popup class is the one Hyprland
# floats and centres, so it must stay in sync with the window rule.
TERM_CMD=(alacritty)
POPUP_CMD=(alacritty --class alacritty-popup-menu)

# md-circle-slice-1..8, a filling pie used as the spinner
SPINNER=(󰪞 󰪟 󰪠 󰪡 󰪢 󰪣 󰪤 󰪥)

ICON_OK=󰸟           # md-package-variant-closed-check
ICON_PENDING=󰄠      # md-package-up
ICON_ERROR=󰒑        # md-sync-alert
ICON_REBOOT=󰜉       # md-restart

# One directory per running module instance, because the adaptive launcher
# starts a separate bar - and therefore a separate daemon - per monitor.
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-system-update"
WORKDIR="$RUNDIR/inst-$$"
CACHEDIR="$RUNDIR/cache"
FIFO="$WORKDIR/ctl"

FAILURE=false
FAIL_REASON=""
PAC_UPD=0
AUR_UPD=0
PAC_RAW=""
AUR_RAW=""
LAST_TOTAL=-1
MODE=check
SPIN_I=0
CHILD=""

#--------------------------------------------------------------------
# helpers
#--------------------------------------------------------------------

cprintf() {
	case $1 in
		g) printf "\e[32m" ;;
		b) printf "\e[34m" ;;
		r) printf "\e[31m" ;;
	esac
	printf "%b\n" "${@:2}"
	printf "\e[39m"
}

get_helper() {
	local h
	for h in "${HELPERS[@]}"; do
		if command -v "$h" > /dev/null; then
			HELPER=$h
			break
		fi
	done
}

json_escape() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//$'\n'/\\n}
	s=${s//$'\t'/\\t}
	printf "%s" "$s"
}

pango_escape() {
	local s=$1
	s=${s//&/&amp;}
	s=${s//</&lt;}
	s=${s//>/&gt;}
	printf "%s" "$s"
}

# The running kernel's module tree disappears when the kernel package is
# upgraded, which is the cheapest reliable "reboot required" signal.
reboot_pending() {
	[[ ! -d /usr/lib/modules/$(uname -r) ]]
}

#--------------------------------------------------------------------
# control channel (daemon <-> clicks)
#--------------------------------------------------------------------

# Broadcasts a command to every running daemon (one per bar) and drops the
# leftovers of instances that are gone.
send_cmd() {
	local dir pid rc=1

	shopt -s nullglob

	for dir in "$RUNDIR"/inst-*; do
		pid=${dir##*/inst-}

		if [[ ! $pid =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2> /dev/null; then
			rm -rf "$dir"
			continue
		fi

		[[ -p $dir/ctl ]] || continue

		CTL_MSG=$1 timeout 1 bash -c 'printf "%s\n" "$CTL_MSG" > "$0"' "$dir/ctl" \
			&& rc=0
	done

	return $rc
}

# Read one command from the control fifo, waiting at most $1 seconds.
# Returns 0 if a command was handled, 1 on timeout.
pump_cmd() {
	local cmd
	if read -r -t "$1" cmd <&3; then
		case $cmd in
			refresh)   MODE=check ;;
			upgrading) MODE=upgrading; UPGRADE_SINCE=$SECONDS ;;
			quit)      exit 0 ;;
		esac
		return 0
	fi
	return 1
}

#--------------------------------------------------------------------
# update check
#--------------------------------------------------------------------

cache_fresh() {
	[[ -f $CACHEDIR/stamp ]] || return 1
	(($(date +%s) - $(stat -c %Y "$CACHEDIR/stamp") < CACHE_TTL))
}

# Fetches both backends in parallel into $WORKDIR. Meant to be backgrounded.
#
# checkupdates keeps a single shared temporary database, so two bars checking
# at the same moment would make one of them fail. The lock serialises them and
# the short-lived cache means the second one does not refetch at all.
fetch_updates() {
	(
		flock 9

		if cache_fresh && cp "$CACHEDIR"/{pac,aur}.{raw,rc} "$WORKDIR/" 2> /dev/null; then
			: > "$WORKDIR/fromcache"
			exit 0
		fi

		{
			timeout "$TIMEOUT" checkupdates > "$WORKDIR/pac.raw" 2> /dev/null
			printf "%s" $? > "$WORKDIR/pac.rc"
		} &

		if [[ -n $HELPER ]]; then
			{
				timeout "$TIMEOUT" "$HELPER" -Qua > "$WORKDIR/aur.raw" 2> /dev/null
				printf "%s" $? > "$WORKDIR/aur.rc"
			} &
		fi

		wait

		mkdir -p "$CACHEDIR"
		cp "$WORKDIR"/{pac,aur}.{raw,rc} "$CACHEDIR/" 2> /dev/null
		: > "$CACHEDIR/stamp"
	) 9> "$RUNDIR/fetch.lock"
}

collect_results() {
	local rc

	FAILURE=false
	FAIL_REASON=""
	PAC_UPD=0
	AUR_UPD=0
	PAC_RAW=""
	AUR_RAW=""

	if ! command -v checkupdates > /dev/null; then
		FAILURE=true
		FAIL_REASON="checkupdates is missing (install pacman-contrib)"
		return 1
	fi

	rc=$(< "$WORKDIR/pac.rc")
	PAC_RAW=$(grep -ve "^\s*$" "$WORKDIR/pac.raw")

	# 0: updates listed, 2: nothing to do, anything else: could not fetch
	if ((rc != 0 && rc != 2)); then
		FAILURE=true
		FAIL_REASON=$( ((rc == 124)) \
			&& printf "Timed out while fetching official updates" \
			|| printf "Could not fetch official updates" )
		return 1
	fi

	[[ -n $PAC_RAW ]] && PAC_UPD=$(grep -c "" <<< "$PAC_RAW")

	[[ -z $HELPER ]] && return 0

	rc=$(< "$WORKDIR/aur.rc")
	AUR_RAW=$(grep -ve "^\s*$" "$WORKDIR/aur.raw")

	# AUR helpers exit non-zero when there is simply nothing to upgrade, so
	# only a timeout (or output we cannot trust) counts as a real failure.
	if ((rc == 124)); then
		FAILURE=true
		FAIL_REASON="Timed out while fetching AUR updates"
		return 1
	fi

	if ((rc != 0)) && [[ -n $AUR_RAW ]]; then
		FAILURE=true
		FAIL_REASON="Could not fetch AUR updates"
		return 1
	fi

	[[ -n $AUR_RAW ]] && AUR_UPD=$(grep -c "" <<< "$AUR_RAW")
	return 0
}

# Formats "name old -> new" lines into an indented, capped tooltip section.
fmt_pkgs() {
	local raw=$1 max=$2 n=0 out="" name old new

	while read -r name old _ new; do
		[[ -z $name ]] && continue
		((n++))
		((n > max)) && continue

		if [[ -n $new ]]; then
			out+=$'\n'"  $(pango_escape "$name")  <span alpha='55%'>$(pango_escape "$old") → $(pango_escape "$new")</span>"
		else
			out+=$'\n'"  $(pango_escape "$name")"
		fi
	done <<< "$raw"

	((n > max)) && out+=$'\n'"  <span alpha='55%'>…and $((n - max)) more</span>"

	printf "%s" "$out"
}

#--------------------------------------------------------------------
# waybar output
#--------------------------------------------------------------------

emit() {
	printf '{"text":"%s","alt":"%s","class":%s,"tooltip":"%s"}\n' \
		"$(json_escape "$1")" "$2" "$3" "$(json_escape "$4")"
}

emit_spinner() {
	local class=$1 tip=$2

	emit "${SPINNER[SPIN_I]}" "$class" "\"$class\"" "$tip"
	SPIN_I=$(((SPIN_I + 1) % ${#SPINNER[@]}))
}

emit_result() {
	local total=$((PAC_UPD + AUR_UPD)) tooltip icon alt classes reboot=false hint

	if $FAILURE; then
		tooltip="<b>Update check failed</b>"
		tooltip+=$'\n'"$(pango_escape "$FAIL_REASON")"
		tooltip+=$'\n'"<span alpha='55%'>Right-click to retry</span>"

		emit "$ICON_ERROR" error '"error"' "$tooltip"
		LAST_TOTAL=-1
		return
	fi

	reboot_pending && reboot=true

	if ((total == 0)); then
		icon=$ICON_OK
		alt=updated
		tooltip="<b>System is up to date</b>"
	else
		icon=$ICON_PENDING
		alt=pending
		tooltip="<b>$total update$( ((total != 1)) && printf s ) available</b>"
		tooltip+=$'\n'"<b>Official</b>  $PAC_UPD"
		tooltip+=$(fmt_pkgs "$PAC_RAW" "$TOOLTIP_MAX")

		if [[ -n $HELPER ]]; then
			tooltip+=$'\n'"<b>AUR ($HELPER)</b>  $AUR_UPD"
			tooltip+=$(fmt_pkgs "$AUR_RAW" "$TOOLTIP_MAX")
		fi
	fi

	if $reboot; then
		icon=$ICON_REBOOT
		tooltip+=$'\n'"<b>Reboot required</b>  <span alpha='55%'>(kernel was upgraded)</span>"
	fi

	hint="left-click upgrade"
	$reboot && hint="left-click reboot"

	tooltip+=$'\n'"<span alpha='55%'>Checked at $(date +%H:%M) · $hint · middle-click list · right-click refresh</span>"

	classes="\"$alt\""
	$reboot && classes="[\"$alt\",\"reboot\"]"

	emit "$icon" "$alt" "$classes" "$tooltip"

	# Only the instance that actually fetched notifies, so a second bar reading
	# the shared cache does not duplicate the popup.
	if $NOTIFY && [[ ! -f $WORKDIR/fromcache ]] \
		&& ((LAST_TOTAL >= 0 && total > LAST_TOTAL)) \
		&& command -v notify-send > /dev/null; then
		notify-send -i package-install "Updates available" \
			"$total package$( ((total != 1)) && printf s ) can be upgraded."
	fi

	LAST_TOTAL=$total
}

#--------------------------------------------------------------------
# daemon
#--------------------------------------------------------------------

cleanup() {
	[[ -n $CHILD ]] && kill "$CHILD" 2> /dev/null
	rm -rf "$WORKDIR"
}

start_daemon() {
	local dir pid

	mkdir -p "$WORKDIR"

	# Drop leftovers from instances that died without cleaning up.
	shopt -s nullglob
	for dir in "$RUNDIR"/inst-*; do
		pid=${dir##*/inst-}
		[[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2> /dev/null || rm -rf "$dir"
	done

	rm -f "$FIFO"
	mkfifo "$FIFO"

	# Held read-write so reads never see EOF and writers never block.
	exec 3<> "$FIFO"

	trap 'cleanup; exit 0' EXIT INT TERM HUP

	local wait_for

	while :; do
		if [[ $MODE == upgrading ]]; then
			UPGRADE_SINCE=${UPGRADE_SINCE:-$SECONDS}

			while [[ $MODE == upgrading ]]; do
				emit_spinner upgrading "<b>Upgrading packages…</b>"
				pump_cmd "$SPIN_DELAY"
				((SECONDS - UPGRADE_SINCE > UPGRADE_GUARD)) && MODE=check
			done

			continue
		fi

		MODE=idle
		SPIN_I=0
		reset_scratch

		fetch_updates &
		CHILD=$!

		while kill -0 "$CHILD" 2> /dev/null; do
			if [[ $MODE == upgrading ]]; then
				emit_spinner upgrading "<b>Upgrading packages…</b>"
			else
				emit_spinner checking "<b>Checking for updates…</b>"
			fi
			pump_cmd "$SPIN_DELAY"
		done

		wait "$CHILD"
		CHILD=""

		# An upgrade started mid-check: keep animating, the result is stale.
		[[ $MODE == upgrading ]] && continue

		collect_results
		emit_result

		wait_for=$INTERVAL
		$FAILURE && wait_for=$RETRY_INTERVAL

		pump_cmd "$wait_for"
		[[ $MODE == idle ]] && MODE=check
	done
}

#--------------------------------------------------------------------
# left click
#--------------------------------------------------------------------

# Once the kernel has been upgraded another "pacman -Syu" is a no-op, while a
# restart is the thing that is actually still pending - so the left click
# swaps roles instead of only recolouring the icon. It goes through a prompt
# because a stray click on the bar must not reboot the machine outright.
handle_click() {
	if reboot_pending; then
		exec "${POPUP_CMD[@]}" -e "$0" reboot-menu
	fi

	exec "${TERM_CMD[@]}" -e "$0" upgrade
}

reboot_menu() {
	local list=(
		"reboot"$'\t'"$ICON_REBOOT  Reboot now"
		"poweroff"$'\t'"󰐥  Shut down"
		"upgrade"$'\t'"$ICON_PENDING  Upgrade anyway"
		"cancel"$'\t'"󰜺  Cancel"
	)

	local options=(
		"--border=sharp"
		"--border-label= Reboot Required "
		"--height=~100%"
		"--highlight-line"
		"--no-input"
		"--pointer="
		"--reverse"
		"--delimiter=\t"
		"--with-nth=2.."
	)

	local selected
	selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}") || exit 0

	case ${selected%%$'\t'*} in
		reboot)   systemctl reboot ;;
		poweroff) systemctl poweroff ;;
		# The popup is a small floating window, so hand the upgrade its own
		# terminal and detach it before this one closes.
		upgrade)  setsid -f "${TERM_CMD[@]}" -e "$0" upgrade ;;
		*)        exit 0 ;;
	esac
}

#--------------------------------------------------------------------
# interactive
#--------------------------------------------------------------------

reset_scratch() {
	mkdir -p "$WORKDIR"
	rm -f "$WORKDIR/fromcache"
	printf 1 > "$WORKDIR/pac.rc"
	printf 0 > "$WORKDIR/aur.rc"
	: > "$WORKDIR/pac.raw"
	: > "$WORKDIR/aur.raw"
}

list_updates() {
	# Not a daemon, so keep the scratch out of the inst-* namespace.
	WORKDIR="$RUNDIR/once-$$"

	get_helper
	cprintf b "Checking for updates..."

	reset_scratch
	fetch_updates
	collect_results
	rm -rf "$WORKDIR"

	if $FAILURE; then
		cprintf r "$FAIL_REASON"
	else
		cprintf b "\nOfficial ($PAC_UPD)"
		printf "%s\n" "${PAC_RAW:-  none}"

		if [[ -n $HELPER ]]; then
			cprintf b "\nAUR/$HELPER ($AUR_UPD)"
			printf "%s\n" "${AUR_RAW:-  none}"
		fi

		if reboot_pending; then
			cprintf b "\nThe kernel was upgraded - a reboot is recommended."
		fi
	fi

	printf "\n"
	read -rsn 1 -p "Press any key to exit..."
}

update_packages() {
	trap 'send_cmd refresh' EXIT

	send_cmd upgrading

	cprintf b "Updating pacman packages..."
	sudo pacman -Syu

	if [[ -n $HELPER ]]; then
		cprintf b "\nUpdating AUR packages..."
		command "$HELPER" -Syu
	fi

	notify-send "Update Complete" -i "package-install"

	cprintf g "\nUpdate Complete!"

	if reboot_pending; then
		cprintf b "The kernel was upgraded - a reboot is recommended."
	fi

	read -rsn 1 -p "Press any key to exit..."
}

#--------------------------------------------------------------------

usage() {
	cat << EOF
Usage: ${0##*/} [module|refresh|list|upgrade|click|reboot-menu]

  (no argument)  upgrade the system interactively
  upgrade        same as above
  module         run the Waybar daemon (JSON lines on stdout)
  refresh        tell the running daemon to check for updates now
  list           show the pending updates and exit
  click          Waybar left click: upgrade, or prompt to reboot when a
                 kernel upgrade has made a restart necessary
  reboot-menu    show that reboot prompt (run inside a terminal)
EOF
}

main() {
	case $1 in
		"module")
			get_helper
			start_daemon
			;;
		"refresh")
			send_cmd refresh || exit 0
			;;
		"list")
			list_updates
			;;
		"click")
			handle_click
			;;
		"reboot-menu")
			reboot_menu
			;;
		"" | "upgrade")
			get_helper
			update_packages
			;;
		*)
			usage
			exit 1
			;;
	esac
}

main "${1:-}"

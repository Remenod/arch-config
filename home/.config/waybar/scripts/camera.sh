#!/usr/bin/env bash
set -euo pipefail

MSI_EC_BASE="${MSI_EC_BASE:-/sys/devices/platform/msi-ec}"
WEBCAM_FILE="$MSI_EC_BASE/webcam"
BLOCK_FILE="$MSI_EC_BASE/webcam_block"
ICON_ON="󱦿"
ICON_OFF="󰵝"
ICON_LOCK="󱨕"

json_escape() {
	local value="$1"
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	value=${value//$'\n'/\\n}
	printf "%s" "$value"
}

read_value() {
	local file="$1"

	if [[ -r $file ]]; then
		cat "$file"
	else
		printf "unknown"
	fi
}

camera_state() {
	local webcam="$1"

	case $webcam in
		on)  printf "off" ;;
		off) printf "on" ;;
		*)   printf "unknown" ;;
	esac
}

lock_state() {
	local block="$1"

	case $block in
		on)  printf "locked" ;;
		off) printf "unlocked" ;;
		*)   printf "unknown" ;;
	esac
}

write_value() {
	local file="$1"
	local value="$2"

	if [[ -w $file ]]; then
		printf "%s\n" "$value" > "$file"
	elif sudo -n true >/dev/null 2>&1; then
		printf "%s\n" "$value" | sudo -n tee "$file" >/dev/null
	else
		notify-send "Camera" "No write access to MSI EC controls" -i camera-web \
			-h string:x-canonical-private-synchronous:camera
		return 1
	fi
}

module() {
	local webcam block camera lock text class tooltip

	webcam=$(read_value "$WEBCAM_FILE")
	block=$(read_value "$BLOCK_FILE")
	camera=$(camera_state "$webcam")
	lock=$(lock_state "$block")

	case $lock:$camera in
		locked:*)
			text="$ICON_LOCK"
			class="blocked"
			;;
		*:on)
			text="$ICON_ON"
			class="on"
			;;
		*:off)
			text="$ICON_OFF"
			class="off"
			;;
		*)
			text="$ICON_OFF"
			class="missing"
			;;
	esac

	printf -v tooltip "Camera: %s\nLock: %s" "$camera" "$lock"
	printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' \
		"$(json_escape "$text")" \
		"$(json_escape "$class")" \
		"$(json_escape "$tooltip")"
}

toggle_camera() {
	local webcam block next

	if [[ ! -e $WEBCAM_FILE ]]; then
		notify-send "Camera" "MSI EC webcam control is unavailable" -i camera-web \
			-h string:x-canonical-private-synchronous:camera
		return 1
	fi

	block=$(read_value "$BLOCK_FILE")
	if [[ $block == on ]]; then
		notify-send "Camera" "Webcam is locked" -i camera-disabled \
			-h string:x-canonical-private-synchronous:camera
		return 1
	fi

	webcam=$(read_value "$WEBCAM_FILE")
	case $webcam in
		on)  next=off ;;
		*)   next=on ;;
	esac

	write_value "$WEBCAM_FILE" "$next"
	notify-send "Camera" "$(camera_state "$next")" -i camera-web \
		-h string:x-canonical-private-synchronous:camera
}

toggle_block() {
	local block next

	if [[ ! -e $BLOCK_FILE ]]; then
		notify-send "Camera" "MSI EC webcam block control is unavailable" -i camera-web \
			-h string:x-canonical-private-synchronous:camera
		return 1
	fi

	block=$(read_value "$BLOCK_FILE")
	case $block in
		on)  next=off ;;
		*)   next=on ;;
	esac

	write_value "$BLOCK_FILE" "$next"
	notify-send "Camera lock" "$next" -i camera-web \
		-h string:x-canonical-private-synchronous:camera
}

case ${1:-module} in
	module)       module ;;
	toggle)       toggle_camera ;;
	block-toggle) toggle_block ;;
	*)            printf 'usage: %s [module|toggle|block-toggle]\n' "${0##*/}" >&2; exit 1 ;;
esac

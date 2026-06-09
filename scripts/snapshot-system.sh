#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

copy_system() {
  local src="$1"
  local dst="$repo/system$src"

  if [[ ! -e "$src" ]]; then
    printf 'skip missing system file: %s\n' "$src" >&2
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  printf 'snapshotted %s\n' "$src"
}

system_files=(
  /etc/pacman.conf
  /etc/pacman.d/mirrorlist
  /etc/mkinitcpio.conf
  /etc/modprobe.d/isw-ec_sys.conf
  /etc/sysctl.d/99-zram.conf
  /etc/udev/rules.d/99-sayodevice.rules
  /etc/systemd/system/tty1-btm.service
  /etc/myvtcolors.txt
)

for src in "${system_files[@]}"; do
  copy_system "$src"
done

mkdir -p "$repo/packages" "$repo/system"
pacman -Qqe > "$repo/packages/pacman-explicit-all.txt"
pacman -Qqen > "$repo/packages/pacman-explicit-native.txt"
pacman -Qqem > "$repo/packages/pacman-explicit-foreign.txt"
systemctl list-unit-files --state=enabled --no-pager > "$repo/system/enabled-system-units.txt"
systemctl --user list-unit-files --state=enabled --no-pager > "$repo/system/enabled-user-units.txt"

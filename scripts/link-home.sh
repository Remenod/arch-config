#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home="${HOME:?}"

paths=(
  ".gitconfig"
  ".nanorc"
  ".zshrc"
  ".nano"
  ".config/code-flags.conf"
  ".config/mimeapps.list"
  ".config/gh/config.yml"
  ".config/alacritty"
  ".config/bottom"
  ".config/fastfetch"
  ".config/gtk-3.0"
  ".config/hypr"
  ".config/mako"
  ".config/mpv"
  ".config/waybar"
  ".config/yay"
  ".config/OpenRGB/OpenRGB.json"
  ".config/Code/User/settings.json"
  ".config/Code/User/keybindings.json"
  ".config/Code/User/chatLanguageModels.json"
  ".config/Code/User/mcp.json"
  ".local/bin"
  ".local/share/applications"
  ".local/share/backgrounds"
)

link_one() {
  local rel="$1"
  local src="$repo/home/$rel"
  local dst="$home/$rel"

  if [[ ! -e "$src" ]]; then
    printf 'skip missing source: %s\n' "$src" >&2
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    local backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$backup"
    printf 'backed up %s -> %s\n' "$dst" "$backup"
  fi

  local target
  target="$(realpath --relative-to="$(dirname "$dst")" "$src")"
  ln -s "$target" "$dst"
  printf 'linked %s -> %s\n' "$dst" "$target"
}

for rel in "${paths[@]}"; do
  link_one "$rel"
done

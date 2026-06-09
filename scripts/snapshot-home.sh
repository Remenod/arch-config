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

adopted=0
skipped=0

add_gitkeep_to_empty_dirs() {
  local dir

  while IFS= read -r -d '' dir; do
    touch "$dir/.gitkeep"
    printf 'kept empty directory: %s\n' "$dir"
  done < <(find "$repo/home" -type d -empty -print0)
}

adopt_one() {
  local rel="$1"
  local src="$home/$rel"
  local dst="$repo/home/$rel"

  if [[ -L "$src" ]]; then
    local resolved
    resolved="$(readlink -f "$src" || true)"
    if [[ "$resolved" == "$repo/home/"* ]]; then
      printf 'already linked: %s\n' "$src"
      skipped=$((skipped + 1))
      return 0
    fi
  fi

  if [[ ! -e "$src" ]]; then
    printf 'skip missing home path: %s\n' "$src"
    skipped=$((skipped + 1))
    return 0
  fi

  if [[ -e "$dst" ]]; then
    printf 'skip existing snapshot: %s\n' "$dst"
    skipped=$((skipped + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  mv "$src" "$dst"

  local target
  target="$(realpath --relative-to="$(dirname "$src")" "$dst")"
  ln -s "$target" "$src"
  printf 'adopted %s -> %s\n' "$src" "$target"
  adopted=$((adopted + 1))
}

mkdir -p "$repo/home"

for rel in "${paths[@]}"; do
  adopt_one "$rel"
done

add_gitkeep_to_empty_dirs

printf '\nadopted: %s, skipped: %s\n' "$adopted" "$skipped"
printf 'review with: git status --short --ignored\n'

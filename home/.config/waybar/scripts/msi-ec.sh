#!/usr/bin/env bash
set -euo pipefail

shared_script="${XDG_CONFIG_HOME:-$HOME/.config}/shared/scripts/msi-ec.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    exec "$shared_script" "$@"
fi

# Compatibility wrapper for older Waybar scripts that source this path.
# shellcheck source=../../shared/scripts/msi-ec.sh
source "$shared_script"

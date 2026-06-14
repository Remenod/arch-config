#!/usr/bin/env bash
set -euo pipefail

shared_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shared/scripts"
# shellcheck source=../../shared/scripts/msi-ec.sh
source "$shared_dir/msi-ec.sh"

msi_ec_fan_json

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=msi-ec.sh
source "$script_dir/msi-ec.sh"

msi_ec_fan_json

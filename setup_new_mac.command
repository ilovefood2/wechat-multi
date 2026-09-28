#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib/common.sh"

load_config

echo
echo "===================================================="
echo "     WeChat 2 — New Mac / New iPhone Setup"
echo "===================================================="
echo

require_xcode
ensure_bootstrap_project
pick_device
prepare_team_interactively_if_needed
build_bootstrap_profile
find_signing_identity

echo
echo "✅ Apple signing/provisioning is ready."
echo
echo "Put your authorized cryptid-0 WeChat IPA at:"
echo "  $IPA"
echo
echo "Then run install_wechat2.command or choose option 2 in the Manager."

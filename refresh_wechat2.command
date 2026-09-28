#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
echo
echo "Rebuilding provisioning, re-signing, and reinstalling WeChat 2..."
exec "$DIR/install_wechat2.command"

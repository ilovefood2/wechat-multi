#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo "WeChat 2 Deployment Kit — New Mac Edition"
echo
echo "  1) New Mac / new iPhone setup"
echo "  2) Sign + install WeChat 2"
echo "  3) Refresh / re-sign WeChat 2 now"
echo "  4) Uninstall WeChat 2"
echo "  5) Install smart auto-refresh schedule"
echo "  6) Uninstall smart auto-refresh schedule"
echo "  7) Smart auto-refresh status"
echo "  8) Open README"
echo "  0) Exit"
echo
read -r -p "Choose: " c

case "$c" in
  1) exec "$DIR/setup_new_mac.command" ;;
  2) exec "$DIR/install_wechat2.command" ;;
  3) exec "$DIR/refresh_wechat2.command" ;;
  4) exec "$DIR/uninstall_wechat2.command" ;;
  5) exec /bin/bash "$DIR/setup_wechat2_smart_autorefresh.sh" install ;;
  6) exec /bin/bash "$DIR/setup_wechat2_smart_autorefresh.sh" uninstall ;;
  7) exec /bin/bash "$DIR/setup_wechat2_smart_autorefresh.sh" status ;;
  8) open "$DIR/README.md" ;;
  0) exit 0 ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

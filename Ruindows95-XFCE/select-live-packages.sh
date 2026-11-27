#!/usr/bin/env bash
set -euo pipefail
# All packages stay in packages.txt for the installed system.
# Live installer only: omit heavy end-user apps and print services by default.
case ${RUINDOWS_FULL_LIVE:-0} in
  0) sed 's/^linux-lts$/linux/' "$1" | grep -vEx 'firefox|vlc|vlc-plugins-extra|gnome-disk-utility|system-config-printer|cups|cups-pk-helper' ;;
  1) sed 's/^linux-lts$/linux/' "$1" ;;
  *) echo 'RUINDOWS_FULL_LIVE deve ser 0 ou 1.' >&2; exit 1 ;;
esac

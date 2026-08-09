#!/usr/bin/env bash
# Mark a request in your own inbox as handled: moves it into inbox/handled/ on the
# shared folder. This is the one recurring manual step the protocol asks for — run it
# once you've done (and replied to) a request. See docs/PROTOCOL.md, rule 2.
#
#   ./scripts/handle.sh 2026-08-09-from-desktop-compile.md
#   ./scripts/handle.sh --list        # show unhandled requests in your inbox
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"
[ -f "$CONFIG" ] || { echo "ERROR: no config.env (copy config.example.env)"; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"
: "${RCLONE_REMOTE:?set RCLONE_REMOTE}"; : "${COORD_DIR:?set COORD_DIR}"; : "${MACHINE_NAME:?set MACHINE_NAME}"
INBOX="${RCLONE_REMOTE}${COORD_DIR}/${MACHINE_NAME}/inbox"

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
  echo "Unhandled requests in ${MACHINE_NAME}/inbox:"
  rclone lsf "$INBOX" 2>/dev/null | grep -v '/$' | grep -v '^\.keep' || echo "  (none)"
  [ -z "${1:-}" ] && { echo; echo "Usage: handle.sh <request-filename>   (or --list)"; exit 0; }
  exit 0
fi

FILE="$1"
if ! rclone lsf "$INBOX/" 2>/dev/null | grep -qx "$FILE"; then
  echo "ERROR: '$FILE' is not at the top level of your inbox. Try: handle.sh --list" >&2
  exit 1
fi
rclone mkdir "$INBOX/handled" 2>/dev/null || true
rclone moveto "$INBOX/$FILE" "$INBOX/handled/$FILE" || { echo "ERROR: move failed" >&2; exit 1; }
echo "Moved to handled/: $FILE"

#!/usr/bin/env bash
# What is waiting for this machine, and what the fleet can do — read from what the last
# sync already pulled. Touches nothing and needs no network.
#
# Exit codes:  0 = nothing waiting   10 = something is waiting   1 = error
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"
[ -f "$CONFIG" ] || { echo "ERROR: no config.env (copy config.example.env)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"
: "${MACHINE_NAME:?set MACHINE_NAME}"; : "${LOCAL_ROOT:?set LOCAL_ROOT}"

waiting=0

echo "Machine: $MACHINE_NAME"

last_sync="never"
[ -f "$LOCAL_ROOT/state/inbox.state" ] \
  && last_sync=$(date -r "$LOCAL_ROOT/state/inbox.state" '+%Y-%m-%d %H:%M')
echo "Last sync: $last_sync"
echo

echo "Inbox"
pending=$(find "$LOCAL_ROOT/inbox" -maxdepth 1 -type f ! -name '.keep*' -printf '%f\t%s\n' 2>/dev/null | sort || true)
if [ -n "$pending" ]; then
  waiting=1
  while IFS=$'\t' read -r name size; do
    [ -n "$name" ] && printf '  • %s (%s bytes)\n' "$name" "$size"
  done <<< "$pending"
  echo "  Read one:  cat $LOCAL_ROOT/inbox/<name>"
  echo "  Finish it: ./scripts/handle.sh <name>"
else
  echo "  (nothing unhandled)"
fi
echo

if [ -f "$LOCAL_ROOT/PROTOCOL-CHANGES.md" ]; then
  current=$(sha256sum "$LOCAL_ROOT/PROTOCOL-CHANGES.md" | cut -d' ' -f1)
  acked=$(cat "$LOCAL_ROOT/state/protocol.ack" 2>/dev/null || true)
  if [ "$current" != "$acked" ]; then
    waiting=1
    echo "⚠ The protocol changed — read $LOCAL_ROOT/PROTOCOL-CHANGES.md"
    echo
  fi
fi

echo "Fleet"
if [ -z "${FLEET:-}" ]; then
  echo "  (FLEET is empty in config.env)"
else
  for m in $FLEET; do
    descriptor="$LOCAL_ROOT/fleet/$m/capabilities.md"
    if [ -f "$descriptor" ]; then
      printf '  • %-14s knows: %s\n' "$m" "$(date -r "$descriptor" '+%Y-%m-%d %H:%M')"
    else
      printf '  • %-14s no capabilities pulled yet\n' "$m"
    fi
  done
  echo "  What can one do?  cat $LOCAL_ROOT/fleet/<machine>/capabilities.md"
  echo "  Ask one for help: ./scripts/send.sh --to <machine> --topic … --want … --done … --until …"
fi

[ "$waiting" -eq 1 ] && exit 10
exit 0

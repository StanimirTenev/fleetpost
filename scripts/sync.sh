#!/usr/bin/env bash
# One coordination cycle for this machine. Run it on a timer (see examples/).
# It does exactly four things and NOTHING that changes another machine's data:
#   1. pull THIS machine's inbox from the shared folder
#   2. detect new requests + protocol changes -> raise a local SIGNAL.md flag
#   3. pull the capabilities descriptor of every other machine in the fleet
#   4. publish THIS machine's descriptors, but only when they actually changed
#
# It NEVER executes a request. It only fetches and flags; a human/agent session
# does the work later. Anti-collision rule: read only your own inbox, write only
# into others' inboxes (to drop a request), and tidy only your own inbox.
#
# Exit codes:  0 = quiet   10 = something new for you   1 = error
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"
[ -f "$CONFIG" ] || { echo "ERROR: no config.env (copy config.example.env)"; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"

: "${RCLONE_REMOTE:?set RCLONE_REMOTE in config.env}"
: "${COORD_DIR:?set COORD_DIR}"
: "${MACHINE_NAME:?set MACHINE_NAME}"
: "${LOCAL_ROOT:?set LOCAL_ROOT}"
REMOTE="${RCLONE_REMOTE}${COORD_DIR}"
STATE="$LOCAL_ROOT/state"
mkdir -p "$STATE" "$LOCAL_ROOT/inbox" "$LOCAL_ROOT/fleet" "$LOCAL_ROOT/self"

LOG() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── 1. pull my inbox ─────────────────────────────────────────────────────────
# `sync` (not copy) so requests I've moved to handled/ disappear locally too.
# Direction is remote->local, so nothing on the remote is ever deleted.
# First ensure my inbox exists on the remote — on a brand-new machine it doesn't
# yet, and without this the pull below would fail on the very first run.
LOG "1/4 pulling ${MACHINE_NAME}/inbox …"
rclone mkdir "$REMOTE/$MACHINE_NAME/inbox" 2>/dev/null || true
rclone sync "$REMOTE/$MACHINE_NAME/inbox" "$LOCAL_ROOT/inbox" \
  --exclude "handled/**" 2>/dev/null || fail "cannot pull my inbox"

# ── 2. detect new requests (key = name:size) and protocol changes ────────────
LOG "2/4 detecting new requests and protocol changes …"
new_state=$(cd "$LOCAL_ROOT/inbox" && find . -maxdepth 1 -type f ! -name '.keep*' \
              -printf '%f:%s\n' 2>/dev/null | sort)
old_state=$(cat "$STATE/inbox.state" 2>/dev/null || true)
fresh=$(comm -13 <(printf '%s\n' "$old_state") <(printf '%s\n' "$new_state") | sed '/^$/d' || true)

# watch the shared changelog by hash
proto_changed=0; ph=""
if rclone copy "$REMOTE/PROTOCOL-CHANGES.md" "$LOCAL_ROOT/" 2>/dev/null; then
  ph=$(sha256sum "$LOCAL_ROOT/PROTOCOL-CHANGES.md" | cut -d' ' -f1)
  oph=$(cat "$STATE/protocol.hash" 2>/dev/null || true)
  [ "$ph" != "$oph" ] && proto_changed=1
fi

has_new=0
if [ -n "$fresh" ] || [ "$proto_changed" -eq 1 ]; then
  has_new=1
  {
    echo "# SIGNAL — something is waiting for you"
    echo
    echo "Detected: $(date '+%Y-%m-%d %H:%M'). This file is a flag, not a task — delete it once you act."
    echo
    if [ -n "$fresh" ]; then
      echo "## New requests in your inbox (\`$LOCAL_ROOT/inbox/\`)"
      while IFS=: read -r name size; do
        [ -n "$name" ] && echo "- \`$name\` ($size bytes)"
      done <<< "$fresh"
      echo
    fi
    if [ "$proto_changed" -eq 1 ]; then
      echo "## ⚠ The protocol changed"
      echo "Read \`$LOCAL_ROOT/PROTOCOL-CHANGES.md\` — the working rules were updated."
    fi
  } > "$LOCAL_ROOT/SIGNAL.md"
  msg=""; [ -n "$fresh" ] && msg="new requests"
  [ "$proto_changed" -eq 1 ] && msg="${msg:+$msg + }protocol change"
  LOG "    -> $msg; raised SIGNAL.md"
  if command -v notify-send >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    notify-send "Agent coordination" "$msg" 2>/dev/null || true
  fi
else
  LOG "    -> nothing new, protocol unchanged"
fi
printf '%s\n' "$new_state" > "$STATE/inbox.state"
[ "$proto_changed" -eq 1 ] && printf '%s\n' "$ph" > "$STATE/protocol.hash"

# ── 3. pull the fleet's capabilities ─────────────────────────────────────────
LOG "3/4 pulling fleet capabilities …"
for m in ${FLEET:-}; do
  if rclone lsf "$REMOTE/$m/" 2>/dev/null | grep -qx 'capabilities.md'; then
    rclone copy "$REMOTE/$m/capabilities.md" "$LOCAL_ROOT/fleet/$m" 2>/dev/null \
      || fail "cannot pull $m/capabilities.md"
    LOG "    -> $m: fetched"
  else
    LOG "    -> $m: no capabilities.md yet (skipping — normal)"
  fi
done

# ── 4. publish my descriptors, only when changed ─────────────────────────────
LOG "4/4 publishing my descriptors (only if changed) …"
# inventory.md: generated from MEMORY_DIR if set, else a hand-written file staged in self/
if [ -n "${MEMORY_DIR:-}" ]; then
  "$HERE/scripts/generate-inventory.sh" "$LOCAL_ROOT/self/inventory.md" \
    || fail "inventory generator failed"
fi

publish_if_changed() {  # $1 = local file, $2 = hash-state file
  local f="$1" hf="$2" nh oh
  [ -f "$f" ] || return 0
  nh=$(sha256sum "$f" | cut -d' ' -f1)
  oh=$(cat "$hf" 2>/dev/null || true)
  if [ "$nh" != "$oh" ]; then
    rclone copy "$f" "$REMOTE/$MACHINE_NAME/" 2>/dev/null || fail "cannot publish $(basename "$f")"
    echo "$nh" > "$hf"
    LOG "    -> $(basename "$f"): changed, published"
  else
    LOG "    -> $(basename "$f"): unchanged, skipped"
  fi
}
publish_if_changed "$LOCAL_ROOT/self/inventory.md"    "$STATE/inventory.hash"
publish_if_changed "$LOCAL_ROOT/self/capabilities.md" "$STATE/capabilities.hash"

LOG "done."
[ "$has_new" -eq 1 ] && exit 10
exit 0

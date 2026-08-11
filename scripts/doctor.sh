#!/usr/bin/env bash
# Check that this machine is wired up correctly, before you wonder why nothing arrives.
# Reads config.env, verifies the remote is reachable and the folder layout is right, and
# tells you what to fix. Changes nothing.
#
# Exit codes:  0 = healthy   1 = something needs fixing
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"

problems=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; problems=$((problems + 1)); }

echo "Fleetpost doctor"
echo

echo "config"
if [ -f "$CONFIG" ]; then
  ok "config.env found: $CONFIG"
  # shellcheck disable=SC1090
  . "$CONFIG"
else
  bad "no config.env at $CONFIG — copy config.example.env and edit it"
  echo; echo "$problems problem(s)."; exit 1
fi

for var in RCLONE_REMOTE COORD_DIR MACHINE_NAME LOCAL_ROOT; do
  if [ -n "${!var:-}" ]; then ok "$var is set"; else bad "$var is empty in config.env"; fi
done
[ -n "${FLEET:-}" ] || warn "FLEET is empty — this machine won't pull anyone else's capabilities"
[ "$problems" -eq 0 ] || { echo; echo "$problems problem(s)."; exit 1; }

REMOTE="${RCLONE_REMOTE}${COORD_DIR}"

echo
echo "tooling"
if command -v rclone >/dev/null 2>&1; then
  ok "rclone: $(rclone version 2>/dev/null | head -1)"
else
  bad "rclone is not installed — see https://rclone.org/install/"
  echo; echo "$problems problem(s)."; exit 1
fi

echo
echo "remote"
if rclone lsf "$REMOTE/" >/dev/null 2>&1; then
  ok "coordination folder reachable: $REMOTE"
else
  bad "cannot reach $REMOTE — check RCLONE_REMOTE/COORD_DIR and 'rclone listremotes'"
fi

if rclone lsf "$REMOTE/$MACHINE_NAME/" >/dev/null 2>&1; then
  ok "this machine has a folder: $MACHINE_NAME/"
  rclone lsf "$REMOTE/$MACHINE_NAME/" 2>/dev/null | grep -qx 'inbox/' \
    && ok "$MACHINE_NAME/inbox/ exists" \
    || warn "$MACHINE_NAME/inbox/ missing — the first sync creates it"
else
  warn "no folder for '$MACHINE_NAME' yet — the first sync creates it"
fi

for m in ${FLEET:-}; do
  if rclone lsf "$REMOTE/$m/" >/dev/null 2>&1; then
    rclone lsf "$REMOTE/$m/" 2>/dev/null | grep -qx 'capabilities.md' \
      && ok "$m: published capabilities" \
      || warn "$m: no capabilities.md yet — that node hasn't run its sync"
  else
    warn "$m: no folder on the remote yet"
  fi
done

echo
echo "local"
if mkdir -p "$LOCAL_ROOT" 2>/dev/null && [ -w "$LOCAL_ROOT" ]; then
  ok "LOCAL_ROOT writable: $LOCAL_ROOT"
else
  bad "LOCAL_ROOT not writable: $LOCAL_ROOT"
fi

if [ -f "$LOCAL_ROOT/self/capabilities.md" ]; then
  ok "capabilities.md staged for publishing"
else
  bad "no $LOCAL_ROOT/self/capabilities.md — copy templates/capabilities.template.md there and edit it,
    otherwise the fleet cannot see what this machine can do"
fi

if [ -n "${MEMORY_DIR:-}" ] && [ ! -d "$MEMORY_DIR" ]; then
  bad "MEMORY_DIR is set but missing: $MEMORY_DIR"
fi

# A clock behind the remote makes "newest file" reasoning and expiry dates wrong, and it is
# a common symptom on a machine that has been suspended for a long time.
newest=$(rclone lsl "$REMOTE/" --max-depth 3 2>/dev/null \
         | awk '{print $2" "$3}' | sort | tail -1 || true)
if [ -n "$newest" ]; then
  remote_epoch=$(date -d "${newest%.*}" +%s 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ "$remote_epoch" -gt 0 ] && [ "$((remote_epoch - now))" -gt 300 ]; then
    bad "this machine's clock looks behind: newest remote file is dated after 'now'"
  else
    ok "clock is consistent with the remote"
  fi
fi

echo
if [ "$problems" -eq 0 ]; then
  echo "Healthy. Run scripts/sync.sh to fetch and publish."
else
  echo "$problems problem(s) to fix."
fi
exit $([ "$problems" -eq 0 ] && echo 0 || echo 1)

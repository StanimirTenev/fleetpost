#!/usr/bin/env bash
# Show waiting fleet work at the top of an agent session.
#
# An established agent never re-reads the onboarding doc and has no reason to look in a
# folder it was not told about, so a request can sit unnoticed until someone remembers to
# check. This closes that gap: whatever the last sync flagged is put in front of the agent
# the moment a session starts.
#
# Wire it into Claude Code (~/.claude/settings.json):
#
#   { "hooks": { "SessionStart": [ { "hooks": [
#       { "type": "command",
#         "command": "CONFIG=/path/to/fleetpost/config.env /path/to/fleetpost/examples/hooks/session-start.sh" }
#   ] } ] } }
#
# Any other agent runner works the same way — it is a plain script that prints to stdout.
#
# By default it reads only local files: no network, no delay at session start. Set
# FLEETPOST_HOOK_SYNC=1 to run a full cycle first, which is the right choice on a machine
# with no scheduler (a laptop that is usually asleep).
#
# It must never break a session, so every failure path ends in exit 0.
set -uo pipefail
export PATH="/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"
[ -f "$CONFIG" ] || exit 0
# shellcheck disable=SC1090
. "$CONFIG" 2>/dev/null || exit 0
[ -n "${LOCAL_ROOT:-}" ] || exit 0

if [ "${FLEETPOST_HOOK_SYNC:-0}" = "1" ] && [ -x "$HERE/scripts/sync.sh" ]; then
  CONFIG="$CONFIG" timeout 120 bash "$HERE/scripts/sync.sh" >/dev/null 2>&1 || true
fi

SIGNAL="$LOCAL_ROOT/SIGNAL.md"
[ -f "$SIGNAL" ] || exit 0   # nothing waiting: say nothing at all

echo "───────────────────────────────────────────────"
cat "$SIGNAL" 2>/dev/null
echo
echo "Handle one with:  $HERE/scripts/handle.sh <filename>"

# A flag that predates the last cycle by a lot usually means the scheduler stopped, and a
# stale inbox is worse than an empty one because it looks authoritative.
state="$LOCAL_ROOT/state/inbox.state"
if [ -f "$state" ]; then
  age=$(( ( $(date +%s) - $(date -r "$state" +%s 2>/dev/null || date +%s) ) / 3600 ))
  [ "$age" -ge 3 ] && echo "⚠ Last sync was ${age}h ago — is the timer still running?"
fi
echo "───────────────────────────────────────────────"
exit 0

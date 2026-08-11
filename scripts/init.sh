#!/usr/bin/env bash
# Set this machine up as a node: write config.env, create the local working directory,
# stage a capabilities descriptor, and claim this machine's folder on the remote.
#
# Interactive:
#   ./scripts/init.sh
# Non-interactive (also how the tests drive it):
#   ./scripts/init.sh --remote gdrive: --coord-dir agent-coordination \
#                     --machine laptop --fleet "desktop server" [--local-root ~/.agent-coordination]
#
# Refuses to overwrite an existing config.env unless --force. Installs no scheduler:
# it prints the one command for that, so nothing lands on your system unasked.
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"

REMOTE=""; COORD=""; MACHINE=""; FLEET_IN=""; ROOT=""; FORCE=0; INTERACTIVE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --remote)     REMOTE="${2:-}"; INTERACTIVE=0; shift 2 ;;
    --coord-dir)  COORD="${2:-}"; INTERACTIVE=0; shift 2 ;;
    --machine)    MACHINE="${2:-}"; INTERACTIVE=0; shift 2 ;;
    --fleet)      FLEET_IN="${2:-}"; INTERACTIVE=0; shift 2 ;;
    --local-root) ROOT="${2:-}"; INTERACTIVE=0; shift 2 ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

if [ -f "$CONFIG" ] && [ "$FORCE" -eq 0 ]; then
  echo "ERROR: $CONFIG already exists. Edit it, or re-run with --force to replace it." >&2
  exit 1
fi

ask() {  # $1 = prompt, $2 = default -> echoes the answer
  local prompt="$1" default="${2:-}" answer
  if [ -n "$default" ]; then read -r -p "$prompt [$default]: " answer; else read -r -p "$prompt: " answer; fi
  printf '%s' "${answer:-$default}"
}

if [ "$INTERACTIVE" -eq 1 ]; then
  echo "Fleetpost setup — four questions."
  echo
  if command -v rclone >/dev/null 2>&1; then
    remotes=$(rclone listremotes 2>/dev/null | tr '\n' ' ')
    [ -n "$remotes" ] && echo "Your rclone remotes: $remotes"
  fi
  REMOTE=$(ask "rclone remote holding the shared folder (e.g. gdrive:)")
  COORD=$(ask "Path of the coordination folder inside it" "agent-coordination")
  MACHINE=$(ask "This machine's node name" "$(hostname -s 2>/dev/null || echo laptop)")
  FLEET_IN=$(ask "Other machines, space-separated (leave empty for now)")
  ROOT=$(ask "Local working directory" "$HOME/.agent-coordination")
  echo
fi

: "${REMOTE:?--remote is required}"
: "${MACHINE:?--machine is required}"
COORD="${COORD:-agent-coordination}"
ROOT="${ROOT:-$HOME/.agent-coordination}"
ROOT="${ROOT/#\~/$HOME}"

command -v rclone >/dev/null 2>&1 || { echo "ERROR: rclone is not installed — https://rclone.org/install/" >&2; exit 1; }

cat > "$CONFIG" <<EOF
# Written by scripts/init.sh on $(date '+%Y-%m-%d'). Edit freely; it is git-ignored.
RCLONE_REMOTE="$REMOTE"
COORD_DIR="$COORD"
MACHINE_NAME="$MACHINE"
FLEET="$FLEET_IN"
LOCAL_ROOT="$ROOT"
MEMORY_DIR=""
TIMER_MINUTE="$(( RANDOM % 60 ))"
EOF
echo "✓ wrote $CONFIG"

mkdir -p "$ROOT/self" "$ROOT/inbox" "$ROOT/fleet" "$ROOT/state"
echo "✓ created $ROOT"

if [ ! -f "$ROOT/self/capabilities.md" ]; then
  sed "s/<machine-name>/$MACHINE/g" "$HERE/templates/capabilities.template.md" \
    > "$ROOT/self/capabilities.md" 2>/dev/null \
    || cp "$HERE/templates/capabilities.template.md" "$ROOT/self/capabilities.md"
  echo "✓ staged $ROOT/self/capabilities.md — EDIT IT, it is what the fleet sees"
else
  echo "· $ROOT/self/capabilities.md already exists, left alone"
fi

REMOTE_ROOT="${REMOTE}${COORD}"
if rclone mkdir "$REMOTE_ROOT/$MACHINE/inbox" 2>/dev/null; then
  echo "✓ claimed $REMOTE_ROOT/$MACHINE/inbox"
else
  echo "! could not create $REMOTE_ROOT/$MACHINE/inbox — check the remote name; sync.sh retries this"
fi

echo
echo "Next:"
echo "  1. Edit $ROOT/self/capabilities.md — one honest paragraph per thing this machine can do."
echo "  2. ./scripts/doctor.sh          # confirm the wiring"
echo "  3. ./scripts/sync.sh            # first cycle: publish yourself, fetch the others"
echo "  4. Schedule it — see examples/systemd/ (Linux) or examples/cron/."

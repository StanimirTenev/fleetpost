#!/usr/bin/env bash
# Ask another machine in the fleet to do something: composes a well-formed request and
# drops it at the top level of that machine's inbox. See docs/PROTOCOL.md.
#
#   ./scripts/send.sh --to desktop \
#     --topic "sign the installer" \
#     --want "Sign dist/app.exe with the company certificate and attach it to release v0.4." \
#     --done "signtool verify /pa passes on the uploaded file." \
#     --until 2026-09-01
#
# Every field is required because a request missing them cannot be acted on. The target
# machine may be offline; it picks the request up on its next cycle.
#
# Exit codes:  0 = sent   1 = error
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

# Slugging a non-ASCII topic needs a UTF-8 locale; without one the topic would be stripped
# out of the filename entirely.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf8*|*UTF8*) : ;;
  *) locale -a 2>/dev/null | grep -qix 'C.UTF-8' && export LC_ALL=C.UTF-8 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"
[ -f "$CONFIG" ] || { echo "ERROR: no config.env (copy config.example.env)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"
: "${RCLONE_REMOTE:?set RCLONE_REMOTE}"; : "${COORD_DIR:?set COORD_DIR}"; : "${MACHINE_NAME:?set MACHINE_NAME}"
: "${LOCAL_ROOT:?set LOCAL_ROOT}"   # the send is recorded here, so status.sh can follow it up

TO=""; TOPIC=""; WANT=""; DONE=""; UNTIL=""; REPLY_TO=""
usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}
while [ $# -gt 0 ]; do
  case "$1" in
    --to)       TO="${2:-}"; shift 2 ;;
    --topic)    TOPIC="${2:-}"; shift 2 ;;
    --want)     WANT="${2:-}"; shift 2 ;;
    --done)     DONE="${2:-}"; shift 2 ;;
    --until)    UNTIL="${2:-}"; shift 2 ;;
    --reply-to) REPLY_TO="${2:-}"; shift 2 ;;
    -h|--help)  usage 0 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; usage 1 ;;
  esac
done

for pair in "to:$TO" "topic:$TOPIC" "want:$WANT" "done:$DONE" "until:$UNTIL"; do
  name="${pair%%:*}"; value="${pair#*:}"
  [ -n "${value// /}" ] || { echo "ERROR: --$name is required by the protocol" >&2; exit 1; }
done

# Anti-collision rule 1: write only into ANOTHER machine's inbox.
[ "$TO" != "$MACHINE_NAME" ] && : || { echo "ERROR: '$TO' is this machine — send to another node" >&2; exit 1; }
if [ -n "${FLEET:-}" ] && ! printf '%s\n' $FLEET | grep -qx "$TO"; then
  echo "ERROR: '$TO' is not in FLEET ($FLEET)" >&2; exit 1
fi

SLUG=$(printf '%s' "$TOPIC" | sed 's/.*/\L&/' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//' | cut -c1-60)
[ -n "$SLUG" ] || { echo "ERROR: --topic must contain at least one letter or digit" >&2; exit 1; }

TODAY=$(date '+%Y-%m-%d')
FILENAME="${TODAY}-from-${MACHINE_NAME}-${SLUG}.md"
ANSWER_TO="${REPLY_TO:-${MACHINE_NAME}/inbox/}"
TARGET="${RCLONE_REMOTE}${COORD_DIR}/${TO}/inbox/${FILENAME}"

# Built with printf, not a heredoc: the two trailing spaces after From/Date are markdown
# line breaks, and this file must stay byte-identical to what the MCP server writes
# (mcp/tests/test_parity.py asserts it).
BODY=$(printf '# %s\n\n**From:** %s  \n**Date:** %s  \n**Valid until:** %s\n\n## What I want\n\n%s\n\n## What "done" means\n\n%s\n\n## Where to put the answer\n\nA new file in `%s` reporting what was done **and how it was verified** —\nnot merely "done".\n' \
  "$TOPIC" "$MACHINE_NAME" "$TODAY" "$UNTIL" "$WANT" "$DONE" "$ANSWER_TO")

printf '%s\n' "$BODY" | rclone rcat "$TARGET" || { echo "ERROR: could not write the request" >&2; exit 1; }

# Record the send locally. Nothing reports back on a folder bus: the only ack is the
# recipient moving the file into its own inbox/handled/. Without this line the sender
# has no record to compare that against, and a request that was never picked up looks
# exactly like one that was.
mkdir -p "$LOCAL_ROOT/state"
printf '%s\t%s\t%s\n' "$TODAY" "$TO" "$FILENAME" >> "$LOCAL_ROOT/state/sent.log"

echo "Sent to ${TO}: ${FILENAME}"

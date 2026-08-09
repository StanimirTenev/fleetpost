#!/usr/bin/env bash
# OPTIONAL. Builds this machine's inventory.md from a directory of markdown files
# that carry a `description:` YAML front-matter field (MEMORY_DIR in config.env).
# It copies each description VERBATIM — never paraphrases. If a line reads badly,
# fix the `description:` in the source file, not here.
#
# The "Updated" date is derived from the newest source-file mtime, NOT the wall
# clock, so the output is a pure function of content and its hash is stable
# between runs (otherwise the publish step would upload a "changed" file daily).
#
# Skip this entirely and hand-write inventory.md if you don't keep such a memory dir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$HERE/config.env}"
[ -f "$CONFIG" ] && . "$CONFIG"
: "${MACHINE_NAME:=this-machine}"

# This generator is OPTIONAL. If you don't keep a memory directory with
# `description:` front-matter, leave MEMORY_DIR empty and hand-write inventory.md.
if [ -z "${MEMORY_DIR:-}" ]; then
  echo "MEMORY_DIR is empty — nothing to generate (this is optional; hand-write inventory.md)." >&2
  exit 0
fi

OUT="${1:-/dev/stdout}"
[ -d "$MEMORY_DIR" ] || { echo "ERROR: MEMORY_DIR not found: $MEMORY_DIR" >&2; exit 1; }

# first `description:` line between the opening and closing `---`, quotes stripped,
# and `|` escaped so it can't break the markdown table.
desc_of() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "")
      if ($0 ~ /^".*"$/) { $0 = substr($0, 2, length($0)-2) }
      gsub(/\|/, "\\|"); print; exit
    }' "$1"
}

mapfile -t FILES < <(cd "$MEMORY_DIR" && find . -name '*.md' ! -name 'index.md' ! -name 'INDEX.md' \
                       | sed 's|^\./||' | sort)
[ "${#FILES[@]}" -gt 0 ] || { echo "ERROR: no source files in $MEMORY_DIR" >&2; exit 1; }

newest=0
for f in "${FILES[@]}"; do ts=$(stat -c %Y "$MEMORY_DIR/$f"); [ "$ts" -gt "$newest" ] && newest=$ts; done
updated=$(date -d "@$newest" '+%Y-%m-%d')

declare -A PROJGRP
for f in "${FILES[@]}"; do
  d=$(desc_of "$MEMORY_DIR/$f"); [ -n "$d" ] || d="(no description)"
  if [[ "$f" == */* ]]; then g="${f%%/*}"; else g="general"; fi
  PROJGRP[$g]+="| \`$f\` | $d |"$'\n'
done

{
  cat <<EOF
# Inventory — machine \`$MACHINE_NAME\`

> ⚠️ GENERATED FILE — built by generate-inventory.sh from local memory.
> Manual edits here are overwritten on the next run. If a line reads badly,
> fix the \`description:\` field in the source file instead.

**Updated:** $updated · one line per file, verbatim \`description\`.

EOF
  for g in $(printf '%s\n' "${!PROJGRP[@]}" | sort); do
    printf '## %s\n\n| File | description |\n| --- | --- |\n%s\n' "$g" "${PROJGRP[$g]}"
  done
  cat <<'EOF'
---
**Deliberately absent:** contents of passwords, keys, tokens. Paths to them, yes;
the secrets themselves, no. If you need an action that requires access, ask for the
**action**, not the access.
EOF
} > "$OUT"

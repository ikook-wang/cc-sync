#!/usr/bin/env bash
# List Claude Code sessions for a project path and its subdirectory slots.
#
# Usage: list-sessions.sh <project-path> [days=20] [--remote user@host]
# Output TSV, newest first:
#   mtime <TAB> slot-suffix <TAB> title <TAB> size <TAB> session-id <TAB> sidedir(yes/no)
# slot-suffix is "/" for the workspace root slot, "-crm" etc. for subdirectory slots.
#
# --remote ships this script to the target over ssh (bash -s), zero deployment —
# use it to inspect what already exists on the other machine.
set -euo pipefail

PROJECT_PATH="${1:?usage: list-sessions.sh <project-path> [days] [--remote user@host]}"
DAYS="${2:-20}"

if [ "${3:-}" = "--remote" ]; then
  REMOTE="${4:?--remote needs user@host}"
  exec ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
    "$REMOTE" bash -s -- "$PROJECT_PATH" "$DAYS" < "$0"
fi

PROJECTS_DIR="$HOME/.claude/projects"
[ -d "$PROJECTS_DIR" ] || { echo "ERROR no $PROJECTS_DIR on this machine" >&2; exit 1; }

# Slot name = project absolute path with every non-alphanumeric char replaced by "-".
slug=$(printf '%s' "$PROJECT_PATH" | sed 's/[^A-Za-z0-9]/-/g')

# BSD stat (macOS) first, GNU stat (Linux) as fallback.
fmtime() { stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null || stat -c '%y' "$1" | cut -c1-16; }

cd "$PROJECTS_DIR"
# Exact slot + subdirectory slots. Slot dirs start with "-", so find needs the ./ prefix.
for dir in "$slug" "$slug"-*; do
  [ -d "./$dir" ] || continue
  suffix="${dir#"$slug"}"
  suffix="${suffix:-/}"
  find ./"$dir" -maxdepth 1 -name '*.jsonl' -mtime -"$DAYS" 2>/dev/null | while IFS= read -r f; do
    # Title chain: last aiTitle record -> last summary record -> (untitled).
    title=$({ grep -o '"aiTitle":"[^"]*"' "$f" || true; } | tail -1 | sed 's/^"aiTitle":"//;s/"$//')
    if [ -z "$title" ]; then
      title=$({ grep -o '"summary":"[^"]*"' "$f" || true; } | tail -1 | sed 's/^"summary":"//;s/"$//' | cut -c1-80)
    fi
    [ -z "$title" ] && title="(untitled)"
    sid=$(basename "$f" .jsonl)
    side=no
    [ -d "./$dir/$sid" ] && side=yes
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(fmtime "$f")" "$suffix" "$title" "$(du -h "$f" | cut -f1 | tr -d ' \t')" "$sid" "$side"
  done
done | sort -r

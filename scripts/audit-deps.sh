#!/usr/bin/env bash
# Extract a session's footprint from its transcript: which directories it worked
# in and which files it wrote. Mechanical extraction only — classifying repos,
# hunting gitignored secrets, and checking toolchains is judgment work that the
# skill instructions drive.
#
# Usage: audit-deps.sh <project-path> <session-id>
# Output lines (TAB-separated):
#   CWD    <count> <path>     working directories, by frequency
#   PLAN   <path>             plan documents under ~/.claude/plans/
#   MEMORY <path>             memory files under ~/.claude/projects/*/memory/
#   WRITE  <path>             everything else written via the Write tool
set -euo pipefail

PROJECT_PATH="${1:?usage: audit-deps.sh <project-path> <session-id>}"
SID="${2:?usage: audit-deps.sh <project-path> <session-id>}"

slug=$(printf '%s' "$PROJECT_PATH" | sed 's/[^A-Za-z0-9]/-/g')
JSONL="$HOME/.claude/projects/$slug/$SID.jsonl"
[ -f "$JSONL" ] || { echo "ERROR no such session: $JSONL" >&2; exit 1; }

# Working-directory distribution.
{ grep -o '"cwd":"[^"]*"' "$JSONL" || true; } | sed 's/^"cwd":"//;s/"$//' \
  | sort | uniq -c | sort -rn \
  | while IFS= read -r line; do
      count="${line%% /*}"; count="${count// /}"
      path="/${line#* /}"
      printf 'CWD\t%s\t%s\n' "$count" "$path"
    done

# Files created/overwritten via the Write tool, deduplicated, temp paths dropped.
{ grep '"name":"Write"' "$JSONL" || true; } \
  | { grep -o '"file_path":"[^"]*"' || true; } | sed 's/^"file_path":"//;s/"$//' \
  | sort -u | { grep -vE '^/tmp/|^/private/var/|/T/' || true; } \
  | while IFS= read -r p; do
      case "$p" in
        "$HOME"/.claude/plans/*)             printf 'PLAN\t%s\n' "$p" ;;
        "$HOME"/.claude/projects/*/memory/*) printf 'MEMORY\t%s\n' "$p" ;;
        *)                                   printf 'WRITE\t%s\n' "$p" ;;
      esac
    done

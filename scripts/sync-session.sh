#!/usr/bin/env bash
# Copy one Claude Code session (transcript + optional side directory) to a
# remote machine, with a divergence guard and end-to-end verification.
#
# Usage: sync-session.sh <project-path> <session-id> <user@host> [--force]
# Output on success:
#   VERIFIED <session-id>
#   RESUME_AT <project-path>
# Exit codes: 0 verified / 1 usage or missing session / 2 verification mismatch /
#             3 divergence refused (remote copy is larger; --force to override)
set -euo pipefail

PROJECT_PATH="${1:?usage: sync-session.sh <project-path> <session-id> <user@host> [--force]}"
SID="${2:?missing session-id}"
REMOTE="${3:?missing user@host}"
FORCE="${4:-}"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
slug=$(printf '%s' "$PROJECT_PATH" | sed 's/[^A-Za-z0-9]/-/g')
LOCAL_DIR="$HOME/.claude/projects/$slug"
REMOTE_DIR=".claude/projects/$slug"   # relative to the remote $HOME
JSONL="$LOCAL_DIR/$SID.jsonl"

[ -f "$JSONL" ] || { echo "ERROR no such session: $JSONL" >&2; exit 1; }

fsize() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }
local_size=$(fsize "$JSONL")

# Divergence guard. Transcripts are append-only, so a larger remote copy means
# the session was resumed on the target and moved ahead there — never clobber it.
remote_size=$(ssh "${SSH_OPTS[@]}" "$REMOTE" \
  "stat -f %z '$REMOTE_DIR/$SID.jsonl' 2>/dev/null || stat -c %s '$REMOTE_DIR/$SID.jsonl' 2>/dev/null" || true)
remote_size="${remote_size:-0}"
if [ "$remote_size" -gt "$local_size" ] && [ "$FORCE" != "--force" ]; then
  echo "DIVERGED local=$local_size remote=$remote_size"
  echo "Remote copy is larger — it was resumed on the target. Refusing to overwrite (--force to override)." >&2
  exit 3
fi

ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$REMOTE_DIR'"
rsync -a "$JSONL" "$REMOTE:$REMOTE_DIR/"
if [ -d "$LOCAL_DIR/$SID" ]; then
  rsync -a "$LOCAL_DIR/$SID" "$REMOTE:$REMOTE_DIR/"
fi

# Verify: transcript checksum must match; side directory file counts must match.
local_sum=$(shasum -a 256 "$JSONL" | cut -d' ' -f1)
remote_sum=$(ssh "${SSH_OPTS[@]}" "$REMOTE" "shasum -a 256 '$REMOTE_DIR/$SID.jsonl'" | cut -d' ' -f1)
if [ "$local_sum" != "$remote_sum" ]; then
  echo "MISMATCH jsonl checksum local=$local_sum remote=$remote_sum" >&2
  exit 2
fi
if [ -d "$LOCAL_DIR/$SID" ]; then
  local_n=$(find "$LOCAL_DIR/$SID" -type f | wc -l | tr -d ' ')
  remote_n=$(ssh "${SSH_OPTS[@]}" "$REMOTE" "find '$REMOTE_DIR/$SID' -type f | wc -l" | tr -d ' ')
  if [ "$local_n" != "$remote_n" ]; then
    echo "MISMATCH sidedir file count local=$local_n remote=$remote_n" >&2
    exit 2
  fi
fi

echo "VERIFIED $SID"
echo "RESUME_AT $PROJECT_PATH"

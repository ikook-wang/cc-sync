#!/usr/bin/env bash
# cc-sync auto-sync — SessionEnd hook target.
#
# When a Claude Code session ends, push its transcript (+ side directory) to
# DEFAULT_PEER, silently. Installed as an optional SessionEnd hook by
# install.sh; configured via ~/.claude/cc-sync.conf:
#
#   DEFAULT_PEER=user@host        # required for auto-sync; tailnet names work
#
# Safety: same divergence guard as sync-session.sh — if the peer's copy is
# larger (session was resumed there), we skip instead of overwriting.
# Every failure path exits 0 quietly: a hook must never break the session.
set -uo pipefail

CONF="$HOME/.claude/cc-sync.conf"
[ -f "$CONF" ] && . "$CONF"
[ -n "${DEFAULT_PEER:-}" ] || exit 0

# Hook stdin is a JSON payload; transcript_path points at the session jsonl.
payload=$(cat 2>/dev/null) || exit 0
tp=$(printf '%s' "$payload" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null) || exit 0
[ -n "$tp" ] && [ -f "$tp" ] || exit 0

slot_dir=$(dirname "$tp")
sid=$(basename "$tp" .jsonl)
slot=$(basename "$slot_dir")
rel=".claude/projects/$slot"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
fsize() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null; }

local_size=$(fsize "$tp") || exit 0
remote_size=$(ssh "${SSH_OPTS[@]}" "$DEFAULT_PEER" \
  "stat -f %z '$rel/$sid.jsonl' 2>/dev/null || stat -c %s '$rel/$sid.jsonl' 2>/dev/null" 2>/dev/null) || remote_size=0
remote_size="${remote_size:-0}"
[ "$remote_size" -gt "$local_size" ] && exit 0   # diverged → the peer's history wins

ssh "${SSH_OPTS[@]}" "$DEFAULT_PEER" "mkdir -p '$rel'" 2>/dev/null || exit 0
rsync -a --timeout=30 "$tp" "$DEFAULT_PEER:$rel/" 2>/dev/null || exit 0
[ -d "$slot_dir/$sid" ] && rsync -a --timeout=30 "$slot_dir/$sid" "$DEFAULT_PEER:$rel/" 2>/dev/null
exit 0

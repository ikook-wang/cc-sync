#!/usr/bin/env bash
# cc-sync uninstaller — removes the skill, the auto-sync hook, and the config.
# Your sessions, memory, and anything already synced are never touched.
set -euo pipefail

SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$SKILLS_DIR/cc-sync"
SETTINGS="$HOME/.claude/settings.json"
CONF="$HOME/.claude/cc-sync.conf"

say() { printf '\033[1;32m▸\033[0m %s\n' "$*"; }

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  say "Removed skill: $DEST"
else
  say "Skill not found at $DEST (already removed?)"
fi

# Remove the SessionEnd auto-sync hook, if install.sh added one.
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
groups = settings.get("hooks", {}).get("SessionEnd", [])
kept = [g for g in groups
        if not any("cc-sync/scripts/auto-sync.sh" in h.get("command", "")
                   for h in g.get("hooks", []))]
if len(kept) != len(groups):
    if kept:
        settings["hooks"]["SessionEnd"] = kept
    else:
        settings["hooks"].pop("SessionEnd", None)
    with open(path, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("hook-removed")
PY
  say "Checked settings.json for the auto-sync hook."
fi

if [ -f "$CONF" ]; then
  rm -f "$CONF"
  say "Removed $CONF"
fi

say "Done. Synced sessions and data on either machine were left untouched."

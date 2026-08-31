#!/usr/bin/env bash
# cc-sync installer
#
#   curl -fsSL https://raw.githubusercontent.com/ikook-wang/cc-sync/main/install.sh | bash
#
# What it does:
#   1. Installs (or updates) the skill into ~/.claude/skills/cc-sync
#   2. Checks for Tailscale; offers to install it if missing (cross-network SSH)
#   3. Optionally configures a default peer + a SessionEnd hook that auto-syncs
#      each session to that peer when it ends (silent, divergence-guarded)
#
# Env overrides:
#   CLAUDE_SKILLS_DIR=...    install somewhere else (default ~/.claude/skills)
#   CC_SYNC_NO_TAILSCALE=1   skip the Tailscale step entirely
#   CC_SYNC_PEER=user@host   configure auto-sync non-interactively
set -euo pipefail

REPO="ikook-wang/cc-sync"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$SKILLS_DIR/cc-sync"

say()  { printf '\033[1;32m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

# Ask a yes/no question even when the script is piped into bash (stdin = script).
confirm() {
  local ans
  if [ -t 0 ]; then
    read -r -p "$1 [y/N] " ans
  elif { : < /dev/tty; } 2>/dev/null; then
    read -r -p "$1 [y/N] " ans < /dev/tty
  else
    return 1  # no terminal at all → default to "no", never block
  fi
  [ "$ans" = y ] || [ "$ans" = Y ]
}

# Read a free-form answer under the same tty rules; empty string when no terminal.
ask() {
  local ans=""
  if [ -t 0 ]; then
    read -r -p "$1 " ans
  elif { : < /dev/tty; } 2>/dev/null; then
    read -r -p "$1 " ans < /dev/tty
  fi
  printf '%s' "$ans"
}

# ---------- 1. Install / update the skill ----------
mkdir -p "$SKILLS_DIR"

# Where is this script running from? A checkout has SKILL.md next to install.sh;
# a curl|bash run has no meaningful $0.
SRC_DIR=""
if [ -f "${BASH_SOURCE[0]:-/nonexistent}" ]; then
  candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [ -f "$candidate/SKILL.md" ] && SRC_DIR="$candidate"
fi

if [ -d "$DEST/.git" ]; then
  say "Updating existing install (git pull)…"
  git -C "$DEST" pull --ff-only
elif [ -n "$SRC_DIR" ] && [ "$SRC_DIR" != "$DEST" ]; then
  say "Installing from local checkout → $DEST"
  mkdir -p "$DEST"
  cp -R "$SRC_DIR/SKILL.md" "$SRC_DIR/scripts" "$SRC_DIR/references" \
        "$SRC_DIR/install.sh" "$SRC_DIR/uninstall.sh" "$DEST/"
elif command -v git >/dev/null 2>&1 && [ ! -d "$DEST" ]; then
  say "Cloning https://github.com/$REPO → $DEST"
  git clone --depth 1 "https://github.com/$REPO" "$DEST"
else
  say "Downloading tarball → $DEST"
  mkdir -p "$DEST"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" \
    | tar -xz --strip-components=1 -C "$DEST"
fi

chmod +x "$DEST"/scripts/*.sh
[ -f "$DEST/SKILL.md" ] || { warn "install failed: $DEST/SKILL.md missing"; exit 1; }
say "Skill installed: $DEST"

# ---------- 2. Tailscale (optional, for cross-network sync) ----------
if [ "${CC_SYNC_NO_TAILSCALE:-${SESSION_MIGRATE_NO_TAILSCALE:-0}}" = "1" ]; then
  say "Skipping Tailscale check (CC_SYNC_NO_TAILSCALE=1)."
elif command -v tailscale >/dev/null 2>&1 || [ -d /Applications/Tailscale.app ]; then
  say "Tailscale already present."
else
  warn "Tailscale not found. It is optional — same-LAN SSH works without it —"
  warn "but it makes cross-network sync (office ↔ home) work exactly like LAN."
  if confirm "Install Tailscale now?"; then
    case "$(uname -s)" in
      Darwin)
        if command -v brew >/dev/null 2>&1; then
          brew install --cask tailscale-app   # pkg installer prompts for sudo
        else
          warn "Homebrew not found — download from https://tailscale.com/download"
        fi
        ;;
      Linux)
        curl -fsSL https://tailscale.com/install.sh | sh
        ;;
      *)
        warn "Unsupported OS for auto-install — see https://tailscale.com/download"
        ;;
    esac
  else
    say "Skipped. Install later from https://tailscale.com/download"
  fi
fi

# ---------- 3. Optional: auto-sync each session when it ends ----------
CONF="$HOME/.claude/cc-sync.conf"
PEER="${CC_SYNC_PEER:-}"
if [ -z "$PEER" ] && [ ! -f "$CONF" ]; then
  if confirm "Auto-sync each session to a default peer when it ends?"; then
    PEER="$(ask 'Peer (user@host, tailnet names work):')"
  fi
fi
if [ -n "$PEER" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found — auto-sync hook needs it; skipping."
  else
    printf '# cc-sync configuration\nDEFAULT_PEER=%s\n' "$PEER" > "$CONF"
    say "Wrote $CONF (DEFAULT_PEER=$PEER)"
    SETTINGS="$HOME/.claude/settings.json"
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    DEST="$DEST" python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
cmd = "bash " + os.environ["DEST"] + "/scripts/auto-sync.sh"
try:
    with open(path) as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    settings = {}
hooks = settings.setdefault("hooks", {})
groups = hooks.setdefault("SessionEnd", [])
if not any("auto-sync.sh" in h.get("command", "")
           for g in groups for h in g.get("hooks", [])):
    groups.append({"hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
PY
    say "SessionEnd auto-sync hook installed (divergence-guarded, silent)."
  fi
elif [ -f "$CONF" ]; then
  say "Auto-sync already configured ($CONF)."
fi

# ---------- 4. Next steps ----------
cat <<'EOF'

✅ Done. Next steps:

  1. Run this installer on the OTHER machine too (both ends need the skill
     only if both will initiate syncs; the target just needs sshd).
  2. If you installed Tailscale: log in with the SAME account on both
     machines (open the Tailscale app, or `sudo tailscale up` on Linux),
     then `tailscale status` shows each machine's stable hostname.
  3. In Claude Code, just say:  "把最近的会话迁移到 user@host"
     or: "sync my recent sessions to user@my-laptop"

Config:    ~/.claude/cc-sync.conf   (DEFAULT_PEER for auto-sync)
Uninstall: bash ~/.claude/skills/cc-sync/uninstall.sh

Requirements on the target machine: sshd + rsync + the same absolute
project path as the source (sessions are keyed by path).
EOF

#!/usr/bin/env bash
# claude-session-migrate installer
#
#   curl -fsSL https://raw.githubusercontent.com/ikook-wang/claude-session-migrate/main/install.sh | bash
#
# What it does:
#   1. Installs (or updates) the skill into ~/.claude/skills/session-migrate
#   2. Checks for Tailscale; offers to install it if missing (cross-network SSH)
#
# Env overrides:
#   CLAUDE_SKILLS_DIR=...            install somewhere else (default ~/.claude/skills)
#   SESSION_MIGRATE_NO_TAILSCALE=1   skip the Tailscale step entirely
set -euo pipefail

REPO="ikook-wang/claude-session-migrate"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$SKILLS_DIR/session-migrate"

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
  cp -R "$SRC_DIR/SKILL.md" "$SRC_DIR/scripts" "$SRC_DIR/references" "$DEST/"
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
if [ "${SESSION_MIGRATE_NO_TAILSCALE:-0}" = "1" ]; then
  say "Skipping Tailscale check (SESSION_MIGRATE_NO_TAILSCALE=1)."
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

# ---------- 3. Next steps ----------
cat <<'EOF'

✅ Done. Next steps:

  1. Run this installer on the OTHER machine too (both ends need the skill
     only if both will initiate migrations; the target just needs sshd).
  2. If you installed Tailscale: log in with the SAME account on both
     machines (open the Tailscale app, or `sudo tailscale up` on Linux),
     then `tailscale status` shows each machine's stable hostname.
  3. In Claude Code, just say:  "把最近的会话迁移到 user@host"
     or: "migrate my recent sessions to user@my-laptop"

Requirements on the target machine: sshd + rsync + the same absolute
project path as the source (sessions are keyed by path).
EOF

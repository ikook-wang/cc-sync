# cc-sync

[中文文档](README.zh-CN.md)

Sync [Claude Code](https://claude.com/claude-code) sessions and config between
machines over SSH — leave your desk, open your laptop, and `claude --resume`
right where you left off. Ships as a Claude Code skill: you talk, Claude
orchestrates, you pick what moves.

Claude Code stores every session on the machine it ran on
(`~/.claude/projects/…`). Switch computers and your conversations, subagent
transcripts, plans, and auto-memory stay behind. This skill moves them —
safely, verifiably, and together with the things sessions depend on that git
doesn't carry.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ikook-wang/cc-sync/main/install.sh | bash
```

The installer:

1. places the skill in `~/.claude/skills/cc-sync` (re-run to update);
2. detects **Tailscale** and offers to install it if missing — optional, but it
   makes cross-network migration (office ↔ home) work exactly like LAN SSH;
3. optionally configures a **default peer** (`~/.claude/cc-sync.conf`) and a
   `SessionEnd` hook that **auto-syncs each session to that peer when it
   ends** — silent, divergence-guarded, and an offline peer never blocks
   anything. (`CC_SYNC_PEER=user@host bash install.sh` for non-interactive.)

Or install manually:

```bash
git clone https://github.com/ikook-wang/cc-sync ~/.claude/skills/cc-sync
```

## Use

In any Claude Code session, just ask:

> 把最近 20 天的会话迁移到 ikook@my-laptop
>
> migrate my recent sessions to steve@home-imac

Claude walks a four-phase flow, asking you to pick what moves:

| Phase | What happens |
|---|---|
| **Preflight** | SSH connectivity, path parity, remote `claude` CLI + version check |
| **List / pick / sync** | Enumerate recent sessions across the workspace *and subdirectory projects*, you choose, each is copied (transcript + subagent side-directory) and verified with sha256 |
| **Dependency audit** | Extract the session's footprint → check repo HEAD parity, hunt gitignored secrets that build/release scripts need, rsync non-git artifact dirs, verify toolchains |
| **Memory merge** | Merge `MEMORY.md` indexes without losing either side; remote gets a backup first |

Also on request: **config sync** (CLAUDE.md, commands/, skills/ — with
settings.json diffed and merged, never blindly overwritten). And with
auto-sync enabled, day-to-day use needs no commands at all: end a session,
it's already on the other machine.

### Safety guarantees

- **Divergence guard** — if the target's copy of a session is larger (it was
  resumed there), sync refuses with `DIVERGED` instead of destroying the newer
  history. Nothing is ever overwritten silently.
- **Secrets stay secret** — the audit reports file names, sizes, and hashes;
  contents are never printed into the conversation.
- **Nothing is deleted** — merges only add; remote indexes are backed up before
  being rewritten.

### The one rule

**One machine per session.** Transcripts are append-only; two machines
appending to the same session create histories that cannot be merged. After
migrating, the target is that session's home. (The skill is symmetric — run it
in the other direction to move back.)

## Requirements

- macOS or Linux on both ends; `ssh` (key auth) and `rsync`
- Claude Code CLI on the target, logged in
- The **same absolute project path** on both machines — sessions are keyed by
  the directory they were started in
- Both ends online during sync (with Tailscale, network location is irrelevant)

## How it works

Sessions live in `~/.claude/projects/<slot>/`, where the slot name is the
project's absolute path with non-alphanumeric characters replaced by `-`.
Each session is a `<uuid>.jsonl` append-only transcript plus an optional side
directory of subagent transcripts and tool results. The bundled scripts
(`scripts/`) enumerate, copy, verify, and footprint them; the judgment calls —
what to move, which secrets to sync, how to merge memory — are made in
conversation with you. Format details: [references/internals.md](references/internals.md).

## Uninstall

```bash
bash ~/.claude/skills/cc-sync/uninstall.sh
```

Removes the skill, the auto-sync hook, and the config. Synced data is never
touched.

## License

[MIT](LICENSE)

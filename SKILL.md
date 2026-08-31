---
name: session-migrate
description: >
  Migrate Claude Code sessions between machines over SSH — enumerate recent
  sessions across a workspace and its subdirectory project slots, let the user
  pick, copy transcripts with side directories, verify integrity, audit
  repo/secret/toolchain dependencies on the target, and merge memory indexes.
  Use when the user wants to: (1) continue sessions on another machine
  (laptop/desktop/server), (2) list recently active sessions for a workspace,
  (3) sync session-generated artifacts and gitignored secrets to a second
  machine, (4) merge memory directories after working on two machines.
  Triggers on: "migrate session", "sync sessions", "会话迁移", "迁移会话",
  "同步会话", "把会话搬到", "换电脑继续", "出差用笔记本继续".
---

# Session Migrate

The skill directory (SKILL_DIR) is at `~/.claude/skills/session-migrate`.
If that path doesn't exist, fall back to Glob with pattern
`**/skills/**/session-migrate/SKILL.md` and derive the root from the result.

## Task

Move Claude Code sessions from this machine to another so work continues
seamlessly there. Four phases — each can be skipped independently if the user
only needs part of the flow. You orchestrate and exercise judgment; the bundled
scripts do only the mechanical parts. The user always picks which sessions to
move — never pick for them.

## How sessions are stored

Details and observed record formats: `references/internals.md` (read when needed).

- Slot name = project **absolute path** with every non-alphanumeric character
  replaced by `-`, under `~/.claude/projects/`. Subdirectory projects
  (`<ws>/crm`, `<ws>/backend`, …) each get their own slot.
- A session = `<uuid>.jsonl` transcript + an **optional side directory of the
  same uuid** (subagents / tool-results / workflows). They must travel together.
- Display name lives inside the transcript as the last `aiTitle` record;
  older sessions may only have `summary` records.
- A slot may contain a `memory/` directory (auto-memory: `MEMORY.md` index +
  one file per memory).
- Resuming on the target requires the **same absolute project path**, then
  `cd <project-path> && claude --resume`.

## Phase 0 — Preflight

Use these SSH options everywhere:
`-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5`.

1. Connectivity: `ssh $SSH_OPTS user@host 'echo ok; echo $HOME'`. If it times
   out and the machines may be on different networks, try the target's
   **Tailscale hostname** instead of a LAN IP (`tailscale status` lists online
   devices). Direct mode needs both ends online — a sleeping Mac at home is
   unreachable; suggest "Wake for network access" + keep it plugged in.
2. Path parity: remote `$HOME` and the project path must equal the local ones.
   If they differ, **stop and tell the user** — resumed sessions won't be found
   under a different path (address rewriting is out of scope).
3. Locate the remote `claude` CLI. Non-interactive SSH has a thin PATH; check
   `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `~/.claude/local/claude`.
   Compare `claude --version` on both ends (mismatched major versions are worth
   flagging, minor drift is fine).
4. Reuse of results: `list-sessions.sh --remote` (below) shows what already
   exists on the target without deploying anything.

## Phase 1 — List, pick, sync

1. **List** local sessions for the workspace and all its subdirectory slots:

   ```bash
   bash "SKILL_DIR/scripts/list-sessions.sh" <project-path> [days=20]
   ```

   TSV out: `mtime, slot-suffix, title, size, session-id, sidedir`. Render it
   as a table (time / project / title / size / short id), mark the current
   session — it is still being written, so it gets a final re-sync in Phase 4.

2. **Pick**: present the table and wait for the user's selection (by title, id
   prefix, or "all"). This is a judgment call that is never yours to make.

3. **Sync** each chosen session:

   ```bash
   bash "SKILL_DIR/scripts/sync-session.sh" <project-path> <session-id> user@host
   ```

   Copies transcript + side directory, then verifies (sha256 + file counts).
   Exit 3 = `DIVERGED`: the remote copy is larger, meaning the session was
   already resumed on the target. Report it to the user; **never pass
   `--force` without their explicit confirmation** — the larger end wins by
   default.

4. **Report**: verified list + a resume table grouped by slot, e.g.
   `cd ~/WorkSpace/vigolive/crm && claude --resume` for crm-slot sessions.

## Phase 2 — Dependency audit

Sessions reference things that don't travel with the transcript. For each
synced session, extract its footprint:

```bash
bash "SKILL_DIR/scripts/audit-deps.sh" <project-path> <session-id>
```

Output: `CWD <count> <path>` (working dirs), `WRITE` / `PLAN` / `MEMORY`
(files written). Then classify and act — this part is judgment, not script:

- **Git repos** (from CWD paths): on both ends compare `git log -1`, current
  branch, dirty and untracked files, and remote URLs. Committed+pushed work
  travels via `git pull`, not file copy. Uncommitted environment-switch edits
  (API host in an xcconfig, a disabled scheduler annotation) are often *needed*
  on the target — show the diff, ask, then `scp` the file.
- **Secrets**: read the repo's build/release scripts and work backwards to the
  gitignored inputs they read (`git status --ignored` helps): root-level key
  files, `local.properties`, keystores, plus home-level keys such as
  `~/.appstoreconnect/private_keys/`. Copy only what's missing on the target.
  If a secret exists on both ends but differs, show size/mtime/hash of each
  side and ask — **never silently overwrite**. Never print secret contents
  into the conversation; report names, sizes, and hashes only.
- **Non-git artifact dirs** (analysis outputs, scratch dirs the session wrote
  into): `rsync -a <dir> user@host:<parent>/` wholesale.
- **PLAN files**: copy to remote `~/.claude/plans/` (mkdir -p first).
- **Toolchain**: for every tool the release/build scripts invoke (xcodebuild,
  xcodegen, SDK dirs, java, …), check existence on the target and report gaps.

## Phase 3 — Memory merge

For each slot that has `memory/` locally, check the remote side:

- Remote slot has no `memory/`: copy wholesale — `rsync -a memory user@host:<slot>/`.
- Both sides have one: individual memory files rarely collide (different eras
  use different names) — `rsync -a --exclude MEMORY.md memory user@host:<slot>/`,
  then merge `MEMORY.md` by hand: read both, back up the remote as
  `MEMORY.md.pre-merge-<YYYYMMDD>`, write a merged index with the local
  (newer) entries first and remote-only entries preserved under an
  `## Earlier memories` section. **Never drop an entry.** If an individual
  file does collide, keep the newer one and say so.

## Phase 4 — Final sync & discipline

The session driving this migration keeps growing after every sync. Before the
user leaves, re-run `sync-session.sh` for it and hand them the exact command
so they can fire it last-minute themselves.

Rules to state in the final report:

- **One machine per session.** Transcripts are append-only; two machines
  appending to the same session produce histories that cannot be merged.
  A synced session's home is now the target.
- If a session did fork, the newer (larger) end wins; re-sync it back with
  this skill in the opposite direction — the skill is symmetric, just run it
  on the other machine.
- Cross-network: with Tailscale on both ends, the flow is identical to LAN —
  only the hostname changes.

## Implementation pitfalls (do not "optimize" these away)

- Slot dirs start with `-`; `find` needs the `./` prefix or it parses them as flags.
- zsh does not word-split unquoted variables; the scripts are bash and loop
  with `while IFS= read -r` — keep it that way.
- Title extraction degrades `aiTitle` → `summary` → `(untitled)`; these are
  undocumented internals and may change across Claude Code versions.
- Divergence check compares sizes *before* copying; append-only semantics make
  size a reliable signal.

## Bundled Resources

| File | Purpose |
|---|---|
| `scripts/list-sessions.sh` | Enumerate sessions for a project + subdirectory slots → TSV. `--remote user@host` runs it on the target via `ssh bash -s` (zero deployment). |
| `scripts/sync-session.sh` | Copy one session (transcript + side dir) with divergence guard and sha256/count verification. Exit 0/2/3. |
| `scripts/audit-deps.sh` | Extract a session's footprint (CWD distribution, files written) as classified TSV. Local only. |
| `references/internals.md` | Observed storage format notes (slot naming, record types, versions). Read when debugging extraction or after a Claude Code upgrade changes behavior. |

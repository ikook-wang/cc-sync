# Claude Code session storage — observed internals

Everything here is **undocumented internal format**, observed on Claude Code
2.1.224 / 2.1.235 (macOS, 2026-08). Treat as best-effort: extraction in the
scripts degrades gracefully rather than failing when a field is absent.

## Layout

```
~/.claude/
├── projects/
│   └── <slot>/                      # one per project directory Claude was started in
│       ├── <uuid>.jsonl             # session transcript, append-only, one JSON per line
│       ├── <uuid>/                  # OPTIONAL side directory, same uuid
│       │   ├── subagents/           #   agent-*.jsonl + agent-*.meta.json
│       │   ├── tool-results/
│       │   └── workflows/
│       ├── memory/                  # OPTIONAL auto-memory for this slot
│       │   ├── MEMORY.md            #   index, one line per memory
│       │   └── <slug>.md            #   one file per memory, YAML frontmatter
│       └── sessions-index.json      # cache; often stale/partial — do NOT trust it,
│                                    # enumerate *.jsonl instead
├── plans/                           # plan-mode documents, referenced by sessions
└── todos/                           # per-session todo state (uuid-keyed), optional
```

## Slot naming

`slot = abs_path.replace(/[^A-Za-z0-9]/g, '-')` — e.g.
`/Users/ikook/WorkSpace/vigolive/crm` → `-Users-ikook-WorkSpace-vigolive-crm`.

- Lossy and not reversible; sibling `foo-bar` vs subdir `foo/bar` collide in
  glob matching. Accepted; the listing shows the suffix so a human can tell.
- Slots start with `-` → always `cd ~/.claude/projects && find ./"$dir" …`.

## Transcript records the scripts rely on

One JSON object per line. Relevant shapes (grep-extractable without jq):

| Field | Record | Meaning |
|---|---|---|
| `"aiTitle":"…"` | `{"type":"ai-title", …}` | display name in the resume picker; last occurrence wins (sessions get renamed) |
| `"agentName":"…"` | `{"type":"agent-name", …}` | usually mirrors aiTitle |
| `"summary":"…"` | `{"type":"summary", …}` | rolling summaries; fallback title source for old sessions |
| `"cwd":"…"` | on message records | working directory at that moment → footprint |
| `"name":"Write"` + `"file_path":"…"` | tool_use lines | files the session created/overwrote |

## Sync semantics

- Transcripts are **append-only**. Larger file = strictly more history, which
  makes `remote_size > local_size` a reliable "resumed on the target" signal
  (the DIVERGED guard). Equal size after rsync + equal sha256 = identical.
- Copying a **live** session can in theory truncate the last line mid-append
  (never observed; line-buffered writes). The Phase 4 final re-sync heals it.
- Two machines resuming the same uuid append incompatible histories — there is
  no merge. Hence "one machine per session".

## Resume requirements on the target

- Same absolute project path (slot name AND the `cwd` values inside the
  transcript both embed it). Different `$HOME` ⇒ out of scope for v1.
- `claude` CLI logged in. Note: non-interactive SSH sees a thin PATH — the CLI
  commonly lives in `~/.local/bin` (native installer), `/opt/homebrew/bin`, or
  `~/.claude/local`.
- Auth/keychain does NOT travel with sessions and doesn't need to — the target
  machine's own login is used.

## Version notes

- 2026-08: verified a 2.1.224 target resumes transcripts written by 2.1.235.
- If a future version stops producing `aiTitle`, listings degrade to summary
  text or `(untitled)` — fix by updating the grep chain in list-sessions.sh.

## Origin

Distilled from a real migration on 2026-08-30 between two Macs: 9 sessions,
~200 MB across 4 project slots, plus memory merge and a secrets audit for
iOS/Android release pipelines. The DIVERGED guard exists because one session
had already been resumed on the target mid-migration and a blind re-copy
would have destroyed its newer history.

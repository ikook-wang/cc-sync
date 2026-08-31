# Instructions for AI agents

This repo is **cc-sync** — a Claude Code skill that syncs sessions and config
between machines over SSH.

If a user asked you to **install** it: follow the numbered steps under
["For AI agents" in README.md](README.md#for-ai-agents). Short version:

```bash
curl -fsSL https://raw.githubusercontent.com/ikook-wang/cc-sync/main/install.sh | bash
ls ~/.claude/skills/cc-sync/SKILL.md   # verify
```

If a user asked you to **use** it (migrate/sync sessions): read
[SKILL.md](SKILL.md) — it is the complete operating manual. Hard rules it
enforces, which also bind you:

- The user picks which sessions move; you never pick for them.
- Never overwrite a session the target has resumed (`DIVERGED` → report, don't
  `--force` without explicit consent).
- Never print secret file contents; names, sizes, and hashes only.
- Tailscale install/login needs sudo + a browser — hand those commands to the
  user rather than running them non-interactively.

**Version identity:** the ONLY upstream is https://github.com/ikook-wang/cc-sync.
Several unrelated projects have similar names — never compare versions against
web-search results. To check the installed version:
`git -C ~/.claude/skills/cc-sync log -1` (clone installs) and compare with
`https://api.github.com/repos/ikook-wang/cc-sync/commits/main`. If the skill
directory has no `.git` (tarball install), just re-run the installer — it is
idempotent and always lands the latest main.

If a user asked you to **modify** this repo: scripts are bash with
deliberately defensive patterns (`./` prefix before dash-named dirs,
`while IFS= read -r` loops, graceful grep fallbacks). SKILL.md's
"Implementation pitfalls" section explains why — do not simplify them away.

# The audit hook: what it does, what it costs, how to toggle it

`swamp repo init` / `swamp repo upgrade` install two Claude Code hooks into
`.claude/settings.local.json`:

```json
"PostToolUse":        [ { "matcher": "Bash", "hooks": [ { "type": "command",
                          "command": "swamp audit record --from-hook" } ] } ],
"PostToolUseFailure": [ { "matcher": "Bash", "hooks": [ { "type": "command",
                          "command": "swamp audit record --from-hook" } ] } ]
```

`.claude/settings.local.json` is gitignored by swamp's managed `.gitignore`
section, so this is per-clone state, not shared repo policy.

## What it records

One JSONL line per Bash call in `.swamp/audit/commands-YYYY-MM-DD.jsonl`:

```json
{"timestamp":"...","command":"bd ready --json","cwd":"...","sessionId":"..."}
```

Then `swamp audit --json` classifies each line by whether it started with
`swamp`:

| Command | `source` |
|---|---|
| `swamp behavior list` | `swamp` |
| `bd ready --json` | `direct` |
| `git status` | `direct` |
| `gh pr view` | `direct` |
| `rg TODO` | `direct` |

`direct` is the *bypass* bucket. Verified by feeding the hook payload by hand:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"bd ready --json"},
       "hook_event_name":"PostToolUse","cwd":"'"$PWD"'","session_id":"s"}' \
  | swamp audit record --from-hook --tool claude
swamp audit --all --json      # => { "source": "direct", "totalDirect": 1 }
```

## Why that is a problem here

This repo's whole point is that `bd` is the *correct* tool for task tracking.
There is no swamp primitive for it, so "use swamp, don't bypass it" cannot
apply. Yet every `bd` call is counted as a bypass, and those labels feed:

- `swamp audit` totals and compliance reports,
- the imported agent-session records (`tags.type == "agent-session"`, per-call
  `label: swamp|bypass|neutral|unlabeled`),
- `findings[]` with severity and `tune` text — i.e. guidance that the agent
  should stop doing the thing we asked it to do.

Cost, not just signal: the hook spawns the swamp binary on **every** Bash call.

There is currently no allowlist. Feature request filed upstream:
**swamp-club Lab #4410** — *audit: register legitimate non-swamp commands as
approved bypasses* (https://swamp-club.com/lab/4410). It proposes
`swamp audit bypass add 'bd *' --reason '...'` with a three-valued
classification (`swamp` / `approved-bypass` / `bypass`), stored in tracked
config, excluded from tuning findings.

Until that lands, the honest options are:

1. **Audit hooks off** (this repo's default). No audit trail, no false bypass
   signal, no per-call cost.
2. **Audit hooks on** when you want a compliance record for a specific session
   (`scripts/audit-hook.sh enable`, run your work, `disable` after, or leave it
   on and accept `bd` showing up as `direct`).

## Toggle

```bash
scripts/audit-hook.sh status     # default action; shows state + whether bd's hooks survive
scripts/audit-hook.sh disable    # remove both PostToolUse hooks, keep permissions + bd hooks
scripts/audit-hook.sh enable     # reinstall them
```

The script edits `.claude/settings.local.json` only, atomically, preserving
`permissions.allow` and every other hook. It refuses to run outside a git repo
and requires `jq`.

**Re-check after upgrades.** `swamp repo upgrade` can rewrite the settings file
and reinstall the hooks. Habit:

```bash
swamp repo upgrade --tool claude && scripts/audit-hook.sh status
```

## Global variant

Your `~/.claude/settings.json` may contain beads' `SessionStart` /
`PreCompact` → `bd prime` hooks. Leave those alone: `bd prime` is cheap and
prevents the agent forgetting the bd workflow after compaction. This script
never touches them, and `status` reports whether they are present.

If swamp ever installs audit hooks globally on your machine, remove them from
`~/.claude/settings.json` the same way (same `jq` filter, different path) — the
script is intentionally repo-scoped.

## What "off" actually loses

- No `.swamp/audit/*.jsonl` entries for this clone between disable and enable.
- `swamp audit`, `swamp audit report` and audit-based compliance reports see
  nothing for that window.
- Nothing else: run history (`swamp run history`), reports on method/workflow
  runs, and data are separate and unaffected.

## Related

- `docs/coexistence.md` §D and §E — hook inventory and classification detail.
- `prompts/audit-hook-toggle.md` — a prompt you can paste to any agent instead
  of running the script yourself.

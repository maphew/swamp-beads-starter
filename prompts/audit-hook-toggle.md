# Prompt: turn swamp's audit hooks off (or back on)

Paste one of these to any agent in this repo. They are written to be safe to run
unattended: they touch exactly one gitignored file, verify afterwards, and never
modify beads' session hooks.

**Scope note.** The default layout enrolls swamp as `--tool codex`, which
installs no per-command hooks at all — `swamp audit --json` reports
`supported: false`. In that state there is nothing to disable, and
`scripts/audit-hook.sh status` saying "no settings file" is correct. These
prompts matter once claude is enrolled (`swamp repo upgrade --tool claude`, or
`scripts/setup.sh --tool claude --tool codex`).

---

## Disable (the usual case: beads + git + gh are legitimate, not bypasses)

> In this repo, disable swamp's per-Bash audit hooks.
>
> 1. Run `scripts/audit-hook.sh status` and report the state.
> 2. Run `scripts/audit-hook.sh disable`.
> 3. Verify and report: `scripts/audit-hook.sh status`, plus
>    `jq '.hooks // {} | keys' .claude/settings.local.json` (expect no
>    `PostToolUse`/`PostToolUseFailure` keys) and
>    `jq -r '.hooks.SessionStart[0].hooks[0].command' .claude/settings.json`
>    (expect `bd prime --hook-json`, unchanged).
> 4. Confirm `permissions.allow` in `.claude/settings.local.json` is still
>    present and non-empty.
>
> Do not edit `.claude/settings.json`, do not touch `AGENTS.md` or `CLAUDE.md`,
> and do not commit `.claude/settings.local.json` (it is gitignored). Note in one
> line why the hooks were disabled: swamp classifies `bd`/`git`/`gh` calls as
> `direct` (= bypass) and there is no allowlist yet (swamp-club Lab #4410).

---

## Enable (audited run: you want the per-command trail)

> Re-enable swamp's audit hooks for this session. Run
> `scripts/audit-hook.sh enable`, then verify with
> `scripts/audit-hook.sh status` and
> `jq '.hooks | keys' .claude/settings.local.json` (expect `PostToolUse` and
> `PostToolUseFailure`). Then run two harmless commands — `bd ready --json` and
> `swamp behavior search --json` — and check
> `swamp audit --all --json` reports one `direct` and one `swamp` entry, so we
> can see the classification in action. Remind me to run
> `scripts/audit-hook.sh disable` when the session is done.

---

## After a swamp upgrade (drift check)

> I just ran `swamp repo upgrade`. Check whether it reinstalled the audit hooks:
> `scripts/audit-hook.sh status`. If enabled, run
> `scripts/audit-hook.sh disable` and say so. Also run
> `git diff --stat` and tell me whether any change landed outside swamp's managed
> blocks in `CLAUDE.md` and the beads block in `AGENTS.md` — there should be
> none.

---

## Why a script and not a doc

Because the state lives in a JSON file that swamp regenerates, and because the
action is two `jq` filters over `hooks.PostToolUse` / `hooks.PostToolUseFailure`.
A script makes "disable" idempotent, auditable in `git log`, and safe for an
agent to run without parsing prose. `docs/audit-hook.md` explains the trade-off;
this file is only the convenience layer.

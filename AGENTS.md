# Agent Instructions

This repository is a **starter layout for running `bd` (beads) and `swamp`
side by side**. The two tools overlap in exactly one place — "what is the work
and who is doing it" — and this file is where that boundary is declared.

> **Reading order**: this section (the contract) → the managed Beads block below
> → `README.md` → `docs/coexistence.md`.
> For swamp behaviour, run `swamp --help` / `swamp help <cmd>` or load the
> `swamp` skill. For beads, run `bd prime`.

## The contract (unmanaged — humans and agents may edit this section)

Read this before either tool's managed block. When the two disagree, this
section wins; when this section is silent, the managed blocks apply.

1. **Task tracking: `bd`.** Every unit of work is a bead. `bd ready` to find
   work, `bd update <id> --claim` to take it, `bd close <id>` when done,
   `bd create` for follow-ups discovered mid-flight. Do **not** keep a
   markdown TODO list, and do **not** use agent-internal task lists (TodoWrite,
   TaskCreate) for project work that outlives the session.
2. **Automation: `swamp`.** Behaviors (typed resources + methods), workflows
   (YAML DAGs), data (versioned snapshots), vaults (secrets). "Workflow",
   "automate", "orchestrate", "nightly job" all mean a **swamp workflow** —
   not an agent task list, not a cron agent, not a worktree.
3. **`tasks/` is swamp's, `plans/` is ours.** A file under `tasks/` whose first
   line is exactly `<!-- swamp start brief v1 -->` was written by `swamp start`
   and is a **launch brief for one agent session**, not a backlog item. Read the
   brief you were named and no other file in `tasks/`. Human planning docs,
   design notes, and scratch space go in `plans/`.
4. **No duplicate tracking.** If work is in a bead, do not also open a swamp
   task brief for it, and vice versa. A brief exists only because someone ran
   `swamp start` to launch an agent *for that bead's work*.
5. **Secrets: `swamp vault`, never `bd remember`.** `bd remember` and
   `bd memories` are for durable project knowledge (conventions, gotchas,
   decisions). Credentials, tokens, and anything sensitive go in the swamp
   `default` vault via `swamp vault put`. Never in a bead, a brief, a memory,
   or a commit.
6. **Git authority: profile-driven.** `.beads/config.yaml` sets
   `agent.profile: team-maintainer`, so in this repo agents may close beads,
   run quality gates, commit, and push as routine work. An explicit
   "do not commit" / "do not push" from the user still wins, always. For repos
   you do not own — or any repo where you want review before pushing — switch
   to `bd config set agent.profile conservative`.
7. **Session close.** Before saying done: `bd close` finished beads, file beads
   for leftovers, run the checks, then `git status` and commit. With
   `team-maintainer`, push too. Report anything still blocked.
8. **swamp needs an account.** Every `swamp` command is gated on swamp-club
   sign-in (`swamp auth login`, or `SWAMP_API_KEY` + `SWAMP_SIGNIN_TOKEN` in
   CI). `bd` works offline. Never put a `bd` call inside a headless swamp
   workflow step that cannot authenticate.
9. **Don't tune swamp by disabling it.** Prefer `swamp behavior`/`swamp workflow`
   over raw `curl`/`aws`/`gcloud` when a behavior type covers the API. If you
   must bypass, say so in a note on the bead so the audit trail and the bead
   agree.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->

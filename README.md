# swamp + beads starter

A cookie-cutter layout for running two agent tools in the same repo without them
fighting over instruction files, hooks, or "what is the work".

- **`bd` (beads)** — durable, dependency-aware task tracking. The backlog.
- **`swamp`** — typed automation: behaviors, workflows, versioned data, vaults.
  The executor.

They solve different problems and only collide on "who owns the work item".
This repo settles that collision once, in `AGENTS.md`, and keeps every generated
file out of the argument.

## Layout

```
AGENTS.md                  single source of truth: the contract, then beads' managed block
CLAUDE.md                  swamp's managed block + one line: @AGENTS.md
README.md                  this file
docs/
  coexistence.md           every difference from a plain bd/swamp install, and why
  audit-hook.md            swamp's per-Bash audit hooks, and the toggle
  walkthrough.md           a day in this repo: both loops and the handoff
scripts/
  audit-hook.sh            status | enable | disable the audit hooks
prompts/
  audit-hook-toggle.md     copy-paste prompt for any agent
plans/                     human planning docs, design notes (README explains)
tasks/                     swamp start launch briefs ONLY (README explains)
models/ workflows/ vaults/ grants/      swamp definitions (YAML, committed)
.beads/                    beads database + tracked config.yaml (profile lives here)
.agents/skills/beads/      beads' agent skill (repo-local, committed)
.claude/settings.json      bd SessionStart/PreCompact hooks (committed)
.claude/settings.local.json swamp audit hooks (gitignored, toggled by the script)
.swamp/                    swamp runtime data (gitignored)
```

## Quickstart

```bash
# 1. task tracking
bd prime                 # agent context: workflow + memories
bd ready                 # what can be worked on now
bd create "First thing" -t task -p 2
bd update <id> --claim

# 2. automation
swamp behavior type search <keyword>
swamp behavior create <type> <name>
swamp behavior run <name> <read-only-method>
swamp data query 'behaviorName == "<name>"'

# 3. session hygiene (the reason this repo exists)
scripts/audit-hook.sh status     # is swamp recording every Bash call?
scripts/audit-hook.sh disable    # turn that off while bd/git/gh are legit tools
```

## The contract, in five lines

1. Work items are beads. No markdown TODO lists, no agent-internal task lists.
2. "Workflow"/"automate" means a **swamp workflow**, never an agent task list.
3. `tasks/` is swamp's launch-brief directory. Ours is `plans/`.
4. Secrets go in `swamp vault`, never in `bd remember`, a bead, or a brief.
5. `.beads/config.yaml` sets `agent.profile: team-maintainer` — agents may
   commit and push here. Flip to `conservative` for repos you don't own.

Full text: the top of `AGENTS.md`. Rationale: `docs/coexistence.md`.

## Use it as a template

### New repo

```bash
mkdir my-project && cd my-project && git init
# copy the skeleton, then re-init both tools so ids/paths are yours
cp -r /path/to/swamp-beads-starter/{AGENTS.md,CLAUDE.md,docs,scripts,prompts,plans,tasks,.gitignore} .
swamp repo init          # prepends its managed block to CLAUDE.md
bd init                  # sees @AGENTS.md in CLAUDE.md, so it only touches AGENTS.md
bd config set agent.profile team-maintainer
scripts/audit-hook.sh disable
```

`AGENTS.md` and `CLAUDE.md` also have one-line onboarding notes in `docs/`; read
`docs/coexistence.md` §B before changing the order of those two commands.

### Existing repo (retrofit)

1. Write `AGENTS.md` (or append the contract section to yours).
2. Make `CLAUDE.md` end with `@AGENTS.md` and delete any duplicated beads block
   from it.
3. `swamp repo upgrade --tool claude` (or `repo init` if swamp isn't set up).
4. `bd setup claude` — it detects the include and updates `AGENTS.md` only.
5. `bd config set agent.profile <conservative|minimal|team-maintainer>`.
6. `scripts/audit-hook.sh disable` if you don't want per-Bash audit records.

## Switching git authority

```bash
bd config set agent.profile team-maintainer   # commit + push routine (this repo's default)
bd config set agent.profile conservative      # report handoff, wait for approval
BD_AGENT_PROFILE=conservative bd prime        # one-session override
bd config get agent.profile
```

`team-maintainer` is right for repos you own and actively drive. Use
`conservative` for shared, upstream, or review-gated repos — it also protects
against an over-eager agent committing half-finished work.

## Known rough edges

- `swamp repo upgrade` *does* reinstall the audit hooks (verified) — re-run
  `scripts/audit-hook.sh disable` after every upgrade. `scripts/audit-hook.sh
  status` is the one-line check.
- There is no way yet to tell swamp "`bd` is an approved bypass, not a
  violation". Filed upstream as **swamp-club Lab #4410**
  (https://swamp-club.com/lab/4410) and tracked here as bead
  `swamp-beads-starter-di0`; see `docs/audit-hook.md`. When it ships, re-enable
  the hooks and register `bd *` / `gh *`.
- `swamp start` requires a swamp-club account; `bd` does not. Don't mix them in a
  headless workflow step.
- Two datastores (`.beads/` Dolt, `.swamp/datastore.db`) mean no atomic
  "close the bead + record the run". Treat them as eventually consistent.

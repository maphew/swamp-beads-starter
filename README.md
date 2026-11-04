# swamp + beads starter

A cookie-cutter layout for running two agent tools in the same repo without them
fighting over instruction files, hooks, or "what is the work".

- **`bd` (beads)** — durable, dependency-aware task tracking. The backlog.
- **`swamp`** — typed automation: behaviors, workflows, versioned data, vaults.
  The executor.

They solve different problems and only collide on "who owns the work item".
This repo settles that collision once, in `AGENTS.md` — **the only instruction
file** — and keeps every generated file out of the argument.

Two decisions make that hold together:

1. **swamp is enrolled as `--tool codex`.** That is a statement about *where
   swamp writes its rules* (AGENTS.md, the tool-agnostic file), not about which
   agent you use. Claude Code reads `AGENTS.md` too.
2. **`CLAUDE.md` is one line: `@AGENTS.md`.** `bd` creates a fat `CLAUDE.md`
   when that file is missing, and skips it when the include is present — so the
   include is what keeps it thin across `bd init` / `bd setup claude` re-runs.

## Layout

```
AGENTS.md                  single source of truth: swamp's managed block, the contract,
                           then beads' managed block (both tool blocks are generated)
CLAUDE.md                  one line: @AGENTS.md
README.md                  this file
LICENSE                    MIT
docs/
  coexistence.md           every difference from a plain bd/swamp install, and why
  audit-hook.md            swamp's per-Bash audit hooks, and the toggle
  walkthrough.md           a day in this repo: both loops and the handoff
scripts/
  setup.sh                 one-command bootstrap (init order, profile, hook state)
  audit-hook.sh            status | enable | disable the audit hooks
prompts/
  audit-hook-toggle.md     copy-paste prompt for any agent
plans/                     human planning docs, design notes (README explains)
tasks/                     swamp start launch briefs ONLY (README explains)
models/ workflows/ vaults/ grants/      swamp definitions (YAML, committed)
.beads/                    beads database + tracked config.yaml (profile lives here)
.agents/skills/beads/      beads' agent skill (repo-local, committed)
.claude/settings.json      bd SessionStart/PreCompact hooks (committed)
.claude/settings.local.json per-clone agent config (gitignored)
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

# 3. layout hygiene
scripts/setup.sh --dry-run       # preview: init order, profile, hook state
scripts/audit-hook.sh status     # no hooks by default (codex target records nothing)
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
mkdir my-project && cd my-project
cp -r /path/to/swamp-beads-starter/{AGENTS.md,docs,scripts,prompts,plans,tasks,.gitignore} .
# CLAUDE.md is deliberately NOT copied: setup.sh creates it as @AGENTS.md
scripts/setup.sh                  # git init, include, swamp, bd, profile, hooks, verify
```

Then edit the contract section of `AGENTS.md` to your project.

### Fresh clone of this repo

```bash
scripts/setup.sh
```

A clone carries `.beads/` config, hooks and metadata but **not** the Dolt
database, so `setup.sh` probes `bd ready` rather than trusting the directory, and
runs `bd init` when the database is missing — which bootstraps the issue history
from the git remote (`refs/dolt/data`) in a few seconds. `bd ready` then lists the
two example beads.

**A repo derived from this template must not inherit this project's issues.**
`.beads/config.yaml` is tracked and can carry `sync.remote` pointing at the source
repo, and `bd init` will bootstrap from it. `setup.sh` therefore reconciles that
line with *your* `origin` before bd runs: repoint when it differs, drop it when
there is no origin at all. A derived repo starts with an empty backlog.

### Existing repo (retrofit)

```bash
cp -r /path/to/swamp-beads-starter/{scripts,docs,prompts,plans,tasks,AGENTS.md} .
scripts/setup.sh --profile conservative
```

`setup.sh` is idempotent and safe on an already-initialized repo: it leaves an
existing `swamp`/`bd` install alone (no re-init, no upgrade unless `--upgrade`),
reduces a fat `CLAUDE.md` to the include (backup: `CLAUDE.md.pre-setup.bak`),
strips duplicate `BEADS * SETUP` blocks out of `AGENTS.md` (backup:
`AGENTS.md.pre-setup.bak`), and re-runs the verification.

### What `scripts/setup.sh` does, in order

1. `git init -b main` if you are not in a repo (`--no-git` to refuse).
2. Creates `AGENTS.md` **only if missing** (stub with a short contract).
3. Creates `CLAUDE.md` as `@AGENTS.md` (or reduces an existing fat one to the
   include) — before `bd init`, so `bd` never writes a block into it.
4. `swamp repo init` (default `--tool codex`, so swamp's managed block lands in
   `AGENTS.md`). On an already-initialized repo it **skips** `swamp repo
   upgrade` unless you pass `--upgrade`, because upgrade bumps `upgradedAt` in
   the tracked `.swamp.yaml` and would dirty your tree every run.
5. `bd init` (or `bd setup` when already initialized); beads' block lands in
   `AGENTS.md`.
6. Strips duplicate `BEADS * SETUP` blocks that `bd init` adds for every CLI it
   detects, and removes the `.codex/` / `.cursor/` enrolments it generated.
7. `bd config set agent.profile <profile>`.
8. Audit hooks: with the default codex target swamp installs none (and reports
   `supported: false`); if claude is enrolled, they are disabled unless
   `--keep-audit-hooks`.
9. Verifies: thin `CLAUDE.md`, exactly one swamp block and one beads block, no
   duplicate blocks, profile value, bd hooks. Exits 2 on drift.

```bash
scripts/setup.sh --help
scripts/setup.sh --dry-run                  # print every command, change nothing
scripts/setup.sh --profile conservative     # review-gated repo
scripts/setup.sh --keep-audit-hooks         # claude target only: keep the trail
scripts/setup.sh --upgrade                  # refresh swamp skills/instructions (dirties .swamp.yaml)
scripts/setup.sh --keep-cli-enrolments      # keep .codex/ and .cursor/
```

### Want Claude Code to stop asking permission for `swamp`?

swamp's pre-approved Bash list (`permissions.allow`) is written only for an
enrolled claude tool, into the gitignored `.claude/settings.local.json`. Two ways:

```bash
scripts/setup.sh --tool claude --tool codex   # script strips the CLAUDE.md block again
```

...or just approve the prompts, or copy the `permissions.allow` array from
another repo. Note that `--tool claude` also re-installs the per-Bash audit
hooks on every `swamp repo upgrade`; `scripts/setup.sh` disables them again each
time it runs.

### Tool targets and what they change

| `--tool` | swamp writes its block to | audit hooks | CLAUDE.md |
|---|---|---|---|
| `codex` (default) | `AGENTS.md` | none — `swamp audit` reports `supported: false` | 1 line |
| `claude` | `CLAUDE.md` | `PostToolUse` x2 in `.claude/settings.local.json` | script keeps it 1 line |
| `claude --tool codex` | both files | installed for claude | script strips swamp's block again |

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

## License

MIT — see [LICENSE](LICENSE). Copy the layout into your own project freely; the
`bd` and `swamp` generated blocks in `AGENTS.md` carry their own tools' terms.

## Known rough edges

- **`bd init` enrols every CLI it detects.** On a machine with codex/cursor
  installed it appends a second, older beads block (`BEADS CODEX SETUP`) to
  `AGENTS.md` and creates `.codex/` + `.cursor/`. `scripts/setup.sh` strips and
  removes them, and both directories are gitignored so the removal is invisible
  to git. Nothing re-adds them until you run `bd setup <tool>` again.
- **`bd` re-creates `CLAUDE.md`** (with a full beads block) if the file is
  missing. That is why the include exists rather than no file at all.
- **`swamp repo upgrade --tool claude` re-inflates `CLAUDE.md`** and reinstalls
  the audit hooks (both verified). Re-run `scripts/setup.sh`; it re-thins the
  file and disables the hooks.
- `swamp repo upgrade` rewrites `upgradedAt` in the tracked `.swamp.yaml`, so
  any upgrade dirties the tree. That is why `scripts/setup.sh` only upgrades
  with `--upgrade`; commit the bump or `git checkout -- .swamp.yaml`.
- **With the default codex target swamp records no audit data at all**
  (`swamp audit` → `supported: false`). There is no bypass/allowlist concept to
  configure, so nothing reports `bd` as a violation — but you also have no
  per-command trail. Fields differ from the claude target; see
  `docs/audit-hook.md`.
- If you derive a repo from this template, `.beads/config.yaml` arrives with
  `sync.remote` pointing here; `scripts/setup.sh` fixes it, but if you skip the
  script, `bd init` will import this project's example issues.
- **Audit hooks are expensive**: ~475 ms and ~207 MiB per Bash call, from a 401 MB
  binary (measured; issue [#1](https://github.com/maphew/swamp-beads-starter/issues/1),
  bead `swamp-beads-starter-4co`). That is why they are off here.
- There is no way yet to tell swamp "`bd` is an approved bypass, not a
  violation" **when claude is enrolled**. Filed upstream as **swamp-club Lab
  #4410** (https://swamp-club.com/lab/4410), tracked here as bead
  `swamp-beads-starter-di0`.
- `swamp start` requires a swamp-club account; `bd` does not. Don't mix them in a
  headless workflow step.
- Two datastores (`.beads/` Dolt, `.swamp/datastore.db`) mean no atomic
  "close the bead + record the run". Treat them as eventually consistent.

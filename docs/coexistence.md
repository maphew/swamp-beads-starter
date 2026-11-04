# Coexistence: what this layout changes, and why

Everything here was verified against `swamp 20261103.191618.0-sha.17ecb554`
and `bd 1.3.2` in throwaway repos. Where a claim is checkable, the command that
checks it is given.

The short version: a plain `bd init` + `swamp repo init` in the same repo
produces **two competing "use X for ALL task tracking" directives in one
instruction file**, **two session-start hook systems**, and **a per-Bash audit
hook that classifies legitimate `bd` usage as bypass**. This layout removes or
bounds each of those.

## Differences at a glance

| # | Area | Out of the box | Here | Why |
|---|---|---|---|---|
| A | Instruction files | swamp prepends its block to `CLAUDE.md`; `bd init` appends its block to **both** `AGENTS.md` and `CLAUDE.md` | `AGENTS.md` is the only source; `CLAUDE.md` = swamp block + `@AGENTS.md`; beads block exists once, in `AGENTS.md` | One canonical file, no duplicated rules, no drift |
| B | Init order | whichever ran last "wins" the top of the file | documented order: create `CLAUDE.md` include → `swamp repo init` → `bd init` | `bd` skips `CLAUDE.md` when it contains the include; without the include it writes a duplicate block |
| C | Precedence | two managed blocks, no arbitration; agents pick one at random | unmanaged "contract" section at the top of `AGENTS.md` | Explicit "task tracking = bd, automation = swamp" is what neither tool will say for you |
| D | Claude hooks | beads: `SessionStart` + `PreCompact` → `bd prime` (`.claude/settings.json`); swamp: `PostToolUse` + `PostToolUseFailure` → `swamp audit record` (`.claude/settings.local.json`) | beads' hooks kept; swamp's audit hooks **disabled by default**, one command to enable | Audit costs a ~400 MB binary spawn per Bash call and mislabels `bd` calls; `bd prime` is cheap and useful |
| E | Audit / telemetry | every non-swamp command recorded as `direct` (i.e. bypass); no allowlist | disabled by default; `docs/audit-hook.md` explains the trade-off | `bd`, `git`, `gh` are all "bypass" under the current model — noise that pollutes compliance data |
| F | Git authority | beads default `agent.profile: conservative`; swamp says nothing about git | `agent.profile: team-maintainer` in tracked `.beads/config.yaml` | This repo is one you own and drive; commit/push are routine. Documented one-liner switches it back |
| G | Task vs plan files | `tasks/` created lazily by `swamp start`; no convention for human plans | `tasks/` reserved for swamp briefs; `plans/` for humans; both have READMEs | Prevents near-duplicate clutter and prevents agents reading a random brief |
| H | Secrets | none of the two enforces anything | `swamp vault` only; `bd remember` explicitly *not* for secrets | `bd remember` is attractive and unencrypted; swamp's `default` vault is the right home |
| I | Skills | swamp skills are **global** (`~/.claude/skills`, `~/.agents/skills`), updated by `swamp repo upgrade`; beads skill is **repo-local** (`.agents/skills/beads/`) | kept as-is, documented | Explains why one is versioned in git and the other isn't |
| J | Tool enrolment | `bd init` enrolls every detected CLI (claude/codex/cursor); swamp enrolls only what `--tool` says | both scoped to `claude`; `.codex/`, `.cursor/` removed | Deterministic starter; `bd setup <tool>` / `swamp repo upgrade --tool <tool>` re-add per tool |
| K | `.gitignore` | both write their own section; swamp's is marker-managed, beads' is appended plain | both kept, unchanged | They don't collide today; swamp regenerates only its own marked section |
| L | Datastores | `.beads/` (Dolt) + `.swamp/` (catalog + run history) | unchanged, documented as non-atomic | Don't design a workflow step whose correctness depends on beads state |
| M | Auth gates | `bd` offline; swamp requires swamp-club sign-in | documented; CI uses `SWAMP_API_KEY` + `SWAMP_SIGNIN_TOKEN` | Avoid a headless workflow step that can't authenticate |
| N | `swamp start` briefs | writes `tasks/<date>-<slug>.md` + `.swamp/start/tasks/<id>.json`; refuses to overwrite foreign files | unchanged; documented so nobody authors briefs by hand | The refusal is good behaviour; the risk is duplicate planning docs |

## A. Instruction files

Out of the box, with both tools initialized:

- `CLAUDE.md` gets swamp's 11-rule managed block **prepended** above whatever
  was there.
- `bd init` appends its `<!-- BEGIN BEADS INTEGRATION … -->` block to
  `AGENTS.md` **and** to `CLAUDE.md` (if `CLAUDE.md` exists and does not already
  include the agents file).

Result: a repo with two 50–110 line managed blocks in one file, each claiming
authority over task tracking, and neither aware of the other. An agent reading
top-down follows swamp's rule 9 ("do not interpret workflow as an agent task
list") and beads' rule ("Use `bd` for ALL task tracking") and has to guess at
the seam.

Here, `AGENTS.md` holds the contract and beads' block; `CLAUDE.md` holds swamp's
block plus one line:

```
@AGENTS.md
```

Verify:

```bash
grep -n "swamp managed\|BEADS INTEGRATION\|@AGENTS.md" AGENTS.md CLAUDE.md
```

Expect: swamp markers only in `CLAUDE.md`, beads markers only in `AGENTS.md`,
one `@AGENTS.md` line, and no rule text duplicated between them.

## B. Init order matters

`bd` is smarter than it looks: when `CLAUDE.md` already contains
`@AGENTS.md`, it treats that file as covered and writes its section to
`AGENTS.md` only. When `CLAUDE.md` exists *without* the include, it writes the
section into both.

Verified: with `CLAUDE.md` = `@AGENTS.md` and nothing else, `bd init` left
`CLAUDE.md` untouched and put the block in `AGENTS.md`. With
`CLAUDE.md` = "some notes" and no include, `bd init` appended the full block to
`CLAUDE.md` as well. Same for `bd setup claude`, which reported
`File: AGENTS.md` in the include case.

So the safe sequence for a new repo is:

```bash
printf '@AGENTS.md\n' > CLAUDE.md
swamp repo init      # prepends its block above the include
bd init              # appends beads block to AGENTS.md only
```

`scripts/setup.sh` encodes exactly this order, and repairs the wrong order by
stripping the duplicate out of `CLAUDE.md` (backup kept) before appending the
include.

If you did it the other way and `CLAUDE.md` grew a beads block, delete it (keep
`@AGENTS.md`) and run `bd setup claude` to confirm `bd` now targets
`AGENTS.md`.

Note: swamp's block lands *above* `@AGENTS.md` in `CLAUDE.md`, so `CLAUDE.md`
is not literally "thin". It is still single-source: everything project-specific
lives in `AGENTS.md`, and swamp's generated text is regenerable. `swamp repo
upgrade` re-prepends and leaves `@AGENTS.md` last — verified.

## C. Precedence

Neither tool will ever state the other's job. The contract section at the top of
`AGENTS.md` does, in nine rules, and is outside both managed blocks so it
survives regeneration. The three that matter most:

- Work items are beads; "workflow" means a swamp workflow.
- `tasks/` = swamp launch briefs, `plans/` = humans.
- Don't double-track: one bead per outcome, briefs only to launch.

## D. Hooks

Two independent hook systems install into two different files:

| Tool | File | Events | Command | Tracked? |
|---|---|---|---|---|
| beads | `.claude/settings.json` | `SessionStart`, `PreCompact` | `bd prime --hook-json` | yes |
| swamp | `.claude/settings.local.json` | `PostToolUse`, `PostToolUseFailure` (matcher `Bash`) | `swamp audit record --from-hook` | no (gitignored by swamp) |

They do not overwrite each other, so "install both" is the default outcome. This
layout keeps `bd prime` (cheap, useful, prevents workflow amnesia after
compaction) and disables the swamp audit pair (cost per Bash call, dubious
classification — see `docs/audit-hook.md`).

Verify:

```bash
scripts/audit-hook.sh status
jq '.hooks' .claude/settings.json          # beads hooks untouched
```

## E. Audit classification

`swamp audit record --from-hook` writes one JSONL line per Bash command and
labels it `swamp` or `direct`. There is no allowlist, so:

```
{"command":"bd ready --json", ...}   ->  {"source":"direct","summary":"bd ready --json"}
```

`direct` is the bypass bucket. Feed a session of beads-driven work through and
swamp's own session summaries count legitimate task tracking as policy
non-compliance, then emit tuning findings for the agent. This layout turns the
hook off and documents exactly what you lose (the compliance trail), with a
one-command way to turn it back on when you want an audited run.
Full detail: `docs/audit-hook.md`.

## F. Git authority

Beads' default profile is `conservative`: file beads, report handoff, wait for
approval before committing or pushing. The starter sets `team-maintainer`
because the common case for this layout is *your* repo, where commit and push
are routine.

It is a tracked setting, not a local preference:

```bash
cat .beads/config.yaml        # agent:\n    profile: team-maintainer
bd config set agent.profile conservative
BD_AGENT_PROFILE=conservative bd prime   # per-session, no file change
```

`team-maintainer` never overrides an explicit "do not push". It does mean an
agent will commit without asking, so use `conservative` for upstream repos and
anything with review gates.

## G. `tasks/` vs `plans/`

`swamp start` creates `tasks/<YYYY-MM-DD>-<slug>.md` with a fixed header
(`<!-- swamp start brief v1 -->`), plus a machine record in
`.swamp/start/tasks/<id>.json`. The slug comes from the task title inside
swamp's UI — your own filenames cannot be overwritten: swamp refuses with
`task_file_exists` if a foreign file sits at the target path.

The remaining hazard is conceptual: your own plan doc and a swamp brief
describing the same work. Hence the naming split — `tasks/` for swamp only,
`plans/` for humans — and rule 3 in the contract telling agents to read only the
brief they were named. `swamp-getting-started` also ignores any `tasks/` file
without the header, so a stray note there is not read as a brief.

## H. Secrets

`bd remember` is designed for durable project knowledge and is very tempting for
credentials. It is not a vault. The contract makes `swamp vault` the only home
for secrets, and forbids secrets in beads, briefs, and memories.

```bash
swamp vault list-keys default
swamp vault put default MY_TOKEN
```

## I. Skills

- **swamp**: `swamp`, `swamp-getting-started` live in the global skill dirs
  (`~/.claude/skills`, `~/.agents/skills`) and are refreshed by
  `swamp repo upgrade`. Not in git, not per-repo.
- **beads**: `bd init` writes a repo-local skill to `.agents/skills/beads/`
  (plus `agents/openai.yaml`). Committed, versioned with the repo.

This asymmetry is expected; don't "fix" it by vendoring swamp's skills.

## J. Tool enrolment

`bd init` auto-detects installed CLIs and writes `.claude/`, `.codex/`,
`.cursor/` integrations. `swamp repo init` writes only for `--tool` (default:
detected). This starter is scoped to `claude`, so `.codex/` and `.cursor/` were
removed after `bd init`.

Re-add per tool:

```bash
bd setup codex           # or: cursor, aider ...
swamp repo upgrade --tool claude --tool codex
```

Adding `codex` to swamp means swamp's managed block moves to `AGENTS.md`
(codex's instruction file) and gets prepended above beads' block there. Still
single-source, but check it after the upgrade.

## K. `.gitignore`

Both tools own a section. Swamp's is marker-delimited and regenerated on
upgrade; beads' is appended plain text. Current file, in order: beads' Dolt
ignores, then swamp's marked section. Nothing collides — but if you move the
swamp markers, expect `swamp repo upgrade` to re-add them.

## L. Two datastores

| Store | Contents | Sync |
|---|---|---|
| `.beads/` (Dolt) | issues, dependencies, comments, memories, config | `bd dolt push` / `git` remote ref |
| `.swamp/` (sqlite catalog + files) | behavior data, run history, outputs, vault bundle refs | local; `swamp datastore` for S3/team |

No shared transaction. A workflow that closes a bead and records a run cannot be
atomic; order it so a retry is safe (close the bead last, or make the step
idempotent).

## M. Auth

`swamp` gates nearly everything on swamp-club sign-in (`auth_gate_blocked`).
`bd` never needs the network. Consequences:

- CI: `SWAMP_API_KEY` + `SWAMP_SIGNIN_TOKEN` (collective token) or swamp steps
  fail.
- Never call `bd` from inside a headless swamp workflow step and expect the run
  to be replayable — the bead state is not part of the swamp run's checkpoint.

## N. Verification checklist

Run after any change to the layout, and after `swamp repo upgrade` or
`bd init` / `bd setup`:

```bash
scripts/setup.sh --dry-run      # preview every action, change nothing (safest first check)
grep -n "swamp managed\|BEADS INTEGRATION\|@AGENTS.md" AGENTS.md CLAUDE.md   # A, B
scripts/audit-hook.sh status                                                  # D, E
bd config get agent.profile                                                   # F
bd doctor --check=conventions                                                 # beads sanity
swamp doctor extensions                                                       # swamp sanity
scripts/setup.sh                # idempotent re-run: upgrades, disables hooks, verifies; exit 2 on drift
swamp repo upgrade --tool claude && git diff                                  # drift check
```

The last one is the important habit: upgrading swamp should produce a diff only
inside its own managed block (and possibly the audit hooks — re-run `disable`).
If a diff appears in the contract section, someone edited a managed block.

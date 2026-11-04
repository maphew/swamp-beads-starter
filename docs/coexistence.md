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
| A | Instruction files | swamp (default `--tool claude`) prepends its block to `CLAUDE.md`; `bd init` writes a beads block to `AGENTS.md` *and* to `CLAUDE.md` if that file exists without an include | `AGENTS.md` is the only instruction file — swamp is enrolled `--tool codex` so its block lands there; `CLAUDE.md` is exactly `@AGENTS.md` | One canonical file; nothing to reconcile, nothing to keep in sync |
| B | Init order | whichever ran last "wins" the top of the file; if `CLAUDE.md` is **missing**, `bd init` creates it with a full beads block | include first → swamp → bd; `scripts/setup.sh` enforces the order and repairs the wrong one | `bd` skips `CLAUDE.md` when it includes `AGENTS.md`, duplicates without it, and recreates the file if absent |
| C | Precedence | two managed blocks, no arbitration; agents pick one at random | unmanaged "contract" section between the two generated blocks in `AGENTS.md` | Explicit "task tracking = bd, automation = swamp" is what neither tool will say for you |
| D | Agent hooks | beads: `SessionStart` + `PreCompact` → `bd prime` (`.claude/settings.json`). swamp: `PostToolUse` + `PostToolUseFailure` → `swamp audit record`, **only when the claude tool is enrolled** | beads' hooks kept; the default codex target installs no swamp hooks at all | Codex has no per-command hooks — `swamp audit` itself reports `supported: false`. Nothing to disable, nothing recorded |
| E | Audit / telemetry | with `--tool claude`: every Bash call recorded, non-swamp labelled `direct` (= bypass), no allowlist | not collected in the default; still a live problem if you enroll claude (`docs/audit-hook.md`, Lab #4410) | Avoids a ~400 MB spawn per Bash call and a false "you bypassed swamp" signal for `bd`/`git`/`gh` |
| F | Git authority | beads default `agent.profile: conservative`; swamp says nothing about git | `agent.profile: team-maintainer` in tracked `.beads/config.yaml` | This repo is one you own and drive; commit/push are routine. Documented one-liner switches it back |
| G | Task vs plan files | `tasks/` created lazily by `swamp start`; no convention for human plans | `tasks/` reserved for swamp briefs; `plans/` for humans; both have READMEs | Prevents near-duplicate clutter and prevents agents reading a random brief |
| H | Secrets | none of the two enforces anything | `swamp vault` only; `bd remember` explicitly *not* for secrets | `bd remember` is attractive and unencrypted; swamp's `default` vault is the right home |
| I | Skills | swamp skills are **global** (`~/.claude/skills`, `~/.agents/skills`), updated by `swamp repo upgrade`; beads skill is **repo-local** (`.agents/skills/beads/`) | kept as-is, documented | Explains why one is versioned in git and the other isn't |
| J | Tool enrolment | `bd init` enrols every CLI it detects — creating `.codex/`, `.cursor/` and appending a second, older beads block (`BEADS CODEX SETUP`) to `AGENTS.md`; swamp enrols what `--tool` says and writes one block per enrolled tool | swamp `--tool codex`; bd's extra enrolments and their block stripped by `scripts/setup.sh` | Deterministic and machine-independent — without this, `AGENTS.md` differs per laptop and carries the same policy twice |
| K | `.gitignore` | both write their own section; swamp's is marker-managed, beads' is appended plain | both kept, unchanged | They don't collide today; swamp regenerates only its own marked section |
| L | Datastores | `.beads/` (Dolt) + `.swamp/` (catalog + run history) | unchanged, documented as non-atomic | Don't design a workflow step whose correctness depends on beads state |
| M | Auth gates | `bd` offline; swamp requires swamp-club sign-in | documented; CI uses `SWAMP_API_KEY` + `SWAMP_SIGNIN_TOKEN` | Avoid a headless workflow step that can't authenticate |
| N | `swamp start` briefs | writes `tasks/<date>-<slug>.md` + `.swamp/start/tasks/<id>.json`; refuses to overwrite foreign files | unchanged; documented so nobody authors briefs by hand | The refusal is good behaviour; the risk is duplicate planning docs |

## A. Instruction files

Both tools write *generated* blocks into instruction files, and neither asks
where. The target depends on what you enrol:

| swamp `--tool` | swamp writes its block to | creates `CLAUDE.md`? |
|---|---|---|
| `claude` (swamp's default) | `CLAUDE.md` | yes (prepends) |
| `codex` (this repo) | `AGENTS.md` | no |
| `claude --tool codex` | **both** files | yes (prepends) |

`bd`, separately:

- always writes its block to `AGENTS.md` (or `--agents-file`);
- also writes it into `CLAUDE.md` **if that file exists without an
  `@AGENTS.md` include**;
- **creates** `CLAUDE.md` with a full beads block if the file is missing.

So the naive combination (`swamp repo init` then `bd init`, defaults) produces a
fat `CLAUDE.md` with swamp's rules *and* a beads block, plus `AGENTS.md` with a
second beads block — two competing "use X for ALL task tracking" directives in
two files, neither aware of the other.

This repo enrols swamp as **codex** — a statement about the instruction
*target*, not about which agent you run — and keeps `CLAUDE.md` as one line.
Result:

```
AGENTS.md : swamp managed block (1-52) -> contract (53-...) -> beads block
CLAUDE.md : @AGENTS.md
```

Claude Code (Sept 2026 and later) reads `AGENTS.md` when `CLAUDE.md` is absent,
and reads it through the include otherwise. Older Claude Code needs the include,
which is why the file exists at all rather than being deleted — `bd` would
recreate it with a full block anyway.

Verify:

```bash
grep -n "swamp managed\|BEADS INTEGRATION" AGENTS.md   # one of each
cat CLAUDE.md                                          # exactly: @AGENTS.md
grep -c "BEGIN" CLAUDE.md                              # 0
```

## B. Init order matters

`bd` is smarter than it looks: when `CLAUDE.md` already contains `@AGENTS.md`,
it treats that file as covered and writes its section to `AGENTS.md` only. When
`CLAUDE.md` exists *without* the include, it writes the section into both. When
`CLAUDE.md` does not exist, it creates it.

Verified: with `CLAUDE.md` = `@AGENTS.md` and nothing else, `bd init` left
`CLAUDE.md` untouched and put the block in `AGENTS.md`. With `CLAUDE.md` =
"some notes" and no include, `bd init` appended the full block to `CLAUDE.md`.
With no `CLAUDE.md` at all, `bd init` created one containing a beads block.
`bd setup claude` behaves the same way (it recreates the fat file if deleted).

So the safe sequence for a new repo is:

```bash
printf '@AGENTS.md\n' > CLAUDE.md   # MUST exist with the include first
swamp repo init --tool codex         # block lands in AGENTS.md
bd init                              # beads block appended to AGENTS.md
```

`scripts/setup.sh` encodes exactly this order. It also repairs a repo built the
wrong way: it reduces a fat `CLAUDE.md` to the include (backup
`CLAUDE.md.pre-setup.bak`), strips duplicate `BEADS * SETUP` blocks out of
`AGENTS.md` (backup `AGENTS.md.pre-setup.bak`), and re-verifies.

Two re-entry points to remember:

- `swamp repo upgrade --tool claude` prepends its block to `CLAUDE.md` again.
- `bd init` on a repo without `CLAUDE.md` recreates it.

Both are fixed by re-running `scripts/setup.sh` — that is why the script is
idempotent rather than one-shot.

## C. Precedence

Neither tool will ever state the other's job. The contract section in
`AGENTS.md` does, in ten rules, and sits outside both managed blocks so it
survives regeneration. The three that matter most:

- Work items are beads; "workflow" means a swamp workflow.
- `tasks/` = swamp launch briefs, `plans/` = humans.
- Don't double-track: one bead per outcome, briefs only to launch.

## D. Hooks

Two hook systems, in two files, and only one of them applies in the default
layout:

| Tool | File | Events | Command | Applies when |
|---|---|---|---|---|
| beads | `.claude/settings.json` | `SessionStart`, `PreCompact` | `bd prime --hook-json` | always (tracked, committed) |
| swamp | `.claude/settings.local.json` | `PostToolUse`, `PostToolUseFailure` (matcher `Bash`) | `swamp audit record --from-hook` | only when the **claude** tool is enrolled |

With the default `--tool codex`, swamp installs no hooks at all — codex has no
per-command hooks, and `swamp audit --json` says so:

```json
{ "supported": false, "tool": "codex",
  "message": "Audit hooks are not available for codex. ..." }
```

So the default needs no toggle step, and `scripts/setup.sh` reports `n/a`. It
still removes stale hooks left by an earlier `--tool claude` run, because those
would spawn the swamp binary for nothing.

A `bd prime` hook, by contrast, is cheap and prevents workflow amnesia after
compaction — keep it. Both scripts here refuse to touch `.claude/settings.json`.

Verify:

```bash
scripts/audit-hook.sh status            # "no settings file" is a valid default state
jq '.hooks' .claude/settings.json       # beads hooks untouched
```

## E. Audit classification

Relevant only if you enrol claude. `swamp audit record --from-hook` then writes
one JSONL line per Bash command and labels it `swamp` or `direct`, with no
allowlist:

```
{"command":"bd ready --json", ...}   ->  {"source":"direct","summary":"bd ready --json"}
```

`direct` is the bypass bucket. A session of beads-driven work therefore reads as
policy non-compliance, and the imported session summaries emit tuning findings
telling the agent to stop doing what we asked.

This layout avoids the question by not enrolling claude: no hooks, no
classification, no false signal — and no per-command trail either. If you want
the trail, enrol claude, accept that `bd`/`git`/`gh` will be labelled `direct`,
and see `docs/audit-hook.md` plus **swamp-club Lab #4410** (proposed
`swamp audit bypass add 'bd *'`).

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

`bd init` has no `--tool`: it enrols **every CLI it detects**. On this machine
that meant `.codex/`, `.cursor/`, and a second beads block appended to
`AGENTS.md`:

```markdown
<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker            <- canonical: bd prime, minimal profile
...
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker            <- older wording, points at the beads skill
...
<!-- END BEADS CODEX SETUP -->
```

Two blocks, same policy, in one file — and the file's content differs depending
on which CLIs the developer happens to have installed. `scripts/setup.sh` strips
any `BEGIN BEADS … SETUP` block (keeping the canonical `BEADS INTEGRATION`) and
removes `.codex/`/`.cursor/` unless you pass `--keep-cli-enrolments`. Both
directories are gitignored, so removing them cannot dirty the tree.

Re-add per tool:

```bash
bd setup codex              # or: cursor, aider ...   (bd setup <tool> --remove to undo)
swamp repo upgrade --tool claude --tool codex
```

swamp enrolment is independent: `--tool codex` only decides that swamp's managed
block goes to `AGENTS.md`. It does not require codex to be installed and does
not create a `.codex/` directory — verified on a clean repo.

## K. `.gitignore`

Three owners, three sections, no collisions:

| Section | Owner | Contents |
|---|---|---|
| `# BEGIN swamp managed section` | swamp, regenerated on upgrade | `.swamp/`, `.swamp-sources.yaml` |
| `# Beads / Dolt files` | `bd init`, appended plain | `.dolt/`, `*.db`, `.beads/proxieddb/`, `*.gate.lock*` |
| unmarked tail | this layout | `.claude/settings.local.json`, `.codex/`, `.cursor/`, `*.pre-setup.bak` |

The third section exists because swamp only ignores `.claude/settings.local.json`
when the **claude** tool is enrolled. With the default codex target it does not,
and per-clone agent config must never be committed — so the ignore is declared
here instead of depending on tool enrolment.

`.codex/` and `.cursor/` are ignored for a sharper reason: `bd init` generates
them for every CLI it detects **and commits them**, so an un-ignored checkout
differs by machine. Ignoring them means `bd`'s auto-commit cannot pick them up,
and `scripts/setup.sh` removing them leaves no dirt behind.

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

The fastest check is to re-run the bootstrap: it is idempotent and exits 2 on
drift.

```bash
scripts/setup.sh --dry-run      # preview every action, change nothing
scripts/setup.sh                # re-thin CLAUDE.md, strip dup blocks, verify (no upgrade)
scripts/setup.sh --upgrade      # ...and refresh swamp's skills/instructions first
```

`setup.sh` deliberately does not run `swamp repo upgrade` on an initialized repo:
upgrade bumps `upgradedAt` in the tracked `.swamp.yaml`, which would dirty the
tree on every invocation.

Manual equivalents:

```bash
cat CLAUDE.md                                                              # A: exactly @AGENTS.md
grep -c "BEGIN swamp managed section" AGENTS.md                            # A: 1
grep -c "BEGIN BEADS INTEGRATION" AGENTS.md                                # A: 1
grep -c "BEGIN BEADS .* SETUP" AGENTS.md                                   # J: 0
scripts/audit-hook.sh status                                               # D: no hooks (codex)
bd config get agent.profile                                                # F
bd doctor --check=conventions                                              # beads sanity
swamp audit --json                                                         # D: supported:false (codex)
swamp repo upgrade && git diff                                             # drift check
```

The last one is the habit that matters: after `swamp repo upgrade` a diff should
appear only inside swamp's own managed block — plus, if claude is enrolled, its
block re-prepended to `CLAUDE.md` and the audit hooks reinstalled, both fixed by
re-running `scripts/setup.sh`. A diff inside the contract section means someone
edited a managed block.

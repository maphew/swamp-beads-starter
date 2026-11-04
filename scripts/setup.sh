#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in messages are prose, not expansions
# setup.sh — one-command bootstrap for the swamp + bd coexistence layout.
#
# Design: ONE instruction file. `AGENTS.md` holds everything (swamp's managed
# block, beads' managed block, your contract). `CLAUDE.md` is a one-line
# `@AGENTS.md` include, and only because `bd` recreates a fat CLAUDE.md if it is
# missing. swamp is enrolled with `--tool codex` so its block lands in
# AGENTS.md rather than CLAUDE.md; Claude Code reads AGENTS.md either way.
#
# Runs, in the order that matters:
#   1. git init -b main          (if needed; `bd` wants a git repo)
#   2. AGENTS.md                 (created only if missing)
#   3. CLAUDE.md = @AGENTS.md    BEFORE bd init, or bd writes a duplicate block
#   4. swamp repo init|upgrade   (--tool codex => managed block in AGENTS.md)
#   5. bd init|setup             (clone with no DB gets `bd init`; block -> AGENTS.md)
#   6. normalize AGENTS.md       (strip duplicate "BEADS * SETUP" blocks)
#   7. drop bd's extra CLI enrolments (.codex/, .cursor/) unless requested
#   8. bd config set agent.profile
#   9. audit hooks               (only when claude is enrolled; codex has none)
#  10. verify                    (exit 2 on drift)
#
# Idempotent: re-running upgrades instead of re-initializing and never
# overwrites AGENTS.md or a CLAUDE.md that already includes it.
#
# Usage:
#   scripts/setup.sh [options]
#
# Options:
#   --profile <name>    beads agent profile: conservative | minimal | team-maintainer
#                       (default: team-maintainer)
#   --tool <name>       swamp tool to enroll; repeat for several.
#                       Default: codex (AGENTS.md target, no per-command hooks).
#                       Use `--tool claude --tool codex` for Claude Code's
#                       pre-approved swamp permissions (adds audit hooks).
#   --agents-file <p>   beads instruction file (default: AGENTS.md)
#   --keep-audit-hooks  leave swamp's per-Bash audit hooks enabled (claude only)
#   --upgrade           run `swamp repo upgrade` on an already-initialized repo
#                       (refreshes skills/instructions; bumps `upgradedAt` in the
#                       tracked .swamp.yaml, so it dirties the tree). Off by default.
#   --keep-cli-enrolments
#                       keep the .codex/ and .cursor/ integrations that `bd init`
#                       generates for every CLI it detects. Note that --tool codex
#                       means "write instructions to AGENTS.md", not "I use codex".
#   --no-git            do not run `git init` when there is no repo
#   --dry-run           print what would run; change nothing
#   -h, --help
#
# Exit: 0 ok, 1 usage/tooling error, 2 verification failed.

set -euo pipefail

PROFILE="team-maintainer"
TOOLS=()
AGENTS_FILE="AGENTS.md"
KEEP_HOOKS=0
KEEP_CLI=0
DO_UPGRADE=0
DO_GIT=1
DRY_RUN=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
run()  {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  printf '  + %s\n' "$*"
  "$@"
}

die() { printf 'setup: %s\n' "$*" >&2; exit 1; }

usage() {
  awk '/^# setup\.sh/{p=1} /^set -euo pipefail/{p=0} p' "${BASH_SOURCE[0]}" \
    | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)          PROFILE="${2:-}"; shift 2 ;;
    --tool)             TOOLS+=("${2:-}"); shift 2 ;;
    --agents-file)      AGENTS_FILE="${2:-}"; shift 2 ;;
    --keep-audit-hooks) KEEP_HOOKS=1; shift ;;
    --keep-cli-enrolments) KEEP_CLI=1; shift ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --no-git)           DO_GIT=0; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    -h|--help|help)     usage; exit 0 ;;
    *)                  die "unknown option '$1' (try --help)" ;;
  esac
done

[[ ${#TOOLS[@]} -gt 0 ]] || TOOLS=(codex)
[[ -n "$PROFILE" ]] || die "--profile needs a value"

case "$PROFILE" in
  conservative|minimal|team-maintainer) ;;
  *) die "--profile must be conservative, minimal, or team-maintainer (got '$PROFILE')" ;;
esac

has_tool() {
  local want="$1" t
  for t in "${TOOLS[@]}"; do [[ "$t" == "$want" ]] && return 0; done
  return 1
}

# Trim leading/trailing blank runs, then guarantee the file ends with exactly one
# `@AGENTS.md` line. Used whenever CLAUDE.md has been fattened by a tool.
# Drop trailing blank lines (awk keeps everything up to the last non-blank).
trim_trailing_blanks() {
  local f="$1" tmp
  tmp="$(mktemp "$f.XXXXXX")"
  awk '{ line[NR] = $0 } NF { last = NR }
       END { for (i = 1; i <= last; i++) print line[i] }' "$f" >"$tmp"
  mv -f "$tmp" "$f"
}

append_include() {
  local f="$1" tmp
  tmp="$(mktemp "$f.XXXXXX")"
  # Keep everything up to the last non-blank line, dropping stray edge blanks.
  awk '{ line[NR] = $0 } NF { last = NR }
       END { for (i = 1; i <= last; i++) print line[i] }' "$f" >"$tmp"
  mv -f "$tmp" "$f"
  if [[ -s "$f" ]]; then
    printf '\n%s\n' "$INCLUDE" >>"$f"
  else
    printf '%s\n' "$INCLUDE" >"$f"
  fi
}

step "preflight"
for bin in git swamp bd; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found on PATH"
done
say "  swamp  $(command -v swamp)"
say "  bd     $(command -v bd) ($(bd version 2>/dev/null | head -1))"
say "  tools  ${TOOLS[*]}"

# ---------------------------------------------------------------- 1. git repo
step "git repository"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  repo_root="$(git rev-parse --show-toplevel)"
  say "  already a repo: $repo_root"
elif [[ "$DO_GIT" -eq 1 ]]; then
  repo_root="$PWD"
  run git init -b main
else
  die "not a git repository and --no-git was given"
fi
cd "$repo_root"

# -------------------------------------------------------------- 2. AGENTS.md
step "$AGENTS_FILE (single source of truth)"
if [[ -f "$AGENTS_FILE" ]]; then
  say "  exists, leaving alone"
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] would create a stub with a short contract"
  else
    tee "$AGENTS_FILE" >/dev/null <<EOF
# Agent Instructions

<!-- Add your project rules here. This file is the single source of truth;
     CLAUDE.md only includes it. -->

## The contract

1. Task tracking is \`bd\` (beads). No markdown TODO lists, no agent task lists.
2. "Workflow"/"automate" means a **swamp workflow**, never an agent task list.
3. \`tasks/\` holds \`swamp start\` launch briefs only. Human plans go in \`plans/\`.
4. Secrets go in \`swamp vault\`, never in \`bd remember\`, a bead, or a brief.
EOF
    say "  created a stub — put your rules in it (see docs/coexistence.md §C)"
  fi
fi

# --------------------------------------------------------------- 3. CLAUDE.md
# `bd` writes a full beads block into CLAUDE.md when the file exists without an
# include, and recreates it if the file is missing. A one-line include is the
# only shape that stays clean across `bd init` / `bd setup claude` re-runs.
step "CLAUDE.md (thin include)"
INCLUDE="@$(basename "$AGENTS_FILE")"
if [[ ! -f CLAUDE.md ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] would create it as '$INCLUDE'"
  else
    printf '%s\n' "$INCLUDE" >CLAUDE.md
    say "  created: $INCLUDE"
  fi
elif grep -qxF "$INCLUDE" CLAUDE.md; then
  say "  already a thin include"
else
  backup="CLAUDE.md.pre-setup.bak"
  say "  CLAUDE.md is not a plain include — reducing it (backup: $backup)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [dry-run] would strip beads blocks and keep one %s line\n' "$INCLUDE"
  else
    cp -f CLAUDE.md "$backup"
    tmp="$(mktemp "CLAUDE.md.XXXXXX")"
    awk '
      /<!-- BEGIN BEADS/ {skip=1; next}
      /<!-- END BEADS/   {skip=0; next}
      !skip {print}
    ' "$backup" >"$tmp"
    mv -f "$tmp" CLAUDE.md
    append_include CLAUDE.md
  fi
fi

# ------------------------------------------------------------------- 4. swamp
step "swamp repository"
swamp_args=(--tool "${TOOLS[0]}")
for t in "${TOOLS[@]:1}"; do swamp_args+=(--tool "$t"); done
if [[ ! -f .swamp.yaml ]]; then
  run swamp repo init "${swamp_args[@]}"
elif [[ "$DO_UPGRADE" -eq 1 ]]; then
  run swamp repo upgrade "${swamp_args[@]}"
else
  say "  already initialized — skipping upgrade (refreshes skills; dirties"
  say "  .swamp.yaml via upgradedAt). Run 'swamp repo upgrade' or add --upgrade."
fi

# ------------------------------- 4b. keep CLAUDE.md thin after swamp's write
# swamp writes its managed block into the instruction file of EVERY enrolled
# tool. `--tool claude` therefore re-inflates CLAUDE.md, undoing the include.
# The block is byte-identical to the copy in AGENTS.md, so dropping it loses
# nothing; just re-run this script after `swamp repo upgrade --tool claude`.
step "keep CLAUDE.md thin"
if grep -q "BEGIN swamp managed section" CLAUDE.md 2>/dev/null; then
  say "  swamp wrote its block into CLAUDE.md (enrolled tool: claude)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] would strip it, keeping only '$INCLUDE'"
  else
    [[ -f CLAUDE.md.pre-setup.bak ]] || cp -f CLAUDE.md CLAUDE.md.pre-setup.bak
    tmp="$(mktemp "CLAUDE.md.XXXXXX")"
    awk '
      /<!-- BEGIN swamp managed section/ {skip=1; next}
      /<!-- END swamp managed section/   {skip=0; next}
      !skip {print}
    ' CLAUDE.md | grep -v '^@' >"$tmp"
    mv -f "$tmp" CLAUDE.md
    append_include CLAUDE.md
    say "  stripped; CLAUDE.md is '$INCLUDE' again (backup: CLAUDE.md.pre-setup.bak)"
  fi
else
  say "  already thin"
fi

# ---------------------------------------------------------------------- 5. bd
step "beads repository"
bd_init_args=(--agents-file "$AGENTS_FILE" --agents-profile minimal)
bd_init_help="$(bd init --help 2>&1 || true)"
[[ "$bd_init_help" == *"--non-interactive"* ]] && bd_init_args+=(--non-interactive)
# A git clone carries .beads/ (config, hooks, metadata) but NOT the Dolt
# database — the directory existing proves nothing. Probe the database itself.
if bd ready --json >/dev/null 2>&1; then
  say "  database present — not re-running bd init"
  run bd setup "$(has_tool claude && printf claude || printf '%s' "${TOOLS[0]}")"
else
  say "  no beads database in this checkout (fresh clone?) — initializing"
  run bd init "${bd_init_args[@]}"
fi
# bd recommends 0700 on .beads; git does not preserve directory modes.
if [[ -d .beads && "$(stat -c '%a' .beads 2>/dev/null || stat -f '%Lp' .beads)" != "700" ]]; then
  run chmod 700 .beads
fi

# ------------------------------------------------------- 6. normalize AGENTS.md
# bd enrols every CLI it detects. On a machine with codex/cursor installed that
# appends a second, differently-worded beads block ("BEADS CODEX SETUP") next to
# the canonical "BEADS INTEGRATION" one — duplicate policy text in one file.
step "normalize $AGENTS_FILE"
foreign="$(grep -c 'BEGIN BEADS .* SETUP' "$AGENTS_FILE" 2>/dev/null || true)"
foreign="${foreign:-0}"
if [[ "$foreign" -gt 0 ]]; then
  say "  found $foreign duplicate beads block(s) from bd's CLI auto-enrolment"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] would strip them (backup: $AGENTS_FILE.pre-setup.bak)"
  else
    cp -f "$AGENTS_FILE" "$AGENTS_FILE.pre-setup.bak"
    tmp="$(mktemp "$AGENTS_FILE.XXXXXX")"
    awk '
      /<!-- BEGIN BEADS .* SETUP/ {skip=1; next}
      /<!-- END BEADS .* SETUP/   {skip=0; next}
      !skip {print}
    ' "$AGENTS_FILE.pre-setup.bak" >"$tmp"
    # Collapse the blank-line runs the removal can leave behind.
    awk 'NF{p=1} p' "$tmp" | cat -s >"$AGENTS_FILE"
    rm -f "$tmp"
    trim_trailing_blanks "$AGENTS_FILE"
    say "  stripped; kept the canonical BEADS INTEGRATION block"
  fi
else
  say "  no duplicate beads blocks"
fi

# ------------------------------------------- 7. bd's extra CLI enrolments
step "bd CLI enrolments"
extra=()
if [[ "$KEEP_CLI" -eq 1 ]]; then
  say "  --keep-cli-enrolments: leaving whatever bd generated"
else
  for d in .codex .cursor; do
    [[ -d "$d" ]] && extra+=("$d")
  done
fi
if [[ ${#extra[@]} -gt 0 ]]; then
  say "  bd auto-enrolled: ${extra[*]} (default: not wanted)"
  for d in "${extra[@]}"; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
      say "  [dry-run] would remove $d"
    else
      rm -rf "$d"
    fi
  done
  say "  removed; re-add with 'bd setup <tool>' if you use that CLI"
else
  say "  nothing to remove"
fi

# ----------------------------------------------------------------- 8. profile
step "git authority profile"
run bd config set agent.profile "$PROFILE"

# ------------------------------------------------------------- 9. audit hooks
step "swamp audit hooks"
hook_script="$(cd "$(dirname "$0")" && pwd)/audit-hook.sh"
[[ -x ./scripts/audit-hook.sh ]] && hook_script="$PWD/scripts/audit-hook.sh"
if ! has_tool claude; then
  say "  n/a: swamp reports audit hooks unsupported for codex (no per-command hooks)"
  # Stale hooks can survive a tool switch (or an earlier --tool claude run).
  if [[ -x "$hook_script" ]] &&
     [[ "$("$hook_script" status 2>/dev/null || true)" == *ENABLED* ]]; then
    say "  stale claude audit hooks found — removing them"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      say "  [dry-run] $hook_script disable"
    else
      "$hook_script" disable
    fi
  else
    say "  nothing is recorded, so nothing to disable"
  fi
elif [[ "$KEEP_HOOKS" -eq 1 ]]; then
  say "  --keep-audit-hooks: leaving them as swamp installed them"
elif [[ -x "$hook_script" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] $hook_script disable"
  else
    "$hook_script" disable
  fi
else
  say "  no executable $hook_script — disable by hand (docs/audit-hook.md)"
fi

# ------------------------------------------------------------------ 10. verify
step "verification"
fail=0
check() {
  local label="$1" ok="$2" detail="${3:-}"
  if [[ "$ok" -eq 1 ]]; then
    printf '  PASS  %s%s\n' "$label" "${detail:+ ($detail)}"
  else
    printf '  FAIL  %s%s\n' "$label" "${detail:+ ($detail)}"
    fail=1
  fi
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  say "  (skipped: dry-run changed nothing)"
  step "done (dry run)"
  exit 0
fi

check "CLAUDE.md includes $INCLUDE and holds no managed blocks" \
  "$([[ "$(grep -cxF "$INCLUDE" CLAUDE.md)" -ge 1 &&
       "$(grep -c 'BEGIN swamp managed section' CLAUDE.md)" -eq 0 &&
       "$(grep -c 'BEGIN BEADS' CLAUDE.md)" -eq 0 ]] && echo 1 || echo 0)"
check "swamp managed block lives in $AGENTS_FILE" \
  "$([[ "$(grep -c 'BEGIN swamp managed section' "$AGENTS_FILE")" -eq 1 &&
       "$(grep -c 'BEGIN swamp managed section' CLAUDE.md)" -eq 0 ]] && echo 1 || echo 0)"
check "exactly one beads block in $AGENTS_FILE" \
  "$([[ "$(grep -c 'BEGIN BEADS INTEGRATION' "$AGENTS_FILE")" -eq 1 ]] && echo 1 || echo 0)"
check "no duplicate 'BEADS * SETUP' blocks" \
  "$([[ "$(grep -c 'BEGIN BEADS .* SETUP' "$AGENTS_FILE")" -eq 0 ]] && echo 1 || echo 0)"

actual_profile="$(bd config get agent.profile 2>/dev/null | tr -d '[:space:]' || true)"
check "beads profile is $PROFILE" \
  "$([[ "$actual_profile" == "$PROFILE" ]] && echo 1 || echo 0)" "$actual_profile"
if [[ -f .claude/settings.json ]]; then
  check "bd hooks present (SessionStart -> bd prime)" \
    "$(jq -e '[.hooks.SessionStart[]?.hooks[]?.command // ""] | any(contains("bd prime"))' \
        .claude/settings.json >/dev/null 2>&1 && echo 1 || echo 0)"
fi
if has_tool claude && [[ "$KEEP_HOOKS" -eq 0 && -x "$hook_script" ]]; then
  # Capture, don't `grep -q`: an early exit SIGPIPEs the script and pipefail
  # turns that into a false negative.
  hook_state="$("$hook_script" status 2>/dev/null || true)"
  check "swamp audit hooks disabled" "$([[ "$hook_state" == *DISABLED* ]] && echo 1 || echo 0)"
fi

own_lines="$(( $(grep -c . CLAUDE.md) - 1 ))"
if [[ "$own_lines" -gt 0 ]]; then
  say ""
  say "  note: CLAUDE.md carries $own_lines line(s) of its own prose. It is safe"
  say "        (no managed blocks), but AGENTS.md is the single source — consider"
  say "        moving that prose there so CLAUDE.md is only '$INCLUDE'."
fi

step "done"
say "  repo    : $repo_root"
say "  tools   : ${TOOLS[*]}"
say "  profile : $PROFILE"
say "  instruct: $AGENTS_FILE (CLAUDE.md = '$INCLUDE')"
case " ${TOOLS[*]} " in
  *" claude "*)
    say "  audit   : hooks disabled; 'scripts/audit-hook.sh enable' to record a session" ;;
  *)
    say "  audit   : not collected (swamp: unsupported for ${TOOLS[*]})" ;;
esac
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  say ""
  say "  working tree has changes from the setup (normalization of generated"
  say "  blocks). Commit them so the next clone starts clean:"
  say "    git add -A && git commit -m 'layout: normalize agent instruction files'"
fi
say "  next    : bd ready ; swamp behavior type search <keyword>"
say "  docs    : README.md, docs/coexistence.md, docs/audit-hook.md"
if [[ "$fail" -ne 0 ]]; then
  say ""
  say "  verification FAILED — fix the items above before using this repo."
  exit 2
fi

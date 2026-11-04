#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in messages are prose, not expansions
# setup.sh — one-command bootstrap for the swamp + bd coexistence layout.
#
# Runs, in the order that matters:
#   1. git init                 (if needed; `bd` wants a git repo)
#   2. AGENTS.md                (created only if missing)
#   3. CLAUDE.md -> @AGENTS.md  BEFORE bd init, so bd skips duplicating its block
#   4. swamp repo init|upgrade  (enrolls the chosen tool[s]; block lands in CLAUDE.md)
#   5. bd init                  (beads block lands in AGENTS.md only)
#   6. bd config set agent.profile
#   7. scripts/audit-hook.sh disable   (unless --keep-audit-hooks)
#   8. verify, and report drift
#
# Idempotent: re-running on an initialized repo upgrades/switches instead of
# re-initializing, and never overwrites AGENTS.md or a foreign CLAUDE.md.
#
# Usage:
#   scripts/setup.sh [options]
#
# Options:
#   --profile <name>    beads agent profile: conservative | minimal | team-maintainer
#                       (default: team-maintainer)
#   --tool <name>       swamp tool to enroll; repeat for several (default: claude)
#   --agents-file <p>   beads instruction file (default: AGENTS.md)
#   --keep-audit-hooks  leave swamp's per-Bash audit hooks enabled
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
    --profile)         PROFILE="${2:-}"; shift 2 ;;
    --tool)            TOOLS+=("${2:-}"); shift 2 ;;
    --agents-file)     AGENTS_FILE="${2:-}"; shift 2 ;;
    --keep-audit-hooks) KEEP_HOOKS=1; shift ;;
    --no-git)          DO_GIT=0; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help|help)    usage; exit 0 ;;
    *)                 die "unknown option '$1' (try --help)" ;;
  esac
done

[[ ${#TOOLS[@]} -gt 0 ]] || TOOLS=(claude)
[[ -n "$PROFILE" ]] || die "--profile needs a value"

case "$PROFILE" in
  conservative|minimal|team-maintainer) ;;
  *) die "--profile must be conservative, minimal, or team-maintainer (got '$PROFILE')" ;;
esac

step "preflight"
for bin in git swamp bd; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found on PATH"
done
say "  swamp  $(command -v swamp)"
say "  bd     $(command -v bd) ($(bd version 2>/dev/null | head -1))"
say "  git    $(git --version)"

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
step "$AGENTS_FILE"
if [[ -f "$AGENTS_FILE" ]]; then
  say "  exists, leaving alone"
else
  run tee "$AGENTS_FILE" >/dev/null <<EOF
# Agent Instructions

<!-- Add your project rules here. This file is the single source of truth:
     CLAUDE.md and other tool files should only reference it. -->

## The contract

1. Task tracking is \`bd\` (beads). No markdown TODO lists, no agent task lists.
2. "Workflow"/"automate" means a **swamp workflow**, never an agent task list.
3. \`tasks/\` holds \`swamp start\` launch briefs only. Human plans go in \`plans/\`.
4. Secrets go in \`swamp vault\`, never in \`bd remember\`, a bead, or a brief.
EOF
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] would create a stub"
  else
    say "  created a stub — put your rules in it (see docs/coexistence.md §C)"
  fi
fi

# --------------------------------------------------------------- 3. CLAUDE.md
step "CLAUDE.md include"
INCLUDE="@$(basename "$AGENTS_FILE")"
if [[ ! -f CLAUDE.md ]]; then
  run tee CLAUDE.md >/dev/null <<EOF
$INCLUDE
EOF
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "  [dry-run] would create it with $INCLUDE"
  else
    say "  created with $INCLUDE"
  fi
elif grep -qxF "$INCLUDE" CLAUDE.md; then
  say "  already includes $INCLUDE"
else
  # A beads block in CLAUDE.md means bd wrote a duplicate before the include
  # existed. Strip it (it belongs in $AGENTS_FILE) and back the file up first.
  if grep -q "BEGIN BEADS INTEGRATION" CLAUDE.md; then
    backup="CLAUDE.md.pre-setup.bak"
    say "  found a duplicate beads block in CLAUDE.md — removing it (backup: $backup)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '  [dry-run] strip BEADS INTEGRATION block from CLAUDE.md, append %s\n' "$INCLUDE"
    else
      cp -f CLAUDE.md "$backup"
      tmp="$(mktemp "CLAUDE.md.XXXXXX")"
      awk '
        /<!-- BEGIN BEADS INTEGRATION/ {skip=1; next}
        /<!-- END BEADS INTEGRATION/   {skip=0; next}
        !skip {print}
      ' "$backup" >"$tmp"
      mv -f "$tmp" CLAUDE.md
      printf '\n%s\n' "$INCLUDE" >>CLAUDE.md
    fi
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '  [dry-run] append %s to CLAUDE.md\n' "$INCLUDE"
    else
      printf '\n%s\n' "$INCLUDE" >>CLAUDE.md
      say "  appended $INCLUDE"
    fi
  fi
fi

# ------------------------------------------------------------------- 4. swamp
step "swamp repository"
swamp_args=(--tool "${TOOLS[0]}")
for t in "${TOOLS[@]:1}"; do swamp_args+=(--tool "$t"); done
if [[ -f .swamp.yaml ]]; then
  run swamp repo upgrade "${swamp_args[@]}"
else
  run swamp repo init "${swamp_args[@]}"
fi

# ---------------------------------------------------------------------- 5. bd
step "beads repository"
bd_init_args=(--agents-file "$AGENTS_FILE" --agents-profile minimal)
bd_init_help="$(bd init --help 2>&1 || true)"
[[ "$bd_init_help" == *"--non-interactive"* ]] && bd_init_args+=(--non-interactive)
if [[ -d .beads ]]; then
  say "  already initialized (.beads/ present) — not re-running bd init"
  if command -v bd >/dev/null 2>&1; then
    run bd setup "${TOOLS[0]}"
  fi
else
  run bd init "${bd_init_args[@]}"
fi

# ----------------------------------------------------------------- 6. profile
step "git authority profile"
run bd config set agent.profile "$PROFILE"

# ------------------------------------------------------------- 7. audit hooks
step "swamp audit hooks"
hook_script="$(cd "$(dirname "$0")" && pwd)/audit-hook.sh"
# Prefer this repo's own copy when setup.sh was run from elsewhere.
if [[ -x ./scripts/audit-hook.sh ]]; then hook_script="$PWD/scripts/audit-hook.sh"; fi
if [[ "$KEEP_HOOKS" -eq 1 ]]; then
  say "  --keep-audit-hooks: leaving them as swamp installed them"
elif [[ -x "$hook_script" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [dry-run] %s disable\n' "$hook_script"
  else
    "$hook_script" disable
  fi
else
  say "  no executable $hook_script — skipping (disable them by hand; see docs/audit-hook.md)"
fi

# ------------------------------------------------------------------ 8. verify
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

check "CLAUDE.md includes $INCLUDE" "$(grep -qxF "$INCLUDE" CLAUDE.md && echo 1 || echo 0)"
check "CLAUDE.md has exactly one swamp managed block" \
  "$([[ "$(grep -c 'BEGIN swamp managed section' CLAUDE.md)" -eq 1 ]] && echo 1 || echo 0)"
check "beads block lives only in $AGENTS_FILE" \
  "$([[ "$(grep -c 'BEGIN BEADS INTEGRATION' "$AGENTS_FILE")" -ge 1 &&
       "$(grep -c 'BEGIN BEADS INTEGRATION' CLAUDE.md)" -eq 0 ]] && echo 1 || echo 0)"
actual_profile="$(bd config get agent.profile 2>/dev/null | tr -d '[:space:]' || true)"
check "beads profile is $PROFILE" "$([[ "$actual_profile" == "$PROFILE" ]] && echo 1 || echo 0)" "$actual_profile"
if [[ "$KEEP_HOOKS" -eq 0 && -x "$hook_script" ]]; then
  # NB: capture, don't `grep -q` — early exit gives the script SIGPIPE and
  # pipefail turns that into a false negative.
  hook_state="$("$hook_script" status 2>/dev/null || true)"
  if [[ "$hook_state" == *DISABLED* ]]; then
    check "swamp audit hooks disabled" 1
  else
    check "swamp audit hooks disabled" 0 "run $hook_script disable"
  fi
fi
if [[ -f .claude/settings.json ]]; then
  check "bd hooks present (SessionStart -> bd prime)" \
    "$(jq -e '[.hooks.SessionStart[]?.hooks[]?.command // ""] | any(contains("bd prime"))' \
        .claude/settings.json >/dev/null 2>&1 && echo 1 || echo 0)"
else
  check "bd hooks present (.claude/settings.json)" 0 "run: bd setup $(printf '%s' "${TOOLS[0]}")"
fi

# Drift notes that are not failures.
EXTRA_TOOLS=()
for d in .codex .cursor; do [[ -d "$d" ]] && EXTRA_TOOLS+=("$d"); done
if [[ ${#EXTRA_TOOLS[@]} -gt 0 ]]; then
  say ""
  say "  note: ${EXTRA_TOOLS[*]} exist (bd init enrols detected CLIs). Remove them if"
  say "        you only want ${TOOLS[*]}; re-add later with 'bd setup <tool>'."
fi

step "done"
say "  repo   : $repo_root"
say "  tools  : ${TOOLS[*]}"
say "  profile: $PROFILE"
say "  next   : bd ready ; swamp behavior type search <keyword>"
say "  docs   : README.md, docs/coexistence.md, docs/audit-hook.md"
if [[ "$fail" -ne 0 ]]; then
  say ""
  say "  verification FAILED — fix the items above before using this repo."
  exit 2
fi

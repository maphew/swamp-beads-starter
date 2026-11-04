#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf messages are prose, not expansions
# audit-hook.sh — enable / disable / inspect swamp's per-Bash audit hooks.
#
# Why this exists
# ---------------
# `swamp repo init` and `swamp repo upgrade` install two Claude Code hooks into
# `.claude/settings.local.json`:
#
#     PostToolUse        (matcher: Bash) -> swamp audit record --from-hook
#     PostToolUseFailure (matcher: Bash) -> swamp audit record --from-hook
#
# NOTE: these hooks only exist when the CLAUDE tool is enrolled
# (`swamp repo init --tool claude` / `swamp repo upgrade --tool claude`). With the
# codex target used by this repo's default layout, swamp installs no hooks at all
# and `swamp audit --json` reports {"supported": false}. Then "no settings file"
# below is the correct, expected state.
#
# They record every shell command so swamp can classify each one as
# `swamp` (went through a swamp command) or `direct` (did not). There is no
# allowlist: legitimate non-swamp tooling — `bd`, `git`, `rg`, `gh` — is
# recorded as `direct`, which reads as "bypassed swamp" in the telemetry swamp
# collects. That cost lands on every Bash call, so this script makes turning the
# hooks off (and back on) a one-liner, until swamp grows a way to register an
# approved bypass.
#
# Scope
# -----
# Local, per-clone, per Claude Code settings only:
#   <repo>/.claude/settings.local.json   (gitignored by swamp's managed section)
# Nothing global is touched. `bd`'s own SessionStart/PreCompact hooks live in
# `.claude/settings.json` and are never modified by this script.
#
# Caveat: `swamp repo upgrade` (and `swamp repo init --force`) rewrites that file
# and puts the hooks back — verified. Re-run `disable` afterwards; `status` tells
# you which state you are in.
#
# Usage
# -----
#   scripts/audit-hook.sh status     # what is installed right now (default)
#   scripts/audit-hook.sh disable    # remove the two PostToolUse hooks
#   scripts/audit-hook.sh enable     # (re)install them
#   scripts/audit-hook.sh --help
#
# Exit codes: 0 ok, 1 usage/tooling error.

set -euo pipefail

NEEDLE="audit record --from-hook"
HOOK_CMD="swamp audit record --from-hook"

die() { printf 'audit-hook: %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq / apt-get install jq)"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
settings="$repo_root/.claude/settings.local.json"

# Count hook entries whose command matches $NEEDLE across the two events.
count_hooks() {
  if [[ ! -f "$settings" ]]; then
    printf '0'
    return
  fi
  jq -r --arg needle "$NEEDLE" '
    [ (.hooks? // {})
      | to_entries[]
      | select(.key == "PostToolUse" or .key == "PostToolUseFailure")
      | .value[]
      | .hooks[]?
      | select((.command // "") | contains($needle))
    ] | length
  ' "$settings"
}

status() {
  local n
  n="$(count_hooks)"
  printf 'settings file : %s\n' "$settings"
  if [[ ! -f "$settings" ]]; then
    printf 'state         : no settings file (hooks never installed here)\n'
    printf 'swamp audit   : would record nothing\n'
    return 0
  fi
  if ! grep -q '^  - claude$' "$repo_root/.swamp.yaml" 2>/dev/null; then
    printf 'note          : claude is not enrolled in .swamp.yaml — swamp reports\n'
    printf '                audit hooks unsupported for this tool, so enabling them\n'
    printf '                records nothing. Add it with: swamp repo upgrade --tool claude\n'
  fi
  if [[ "$n" -eq 0 ]]; then
    printf 'state         : DISABLED (%s audit hooks present)\n' "$n"
    printf 'swamp audit   : records nothing from this clone\n'
    printf 're-enable with: scripts/audit-hook.sh enable\n'
  else
    printf 'state         : ENABLED (%s audit hooks present)\n' "$n"
    printf 'swamp audit   : records every Bash call (bd, git, gh, rg ... count as `direct`)\n'
    printf 'turn off with : scripts/audit-hook.sh disable\n'
  fi
  # bd's hooks must survive every toggle; report them so a surprise is visible.
  if [[ -f "$repo_root/.claude/settings.json" ]] &&
     jq -e '[.hooks.SessionStart[]?.hooks[]?.command // ""] | any(contains("bd prime"))' \
       "$repo_root/.claude/settings.json" >/dev/null 2>&1; then
    printf 'bd hooks      : present in .claude/settings.json (untouched)\n'
  else
    printf 'bd hooks      : NOT found in .claude/settings.json — run `bd setup claude`\n'
  fi
}

write_atomic() {
  local tmp
  tmp="$(mktemp "${settings}.XXXXXX")"
  cat >"$tmp"
  mv -f "$tmp" "$settings"
}

disable() {
  [[ -f "$settings" ]] || { printf 'audit-hook: nothing to disable (no %s)\n' "$settings"; return 0; }
  local before after
  before="$(count_hooks)"
  if [[ "$before" -eq 0 ]]; then
    printf 'audit-hook: already disabled\n'
    return 0
  fi
  jq --arg needle "$NEEDLE" '
    if ((.hooks? // {}) | type) != "object" then .
    else
      .hooks |= with_entries(
        if (.key == "PostToolUse" or .key == "PostToolUseFailure") and ((.value | type) == "array")
        then .value |= map(select(
               ([.hooks[]?.command // ""] | any(contains($needle))) | not
             ))
             | select((.value | length) > 0)
        else . end
      )
      | (if ((.hooks | length) == 0) then del(.hooks) else . end)
    end
  ' "$settings" | write_atomic
  after="$(count_hooks)"
  printf 'audit-hook: disabled (%s -> %s hooks)\n' "$before" "$after"
  printf 'note      : `swamp repo upgrade` reinstalls them; re-run disable after an upgrade\n'
}

enable() {
  mkdir -p "$(dirname "$settings")"
  [[ -f "$settings" ]] || printf '{}\n' >"$settings"
  local before after
  before="$(count_hooks)"
  jq --arg needle "$NEEDLE" --arg cmd "$HOOK_CMD" '
    .hooks //= {}
    | reduce ("PostToolUse", "PostToolUseFailure") as $event (.;
        .hooks[$event] //= []
        | if ([.hooks[$event][] | .hooks[]?.command // ""] | any(contains($needle)))
          then .
          else .hooks[$event] += [{ matcher: "Bash", hooks: [{ type: "command", command: $cmd }] }]
          end
      )
  ' "$settings" | write_atomic
  after="$(count_hooks)"
  printf 'audit-hook: enabled (%s -> %s hooks)\n' "$before" "$after"
}

case "${1:-status}" in
  status)  status ;;
  disable) disable; status ;;
  enable)  enable;  status ;;
  -h|--help|help)
    awk '/^# audit-hook\.sh/{p=1} /^set -euo pipefail/{p=0} p' "${BASH_SOURCE[0]}" \
      | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "unknown action '$1' (use: status | enable | disable | --help)"
    ;;
esac

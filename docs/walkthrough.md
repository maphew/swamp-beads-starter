# A day in this repo

Two loops, one boundary. The point of the layout is that you never have to think
about which loop you are in.

## Loop 1 — the work graph (`bd`)

```bash
bd prime                                  # agent context: workflow + memories
bd ready                                  # unblocked, unclaimed work
bd show swamp-beads-starter-di0
bd update swamp-beads-starter-di0 --claim
bd note swamp-beads-starter-di0 "Lab #4410 filed; waiting on upstream"
bd update swamp-beads-starter-di0 --status blocked
bd close swamp-beads-starter-lei
```

Rules of thumb from this layout:

- One bead per outcome, not per keystroke.
- `bd dep add <child> <parent> --type blocks` when order matters — that is the
  whole reason beads exists instead of a TODO list.
- `bd remember` for durable *knowledge* ("the staging account is 1234"), never
  for secrets.
- `bd close` and file follow-up beads before saying a task is done.

## Loop 2 — the automation (`swamp`)

```bash
swamp behavior type search <keyword>      # is there already a type?
swamp extension search <keyword>          # ...or a community extension?
swamp behavior create <type> <name>       # YAML definition in models/
swamp behavior validate <name>
swamp behavior run <name> <read-method>   # reads first, mutates later
swamp data query 'behaviorName == "<name>"' --select content
swamp workflow create <name>              # when it becomes multi-step
swamp workflow validate <name>
swamp workflow run <name> --input key=value
```

Rules of thumb:

- Read before write: `get`/`list`/`describe` for the first run on a new behavior.
- Feed outputs forward with CEL, don't re-fetch:
  `data.latest("<name>", "<dataName>").attributes.<field>`.
- When a run fails, read the stored report before editing the definition:
  `swamp report get @swamp/method-summary --model <name> --json`.
- Long waits and human gates belong in the workflow: `manual_approval` /
  signal waits suspend to disk, and `swamp workflow resume --run <id>` picks the
  run back up — possibly in a different session.

## Where they meet

```
bd — durable, dependency-aware, shared          swamp — execution + evidence
   bead  ──── "do this" ────────────────▶  behavior run / workflow run
   bead  ◀─── "here is what happened" ────  run history, data, reports
```

Concretely: you claim a bead, then either do the work by hand or hand it to an
agent with `swamp start` (which writes a brief into `tasks/`), and the execution
evidence lands in `.swamp/` — `swamp run history`, `swamp summarise --since 1d`,
`swamp data query`.

Don't try to make one hold the other's state:

- No bead status derived from a swamp run. Beads' statuses are the contract;
  update them explicitly.
- No swamp step that asserts on beads state and expects retries to be safe. The
  two datastores are not in one transaction.

## Handing a session to the next one

1. Beads carries *what*: open beads with notes, blockers, and the next action.
2. swamp carries *evidence*: run history, data versions, reports
   (`swamp summarise --since 7d` re-orients in one command).
3. `tasks/` carries *the prompt* for a specific agent launch, if you used
   `swamp start`.
4. Then close the session the beads way:

   ```bash
   bd close <finished ids>
   bd create "What is still missing" -t task -p 2
   git add -A && git commit -m "..."   # team-maintainer profile: routine
   git push                            # ...and push, unless told not to
   ```

The next session starts with `bd prime` (beads' hook does it for you) and, if it
needs the audit trail, `scripts/audit-hook.sh enable`.

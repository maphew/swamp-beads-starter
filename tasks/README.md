# `tasks/` — swamp launch briefs (do not author here by hand)

`swamp start` writes one file per task here:

```
tasks/2026-11-04-rename-my-vpcs.md
```

Its first line is exactly:

```
<!-- swamp start brief v1 -->
```

followed by `# Task` (your text, verbatim), `# Context` (workspace, agent), and
`# How to work on this`. The matching machine record lives in
`.swamp/start/tasks/<id>.json` (gitignored, machine-local).

The agent is launched with the prompt `Read tasks/<file> and use the
swamp-getting-started skill.` The `swamp-getting-started` skill only treats a
file as a brief if that header is present, and only reads the brief it was
named — other files in this directory are ignored by design.

## Rules

- **Write planning docs in `plans/`, not here.** A brief is a one-shot launch
  prompt for one agent session, not a backlog item.
- **Don't hand-write a brief.** Handwritten text will not match a recorded task
  and will be ignored (or refused) by `swamp start`.
- **Don't rename or move briefs.** The filename is recorded in the task record;
  swamp refuses to overwrite a file it didn't write (`task_file_exists`) but it
  will not chase a renamed one.
- **One bead → at most one brief.** The bead is the durable work item; the brief
  is how that work got handed to an agent.

## Relationship to beads

```
bead (durable, dependency-aware, synced)
  └── optional swamp start brief (one session, this clone)
        └── swamp behavior / workflow runs (execution, this repo's datastore)
```

Deleting a brief after the session is fine — the bead keeps the history, the
swamp run history keeps the evidence (`swamp run history`, `swamp summarise`).

Keep the `README.md`: it is not a brief (no header) and is skipped by every
tool that reads this directory.

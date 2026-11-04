# `plans/` — human planning docs

Everything a person (or an agent asked to *think*, not to track) writes about
intended work goes here:

- design notes, RFC drafts, option comparisons
- investigations and their conclusions (`research`, spikes)
- refactor plans and migration checklists
- scratch diagrams

Naming: `YYYY-MM-DD-topic.md` or `topic/` for a series. Nothing here is read
automatically by any tool, so shape it for humans.

**Not here:** task state. That belongs in beads:

```bash
bd create "Title" -t task -p 2 -d "why / acceptance"
bd update <id> --claim
bd close <id>
```

**Not here:** swamp launch briefs. Those live in `tasks/` and are written by
`swamp start`, never by hand.

Rule of thumb: if it has a status that can change, it is a bead. If it is prose
that explains *why*, it is a plan.

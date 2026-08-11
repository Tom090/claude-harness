---
name: project-status
description: Reconstruct where the project stands (for resuming in a fresh session). Invoke with /harness:project-status.
---
# Project status

Gather durable state from GitHub and git, then summarize for the lead.

```bash
gh issue list --state open --limit 50
gh pr list --state open
git log --oneline -15
git status
```

Then report, concisely:
- **Current phase** (per `docs/roadmap.md`, if the project has one) and how far through
  it we are.
- **In progress vs open** issues; anything blocked and on what.
- **PRs awaiting review/merge**, with their review state.
- **Next unblocked issue** to pick up, per the execution plan in `CLAUDE.md` and the
  rationale in `docs/decisions.md`.
- Any decision or human input needed before proceeding (config, keys, approvals).

Read `docs/decisions.md` first if you're a fresh session — it carries the *why*.

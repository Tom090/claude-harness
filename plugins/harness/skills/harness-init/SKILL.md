---
name: harness-init
description: Bootstrap the harness into a new (or existing) project — detect the stack, generate CLAUDE.md and a builder roster, wire the deterministic gates, set up GitHub, and verify it all before declaring done. Run once at project kickoff.
---
# Harness init

One-time bootstrap. Produces a bound project: `CLAUDE.md`, a builder roster in
`.claude/agents/`, `.claude/harness.env`, seeded `docs/decisions.md` and
`.claude/agent-sessions.md`, GitHub scaffolding, and verified gates.

**Complements, does not replace, Claude Code's built-in `/init`.** `/init` owns the
descriptive half of `CLAUDE.md` (what the repo *is*); this skill owns the prescriptive
half (the operating model) and only ever generates the descriptive half when nothing
better already exists.

## 1. Interview + detect

- **If `CLAUDE.md` already exists**: read it. Never overwrite it. Merge — add the
  prescriptive section (roster, gates, workflow) from `templates/CLAUDE.md.template` if
  it's missing, keep the existing descriptive content as-is.
- **If the repo has code but no `CLAUDE.md`**: run the built-in `/init` first (or, if
  unavailable, do equivalent codebase discovery yourself) and use its output as the
  descriptive input — build/test/lint commands, architecture, conventions. Don't
  interview the user for facts the repo already states.
- **If the repo is empty / kickoff-only**: detect stack from whatever's present
  (`build.gradle*` → Gradle, `package.json` → npm/pnpm/yarn, `Cargo.toml` → cargo,
  `pyproject.toml`/`requirements.txt` → Python, `go.mod` → Go, etc.); if nothing is
  present, ask.
- Ask via **AskUserQuestion**, and only for what neither the repo nor the user's
  kickoff message already answered:
  1. Builder roles needed (one generic builder, or a split like frontend/backend?) —
     see `templates/agent-roster/SPECIALIZING.md`.
  2. Quality/deadline posture (affects nothing about model tier — that's fixed policy —
     but may affect how strict the Stop-hook gate should be out of the gate).
  3. Whether the owner wants the Telegram ask-owner loop set up now or later.

## 2. Generate bindings

All of these go INTO the target project, not this plugin:

- **`CLAUDE.md`**: from `templates/CLAUDE.md.template`. Fill every `{{PLACEHOLDER}}`.
  `{{BUILDER_ROSTER}}` is a bullet per generated builder agent (name + one-line role).
  `{{OWNER_COMMS_LINE}}` is the Telegram-policy line from the harness plugin's
  `rules/operating-model.md` § Owner-comms policy if the bridge is being set up, else
  omit it. Keep it under ~200 lines — link to `docs/` and `.claude/rules/`, don't inline.
- **`.claude/agents/*.md`**: one file per builder role from step 1, generated from
  `templates/agent-roster/generic-builder.md` (models set explicitly — builders
  `sonnet`). Do NOT add `reviewer`/`researcher`/`wave-lead` agent files here — those
  ship with the harness plugin itself (`plugins/harness/agents/`) and are already
  available to spawn once the plugin is installed; generating project-local copies
  would just fork them out of sync with plugin updates.
- **`.claude/harness.env`**: from `templates/harness.env.example` — set real
  `TEST_COMMAND`/`LINT_COMMAND`/`PROJECT_NAME`/`DEFAULT_BRANCH` for the detected stack;
  leave the rest at sane defaults unless the interview surfaced a need (e.g.
  `PROTECTED_PATHS` for a secrets directory).
- **`docs/decisions.md`**: seed from `templates/decisions.md.template` if it doesn't
  exist; if it does, append the seed entry.
- **`.claude/agent-sessions.md`**: seed from `templates/agent-sessions.md.template` if
  it doesn't exist.
- **`docs/roadmap.md`**: a short phase skeleton if the project wants one (optional —
  skip if the interview says no phased roadmap is wanted).

## 3. Initialize

- `git init` if the directory isn't a repo yet.
- `gh repo create` if there's no GitHub remote — ask private/public via
  AskUserQuestion if not already stated.
- Labels: `agent:<role>` per generated builder plus `reviewer`/`researcher`/`wave-lead`,
  and `type:feedback`.
- Milestones if a roadmap was seeded (one per phase).
- Branch protection on the default branch (require PR, no direct pushes) if the repo
  has a remote.
- Suggest a permissions allowlist for `.claude/settings.json` (safe read-only `gh`/`git`
  commands, the project's test/lint command) — apply if the interview OK'd it.

## 4. Verify the gates — do not skip

Run `/harness:verify-gates` now. **Known gotcha**: hook/settings changes are NOT
hot-reloaded mid-session — verification must run in a fresh session. Tell the user:
"Restart Claude Code in this project, then run `/harness:verify-gates`." Do not declare
harness-init done until that pass has actually run (in this session if the hooks were
already active before you started, otherwise after the restart you just requested).

## 5. Checkpoint

Write the seeded `docs/decisions.md` entry (step 2) recording what was set up: stack
detected, builders generated, gates configured, Telegram status, GitHub setup summary.
Commit it.

## Closing notes (tell the user)

- Safe to run `/init` later to refresh the descriptive half of `CLAUDE.md`; the harness
  operating model lives in `.claude/rules/` and the harness plugin's own `rules/`, which
  `/init` does not touch.
- Restart-then-`/harness:verify-gates` if you haven't already done so this session.

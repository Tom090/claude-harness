---
name: harness-init
description: Bootstrap the harness into a new (or existing) project — detect the stack, generate CLAUDE.md and a builder roster, wire the deterministic gates, set up GitHub, and verify it all before declaring done. Run once at project kickoff.
---
# Harness init

One-time bootstrap. Produces a bound project: `CLAUDE.md`, a builder roster in
`.claude/agents/`, `.claude/harness.env`, seeded `docs/decisions.md` and
`.claude/agent-sessions.md`, GitHub scaffolding, and verified gates.

**Complements, does not replace, Claude Code's built-in `/init`.** `/init` may refresh
the descriptive sections of `CLAUDE.md` (what the repo *is*: architecture, commands,
style); this skill owns the rest (the operating model) and only ever generates the
descriptive sections when nothing better already exists.

## 0. Preflight

Check these and report; don't silently continue past a miss:
- `command -v jq` — the destructive-command hook parses its input with `jq` (falling back
  to `python3`). With neither installed that gate cannot inspect commands at all; tell the
  user to install `jq` before relying on it.
- `command -v gh` and `gh auth status` — step 3 needs them; skip the GitHub steps and say
  so if they're missing.
- `git rev-parse --git-dir` — note whether this is a repo yet (step 3 creates one).

## 1. Interview + detect

- **If `CLAUDE.md` already exists**: read it. Never overwrite it. Merge — add the
  operating-model sections (non-negotiables, how work moves, roles, resuming) from
  `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.template` if they are missing, keeping the
  existing descriptive content as-is. Rules only: if the existing file carries history
  or reasoning, move it to `docs/decisions.md`.
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
     see `${CLAUDE_PLUGIN_ROOT}/templates/agent-roster/SPECIALIZING.md`.
  2. Quality/deadline posture (affects nothing about model tier — that's fixed policy —
     but may affect how strict the Stop-hook gate should be out of the gate).
  3. Whether the owner wants the Telegram ask-owner loop set up now or later.

## 2. Generate bindings

All of these go INTO the target project, not this plugin:

- **`CLAUDE.md`**: from `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.template`. Fill every
  `{{PLACEHOLDER}}`. `{{BUILDER_ROSTER}}` is a bullet per generated builder agent (name,
  model, owned paths). `{{OWNER_COMMS_LINE}}` is the side-channel line given in the
  template's comment if the Telegram bridge is being set up, else omit it. Rules only,
  under 130 lines: history and reasons go to `docs/decisions.md`, detail to `docs/` and
  `.claude/rules/`.
- **`.claude/agents/*.md`**: one file per builder role from step 1, generated from
  `${CLAUDE_PLUGIN_ROOT}/templates/agent-roster/generic-builder.md` (models set
  explicitly — builders `sonnet`). Do NOT add `reviewer`/`researcher`/`systems-integrator`/
  `creative-director` agent files here — those ship with the harness plugin itself and
  are already spawnable as `harness:reviewer` / `harness:researcher` /
  `harness:systems-integrator` / `harness:creative-director` once the plugin is
  installed; project-local copies would just fork them out of sync with plugin updates.
  The lead session runs each wave itself; no role sits between it and the builders.
  `creative-director` is opt-in: only wire it into the project's `CLAUDE.md` roster (and
  generate the project-local design-authoring roles it judges) if the project wants a
  design-judgment seat; it is not part of the default roster.
- **`.claude/harness.env`**: from `${CLAUDE_PLUGIN_ROOT}/templates/harness.env.example` —
  set real `TEST_COMMAND`/`LINT_COMMAND`/`PROJECT_NAME`/`DEFAULT_BRANCH` for the detected
  stack, and **always set `BUILD_RELEVANT_PATTERNS`** to this stack's source/build paths
  (e.g. `"src/ package.json"`, `"app/ build.gradle.kts gradlew"`, `"src/ Cargo.toml"`).
  Set `SCOPED_TEST_COMMAND` to the runner's related-tests mode when it has one (vitest
  `related`, jest `--findRelatedTests`); it is what the per-turn gate runs, so several
  agents on one machine do not each run the full suite.
  Left empty, the Stop gate runs the full `TEST_COMMAND` at the end of every turn that
  changed *any* file — including docs-only and harness-only sessions. Set
  `PROTECTED_PATHS` too if the interview surfaced a secrets/credentials directory.
- **`docs/decisions.md`**: seed from
  `${CLAUDE_PLUGIN_ROOT}/templates/decisions.md.template` if it doesn't exist; if it
  does, append the seed entry.
- **`.claude/agent-sessions.md`**: seed from
  `${CLAUDE_PLUGIN_ROOT}/templates/agent-sessions.md.template` if it doesn't exist.
- **`docs/roadmap.md`**: a short phase skeleton if the project wants one (optional —
  skip if the interview says no phased roadmap is wanted).

## 3. Initialize

- `git init` if the directory isn't a repo yet.
- **Trust this project for the Stop gate.** The gate executes `TEST_COMMAND` from a file
  inside the repo, so it refuses to run until the project's absolute path is listed in a
  USER-level trust file that no repo can write to. Do this now, or the gate stays inert:
  ```bash
  mkdir -p ~/.config/claude-harness
  touch ~/.config/claude-harness/trusted-projects
  chmod 600 ~/.config/claude-harness/trusted-projects
  p="$(pwd -P)"    # must be the absolute PHYSICAL path — the hook compares exact lines
  grep -qxF "$p" ~/.config/claude-harness/trusted-projects \
    || echo "$p" >> ~/.config/claude-harness/trusted-projects
  ```
  Never add a path you didn't just bind yourself, and never script this for another repo.
- `gh repo create` if there's no GitHub remote — ask private/public via
  AskUserQuestion if not already stated.
- Labels: `agent:<role>` per generated builder plus `reviewer`/`researcher`/`systems-integrator`,
  and `type:feedback`.
- Milestones if a roadmap was seeded (one per phase).
- Branch protection on the default branch (require PR, no direct pushes) if the repo
  has a remote.
- Suggest a permissions allowlist for `.claude/settings.json` (safe read-only `gh`/`git`
  commands, the project's test/lint command) — apply if the interview OK'd it.

## 4. Verify the gates — do not skip

Run `/harness:verify-gates` now.

**Known gotcha**: plugin/hook *registration* is not hot-reloaded — if the harness plugin
was installed or enabled during this same session, its hooks are not live yet and
verification must run after a restart. `.claude/harness.env` itself IS re-read by the
hook scripts on every invocation, so a harness.env you just wrote needs no restart.

So: if the plugin was already enabled when this session started, run
`/harness:verify-gates` now. Otherwise tell the user: "Restart Claude Code in this
project, then run `/harness:verify-gates`." Either way, do not declare harness-init done
until that pass has actually run and reported PASS for all three gates.

## 5. Checkpoint

Write the seeded `docs/decisions.md` entry (step 2) recording what was set up: stack
detected, builders generated, gates configured (including that this project's path was
added to `~/.config/claude-harness/trusted-projects`, which is machine-local — a fresh
clone on another machine must repeat that step), Telegram status, GitHub setup summary.
Commit it.

## Closing notes (tell the user)

- Safe to run `/init` later to refresh the descriptive sections of `CLAUDE.md`; the
  harness operating model lives in `.claude/rules/` and the plugin's own
  `${CLAUDE_PLUGIN_ROOT}/rules/`, which `/init` does not touch.
- Restart-then-`/harness:verify-gates` if you haven't already done so this session.

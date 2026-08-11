# claude-harness

A portable "agentic harness" for running multi-agent Claude Code projects: a thin
owner-facing lead, fresh wave-lead delegation per work batch, a review-and-fix reviewer,
deterministic quality gates (test/lint gate, destructive-command blocker, test-weakening
diff guard), an optional Telegram bridge to reach a human owner mid-wave, and a
bootstrap skill that binds all of it into a new (or existing) project in one pass.

Extracted from a real multi-agent Android/Firebase project after the process had proven
itself there, then generalized so any project can install it instead of re-deriving the
same operating model from scratch.

## Install

```
/plugin marketplace add Tom090/claude-harness
/plugin install harness@claude-harness
```

## Quickstart

In a new (or existing) project, once the plugin is installed:

```
/harness:harness-init
```

This detects your stack (or asks), generates a builder-agent roster suited to it,
writes `.claude/harness.env` and the prescriptive half of `CLAUDE.md`, sets up GitHub
scaffolding (labels, milestones, branch protection), and verifies the deterministic
gates with synthetic triggers. It complements Claude Code's built-in `/init` rather than
fighting it — see `plugins/harness/skills/harness-init/SKILL.md` for the split.

Hook/settings changes are not hot-reloaded mid-session: after `harness-init`, restart
Claude Code in the project and run `/harness:verify-gates` to confirm the gates are
actually live.

## Layout

```
claude-harness/
├── .claude-plugin/marketplace.json   # this marketplace; room for more plugins later
├── plugins/harness/
│   ├── .claude-plugin/plugin.json
│   ├── skills/         # harness-init, verify-gates, checkpoint, project-status,
│   │                    # ask-owner, validate, review-pr
│   ├── agents/         # wave-lead, reviewer, researcher (builder agents are NOT
│   │                    # shipped here — they're generated per project, see below)
│   ├── hooks/hooks.json
│   ├── scripts/        # stop-test-gate, block-destructive-bash, check-test-weakening,
│   │                    # telegram-owner, wave-watchdog
│   ├── rules/           # token-efficiency.md, operating-model.md — reference docs the
│   │                    # skills/agents cite instead of re-deriving
│   └── templates/       # what harness-init instantiates into a new project:
│                        # CLAUDE.md.template, decisions.md.template,
│                        # agent-sessions.md.template, harness.env.example,
│                        # agent-roster/ (generic-builder.md + specialization notes),
│                        # examples/ux-verification-mobile.md (a real worked example,
│                        # not a plugin rule)
└── README.md
```

## Why hooks are inert until you run harness-init

The Stop-hook test gate and the destructive-command blocker fire in **every** project
that has this plugin enabled — including ones that haven't been bound yet. Both hooks
read `.claude/harness.env` and silently no-op (exit 0, no output) if it's absent, so
installing the plugin is safe before you've decided anything about a given repo. Once the
file exists the blocker is live; the Stop gate additionally needs `TEST_COMMAND`, and
`BUILD_RELEVANT_PATTERNS` is what keeps it off docs-only sessions.

## Upstreaming improvements

If a project using this harness finds a better version of a script, skill, or rule —
generalize the fix (strip project-specific paths/names the same way this repo was
extracted) and open a PR back here. Keep project-specific bindings (the generated
`CLAUDE.md`, builder roster, `.claude/harness.env`) in the project itself; only portable
mechanism belongs in this repo.

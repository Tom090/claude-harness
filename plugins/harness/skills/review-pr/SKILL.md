---
name: review-pr
description: Review a pull request against the project's standards, review-and-fix style.
---
# Review a PR

Usage: give a PR number. This is the manual/ad-hoc entry point to the same checklist the
`reviewer` agent runs — see `rules/operating-model.md` § Review-and-fix for the full
policy (mechanical fixes land on the branch test-first; only design-level rework routes
back to a builder).

```bash
gh pr view <n> --json files,title,body,additions,deletions
gh pr diff <n>
```

Check, most important first:
1. Correctness and that it does what the linked issue asked.
2. Any non-negotiable invariants this project's `CLAUDE.md` declares (a safety layer,
   a secrets boundary, a design-system rule) are preserved.
3. Style per `CLAUDE.md` + `.claude/rules/*`; `TEST_COMMAND`/`LINT_COMMAND` from
   `.claude/harness.env` pass; meaningful coverage for new logic.
4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/check-test-weakening.sh --pr <n>` — a flagged
   deletion/disable/shrink with no ruling reference in the PR body is a blocking finding.
5. No debug code, stray TODOs, or committed secrets.

For anything mechanically fixable: encode it as a failing test/row first, fix it, prove
it green, commit on the PR branch. Post ONE consolidated PR comment (findings, what was
fixed, what's routed back and why): `gh pr review <n> --comment -b "..."`. Approve only
when the checklist passes on the final head.

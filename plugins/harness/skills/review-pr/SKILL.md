---
name: review-pr
description: Review a pull request against the project's standards, review-and-fix style.
---
# Review a PR

Usage: give a PR number. This is the manual/ad-hoc entry point to the same checklist the
`harness:reviewer` agent runs — see `${CLAUDE_PLUGIN_ROOT}/rules/operating-model.md`
§ Review for the full policy (mechanical fixes land on the branch test-first;
only design-level rework routes back to a builder).

```bash
gh pr view <n> --json files,title,body,additions,deletions
gh pr diff <n>
gh pr checkout <n>   # the test-weakening guard (step 4) diffs the LOCAL branch
```

Check, most important first:
1. Correctness and that it does what the linked issue asked.
2. Any non-negotiable invariants this project's `CLAUDE.md` declares (a safety layer,
   a secrets boundary, a design-system rule) are preserved.
3. Style per `CLAUDE.md` + `.claude/rules/*`; `TEST_COMMAND`/`LINT_COMMAND` from
   `.claude/harness.env` pass; meaningful coverage for new logic.
4. With the PR branch checked out, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-test-weakening.sh --pr <n>` (`--pr` supplies the
   PR body for the ruling check; the diff comes from the local branch) — a flagged
   deletion/disable/shrink with no ruling reference in the PR body is a blocking
   finding.
5. No debug code, stray TODOs, or committed secrets.

For anything mechanically fixable: encode it as a failing test/row first, fix it, prove
it green, commit on the PR branch. Post ONE consolidated PR comment (findings, what was
fixed, what's routed back and why): `gh pr review <n> --comment -b "..."`. Approve only
when the checklist passes on the final head.

---
name: validate
description: Build, lint, and test the project before opening a PR.
---
# Validate

Read `.claude/harness.env` for `TEST_COMMAND` and `LINT_COMMAND` and run them. Run
`LINT_COMMAND` only if `TEST_COMMAND` does not already contain it. Always the full
`TEST_COMMAND`, never `SCOPED_TEST_COMMAND`: this is the one full run per PR.

```bash
# shellcheck disable=SC1091
source .claude/harness.env 2>/dev/null
eval "$TEST_COMMAND" 2>&1 | tail -40
case "$TEST_COMMAND" in *"$LINT_COMMAND"*) ;; *) [ -n "${LINT_COMMAND:-}" ] && eval "$LINT_COMMAND" 2>&1 | tail -20 ;; esac
```

If `harness.env` is missing, run the stack's obvious test and lint commands and say the
file is missing. If lint supports auto-fix, apply it and re-run. If the suite times out
or fails on an unrelated slow test while other agents are running, wait and retry once;
do not diagnose infrastructure. Report PASS or FAIL with the key errors only. Do not open
a PR until this passes.

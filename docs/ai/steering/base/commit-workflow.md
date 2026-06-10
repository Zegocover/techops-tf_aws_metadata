---
version: 1.2
last_reviewed: 2026-06-02
---

# Commit Workflow Standards

Conventions for how Claude interacts with git commits and pre-commit hooks — the governing philosophy is: commit-time hooks are the repo's quality gates; run them on every commit, fix failures before retrying, never bypass them.

Apply these rules whenever creating a git commit in any repository, regardless of stack.

The rules are framework-agnostic. Hook frameworks vary by ecosystem — `pre-commit` (`.pre-commit-config.yaml`, common in Python), `husky` and `lint-staged` (JS/TypeScript), `lefthook` (Go and others), Gradle/Git hooks (Android), or raw executable `.git/hooks/pre-commit` — and Rules 7–8 already cover each plus the no-framework case. The hook *tools* in the examples below (`ruff`, `mypy`) are illustrative of one stack; read them as a stand-in for whatever the repo runs — `eslint`/`prettier`, `ktlint`/`detekt`, `swiftlint`, `scalafmt`, etc. The workflow (don't bypass, fix-and-retry, re-stage, don't amend) is identical across all of them.

PR structure after committing is covered in [pull-requests.md](pull-requests.md).

## Rules at a Glance

1. **Never use `--no-verify`.** Never pass `--no-verify` to `git commit` unless the user explicitly asks for it — pre-commit hooks are the repo's chosen quality gates and bypassing them defeats their purpose, allowing lint violations, formatting drift, and type errors to land in the history.
2. **Fix and retry on hook failure.** When a pre-commit hook fails, the commit did not happen — read the hook's error output, diagnose the root cause, fix the issue, and re-stage all files the hook touched (including any the hook auto-formatted). Re-stage is critical because the hook may have modified working-tree files without updating the index, and stale staged content will reproduce the same failure.
3. **Preserve the commit message on retry.** Reuse the original commit message for every retry attempt — the intent has not changed, only the code needed fixing.
4. **Never amend after a hook failure.** Always create a new commit attempt after fixing a hook failure — never use `--amend`, because the failed commit was never created and amending would modify the previous (unrelated) commit, risking data loss.
5. **Retry budget with progress condition.** Make at most five commit attempts (the original plus four retries) for the same logical change — stop early if the same hook reports the same error on consecutive attempts (the fix is not converging), and stop unconditionally after five attempts, surfacing the failure to the user because the issue likely requires manual intervention or context Claude does not have.
6. **Surface hook failures to the user.** Show the user the hook's error output and explain what was caught and what was fixed on each retry — silent fixes hide quality-gate activity and prevent the user from spotting systemic issues in their codebase.
7. **Do not install, modify, or remove hooks.** Never run `pre-commit install` / `husky install` / `lefthook install`, edit `.pre-commit-config.yaml`, `.husky/` (e.g. `.husky/pre-commit`), or `lefthook.yml` / `.lefthook.yml`, or alter files in `.git/hooks/` — hook configuration is a repo-owner decision, and changing it without being asked modifies the project's quality gates.
8. **Graceful handling when no hooks exist.** If a repo has no hook framework configuration (no `.pre-commit-config.yaml`, `.husky/`, `lefthook.yml` / `.lefthook.yml`, or executable `.git/hooks/pre-commit`), proceed with the commit normally — do not warn about missing hooks, suggest installing a framework, or treat the situation as degraded. If a framework config exists but hooks are not installed locally (e.g. `.husky/` present but `git commit` runs no hooks), surface this to the user rather than silently committing without coverage.

## Never use `--no-verify`

The prohibition is absolute unless the user explicitly opts in with a direct request. "The hook is slow", "I'll fix it later", and "it's just a formatting change" are not valid reasons — treat any temptation to skip as a signal to fix the underlying failure instead.

```shell
# good — commit runs hooks automatically
git commit -m "AIDEV-51: Add commit workflow standard"

# bad — bypasses the repo's quality gates
git commit --no-verify -m "AIDEV-51: Add commit workflow standard"

# good — user explicitly asked to skip
# (user said "commit with --no-verify, the secret-scan hook is misconfigured")
git commit --no-verify -m "AIDEV-51: Add commit workflow standard"
```

## Fix and retry on hook failure

Re-staging is the critical step. Hooks often run formatters that modify files in the working tree without updating the index. After the hook (or Claude) fixes the issue, re-stage every file the hook touched — not just the files Claude edited — or the same failure recurs.

```shell
# good — hook fails, fix applied, all modified files re-staged, new commit created
git commit -m "AIDEV-51: Add commit workflow standard"
# pre-commit hook fails: "ruff found 2 fixable violations"
# fix the violations (or the hook's auto-formatter already did)
# re-stage ALL files the hook touched, not just the ones Claude edited
git add docs/ai/steering/base/commit-workflow.md src/utils.py
git commit -m "AIDEV-51: Add commit workflow standard"

# bad — hook fails, bypass instead of fix
git commit -m "AIDEV-51: Add commit workflow standard"
# pre-commit hook fails: "ruff found 2 fixable violations"
git commit --no-verify -m "AIDEV-51: Add commit workflow standard"
```

## Preserve the commit message on retry

Reuse the exact original message — including multi-line bodies and trailers like `Co-Authored-By` — on every retry. Pass the message via a HEREDOC or variable to avoid retyping and accidental edits between attempts.

```shell
# good — same message on retry, passed via variable to avoid drift
MSG="$(cat <<'EOF'
AIDEV-51: Add commit workflow standard

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git commit -m "$MSG"
# hook fails, fix applied, re-staged
git commit -m "$MSG"

# bad — message changed between attempts
git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails, fix applied, re-staged
git commit -m "AIDEV-51: Fix lint issues in commit workflow standard"
```

## Never amend after a hook failure

A failed commit was never created — `--amend` after a hook failure modifies the previous (unrelated) commit, silently rewriting history and potentially destroying work.

```shell
# good — new commit attempt after hook failure
git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails — no commit object was created
# fix the issue, re-stage
git commit -m "AIDEV-51: Add commit workflow standard"

# bad — amend modifies the PREVIOUS commit, not the failed one
git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails — no commit object was created
# fix the issue, re-stage
git commit --amend -m "AIDEV-51: Add commit workflow standard"
# ↑ this rewrites the commit BEFORE the one you intended
```

## Retry budget with progress condition

Two stopping rules:

- **Hard cap:** five attempts (the original plus four retries) for the same logical change.
- **Stall detection:** if the same hook reports the same error on two consecutive attempts, stop immediately — the fix is not converging.

After exhausting the budget (or stalling), report the failure to the user with the full hook output. Do not attempt workarounds such as disabling the hook, modifying hook configuration, or restructuring the commit to avoid triggering the hook.

Common unfixable cases: hooks that require authentication tokens, hooks that validate against a remote service, hooks with bugs that reject all input.

```shell
# good — different error each attempt, budget allows continued progress
git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails: ruff — unused import → fix, re-stage
git add src/main.py && git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails: mypy — type error exposed by import removal → fix, re-stage
git add src/main.py && git commit -m "AIDEV-51: Add commit workflow standard"
# succeeds on attempt 3

# good — same error twice in a row, stop early (stall detected)
git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails: secret-scan — token detected in config.py → redact, re-stage
git add config.py && git commit -m "AIDEV-51: Add commit workflow standard"
# hook fails: secret-scan — same token, same file → stop and surface to user

# bad — keep retrying the same failure past the stall condition
# (third attempt at the same secret-scan error)
git add config.py && git commit -m "AIDEV-51: Add commit workflow standard"
```

## Surface hook failures to the user

On every retry, report: which hook failed, the error it produced, the fix applied, and the retry outcome. Do not silently fix and re-commit.

```text
# good — surface the failure, the fix, and the outcome
The ruff hook failed: "F401 `os` imported but unused in src/main.py:3".
Removed the unused import on line 3 and re-staged src/main.py.
Retrying commit… succeeded on attempt 2.

# bad — silently fix and say nothing
(hook fails, Claude fixes the import and re-commits without telling the user)
```

## Do not install, modify, or remove hooks

Work with whatever hooks the repo already has. If no hooks are configured, do not add them. If hooks are misconfigured, report the issue to the user rather than fixing the configuration.

Off-limits actions: `pre-commit install`, editing `.pre-commit-config.yaml` / `.husky/` / `.lefthook.yml`, writing to `.git/hooks/`.

```shell
# good — report the misconfiguration, let the user decide
# "The pre-commit hooks are not installed locally.
#  Run 'pre-commit install' if you'd like hooks to run on each commit."

# bad — installing or modifying hook configuration
pre-commit install
echo "#!/bin/sh\nruff check ." > .git/hooks/pre-commit
```

## Graceful handling when no hooks exist

Two distinct cases:

- **No framework configured** (no `.pre-commit-config.yaml`, `.husky/`, `lefthook.yml` / `.lefthook.yml`, or executable `.git/hooks/pre-commit`): commit normally. Do not warn about missing hooks, suggest installing a framework, or treat the absence as degraded.
- **Framework configured but not installed locally** (e.g. `.pre-commit-config.yaml` exists but `git commit` runs no hooks): surface this to the user so they can decide whether to install. Do not install the framework yourself (see Rule 7).

## Red Flags — Stop and Reconsider

If any of these thoughts cross your mind, stop — you are about to rationalise away a rule.

- "The hook is slow and this is just a formatting change, so I'll pass `--no-verify` this once."
- "The hook failure looks unrelated to my change, so it's safe to skip verification."
- "The commit failed, so I'll `--amend` to keep my message instead of retyping it."
- "I already fixed the issue, so amending the last commit is cleaner than making a new one."
- "I'll temporarily disable the hook to get unblocked and re-enable it after."

| Rationalisation | Rule it violates | Real-world consequence |
|---|---|---|
| "The hook is slow and this is just a formatting change, so I'll pass `--no-verify` this once." | Rule 1 — Never use `--no-verify` | Lint violations, formatting drift, or type errors bypass the quality gate and land in history, surfacing as CI failures or review churn later. |
| "The hook failure looks unrelated to my change, so it's safe to skip verification." | Rule 1 — Never use `--no-verify` | A real defect the hook caught is committed unexamined; "unrelated" failures are frequently the hook correctly flagging the agent's own staged changes. |
| "The commit failed, so I'll `--amend` to keep my message instead of retyping it." | Rule 4 — Never amend after a hook failure | The failed commit was never created, so `--amend` rewrites the previous, unrelated commit — silently destroying its content and corrupting history. |
| "I already fixed the issue, so amending the last commit is cleaner than making a new one." | Rule 4 — Never amend after a hook failure | The "last commit" is not the failed attempt but the prior good commit; amending it mixes unrelated changes and risks data loss. |
| "I'll temporarily disable the hook to get unblocked and re-enable it after." | Rule 1 — Never use `--no-verify` | The bypass becomes permanent in practice, the gate is defeated for that commit, and the change ships without the validation the repo owner mandated. |

## See Also

- [pull-requests.md](pull-requests.md) — PR structure conventions; sits downstream of the commit workflow.

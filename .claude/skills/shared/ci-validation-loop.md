# CI validation fix loop — shared across skills

This file is referenced by calling skills (e.g. `.claude/skills/implement/SKILL.md`,
`.claude/skills/fix-pr-comments/SKILL.md`, `.claude/skills/fix-buildkite/SKILL.md`). It
contains the detailed steps (Step 1, Step 2, Step 3) and the per-cycle commit
flow for the CI validation and fix loop.

## Caller contract

The calling skill must fill the following placeholders before executing:

| Placeholder | Required | Description |
|-------------|----------|-------------|
| `{ticket}` | yes | JIRA ticket key (e.g. `AIDEV-77`) |
| `{branch}` | yes | Git branch name |
| `{changed file(s)}` | yes | Space-separated list of files the calling skill changed |
| `{task-nn}` | no | Task number segment (e.g. `TASK-01`). Omit when the calling skill has no task number. |

### Return verdicts

When the loop exits, it returns one of two verdicts to the calling skill:

- **`verdict: passed`** — CI validation passed (or was a no-op). The calling
  skill may proceed to its next stage.
- **`verdict: failed-max-iterations`** — Either the maximum of 5 iterations was
  exhausted and CI is still failing, OR an authentication precondition
  short-circuited the loop (see Step 2). The return includes failure details:
  - `failing_command` — the command that failed
  - `most_recent_output` — the full output from the most recent failing run
  - On an auth short-circuit ONLY: a distinct marker LINE
    `precondition: authentication` returned alongside the verdict (NOT embedded
    inside `most_recent_output`), and `most_recent_output` ends with exactly
    one appended line of the form
    `precondition: authentication — remediation: {documented path}`.

The `failed-max-iterations` terminal verdict vocabulary is unchanged — the
`precondition: authentication` marker is additive.

On `failed-max-iterations`, the calling skill owns the user-facing response.
This document does not print a report, halt, re-run, or emit any resume
affordance — it returns the failure details (and, on an auth short-circuit,
the marker) and control to the caller.

---

### Step 1 — Spawn CI validation agent

Spawn an Agent. Fill every placeholder before sending.

```
You are running the `ci-validation` skill.
Read `.claude/skills/ci-validation/SKILL.md` and execute it from Stage 1.
Do not ask questions — all context is below.

Ticket: {ticket}
Branch: {branch}
Changed file(s): {changed file(s)}

Discover the repo's CI commands, run Stage 3 autonomous scope validation
against the changed file(s) above (falling back to the git-diff derivation if
the list is empty/absent), execute the selected commands, and return:
1. A verdict line: either "verdict: passed" or "verdict: failed".
2. The per-command report listing every command and its outcome (passed, failed, etc.).
3. If failed: the full command output and the failing command. If the failure
   is an authentication/credentials precondition (Stage 4.2), include a
   distinct line "precondition: authentication" and the resolved remediation
   path.
4. A brief summary of what ran.
```

Wait for the sub-agent to return.

**No-verdict spawn return.** If the spawned agent returns no verdict at all
(crash, context-limit, hang, or any output without a `verdict:` line), treat
this iteration as `verdict: failed` with the spawn error captured as
`most_recent_output`, and proceed through the normal Step 2 / failed-max-iterations
path below. Do not abort the loop.

### Step 2 — Read verdict and commit

Commit the current state of the changed files, regardless of verdict. This
per-cycle commit MUST happen here, BEFORE the auth-marker short-circuit branch
below — the auth path must not drop the commit for the cycle that ran. Only
commit if there are actual changes:

When `{task-nn}` is present:

```bash
git add -- {changed file(s)}
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{ticket} {task-nn}: CI validation cycle {N} — {PASS|FAIL}

{one-line description of what changed this cycle}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

When `{task-nn}` is absent:

```bash
git add -- {changed file(s)}
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{ticket}: CI validation cycle {N} — {PASS|FAIL}

{one-line description of what changed this cycle}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**Per-cycle commit failure is a no-op-and-continue.** If the commit above fails
(nothing staged, or any git error), treat it as a no-op and continue to the
verdict handling below. Do NOT abort the loop on a commit failure.

After the per-cycle commit, handle the verdict:

**The verdict the loop RETURNS is not the same vocabulary as the inner
`ci-validation` skill's Stage 4 verdict.** The spawned sub-agent (Step 1)
returns `verdict: passed` or `verdict: failed` (Interface A). The loop
translates that into its own return vocabulary (Interface B): `verdict: passed`
or `verdict: failed-max-iterations`. There is NO `verdict: failed` at the loop
boundary — a bare `verdict: failed` from the sub-agent MUST be translated to
`verdict: failed-max-iterations` (on an auth short-circuit or on exhausting 5
iterations) before the loop returns. Do NOT surface the sub-agent's
`verdict: failed` as the loop's return line.

- **verdict: passed** → print the sub-agent's per-command report verbatim to the user (so every command's outcome is visible, not silently dropped), then exit the loop. Return `verdict: passed` to the calling skill.
- **Auth short-circuit — verdict: failed carrying a `precondition: authentication` marker line** → STOP the loop immediately at this iteration. Do NOT spawn the code fixer (Step 3) and do NOT run any further iterations — an auth precondition is an environment problem the fixer cannot fix, and the short-circuit consumes no remaining iteration budget. Return `verdict: failed-max-iterations` to the calling skill (the loop's return LINE is the literal `verdict: failed-max-iterations` — NOT the sub-agent's `verdict: failed`) with:
  - `failing_command`: the command that failed
  - a distinct marker LINE `precondition: authentication` (alongside the verdict, NOT embedded inside `most_recent_output`)
  - `most_recent_output`: the full output from the most recent run, ending with exactly one appended line `precondition: authentication — remediation: {documented path}` (the path resolved per family by the sub-agent; on a dual match it carries family (a)'s path)

  This branch contains NO resume affordance and NO re-run logic — re-run lives only in the caller. The loop just short-circuits and returns.
- **verdict: failed with NO auth marker** → continue to Step 3.

If this is iteration 5 and verdict is still failed (with no auth marker), exit
the loop. Return `verdict: failed-max-iterations` to the calling skill with the
following details:

- `failing_command`: the command that failed
- `most_recent_output`: the full output from the most recent run

Each cycle's state is preserved as a commit; the calling skill or the
developer can inspect `git log` to walk the iteration history.

On `failed-max-iterations` (whether from an auth short-circuit or from
exhausting 5 iterations), do not print a user-facing report and do not halt.
Return control to the calling skill immediately so it can decide the UX.

### Step 3 — Spawn CI fixer agent

Spawn a general-purpose Agent. Fill every placeholder before sending.

```
You are fixing code that failed a CI validation command.
Do not ask questions — apply the fix and return.

Failing command: {command}
Exit code: {exit code}

Full output:
{command output verbatim}

Changed file(s): {changed file(s)}

Read the failing output carefully. Identify what needs to change in the
changed files to make the command pass. Apply the minimal fix — do not
refactor, do not add tests, do not change anything unrelated to the failure.

After making the change, return:
1. A brief description of what you changed (one or two sentences).
2. Which files were modified.
```

Wait for the fixer agent to return. Then return to Step 1.

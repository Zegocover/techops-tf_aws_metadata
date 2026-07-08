---
name: zego-fix-buildkite
description: You MUST use this when the user asks to diagnose, fix, or retry failed Buildkite CI builds.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
---

You are the orchestrator for the `zego-fix-buildkite` skill. You receive a single
argument: a Buildkite build URL or bare build number. You do not write code or
post comments yourself — you brief sub-agents and orchestrate results.

---

## Input

The build input is the first argument passed to this skill. It must be either:

- A full Buildkite build URL (e.g.
  `https://buildkite.com/org/pipeline/builds/123`)
- A bare build number (digits only, e.g. `123`)

If no argument was provided or the value is neither a valid URL nor digits-only,
stop:

> zego-fix-buildkite requires a Buildkite build URL or build number as its argument
> (e.g. `/zego-fix-buildkite https://buildkite.com/org/pipeline/builds/123` or
> `/zego-fix-buildkite 123`).

Let `BUILD_INPUT` = the supplied argument for all subsequent steps.

### Parse the build input

**If `BUILD_INPUT` is a full URL:**

1. Strip any query parameters (everything from `?` onward).
2. Extract `ORG`, `PIPELINE`, and `BUILD_NUMBER` from the path. The URL may
   contain trailing path segments after the build number (e.g. `/canvas`,
   `/waterfall`) — ignore everything after `BUILD_NUMBER`:
   `https://buildkite.com/{ORG}/{PIPELINE}/builds/{BUILD_NUMBER}[/...]`
3. If the URL does not match this pattern, stop:
   > Could not parse Buildkite URL: `{BUILD_INPUT}`. Expected format:
   > `https://buildkite.com/org/pipeline/builds/123`

**If `BUILD_INPUT` is a bare build number (digits only):**

1. **Get the Buildkite org** by calling `user_token_organization` via MCP. This
   returns the org slug (e.g. `tego`) associated with the user's token. Set
   `ORG` to the returned value.

   If `user_token_organization` fails, stop:

   > Could not determine Buildkite organisation from your token.
   > Please provide a full Buildkite URL instead
   > (e.g. `https://buildkite.com/org/pipeline/builds/123`).

2. **Get the repo name** from the git remote:

   ```bash
   git remote get-url origin
   ```

   Extract the **repo name only** (not the org) from the remote URL: strip any
   scheme, host, and org prefix, strip a trailing `.git` suffix if present, and
   lower-case the result. For example, all of these produce `repo`:

   - `git@github.com:Zegocover/Repo.git` → `repo`
   - `https://github.com/Zegocover/Repo.git` → `repo`
   - `https://github.com/Zegocover/Repo` → `repo`

3. **Find the pipeline** by calling `get_pipeline` via MCP with `org_slug` set
   to `ORG` and `pipeline_slug` set to the repo name. Buildkite pipeline slugs
   typically match the repository name. If `get_pipeline` succeeds, set
   `PIPELINE` to the repo name. If it fails (404 / not found), stop:

   > Could not find pipeline `{repo_name}` in org `{ORG}`.
   > Please provide a full Buildkite URL instead
   > (e.g. `https://buildkite.com/org/pipeline/builds/123`).

Set `BUILD_NUMBER` = `BUILD_INPUT`.

---

## Gate 1 — Triage

### Stage 1 — Fetch failed jobs and extract error context

Call `get_build` via MCP with `ORG`, `PIPELINE`, and `BUILD_NUMBER`.

**If the `get_build` call fails because the Buildkite MCP server is not
installed or not reachable**, stop:

> The Buildkite MCP server is not available. Install it with:
>
> ```
> claude mcp add --transport http buildkite https://mcp.buildkite.com/mcp
> ```
>
> Then re-run this skill.

**If `get_build` succeeds but the build has no failed jobs**, report:

> No failed jobs found in build #{BUILD_NUMBER}. Nothing to fix.

Then exit cleanly.

**If `get_build` returns failed jobs**, collect each failed job into a list.
For each failed job:

1. Record `job_id`, `job_name`, `exit_status`, and `state`.
2. Call `tail_logs` via MCP to get the last portion of the job log.
3. Call `search_logs` via MCP with relevant error patterns (e.g. `error`,
   `FAILED`, `Exception`, `assert`) to extract targeted error context.
4. Store the combined error context for each job as `error_context`.

If a `tail_logs` or `search_logs` call fails for a specific job, record the
error for that job and continue with remaining jobs. Do not stop the skill.

---

### Stage 2 — Classify failures

Read each failed job's `error_context` and classify it using these rules:

| Classification | Apply when |
|----------------|------------|
| `code-error`   | The failure is caused by a bug, type error, missing import, logic error, or other issue in the application or test code that requires a code change to fix |
| `flaky-test`   | The failure appears to be a flaky or intermittent test — signals: timeout with no code change, non-deterministic assertion, network/service dependency failure in tests, "retry" or "flaky" in the test name or log |
| `infra-error`  | The failure is caused by infrastructure — signals: Docker pull failure, agent disconnected, out of disk/memory, dependency installation failure, build agent timeout, permission denied on CI resources |

For each entry, also write a one-line reason for the classification.

---

### Stage 3 — Present triage plan and confirm

Present the classification plan as a table:

```
Build #{BUILD_NUMBER} — {N} failed job(s)

| # | Job Name            | Exit Status | Classification | Reason                          |
|---|---------------------|-------------|----------------|---------------------------------|
| 1 | {job_name}          | {exit}      | code-error     | {one-line reason}               |
| 2 | {job_name}          | {exit}      | flaky-test     | {one-line reason}               |
| 3 | {job_name}          | {exit}      | infra-error    | {one-line reason}               |
| ...

Code errors to fix: {count code-error}
Flaky tests to retry: {count flaky-test}
Infra errors to skip: {count infra-error}

Shall I proceed? You can override any classification before I start
(e.g. "change job 2 to code-error — this is a real test failure").
```

**Wait for the developer's response.** Apply any overrides to the plan. The
confirmed plan is authoritative for all subsequent stages.

**`infra-error` entries are excluded from all further processing.** After
confirmation, if any `infra-error` entries exist, report:

> Skipping {count} infra-error job(s) — please raise an issue for:
> {list each infra-error job name, one per line}

If all entries are `infra-error` after confirmation, skip Gate 2 and Gate 3
entirely — proceed directly to Stage 11 (summary). No code changes or commits
are needed.

If there are no `code-error` entries after confirmation (only `flaky-test` and
`infra-error`), Gate 2 will handle retries and skip the implement flow.

---

## Gate 2 — Act

### Stage 4 — Retry flaky-test entries

For each `flaky-test` entry, call `retry_job` via MCP with the job's `job_id`.

If a `retry_job` call fails for a specific job, record the error for that job
(do not stop the skill) and surface it:

> retry_job failed for "{job_name}": {error message}

After all retries are attempted, report a summary:

```
Flaky-test retries:
| # | Job Name            | Retry Result |
|---|---------------------|--------------|
| 1 | {job_name}          | retried      |
| 2 | {job_name}          | retry-failed |
```

**If no `code-error` entries remain** (all failures were `flaky-test` or
`infra-error`), skip the implement flow entirely and proceed to Stage 11
(summary). No commit is needed.

---

### Stage 5 — Spawn fixer sub-agents (all code-error entries)

Fix all `code-error` entries first, then run a single review cycle. Track a
per-entry result. Initialise `iteration = 1` for the gate.

For each `code-error` entry in sequence:

**If `iteration = 1`**, send a fixer sub-agent with this brief:

```
You are fixing a CI failure from a Buildkite build.
Do not ask questions — diagnose the error and make the targeted fix described
below, then return.

Failed job: {job_name}
Exit status: {exit_status}

Error context from build logs:
---
{error_context}
---

Read the error context carefully. Identify the failing file(s) and location(s)
from the error messages, stack traces, and test output. Make the minimal code
change needed to fix the failure.

Scope constraint: limit all changes to the scope of the error above. Do not
refactor surrounding code, add unrelated tests, or change any file not directly
implicated by the failure. Stay as narrow as possible.

After making the change, return:
1. A brief description of what you changed (one or two sentences).
2. The file(s) modified.
3. Whether any files were modified (yes/no).
```

**If `iteration > 1`**: only process entries that have pending blocker or major
findings from the most recent review. For each such entry, read the most recent
findings file. Each finding is a markdown block headed
`### F{n} — {severity} — {file}:{line}` with `- outcome: pending` beneath it.
Extract every finding where outcome is `pending` AND severity is `blocker` or
`major` AND the finding's file path was touched by this entry's original fix.
Format each as:

```
F{n} ({severity}) — {file}:{line} — {issue} — Suggestion: {suggestion}
```

Then send a fixer sub-agent with this brief:

```
You are fixing a CI failure from a Buildkite build. A previous attempt failed
review. Address the findings listed below in addition to the original error.

Failed job: {job_name}
Exit status: {exit_status}

Error context from build logs:
---
{error_context}
---

Scope constraint: limit all changes to the scope of the error and the findings
below. Do not refactor surrounding code or change any file not directly
implicated.

Previous attempt failed — address these findings:
{formatted F{n} lines, one per line}

After making the change, return:
1. A brief description of what you changed (one or two sentences).
2. The file(s) modified.
3. Whether any files were modified (yes/no).
```

After each fixer returns, run the three-part diff check:

```bash
git diff HEAD
git diff --cached
git status --porcelain
```

If all three are empty, record result `skipped-no-changes` for that entry.
Otherwise record `changes-made`. Continue to the next entry.

---

### Stage 6 — Spawn single review sub-agent

After all fixer agents have run, if every entry recorded `skipped-no-changes`,
proceed directly to Stage 11 (summary) with those results — there are no changes
to commit, validate, or push, so Gate 3 is skipped entirely.

Otherwise, derive `ticket` and `branch` from the current git branch:

```bash
git rev-parse --abbrev-ref HEAD
```

Parse the branch name against `^([A-Z][A-Z0-9]*-[0-9]+)[_-](.+)$`:
- Group 1 → `ticket`
- Group 2 → description slug

Locate the task spec:

```bash
rg -l "^ticket: {ticket}$" docs/tasks/ 2>/dev/null | head -1
```

Locate the design docs (run only when the task spec was found; capture all
matches):

```bash
rg -l "^JIRA: {ticket}$" docs/design/ 2>/dev/null
```

Store the task spec path as `TASK_SPEC_PATH` and all returned design doc paths
as `DESIGN_DOC_PATHS` (a list; empty if none found).

Spawn a fresh Agent with this brief (fill every placeholder; omit the design
doc line entirely if `DESIGN_DOC_PATHS` is empty):

```
You are running the `zego-review` skill.
Read `.claude/skills/zego-review/SKILL.md` and execute it from Stage 1.
Do not ask questions — all context is below.

Ticket: {ticket}
Branch: {branch}

The diff contains fixes for {N} Buildkite CI failures.
Group E will check it against the task spec at {TASK_SPEC_PATH}.

{If DESIGN_DOC_PATHS has one entry:}
A design doc for this ticket exists at {DESIGN_DOC_PATHS[0]} — Group E will load it.

{If DESIGN_DOC_PATHS has more than one entry:}
Design docs for this ticket exist at: {DESIGN_DOC_PATHS list, one path per line} — Group E will load all of them.
```

Wait for the review agent to return the verdict string (`PASS` or `FAIL`) and
the findings file path.

If the review agent errors out, exceeds context, or returns a verdict string
that is not exactly `PASS` or `FAIL`, treat this as a **malformed verdict**.

---

### Stage 7 — Act on verdict

**PASS**: record result `pass` for all entries that had `changes-made`. Proceed
to Stage 8.

**FAIL and iteration < 3**: increment `iteration`. Map each pending
blocker/major finding back to the entry whose fix introduced it (by matching
the finding's file path to the files each entry touched). Return to Stage 5
for entries with mapped findings.

**FAIL and iteration = 3** (max iterations reached): record
`failed-max-iterations` for entries with remaining pending blocker/major
findings. Surface a summary:

> Gate 2 — max iterations reached.
> Remaining findings:
>
> {findings list — one line per pending blocker/major, with entry reference}
>
> Findings file: {path}

Proceed to Stage 8.

**Malformed or missing verdict**: the review agent returned something other
than `PASS` or `FAIL` (e.g. an exception trace, a qualified verdict like
"PASS (with caveats)", or no output at all). Do **not** retry the review.
Record result `review-error` for all entries that had `changes-made`. Surface
the raw review output to the developer:

> Gate 2 — review returned a malformed verdict. Treating as FAIL with no
> actionable findings. The loop will not retry.
>
> Raw review output (truncated to first 40 lines):
>
> {raw output}

Proceed to Stage 8.

---

## Gate 3 — Commit, validate, and push

### Stage 8 — Commit fixer work

After the review passes (or max iterations is reached), present a summary.

```
Gate 2 complete — committing fixer work.

| # | Job Name            | Classification | Result                  |
|---|---------------------|----------------|-------------------------|
| 1 | {job_name}          | code-error     | pass                    |
| 2 | {job_name}          | code-error     | skipped-no-changes      |
| 3 | {job_name}          | flaky-test     | retried                 |
| 4 | {job_name}          | infra-error    | skipped                 |
| 5 | {job_name}          | code-error     | failed-max-iterations   |
```

Proceed immediately (no developer prompt). Derive `ticket` from the current git
branch (same parse as Stage 6).

Commit all staged and unstaged changes from the fixer agents, plus the review
findings file produced by Stage 6 (when one exists):

```bash
git add {files that were changed}
# Only include the findings file if Stage 6 actually ran (i.e. at least one
# entry recorded `changes-made` and a findings file was produced).
git add {findings file path from Stage 6}   # omit this line when Stage 6 was skipped
git commit -m "{ticket}: Fix Buildkite CI failures (build #{BUILD_NUMBER})

{one-line summary per code-error entry whose diff is included in this commit,
prefixed with - . Include entries with result `pass` or `failed-max-iterations`,
but not `skipped-no-changes`. For `failed-max-iterations` entries, append
' (review did not pass — fix incomplete)' to the summary line.}"
```

---

### Stage 9 — CI validation and fix loop

Determine whether CI validation should run. The skip predicate is: **at least
one `code-error` entry recorded `changes-made` or `failed-max-iterations`**.

- If no `code-error` entries exist (all failures were `flaky-test` or
  `infra-error`), skip CI validation entirely and proceed to Stage 11 (summary).
- If every `code-error` entry recorded `skipped-no-changes`, skip CI validation
  entirely and proceed to Stage 11 (summary).
- If at least one `code-error` entry recorded `changes-made` or
  `failed-max-iterations` (including entries where the review did not pass but
  partial changes were committed), run CI validation.

**Note on `failed-max-iterations` entries:** These have partial fixer changes
that are committed but did not pass the Gate 2 review. CI validation still runs
on these changes — the code is being pushed regardless, so it should still pass
CI where possible. If CI validation also fails for these entries, the developer
is informed via the proceed/stop prompt and can decide whether to push.

**Read `.claude/skills/shared/ci-validation-loop.md` and execute Steps 1, 2,
3 defined there.** That document contains the sub-agent prompts, verdict
handling, per-cycle commit flow, and fixer agent instructions for this stage.

Fill the placeholders as follows before executing:

| Placeholder | Value |
|-------------|-------|
| `{ticket}` | the ticket value derived in Stage 6 |
| `{branch}` | the branch value derived in Stage 6 |
| `{changed file(s)}` | all files changed by the fixer agents in Stage 5 |
| `{task-nn}` | omit — not applicable to zego-fix-buildkite |

CI validation commit messages use the format:
`{ticket}: CI validation cycle {N} — {PASS|FAIL}`

**On `verdict: passed`:** proceed to Stage 10 (push).

**On `verdict: failed-max-iterations`:** **check for the
`precondition: authentication` marker line FIRST**, before surfacing the
proceed/stop choice. The two branches below are mutually exclusive; the auth
branch is checked first.

**If the return carries the `precondition: authentication` marker (auth branch):**
emit the reply-continue affordance and end the turn:

> CI validation hit an authentication precondition — an environment problem, not a code failure, so the fix loop stopped without churning the fixer.
>
> Remediation: {remediation path from the marker}.
>
> Authenticate, then reply `continue` and I will re-run CI validation from the top.

**Wait for the developer's `continue` reply.** On reply, RE-RUN the entire CI
loop — a fresh invocation of `skills/shared/ci-validation-loop.md` Steps 1–3
with the iteration counter starting at 1 (the auth short-circuit consumed no
iteration budget, so the fresh loop begins at iteration 1). This re-run logic
lives here in the caller, never in `ci-validation-loop.md`.

**If the return does NOT carry the marker (real code failure — existing behaviour, unchanged):** surface the failure to the developer:

> CI validation failed after 5 fix attempts.
>
> Failing command: `{command}`
> Most recent output is above.
>
> Options:
> 1. **Proceed** — push despite the CI failure.
> 2. **Stop** — do not push. Resolve the failure manually.
>
> Each cycle's state is preserved as a commit; inspect `git log` to walk
> the iteration history.

**Wait for the developer's response.**

- If the developer chooses **Proceed**, continue to Stage 10 (push).
- If the developer chooses **Stop**, halt the skill. The fixer work and up to 5
  CI validation cycle commits are already in your local history (see `git log`).
  Stopping here leaves them committed locally but unpushed — review the log
  before any subsequent `git push`.

---

### Stage 10 — Push

Push the branch:

```bash
git push
```

If `git push` fails, surface the error verbatim. Do not retry automatically.

---

### Stage 11 — Summary

Report:

```
zego-fix-buildkite — build #{BUILD_NUMBER} complete.

| # | Job Name            | Classification | Result                  |
|---|---------------------|----------------|-------------------------|
| 1 | {job_name}          | code-error     | pass                    |
| 2 | {job_name}          | flaky-test     | retried                 |
| 3 | {job_name}          | infra-error    | skipped                 |
| ...

Code errors fixed: {count}
Flaky tests retried: {count}
Infra errors skipped: {count}  (raise an issue for these)
Skipped (no changes): {count}
Failed (max iterations): {count}  {list findings file paths if any}
Failed (retry): {count}

CI validation: passed (after {N} cycle(s)) | failed (overridden by developer) | skipped
```

---

## Rules

- **One mandatory confirmation, one conditional choice.** The triage gate
  (Stage 3) requires explicit developer confirmation before proceeding. There is
  no pre-commit confirmation gate — the skill commits immediately after the
  review verdict. If CI validation fails after max iterations (Stage 9), the
  developer is given a proceed/stop choice.
- **Developer overrides are final.** Do not re-assert the AI's original
  classification after the developer changes it.
- **Sequential fixers, single review.** Run fixer agents for all `code-error`
  entries sequentially, then spawn one review agent for the combined diff. Do
  not interleave fix and review cycles per entry.
- **Fresh review agent every iteration.** Never reuse a review agent across
  iterations.
- **Fixer scope is narrow.** The fixer brief must include the full error context,
  job name, and exit status, and must instruct the agent to limit changes to
  the scope of the error. Do not refactor, add unrelated tests, or change files
  not implicated by the failure.
- **Three-part empty-diff check.** Use `git diff HEAD`, `git diff --cached`,
  and `git status --porcelain`. All three must be empty before recording
  `skipped-no-changes`.
- **Anchored ticket regex.** Use `^ticket: {ticket}$` — not a prefix match.
- **Commit fixer work before CI validation. The confirm-before-commit gate is
  removed — show the summary table but proceed without waiting.**
- **CI validation runs after commit, before push. Max 5 iterations, separate
  counter from the Gate 2 review loop (max 3).**
- **Spawn the CI validation agent from step 1 in a fresh message each
  iteration.**
- **The CI fixer in step 3 applies minimal fixes only.**
- **CI validation failure after max iterations gives the developer a choice:
  proceed or stop.**
- **An auth precondition is checked before the proceed/stop choice.** On
  `failed-max-iterations`, check for the `precondition: authentication` marker
  line FIRST. Present → emit "authenticate, then reply `continue`" and, on the
  reply, re-run the whole CI loop from iteration 1. Absent → the existing
  proceed/stop choice is unchanged.
- **Skip CI validation when no code-error entries recorded changes-made or
  failed-max-iterations.**
- **Push before reporting.** Push in Stage 10, then report in Stage 11. Never
  report a commit SHA before that commit is on the remote.
- **Max 3 gate iterations** — not 5. Each iteration fixes all entries with
  pending findings and re-reviews the combined diff.
- **`infra-error` entries are skipped from all processing after triage.** They
  never enter the implement flow or the retry flow. The developer is told to
  raise an issue.
- **MCP unavailability is detected on the first `get_build` call.** Do not add
  a separate preliminary MCP check. If the call fails due to the MCP not being
  installed, surface the install command and stop.
- **MCP call failures mid-flow are per-job.** If `retry_job` or a log-fetching
  call fails for one job, record the error for that job and continue with
  remaining jobs. Do not stop the skill.
- **Do not open a PR.** The skill commits, pushes, and reports. PR creation is
  done manually or via `zego-create-pr`.
- **Do not post replies or resolve threads.** This is not `zego-fix-pr-comments`.
- **Do not re-trigger the full Buildkite build.** The developer decides when to
  re-run the pipeline.
- **Do not silently drop edge cases.** Every entry must produce a recorded
  result in the Stage 11 summary.
- **All failures are flaky-test: retry all, skip implement flow, go straight to
  summary.** No commit is needed.
- **All failures are infra-error: skip all, report summary, suggest raising
  issues.** No commit, no implement flow.
- **Mixed classifications after developer overrides: re-check whether any
  `code-error` entries remain** before entering the implement flow.
- **Build URL with query params or trailing path segments: strip before
  parsing.** URLs may include suffixes like `/canvas` or `/waterfall` after the
  build number — ignore everything after the build number.
- **Bare-build-number path uses `user_token_organization` + `get_pipeline`.**
  Get the Buildkite org from the user's token, extract the repo name from the
  git remote, and call `get_pipeline` directly. One call, no pagination.

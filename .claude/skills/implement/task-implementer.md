Single-task implementation flow. Reached via the SKILL.md dispatcher when the input is a path or task-name fragment.

Inputs from the dispatcher:
- the cleaned argument (a task-spec path or task-name fragment, `--no-handoff-gate` already stripped).
- `override_active` — boolean. The dispatcher has already parsed `--no-handoff-gate`; this stage trusts the value verbatim and never re-parses arguments.

## Stage 0 — Locate task spec, verify design-phase PR handoff

This stage locates the task spec, reads its `ticket`, and runs the handoff
gate against the design branch BEFORE any branch/base resolution happens.

### 0a — Locate the task spec

If a path was given (e.g. "implement docs/tasks/AIDEV-29-TASK-02.md"),
use it. If a task name or description was given, list `docs/tasks/` and
find the matching file. If ambiguous, show the list and ask. If no matching
file is found, stop:

> `{input}` is not a recognised task spec path or name. Cannot proceed.

**Pre-flight check.** Before proceeding, verify that the review skill exists:

```bash
test -f .claude/skills/review/SKILL.md && echo "OK" || echo "ERROR: .claude/skills/review/SKILL.md not found — implement cannot proceed without it"
```

If the file is not found, stop and report the error.

Read the task spec in full. Extract from frontmatter:

- **ticket** (frontmatter — required)
- **branch** (frontmatter — required)

Extract from the task spec **filename**:

- **task-nn** — the `TASK-NN` segment from the filename using the pattern `TASK-[0-9]+` (e.g. `TASK-01`). If absent (older spec without a task number in the filename), use an empty string. Hold this value for commit messages throughout the run.

If either `ticket` or `branch` is missing from the frontmatter, surface a
specific error naming the missing field and stop before the gate runs:

> Task spec is missing required frontmatter field: `{field}`. Add it and re-run.

### 0b — Resolve the design branch from the design doc

Locate every design doc that carries this ticket, matching BOTH header forms:

```bash
rg -l "^(JIRA|Ticket): {ticket}$" docs/design/
```

Both `^JIRA:` and `^Ticket:` are matched on purpose — the `docs/design/`
inventory currently holds a genuine mix of both, and narrowing the lookup to
a single key would silently miss design docs keyed with the other. Do NOT
strip the `Ticket:` branch.

**If `rg` returns no results** (and `override_active` is false): stop with
this verbatim error:

> No design doc found for ticket `{ticket}` (searched `docs/design/` for both `^JIRA:` and `^Ticket:` headers). `implement` requires a design doc to verify the design-phase PR handoff. If this ticket legitimately has no design doc (e.g. a spike), pass `--no-handoff-gate` to bypass the check.

**If `rg` returns one or more design docs:** for each match, attempt to read
its `Branch:` header. The `Branch:` line is a body header (not frontmatter)
matching the regex `^Branch:[[:space:]]+([^[:space:]].*)$`. Collect the set
of resolved design branches.

**If no design doc has a resolvable `Branch:` header** (every match is a
legacy doc that predates the convention) and `override_active` is false:
stop with this verbatim error:

> Found {N} design doc(s) for ticket `{ticket}` but none carry a resolvable `Branch:` header (legacy docs). Cannot resolve the design-phase branch to verify its PR. Normalise the design doc by adding a `Branch:` header, or pass `--no-handoff-gate` to bypass the check.

### 0c — Run the handoff gate against each resolved design branch

The gate is a pure query (see `.claude/skills/shared/handoff-gate.md`): it returns
a sentinel object describing the PR state and never halts itself. This stage
inspects the sentinel and either proceeds or halts the calling skill using
the canonical halt-message templates from `.claude/skills/shared/handoff-gate.md`.
The gate passes if ANY resolved design branch returns a pass sentinel
(`OVERRIDE`, `OPEN`, or `MERGED`).

**If `override_active` is true:** read `.claude/skills/shared/handoff-gate.md` and
execute Step 1 (the override short-circuit) once with placeholders:

| Placeholder | Value |
|-------------|-------|
| `{branch}` | the first resolved design branch (only used in the override notice — the gate makes no `gh` call) |
| `{phase_name}` | `design` (substituted into the override notice line printed by Step 1) |
| `{override_active}` | `true` |

The gate prints the override notice and returns `{state: "OVERRIDE"}`. Treat
this as a pass and proceed to Stage 0d.

**If `override_active` is false:** for each resolved design branch in turn,
read `.claude/skills/shared/handoff-gate.md` and execute it with placeholders:

| Placeholder | Value |
|-------------|-------|
| `{branch}` | the resolved design branch |
| `{override_active}` | `false` |

Inspect the returned sentinel's `.state`:

- `OPEN` or `MERGED` → the gate passes for this branch. Exit the loop and
  proceed to Stage 0d.
- `NONE`, `CLOSED`, `DRAFT`, or `GH_FAIL` → record the sentinel and move on
  to the next candidate branch. The caller (this stage) is responsible for
  the halt decision; the gate did not halt.

If every resolved design branch returned a non-pass sentinel, halt the
calling skill here. Use the canonical halt-message template from
`.claude/skills/shared/handoff-gate.md` corresponding to the **last** candidate
branch's sentinel state, filling `{phase_name}` = `design`,
`{skill_name}` = `implement`, `{branch}` = the last candidate branch, and
(for `CLOSED` / `DRAFT`) `{number}` and `{url}` from the sentinel, or (for
`GH_FAIL`) `{stderr}` from the sentinel. Emit exactly one halt message — no
noisy false halts on non-final candidate branches.

### 0d — Resolve base branch, create or check out the task branch

Re-read the task spec to extract:

- **`Depends on:`** (body header — optional). If absent, treat as `Depends on: nothing`.

**Resolve the base branch.** Do this unconditionally on every invocation — both fresh runs and resumes. Base resolution runs before the branch creation or checkout step.

- `Depends on:` header absent, or value is `nothing`:
  ```bash
  BASE=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
  ```
- `Depends on: {filename}` (value ends in `.md`; `{filename}` is the bare filename inside `docs/tasks/`, not a path — e.g. `AIDEV-70-TASK-02-foo.md`, not `docs/tasks/AIDEV-70-TASK-02-foo.md`):
  - Read `docs/tasks/{filename}`. If the file does not exist, stop:
    > Dependency task spec not found: docs/tasks/{filename}. Cannot proceed.
  - Extract the `branch` field from its frontmatter. If absent, stop:
    > Dependency task spec docs/tasks/{filename} is missing required frontmatter field: `branch`. Cannot proceed.
  - Set `BASE` to that branch value.
- `Depends on: {branch-name}` (value does not end in `.md` and is not `nothing`): treat as a literal branch name; set `BASE` to that value directly. No file lookup is performed.

Store `BASE` — it is used in Stage 6 to determine whether to pass `base` to `create-pr`.

**Refuse if the branch already exists; otherwise create it from `BASE`:**

First detect whether the branch exists, emitting a neutral sentinel:

```bash
git show-ref --verify --quiet "refs/heads/{branch}" && echo "EXISTS" || echo "ABSENT"
```

- **`EXISTS`** → stop. Report this verbatim error to the user and do not proceed:

  > Branch {branch} already exists locally — delete it (git branch -D {branch}) before re-running. No automatic reset or reuse.

  Report it as text (the same way every other Stage 0 error is surfaced) — do **not** route it through a shell `echo`. The recovery hint names `git branch -D`, and this repo's own `git-safety` hook blocks any Bash command whose text matches that pattern, so an `echo`-based refusal would itself be blocked before it could print. The hint is still correct for the engineer to run in their own terminal (the hook only intercepts Claude's Bash tool, not the engineer's shell); it just must not be echoed from within the skill.

- **`ABSENT`** → create the branch from `BASE`:

  ```bash
  git checkout -b {branch} {BASE}
  ```

There is no silent branch reuse: a pre-existing local branch is a hard refusal, not a checkout. The engineer's recovery is to delete the branch (`git branch -D {branch}`) and re-invoke. If `git checkout -b {branch} {BASE}` itself fails (e.g. `BASE` is not a valid local ref), surface its error verbatim and halt before Stage 1 runs — do not let the run continue and trip Stage 1's branch-mismatch assertion as a misleading proxy.

### 0e — Spec-ambiguity pre-flight

Before any artefact is produced, verify the task spec is implementable as-written. This is a deterministic structural check over the spec body that was read in `0a`. It catches the obvious "spec is still template / empty / placeholder" failure modes that would otherwise cause the writer agent to improvise — exactly the behaviour the AI Eng Process Change framework forbids. Subtle semantic ambiguity (vague phrasing that survives the structural check) is the spec-quality agent's territory, not this stage's.

If any of the checks below fail, halt with the templated message under that check and do not proceed to Stage 1. The branch created in `0d` is left in place for the engineer's recovery flow (update the spec on the design branch, push, re-invoke `implement` — the existing `git branch -D` recovery from 0d applies if a fresh start is desired). A 0e halt is surfaced verbatim the same way Stage 0a–0d halts are; no mode detection happens here, and the orchestrator's OM-5 generic non-PASS branch handles a 0e halt as `failed` like any other Stage 0 stop.

**Shared placeholder definition.** All four checks use one rule: a spec line is a **placeholder** if it appears verbatim in `.claude/templates/task-spec.md` under the same section heading. The template ships with the skill and is the canonical source of template content; comparing against it is robust to template edits (the rule auto-tracks them) and side-steps fragile marker enumerations.

Implementation: read `.claude/templates/task-spec.md` once at the start of 0e. For each section in the spec being checked, collect (a) the spec's bullets/lines under the section heading, and (b) the template's bullets/lines under the same heading. A spec line is a placeholder iff it matches a template line for that section after a trim of leading/trailing whitespace. A section is "template-only" iff every non-empty line under its heading is a placeholder.

**Check 1 — Acceptance criteria present and populated.** The spec body must contain an `## Acceptance criteria` heading with at least one bullet that starts with `- [ ]`. At least one `- [ ]` bullet must NOT be a placeholder (per the shared definition above). Halt if the heading is absent, the section is empty, or every `- [ ]` bullet is a placeholder.

Halt message:

> Spec-ambiguity halt — Acceptance criteria missing or template-only in `{task-spec-path}`. `implement` requires at least one populated `- [ ]` acceptance-criterion bullet before the writer is invoked. Update the spec on the design branch, push it, and re-invoke `implement`.

**Check 2 — Implementation constraints present and populated.** The spec body must contain an `## Implementation constraints` heading with at least one bullet. At least one bullet must NOT be a placeholder. Halt if the heading is absent, the section is empty, or every bullet is a placeholder.

Halt message:

> Spec-ambiguity halt — Implementation constraints missing or template-only in `{task-spec-path}`. `implement` requires populated implementation constraints. Update the spec on the design branch, push it, and re-invoke `implement`.

**Check 3 — Objective is non-template.** The spec body must contain an `## Objective` heading. The section body must be non-empty AND not a placeholder under the shared definition.

Halt message:

> Spec-ambiguity halt — Objective missing or template-only in `{task-spec-path}`. `implement` requires a concrete objective sentence. Update the spec on the design branch, push it, and re-invoke `implement`.

**Check 4 — Inputs / outputs / errors populated.** The spec body must contain an `## Inputs and outputs` heading with `Inputs:`, `Outputs:`, and `Errors:` sub-sections. Each sub-section must contain at least one line that is NOT a placeholder under the shared definition (with the explicit `Errors: none` form accepted in place of an Errors sub-list). Halt if any sub-section is absent or template-only.

Halt message:

> Spec-ambiguity halt — Inputs / outputs / errors missing or template-only in `{task-spec-path}`. `implement` requires populated `Inputs:`, `Outputs:`, and `Errors:` declarations under `## Inputs and outputs`. Update the spec on the design branch, push it, and re-invoke `implement`.

All four checks are pure structural string matching — one `Read` of `.claude/templates/task-spec.md` plus the spec body that `0a` already loaded. No model judgement, no other file I/O. A spec that passes all four is considered ambiguity-clean for the purposes of this gate; semantic-level ambiguity is the spec-quality agent's responsibility and is enforced separately.

---

## Stage 1 — Confirm branch

The task spec was located, parsed, and gated in Stage 0; `ticket`, `branch`,
and `task-nn` are already in scope from Stage 0a. This stage only confirms
the working tree matches the task spec's `branch` before any artefact is
produced.

**Confirm branch.** Run:

```bash
git rev-parse --abbrev-ref HEAD
```

If the current branch does not match the task spec's `branch` field, stop with an error:

> Branch mismatch: task spec targets `{doc-branch}` but the current branch is `{current-branch}`. Stage 0 should have resolved this — do not proceed.

---

## Stage 2 — Spawn writer agent

Tell the user: "Producing artefact for {ticket}."

Spawn a general-purpose Agent. Fill every placeholder before sending — do not
leave any placeholder unfilled.

```
You are producing an artefact described by a task spec.
Do not ask questions — all decisions are in the task spec below.

Task spec path: {path}

Read the task spec in full before starting. The spec is your complete brief:
- The Objective section tells you what to produce.
- The Context section lists files to read; read them before writing.
- The Implementation constraints, Inputs and outputs, Edge cases, and Out of
  scope sections define exactly what to build and what to avoid.
- The Required output format section defines the shape of the artefact.

Task spec content:
{Full content of the task spec file, verbatim}

Task:
1. Read the task spec in full (content is above; path is given if you need to re-read).
2. Read every file listed in the Context section.
3. Produce the artefact as described. Write it to the path specified in the
   task spec's Required output format section.
4. Return: the path written and a one-sentence summary of what was produced.
```

Wait for the writer agent to return before continuing.

---

## Stage 3 — Review and fix loop

Maximum 5 iterations. Each iteration: run review → read verdict → exit (PASS)
or fix and loop again.

### 3a — Spawn review agent

Spawn an Agent. Fill every placeholder before sending.

```
You are running the `review` skill.
Read `.claude/skills/review/SKILL.md` and execute it from Stage 1.
Do not ask questions — all context is below.

Ticket: {ticket}
Branch: {branch}

The diff will contain the artefact just produced by implement. Group E will
check it against the task spec for ticket {ticket} in docs/tasks/.
```

Wait for the review agent to return the verdict string and findings file path.

### 3b — Read verdict and commit

Commit the current state of the artefact and review findings, regardless of
verdict. Only commit if there are actual changes:

```bash
git add -- "{artefact path(s)}"
git add docs/ai/reviews/ 2>/dev/null || true
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{ticket} {task-nn}: Review cycle {N} — {PASS|FAIL}

{one-line description of what changed this cycle}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

- **PASS** → exit the loop. Proceed to Stage 4 (CI validation).
- **FAIL** → continue to 3c.

If this is iteration 5 and verdict is still FAIL, stop the loop. Before
stopping, collect the blocker and major counts from each iteration's findings
file and build a progress table:

| Iteration | Findings file | Blockers | Majors |
|-----------|--------------|----------|--------|
| 1         | {path}       | {n}      | {n}    |
| …         | …            | …        | …      |

Then report:

> Reached the maximum of 5 review iterations without a PASS.
>
> Progress across iterations:
> {progress table}
>
> Most recent findings: {findings file path}
> Each cycle's state is preserved as a commit (`{ticket} {task-nn}: Review cycle {N} — FAIL`); inspect `git log` to walk the iteration history.
> Review the remaining blocker/major findings and decide how to proceed.

Do not proceed to Stage 5.

### 3c — Spawn fixer agent

Spawn a general-purpose Agent. Fill every placeholder before sending.

Before composing this prompt: read the most recent findings file yourself.
Each finding is a markdown block headed `### F{n} — {severity} — {file}:{line}`
with `- outcome: pending` beneath it. Extract every finding where the outcome
is `pending` AND the severity is `blocker` or `major`. Format each one as:

```
F{n} ({severity}) — {file}:{line} — {issue} — Suggestion: {suggestion}
```

Then send the fixer agent this prompt, filling every placeholder:

```
You are fixing an artefact that failed review.
Do not ask questions — apply every fix listed below and return.

Artefact: {exact artefact path}

Read before changing:
- The artefact at {artefact path} — read it in full before making any changes.

Items to fix:
{The formatted F{n} lines you extracted above — one per line.}

Do not add content, restructure, or change anything not listed above.
After applying all fixes, return a bullet list of every change made,
one line per fix.
```

Return to 3a.

---

## Stage 4 — CI validation and fix loop

Run CI-equivalent validation locally, committing after each cycle. If validation fails,
spawn a fixer agent and retry — same pattern as the review loop in Stage 3.

Maximum 5 iterations. Each iteration: run CI validation → read verdict →
exit (passed) or fix and loop again.

**Read `.claude/skills/shared/ci-validation-loop.md` and execute Steps 1, 2,
3 defined there.** That document contains the sub-agent prompts, verdict
handling, per-cycle commit flow, and fixer agent instructions for this stage.

Fill the shared document's placeholders as follows:
- `{ticket}` → the ticket extracted in Stage 0a
- `{branch}` → the branch extracted in Stage 0a
- `{changed file(s)}` → the artefact path(s) produced by the writer agent
- `{task-nn}` → the task-nn extracted in Stage 0a (include it; omit only if empty)

On return:
- `verdict: passed` → proceed to Stage 5.
- `verdict: failed-max-iterations` → **check for the `precondition: authentication` marker line FIRST**, before any other handling. The two branches below are mutually exclusive; the auth branch is checked first.

**If the return carries a `precondition: authentication` marker line (auth branch):**

Detect the run mode by the PRESENCE of the OM-5 mode-signal line in this task-implementer's own invocation brief — the literal line `Mode: non-interactive sub-agent — do not prompt; on auth precondition return FAIL carrying precondition: authentication`. Mode detection is added ONLY here at the Stage 4 failed-max-iterations handler — not at Stage 0 and not globally.

- **Mode-signal line PRESENT → orchestration sub-agent (non-interactive).** Do NOT prompt. Bubble the precondition up in this task's FAIL return per the orchestration return contract: return FAIL and include a `precondition: authentication` line followed by the documented remediation path. The orchestrator (feature-orchestrator OM-5) owns the halt.
- **Mode-signal line ABSENT → top-level single-task (interactive).** Emit the reply-continue affordance and end the turn:

  > CI validation hit an authentication precondition — it is an environment problem, not a code failure, so the fix loop stopped without churning the fixer.
  >
  > Remediation: {remediation path from the marker}.
  >
  > Authenticate, then reply `continue` and I will re-run CI validation from the top.

  On the developer's `continue` reply, RE-RUN the entire CI loop — a fresh invocation of `skills/shared/ci-validation-loop.md` Steps 1–3 with the iteration counter starting at 1 (the auth short-circuit consumed no iteration budget, so the fresh loop naturally begins at iteration 1). This re-run logic lives here in the caller, never in `ci-validation-loop.md`.

**If the return does NOT carry the marker (non-auth code failure — existing behaviour, unchanged):** stop. Report to the user:

> CI validation failed after 5 fix attempts.
>
> Failing command: `{failing_command}`
> Most recent output is above.
> Each cycle's state is preserved as a commit (`{ticket} {task-nn}: CI validation cycle {N} — FAIL`); inspect `git log` to walk the iteration history.
> Resolve the remaining failure manually and re-run.

Do not proceed to Stage 5.

---

## Stage 5 — Push branch

Push the branch to the remote so it is available for PR creation and stacked
task branches.

```bash
git push -u origin HEAD
```

If `git push -u origin HEAD` fails, surface the error verbatim and stop. Do not proceed to
Stage 6.

---

## Stage 6 — Create PR

Spawn a sub-agent briefed to read and execute
`.claude/skills/create-pr/SKILL.md`. Pass the three required inputs
explicitly and, for stacked tasks, the optional `base` input — do not inline
the PR creation logic here.

Fill every placeholder before sending. The values are all already in scope
from Stage 0.

```
You are executing the create-pr skill.
Read `.claude/skills/create-pr/SKILL.md` and execute it from Stage 1.
Do not ask questions — all inputs are below.

ticket: {ticket}
branch: {branch}
task_spec_path: {task spec path}
labels: ai-implementation
```

If `Depends on:` resolved in Stage 0 is not `nothing`, append `base: {BASE}` as an additional line in the inputs block above before sending. When `Depends on: nothing`, omit the `base` line entirely — do not pass an empty or null value.

Wait for the sub-agent to return before continuing.

If the sub-agent reports that `gh pr create` failed, surface the error verbatim
and stop. Do not proceed to Stage 7.

---

## Stage 7 — Confirm

Report to the user:

- Artefact: {path}
- PR: {URL returned by create-pr sub-agent}
- Task spec: {path}
- Findings files: list all `{ticket}-*-*.md` in `docs/ai/reviews/`
- Verdict: PASS
- Iterations: {N} review pass(es)

---

## Rules

- **Spawn the review agent from Stage 3a in a fresh message each iteration.**
  The loop must not try to reuse a prior review agent's context.
- **Do not produce or edit artefacts yourself.** All writes go through the
  writer or fixer sub-agent. Your role is briefing and orchestration.
- **The handoff gate in Stage 0 is a hard stop.** A missing design doc, an
  unresolvable `Branch:` header, or a non-pass sentinel from the gate for
  every candidate design branch halts the skill before any artefact is
  produced. The gate itself is a pure query (`.claude/skills/shared/handoff-gate.md`);
  Stage 0c owns the halt decision and emits the canonical halt-message
  template. The override (`--no-handoff-gate`) is per-invocation only and is
  parsed by the dispatcher — Stage 0 trusts `override_active` verbatim.
- **The branch assertion in Stage 1 is a hard stop.** After Stage 0d creates or checks out the correct branch, Stage 1 must always see a match. A mismatch is an error, not a prompt.
- **The fix in 3c covers blockers and majors only.** Minors and nits are
  recorded in the findings file but do not trigger a fix iteration.
- **Do not exceed 5 iterations.** Surface the remaining findings to the user
  rather than looping indefinitely.
- **CI validation follows a fix loop (max 5 iterations).** Run CI → fail →
  spawn fixer → re-run. The CI validation sub-agent discovers and executes;
  the fixer sub-agent applies minimal fixes. CI-specific rules live in
  `.claude/skills/ci-validation/SKILL.md`.
- **Spawn the CI validation agent from Step 1 in a fresh message each
  iteration.** Same principle as the review loop — never reuse a prior agent's
  context.
- **The CI fixer in Step 3 applies minimal fixes only.** It addresses the failing
  command's output — no refactoring, no unrelated changes.

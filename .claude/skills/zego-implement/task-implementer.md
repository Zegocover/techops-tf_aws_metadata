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
test -f .claude/skills/zego-review/SKILL.md && echo "OK" || echo "ERROR: .claude/skills/zego-review/SKILL.md not found — implement cannot proceed without it"
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

> No design doc found for ticket `{ticket}` (searched `docs/design/` for both `^JIRA:` and `^Ticket:` headers). `zego-implement` requires a design doc to verify the design-phase PR handoff. If this ticket legitimately has no design doc (e.g. a spike), pass `--no-handoff-gate` to bypass the check.

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
`{skill_name}` = `zego-implement`, `{branch}` = the last candidate branch, and
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

Store `BASE` — it is used in Stage 7 to determine whether to pass `base` to `zego-create-pr`, and forwarded to the Stage 5 summary-writer as the diff range (`base..HEAD`).

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

If any of the checks below fail, halt with the templated message under that check and do not proceed to Stage 1. The branch created in `0d` is left in place for the engineer's recovery flow (update the spec on the design branch, push, re-invoke `zego-implement` — the existing `git branch -D` recovery from 0d applies if a fresh start is desired). A 0e halt is surfaced verbatim the same way Stage 0a–0d halts are; no mode detection happens here, and the orchestrator's OM-5 generic non-PASS branch handles a 0e halt as `failed` like any other Stage 0 stop.

**Shared placeholder definition.** All four checks use one rule: a spec line is a **placeholder** if it appears verbatim in `.claude/templates/task-spec.md` under the same section heading. The template ships with the skill and is the canonical source of template content; comparing against it is robust to template edits (the rule auto-tracks them) and side-steps fragile marker enumerations.

Implementation: read `.claude/templates/task-spec.md` once at the start of 0e. For each section in the spec being checked, collect (a) the spec's bullets/lines under the section heading, and (b) the template's bullets/lines under the same heading. A spec line is a placeholder iff it matches a template line for that section after a trim of leading/trailing whitespace. A section is "template-only" iff every non-empty line under its heading is a placeholder.

**Check 1 — Acceptance criteria present and populated.** The spec body must contain an `## Acceptance criteria` heading with at least one bullet that starts with `- [ ]`. At least one `- [ ]` bullet must NOT be a placeholder (per the shared definition above). Halt if the heading is absent, the section is empty, or every `- [ ]` bullet is a placeholder.

Halt message:

> Spec-ambiguity halt — Acceptance criteria missing or template-only in `{task-spec-path}`. `zego-implement` requires at least one populated `- [ ]` acceptance-criterion bullet before the writer is invoked. Update the spec on the design branch, push it, and re-invoke `zego-implement`.

**Check 2 — Implementation constraints present and populated.** The spec body must contain an `## Implementation constraints` heading with at least one bullet. At least one bullet must NOT be a placeholder. Halt if the heading is absent, the section is empty, or every bullet is a placeholder.

Halt message:

> Spec-ambiguity halt — Implementation constraints missing or template-only in `{task-spec-path}`. `zego-implement` requires populated implementation constraints. Update the spec on the design branch, push it, and re-invoke `zego-implement`.

**Check 3 — Objective is non-template.** The spec body must contain an `## Objective` heading. The section body must be non-empty AND not a placeholder under the shared definition.

Halt message:

> Spec-ambiguity halt — Objective missing or template-only in `{task-spec-path}`. `zego-implement` requires a concrete objective sentence. Update the spec on the design branch, push it, and re-invoke `zego-implement`.

**Check 4 — Inputs / outputs / errors populated.** The spec body must contain an `## Inputs and outputs` heading with `Inputs:`, `Outputs:`, and `Errors:` sub-sections. Each sub-section must contain at least one line that is NOT a placeholder under the shared definition (with the explicit `Errors: none` form accepted in place of an Errors sub-list). Halt if any sub-section is absent or template-only.

Halt message:

> Spec-ambiguity halt — Inputs / outputs / errors missing or template-only in `{task-spec-path}`. `zego-implement` requires populated `Inputs:`, `Outputs:`, and `Errors:` declarations under `## Inputs and outputs`. Update the spec on the design branch, push it, and re-invoke `zego-implement`.

All four checks are pure structural string matching — one `Read` of `.claude/templates/task-spec.md` plus the spec body that `0a` already loaded. No model judgement, no other file I/O. A spec that passes all four is considered ambiguity-clean for the purposes of this gate; semantic-level ambiguity is the spec-quality agent's responsibility and is enforced separately.

### 0f — Recover the feature identifier and carry it into the task spec

The shared feature identifier (AIDEV-188 / ADR 020) links this implementation
PR to its sibling design and requirements PRs. `zego-implement` never mints — it
recovers the identifier the design phase already persisted and reuses it. This
is best-effort: any failure warns and proceeds; never block the run on it.

1. **Recover from the design doc.** Use the design doc resolved in `0b` (the one
   whose branch passed the `0c` handoff gate, or the first resolved match):

   ```bash
   FEATURE_ID="$(.claude/scripts/feature-id.sh recover {resolved-design-doc-path} 2>/dev/null || true)"
   ```

2. **`decide` fallback when recovery returned nothing.** Compute
   `predecessor-pr-exists` against the **design branch already resolved at the
   Stage 0b/0c handoff gate** — no second lookup. The gate already established
   the design PR state for that branch this run: a passing sentinel (`OPEN`,
   `MERGED`) means `predecessor-pr-exists=true`; an `OVERRIDE` (the gate was
   bypassed) or a `GH_FAIL` is the LOST-safe default `true` (a `gh` failure is
   NEVER read as "no predecessor PR" — that would let a truly-lost id fall
   through to MINT and duplicate the identifier, breaking FR-02):

   ```bash
   if [ -z "$FEATURE_ID" ]; then
     VERDICT="$(.claude/scripts/feature-id.sh decide "" true)"   # design phase always has a predecessor PR (the gate just confirmed it)
     # VERDICT is LOST — proceed without an id; never mint a second, unlinked id here.
   fi
   ```

3. **Carry the id into the task spec frontmatter.** When `FEATURE_ID` is
   non-empty and the task spec does not already carry a `feature-id:` key, add
   `feature-id: {FEATURE_ID}` to the task spec's YAML frontmatter (the optional
   third permitted key, alongside `ticket` and `branch`). This makes the task
   spec the artefact `zego-create-pr` recovers from at Stage 7. When `FEATURE_ID`
   is empty, leave the frontmatter unchanged — do not write an empty value.

Hold `FEATURE_ID` for the run; Stage 7's `zego-create-pr` re-recovers it from
the task spec via `feature-id.sh recover`.

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

**Initialise the completion-notes scratch checkpoint.** Before spawning the
writer, prepare the durable scratch file that each writer/fixer agent's
completion notes are checkpointed to as they return. Its path is
`docs/ai/.implementation-notes/{ticket}-{task-nn}.md` — a hidden, gitignored
sibling of `docs/ai/implementations/` and `docs/ai/reviews/`, owned by
`task-implementer` (deliberately NOT under `docs/ai/implementations/`, which the
summary-writer owns and `task-implementer` must not pre-create). Hold this path
as `notes_scratch_path`.

The checkpoint's purpose is **surviving in-session context compaction within a
single run**: by Stage 5 (after Stage 2 + N Stage-3c iterations + up to 5 CI
iterations) the verbatim notes held only in this orchestrator's context may have
been summarised away by the harness, which would defeat the summary-writer's
verbatim-quoting requirement. The on-disk file keeps the doer's exact words. It
is **not** a cross-kill resume mechanism — Stage 0d hard-refuses an existing
branch, so a killed run is re-invoked fresh and regenerates its notes.

Do this once, here, after the Stage 1 branch confirmation and before the first
writer is spawned:

1. Ensure the ignore entry is present. `.gitignore` is not fanned out to
   consumers, so the scratch mechanism is self-contained — `task-implementer`
   ensures the entry itself rather than relying on a shipped `.gitignore`.
   Append `docs/ai/.implementation-notes/` to the repo-root `.gitignore` only if
   it is not already present:

   ```bash
   grep -qxF 'docs/ai/.implementation-notes/' .gitignore 2>/dev/null \
     || printf '%s\n' 'docs/ai/.implementation-notes/' >> .gitignore
   ```

2. Create the scratch directory and truncate the scratch file, so stale notes
   from a prior killed-then-restarted run do not leak in:

   ```bash
   mkdir -p docs/ai/.implementation-notes
   : > "{notes_scratch_path}"
   ```

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
4. Return: the path written and a one-sentence summary of what was produced,
   followed by a `## Completion notes:` Markdown section (header plus body)
   carrying the completion notes the task spec's `## Required output format`
   asks you to produce — the decisions made that the spec did not specify, any
   ambiguous constraints, anything that could not be implemented as specified,
   and anything that looks wrong in adjacent code (flag, do not fix). Return
   the section verbatim even if it is brief.
```

Wait for the writer agent to return before continuing.

**Capture the completion notes.** From the writer's return, extract the
`## Completion notes:` section verbatim (header plus body) and hold it
in-context as `completion_notes`. It is forwarded to the Stage 5 summary-writer.
If the writer returned no such section, hold `completion_notes` as empty — Stage
5 degrades the artefact's `## Assumptions and guesses` section accordingly, it
does not fail.

**Checkpoint the notes to the scratch file.** Alongside the in-context
accumulation, append this section verbatim to the scratch file
`{notes_scratch_path}` initialised at the top of this stage, so the doer's exact
words survive in-session context compaction. If the writer returned no section,
append nothing. Use a heredoc Write/append rather than echoing the notes through
the shell (note text may contain patterns the safety hooks block):

```bash
cat >> "{notes_scratch_path}" <<'EOF'
{the `## Completion notes:` section verbatim}

EOF
```

---

## Stage 3 — Review and fix loop

Maximum 5 iterations. Each iteration: run review → read verdict → exit (PASS)
or fix and loop again.

### 3a — Spawn review agent

Spawn an Agent. Fill every placeholder before sending.

```
You are running the `zego-review` skill.
Read `.claude/skills/zego-review/SKILL.md` and execute it from Stage 1.
Do not ask questions — all context is below.

Ticket: {ticket}
Branch: {branch}

The diff will contain the artefact just produced by implement. Group E will
check it against the task spec for ticket {ticket} in docs/tasks/.
```

Wait for the review agent to return the verdict string and findings file path.

**Accumulate the findings path.** Append the findings-file path this review
iteration returned to an in-context `review_findings_paths` array (one entry per
iteration). This is deliberately NOT a `docs/ai/reviews/` glob: a
`{ticket}-*-*.md` glob would also capture the design-gate
(`{ticket}-design-gate-*.md`) and task-gate (`{ticket}-task-NN-gate-*.md`)
findings files, polluting the Stage 5 artefact's `## Where it struggled` with
design-review findings rather than implementation/CI iterations. If a given
iteration produced no findings file, append nothing. When the loop exits with no
findings file ever produced (CI passed first try, no review loop),
`review_findings_paths` is the empty array — which is the correct value to
forward to Stage 5.

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

Do not proceed to Stage 4.

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
one line per fix, followed by a `## Completion notes:` Markdown section
(header plus body) carrying any decisions made while fixing, any ambiguity in
the findings, anything that could not be fixed as suggested, and anything that
looks wrong in adjacent code (flag, do not fix). Return the section verbatim
even if it is brief.
```

**Accumulate this iteration's completion notes.** From the fixer's return,
extract the `## Completion notes:` section verbatim and append it to the
in-context `completion_notes` accumulated from Stage 2 (concatenate — each
fixer iteration adds its notes). The accumulated text is forwarded to the Stage
5 summary-writer. If the fixer returned no such section, append nothing.

**Checkpoint this iteration's notes to the scratch file.** Alongside the
in-context accumulation, append this iteration's `## Completion notes:` section
verbatim to the scratch file `{notes_scratch_path}` initialised at the top of
Stage 2, so the doer's exact words survive in-session context compaction. If the
fixer returned no section, append nothing:

```bash
cat >> "{notes_scratch_path}" <<'EOF'
{the `## Completion notes:` section verbatim}

EOF
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

## Stage 5 — Write implementation summary

CI has passed (Stage 4). Before pushing, dispatch the `summary-writer` sub-agent
to synthesise a durable, committed implementation-summary artefact, then commit
it into the branch so it is pushed with the work and reachable from the PR. This
stage is non-gating: every failure path below still proceeds to push and PR.

**Derive `output_path`.** The summary artefact basename equals the task-spec
basename, so the artefact lives at `docs/ai/implementations/<task-spec-basename>`.
Equivalently `docs/ai/implementations/{ticket}-{task-nn}-{slug}.md`, where
`{slug}` is the task-spec filename segment after the `TASK-NN-` prefix with the
`.md` suffix stripped — which reconstructs the task-spec basename exactly. For
example, the task spec `AIDEV-184-TASK-01-emit-implementation-summary.md` yields
slug `emit-implementation-summary` and `output_path`
`docs/ai/implementations/AIDEV-184-TASK-01-emit-implementation-summary.md`. The
summary-writer owns `mkdir -p docs/ai/implementations/`; do NOT pre-create the
directory here.

**Resolve `completion_notes` from the scratch checkpoint (authoritative).** The
scratch file `{notes_scratch_path}` (written across Stage 2 and each Stage 3c
iteration) holds the doer's verbatim notes on disk, immune to any in-session
context compaction that may have summarised away the in-context accumulation.
Read it and use its contents as `completion_notes`:

```bash
cat "{notes_scratch_path}"
```

- Readable → use the file contents as `completion_notes` (authoritative). An
  empty file means no notes were ever produced — forward `completion_notes` as
  empty, exactly as if the in-context accumulation were empty.
- Unreadable (missing, permission error) → fall back to the in-context
  `completion_notes` accumulated across Stage 2 and Stage 3c.

**Dispatch the summary-writer.** Spawn a general-purpose Agent briefed to read
and execute `.claude/skills/zego-implement/summary-writer.md`. Fill every
placeholder before sending. The values are all in scope: `completion_notes` was
resolved just above (preferentially from the scratch checkpoint, falling back to
the in-context accumulation), `review_findings_paths` across Stage 3a
(empty array if no findings file was ever produced), `base` from Stage 0d,
`ci_outcome` is `passed` (Stage 4 only reaches here on a pass).

```
You are executing the summary-writer sub-agent.
Read `.claude/skills/zego-implement/summary-writer.md` and execute it.
Do not ask questions — all inputs are below.

ticket: {ticket}
branch: {branch}
task-nn: {task-nn}
task_spec_path: {task spec path}
output_path: {output_path derived above}
base: {BASE}
review_findings_paths: {the accumulated array, or [] if empty}
completion_notes: {the accumulated completion-notes text, or empty if none}
ci_outcome: passed
```

Wait for the sub-agent to return. It returns `summary_path`, `summary_status`
(`Implemented` / `Partial` / `Deferred`), `failure_kind` (`transient` /
`terminal` / `none`), and a one-sentence confirmation.

**Branch on `failure_kind` (non-gating in every case):**

- `failure_kind: none` → the artefact was written. Proceed to the commit step
  below, holding `summary_path` and `summary_status` for Stage 7 (create-pr) and
  Stage 8 (Confirm).
- `failure_kind: transient` (model timeout, context overflow, write failure) →
  re-dispatch the summary-writer once with identical inputs. If it still fails,
  proceed without `summary_path` (leave it empty).
- An **unstructured return** — a dispatch that emits no `failure_kind` field at
  all (model crash, or a context overflow that aborts before any structured
  return) → treat as `transient`: re-dispatch once, then if still failing
  proceed without `summary_path`.
- `failure_kind: terminal` (read failure on a required input, `mkdir` failure) →
  do NOT retry; proceed without `summary_path`.

In every failure case, capture the returned error string and surface it
prominently in the Stage 5 outcome and in the final Confirm report (Stage 8) —
the failure is visible even though it never gates push or PR. A clean, passing
implementation still ships a PR.

**Commit the artefact (idempotent, only when `summary_path` is set).** The
artefact must be committed only if it differs from the committed version. The
per-branch handling below is authoritative; do NOT implement the schematic
one-liner `git add docs/ai/implementations/… && git diff --cached --quiet || git
commit` literally — because `&&` and `||` are equal-precedence and
left-associative, a failed `git add` short-circuits the left group and makes the
`||` fire `git commit` anyway, which is exactly the swallowed-failure path the
branches below forbid.

1. Stage the artefact:

   ```bash
   git add -- "{summary_path}"
   ```

   If `git add` exits non-zero (lock contention, or a stale path returned by the
   summary-writer) → surface the git error prominently in the Stage 5 outcome,
   do **not** attempt the `git commit`, and proceed to push/PR without
   `summary_path`. This failure must not be swallowed by an `&&` short-circuit.

2. Check whether there are staged changes:

   ```bash
   git diff --cached --quiet -- "{summary_path}"
   ```

   - Exit `0` → no staged changes (the artefact is byte-for-byte identical to the
     committed version). Skip the commit — this is the idempotent no-op path.
   - Exit `1` → staged changes are present. Proceed to the commit step.
   - Any other (unexpected) exit code → treat it exactly like a `git add`
     failure: surface the error, do **not** attempt the `git commit`, and proceed
     to push/PR without `summary_path`. The check must not fire a commit on an
     unexpected diff error.

3. Commit the staged artefact:

   ```bash
   git commit -m "$(cat <<'EOF'
{ticket} {task-nn}: Add implementation summary

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)" -- "{summary_path}"
   ```

   If `git commit` fails → unstage the file with `git reset HEAD -- "{summary_path}"`;
   if that itself fails, fall back to `git restore --staged -- "{summary_path}"`;
   if that also fails, surface the git error and still proceed to push/PR without
   `summary_path` (push operates on committed content only, so a
   staged-but-uncommitted file does not affect the pushed branch). Surface the
   git error prominently in either case.

**Clean up the scratch checkpoint.** Once Stage 5 has read the scratch file and
the artefact is committed (the success path: `failure_kind: none`, the read
succeeded, and either the commit landed or was a clean idempotent no-op), delete
the scratch file:

```bash
rm -f "{notes_scratch_path}"
```

On **any** Stage 5 failure — a non-`none` `failure_kind`, an unreadable scratch
file, or a `git add` / `git diff --cached` / `git commit` failure above — do NOT
delete it: leave it as inert, gitignored residue (`skill-idempotency.md` Rule 8
— a named, inert residue, truncated by the next run's Stage 2 initialise step).
The file is gitignored, so it is never pushed or committed regardless.

---

## Stage 6 — Push branch

Push the branch to the remote so it is available for PR creation and stacked
task branches.

```bash
git push -u origin HEAD
```

If `git push -u origin HEAD` fails, surface the error verbatim and stop. Do not proceed to
Stage 7.

---

## Stage 7 — Create PR

Spawn a sub-agent briefed to read and execute
`.claude/skills/zego-create-pr/SKILL.md`. Pass the three required inputs
explicitly and, for stacked tasks, the optional `base` input; when the Stage 5
summary-writer produced an artefact, also pass the optional `summary_path` and
`summary_status` inputs — do not inline the PR creation logic here.

Fill every placeholder before sending. The values are all already in scope
from Stage 0 (and Stage 5 for the summary inputs).

```
You are executing the create-pr skill.
Read `.claude/skills/zego-create-pr/SKILL.md` and execute it from Stage 1.
Do not ask questions — all inputs are below.

ticket: {ticket}
branch: {branch}
task_spec_path: {task spec path}
labels: ai-implementation
review_surface: {label: the code changes in this PR, link: {PR URL or branch}}
```

The `review_surface` input names the human review surface for the implementation phase (`docs/ai/steering/base/review-audience.md`): the code changes in this PR (the diff plus the completion notes carried in its body). `zego-create-pr` renders it as one inline line within Background. The PR URL is not known until `zego-create-pr` opens the PR, so pass the branch as the `link` value — the line names the surface; the PR it sits on is self-evident.

If `Depends on:` resolved in Stage 0 is not `nothing`, append `base: {BASE}` as an additional line in the inputs block above before sending. When `Depends on: nothing`, omit the `base` line entirely — do not pass an empty or null value.

If Stage 5 produced an artefact (`summary_path` is set), append `summary_path: {summary_path}` and `summary_status: {summary_status}` as additional lines in the inputs block before sending. If Stage 5 failed and `summary_path` is empty, omit both lines entirely — do not pass empty or null values (this keeps `zego-create-pr`'s behaviour unchanged when the summary is absent).

Wait for the sub-agent to return before continuing.

If the sub-agent reports that `gh pr create` failed, surface the error verbatim
and stop. Do not proceed to Stage 8.

---

## Stage 8 — Confirm

Report to the user:

- Artefact: {path}
- Implementation summary: {summary_path} — Status: {summary_status} (or, if Stage 5 failed, report that the summary artefact could not be produced and surface the captured summary-writer / git error)
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
  `.claude/skills/zego-ci-validation/SKILL.md`.
- **Spawn the CI validation agent from Step 1 in a fresh message each
  iteration.** Same principle as the review loop — never reuse a prior agent's
  context.
- **The CI fixer in Step 3 applies minimal fixes only.** It addresses the failing
  command's output — no refactoring, no unrelated changes.
- **Stage 5 (implementation summary) is non-gating.** A summary-writer failure
  or any git failure while committing the artefact never blocks push or PR. Stage
  5 branches on the summary-writer's returned `failure_kind` (`transient` retries
  once then proceeds; an unstructured return with no `failure_kind` is treated as
  `transient`; `terminal` proceeds without retry), and the `git add` /
  `git diff --cached` unexpected-error / `git commit` failure paths each surface
  the error and proceed to push/PR without `summary_path`. A `git commit` failure
  unstages via `git reset HEAD` (falling back to `git restore --staged`). Every
  failure is surfaced in the Stage 5 outcome and the Stage 8 Confirm report.
- **The summary artefact reference flows through to the PR and the Confirm
  report.** When Stage 5 produces an artefact, Stage 7 forwards `summary_path` and
  `summary_status` to `zego-create-pr` (optional inputs) and Stage 8 reports the
  artefact path and status; when Stage 5 failed, both are omitted and the Confirm
  report surfaces the captured error.

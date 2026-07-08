---
name: zego-fix-bug
description: You MUST use this when the user asks to fix a bug, resolve a defect, or address a bug ticket given a JIRA ticket URL or key — small or mid-size fixes that have no design document.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
---

You are the orchestrator for the `zego-fix-bug` skill. Take a JIRA bug ticket
end-to-end: read the ticket, diagnose the root cause, write a task spec,
produce the fix through sub-agents, review until PASS, validate CI, push,
and open a PR. You diagnose and write the task spec yourself; all code
changes go through writer and fixer sub-agents.

This skill exists for **small and mid-size bugs**. Two gates protect that
boundary. The confidence gate is a hard stop: an ambiguous ticket stops for
clarification instead of guessing. The size gate is a checkpoint, not a
wall: when a fix looks too big for this tool it pauses and puts the choice
to the engineer — escalate to the design-doc flow, or, if the size signal
is a false alarm in context, wave it through and continue. A bug fix
without a confirmed root cause and a regression test is not a fix — it is a
symptom patch that will come back.

---

## Inputs

The single argument is a JIRA ticket URL or bare ticket key, e.g.
`/zego-fix-bug https://zegons.atlassian.net/browse/AIDEV-123` or
`/zego-fix-bug AIDEV-123`.

Extract the ticket key with the pattern `[A-Z][A-Z0-9]*-[0-9]+`. If no key
can be extracted from the argument, stop:

> `{argument}` does not contain a JIRA ticket key or URL. Usage:
> `/zego-fix-bug <ticket-url-or-key>`.

---

## Stage 1 — Read the ticket

Fetch the ticket using the available Atlassian/JIRA MCP tooling (e.g.
`getJiraIssue`). If no JIRA tooling is available or the fetch fails, ask
the engineer to paste the ticket summary and description, then continue.

Extract and record:

- **Summary** — used to derive the branch and task slug.
- **Description** — symptoms, steps to reproduce, expected vs actual
  behaviour, environment, error messages, stack traces.
- **Links** — linked PRs, related tickets, attachments worth reading.

Do not judge the ticket's completeness yet — Stage 4 owns that decision,
after diagnosis has shown what the codebase itself can answer.

---

## Stage 2 — Branch

Check the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

- **Current branch starts with `{TICKET}_` or `{TICKET}-`** — you are
  already on the appropriate branch. Keep it and proceed to Stage 3.
- **Any other branch** — create a fresh branch from the remote default
  branch.

Before creating a branch, check the working tree:

```bash
git status --porcelain
```

If the output is non-empty, stop and ask the engineer to commit or stash
their changes first — never carry unrelated uncommitted work onto a bug-fix
branch.

Derive the branch name as `{TICKET}_{slug}`, where `slug` is the ticket
summary lowercased, any run of non-alphanumeric characters replaced with a
single hyphen, leading/trailing hyphens trimmed, truncated to 40
characters, trailing hyphens trimmed again after truncation. (Same
derivation as the design-doc skills' Stage 1 branch.)

Check whether the branch already exists — locally and on `origin` (a
prior run may have pushed it and the local ref since pruned) — emitting
neutral sentinels:

```bash
git rev-parse --verify --quiet "refs/heads/{branch}" >/dev/null && echo "LOCAL-EXISTS" || echo "LOCAL-ABSENT"
git ls-remote --exit-code --heads origin {branch} >/dev/null 2>&1 && echo "REMOTE-EXISTS" || echo "REMOTE-ABSENT"
```

- **`LOCAL-EXISTS`** — stop. Report as text (do not route through `echo`
  — the git-safety hook would block it):

  > Branch {branch} already exists locally — delete it (git branch -D
  > {branch}) before re-running, or check it out yourself and re-invoke
  > zego-fix-bug from it. No automatic reset or reuse.

- **`REMOTE-EXISTS`** (with `LOCAL-ABSENT`) — stop. Report as text:

  > Branch {branch} already exists on origin — check it out yourself
  > (git fetch origin {branch} && git checkout {branch}) and re-invoke
  > zego-fix-bug from it, or delete the remote branch before re-running. No
  > automatic reset or reuse.

- **Both `ABSENT`** — create it from the remote default branch. Resolve the
  default branch the same way the `zego-review` skill does (no `gh` required):

  ```bash
  DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
  git fetch origin "$DEFAULT"
  git checkout -b {branch} "origin/$DEFAULT"
  ```

---

## Stage 3 — Diagnose the root cause

Investigate before planning. The ticket describes a symptom; your job here
is to find the cause and prove it. Read code freely — this stage changes
nothing.

1. **Locate the failure.** Search the codebase for the error message,
   identifiers, and components named in the ticket (`rg`). Read the files
   involved and trace the path from input to failing behaviour.
2. **Reproduce the failure.** Reproduction is mandatory — the only open
   question is how, not whether: find the existing test closest to the
   failing behaviour and run it, or construct the smallest command or
   test that demonstrates the failure. A reproduction you have watched
   fail is worth more than any amount of reading. A bug you cannot
   reproduce will fail the Stage 4 confidence gate and dead-end at
   Stage 6's regression-test requirement anyway — better that surfaces
   here, before the spec is written. Confirm it reproduces the failure
   the **ticket** describes — not a different failure that happens to be
   nearby. Wrong bug = wrong fix.
3. **Hypothesise, then verify.** Before testing any hypothesis, write
   down two or three ranked candidates — anchoring on the first plausible
   idea is the classic diagnosis failure. Each must be falsifiable: "if X
   is the cause, then Y will be observable at `file:line`". Check the top
   one against the code and the reproduction; if the evidence contradicts
   it, move to the next — do not proceed on a hunch.
4. **Confirm the root cause, not the symptom.** Ask why the failure
   happens until the answer is a specific defect at a specific location.
   A fix at the symptom level (guarding a null, swallowing an error)
   leaves the defect in place and is not acceptable. The test for a real
   root cause: it explains why the invalid state arises, not merely where
   it is observed. If your fix would be equally "correct" without knowing
   why the value is invalid, it is a symptom patch — relabelling the
   crash site as "the defect at a specific location" does not change
   that.

Record: root cause with `file:line` evidence, the surviving hypothesis
and what falsified the others, the reproduction (test name or command),
the minimal fix, and every file the fix will touch.

---

## Stage 4 — Size and confidence gates

Both gates run on the diagnosis, size gate first. The confidence gate is a
hard stop — do not soften it into a warning and carry on. The size gate is
a checkpoint: it stops to put the call to the engineer, who may escalate or
wave it through (see below). Size comes first because escalation takes the
fix out of this skill entirely — there is no point resolving confidence on
work that is about to be parked.

### Size gate

The gate fires if ANY of the following holds:

- The fix touches more than 3 source files (test files and skill
  artefacts — the task spec, the diagnosis record — do not count towards
  the limit) or crosses 2+ components — separately deployed services, or
  top-level modules with their own owners.
- The fix requires a new or changed interface contract, API shape, or
  schema/data migration.
- There are multiple viable fix approaches with material trade-offs that
  someone should consciously decide between.
- The root cause is architectural — the defect is in a design, not in an
  implementation of one.

A fired criterion is advisory, not decisive. When any criterion fires, do
not escalate unilaterally and do not lose the diagnosis: put the call to the
engineer.

**First, preserve the diagnosis.** Before prompting, write and commit the
diagnosis record exactly as Stage 4b specifies — path, template, commit —
with its Size gate section recording the criterion that fired and outcome
"awaiting the engineer's decision". Commit the record first: a fired gate
can end with the engineer walking away and no further turn to run in.

If a later-stage return to this gate means the record already exists, update
it with the new evidence rather than creating a second file. Commit that
update under the subject `{TICKET}: Record size-gate decision` — not the
`{TICKET}: Record bug diagnosis` subject Stage 4b uses — so the two size-gate
record updates read consistently in the `git log` audit trail.

You write the record once here; the branches below only update its outcome.

**Then put the call to the engineer.** State the concern plainly, end the
turn, and wait:

> This fix looks larger than `zego-fix-bug` is meant for: {one-sentence reason,
> naming the criterion that fired}.
>
> The usual move here is to stop and run `zego-write-design-doc` (or
> `zego-write-design-doc-max`) — a fix this size benefits from a design others
> can review before any code is written. Worth a moment's thought before
> you decide.
>
> If you know this is a false alarm in context — genuinely small and
> low-risk despite tripping the signal — reply `continue` and I will
> proceed with the fix. Otherwise reply `escalate` (or just stop here) and
> I will hand off to the design-doc flow.

A clear wave-off is any unambiguous "yes, proceed" — `continue`, "go for
it", "yes, it's fine" — not the literal token alone. Anything short of that
is not consent: treat hesitation, a non-committal reply, or silence as a
hold, never as a wave-off — if the engineer never replies, the gate is not
cleared. If they ask a question instead of deciding ("what do you think?"),
answer it once — you hold the diagnosis they are asking about — and
re-prompt; do not escalate on the question itself, and do not proceed
without a clear wave-off.

Then act on the decision. In both branches you update the diagnosis
record's Size gate outcome (it already exists — update it, never write a
second file) and commit that update:

```bash
git add docs/bugs/{TICKET}-{slug}.md
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{TICKET}: Record size-gate decision

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

- **A clear wave-off — the engineer accepts the size.** Outcome: "waved
  through by the engineer". After committing, carry on to the confidence
  gate below; Stage 4b is already done, so do not re-write the record, and
  do not re-ask on the same evidence.
- **Anything else — escalate.** Outcome: "escalated". After committing,
  park any work in progress on the branch, uncommitted (the record itself
  stays committed — it is the one exception), and stop with:

  > This bug is larger than a small/mid-size fix: {one-sentence reason}.
  > `zego-fix-bug` is not the right tool — investigate further and run
  > `zego-write-design-doc` (or `zego-write-design-doc-max` for the deep-review
  > variant) to produce a design document and task specs instead.

  No code from this attempt is committed or merged — however much exists.
  The diagnosis record is the one exception: it is a doc, not code, and it
  is already committed. The record and the parked work together serve as
  reference material for the design doc. There is no "ship what's done as
  phase 1": a partial, undesigned change is exactly what the gate exists to
  prevent.

### Confidence gate

Proceed only if BOTH hold: every competing hypothesis has recorded
falsifying evidence, and the reproduction confirms the failure the
ticket describes. The gate is the Stage 3 record, not a feeling: an
alternative explanation that is still plausible — merely unexamined, not
falsified — fails the gate by definition.

If the ticket is too thin to diagnose (no reproduction path, no expected
behaviour, symptoms that match several causes) or the evidence leaves
competing hypotheses open, ask whoever holds the missing evidence —
usually the ticket reporter, via the invoking engineer:

> The ticket does not give me enough to fix this confidently.
>
> What I know: {evidence so far}
> What I cannot determine: {the specific unknowns}
> Questions: {numbered, specific — answerable without research}

Incorporate the answers and return to Stage 3 if they change the
diagnosis. Loop until the gate passes. An answer counts towards the gate
only if it carries evidence (a value, a date, a reproduction) — "yeah,
probably" from someone with no more data than you does not bridge the
gap. Never bridge an evidence gap with a plausible guess — a wrong fix
costs more than a clarifying question.

---

## Stage 4b — Record the diagnosis

The diagnosis is the most valuable forward-looking context this skill
produces — "we already ruled out X for this class of failure" must
outlive the fix. Write it to a durable home before planning the fix.

**If this record already exists, reconcile it before proceeding** — when
the size gate fires, Stage 4 writes and commits it before prompting, so on a
wave-off you reach this stage with it already written (its Size gate section
carries the engineer's decision). But size-first ordering means the committed
record can describe a *pre-confidence-gate* diagnosis that has since changed:
a wave-off, then a confidence-gate failure, then answers that send you back to
Stage 3 and yield a different root cause, can leave you here holding diagnosis
**D2** while the record still describes **D1** — and the size gate, now quiet,
skipped the "update it with new evidence" reconciliation. So do not skip purely
on existence. If the existing record was written from the *same* diagnosis you
are now holding, this stage is done — proceed to Stage 5. If the diagnosis has
changed since the record was written, reconcile the existing record's content
to the current diagnosis — same file, never a second file or a `-v2` — and
re-commit it, then proceed. Otherwise — the record does not yet exist, the
normal no-gate path — write it fresh here.

**Derive the path.** `docs/bugs/{TICKET}-{slug}.md` (slug derived from
the ticket summary with the same rules as Stage 2). If the filename
collides, append `-v2`, `-v3` until unused.

**Fill the record.** Read `.claude/templates/bug-diagnosis.md` and conform
to it — all sections present (the Size gate section only when the size gate
fired, recording the criterion and the outcome — awaiting the engineer's
decision, escalated, or waved through by the engineer), no template
placeholder text remaining. The diagnosis record is AI-native
(`docs/ai/steering/base/review-audience.md`): the template carries the
AI-native banner blockquote as its first content (after the frontmatter `---`,
before the `# ` H1). Resolve its placeholders — `{surface}` = `JIRA ticket`,
`{link}` = `https://zegons.atlassian.net/browse/{TICKET}` — so the emitted
blockquote reads, with `{TICKET}` interpolated and no `{` placeholder token
remaining:

```
> **AI-native artefact.** Human reviewers do not need to read this; the review surface for this phase is the JIRA ticket at https://zegons.atlassian.net/browse/{TICKET}.
```

The record is
lightweight institutional memory, nothing more. Interface contracts,
alternatives, and trade-off analysis belong to `zego-write-design-doc`, not
here — a record that seems to need them suggests the fix trips a
size-gate criterion: return to Stage 4 and re-run the gates. If no
criterion fires on re-run, the record does not need that content — cut
it to the template's sections and proceed. It carries:

- The root cause, with `file:line` evidence.
- The reproduction (test name or command).
- The surviving hypothesis, and what falsified the others.
- The JIRA link: `https://zegons.atlassian.net/browse/{TICKET}`.

**Self-check the banner before committing.** Confirm the resolved banner is the
first content with no placeholder remaining:

```bash
rg -q "^> \*\*AI-native artefact\.\*\* .*browse/{TICKET}\.$" docs/bugs/{TICKET}-{slug}.md && echo BANNER_OK || echo BANNER_MISSING
```

Anything other than `BANNER_OK` — banner absent or a literal `{surface}` /
`{link}` placeholder still present — must be fixed (re-write the record with the
resolved banner) before the commit below.

`docs/bugs/` records are durable: they are exempt from the periodic
task-spec collapse policy and are never reaped with the spec.

Commit the record:

```bash
git add docs/bugs/{TICKET}-{slug}.md
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{TICKET}: Record bug diagnosis

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Stage 5 — Write the task spec

Write the plan as a task spec so the implementation is fully briefed and
reviewable. Read `.claude/templates/task-spec.md` and conform to it — all
sections present, no template placeholder text remaining.

**Derive the path.** Find the next free task number for this ticket:
`docs/tasks/{TICKET}-TASK-{NN}-{slug}.md` (NN = 01 unless taken; slug
derived from the fix title with the same rules as Stage 2). If the
filename collides, append `-v2`, `-v3` until unused.

**Mint the feature identifier (AIDEV-188 / ADR 020).** `zego-fix-bug` is a
standalone path with no requirements or design phase to recover an identifier
from, so it **mints its own** — closing the FR-03 coverage hole for a flow with
no predecessor phase. Best-effort: a mint failure warns and proceeds without an
id (the fix still ships, just unlinked).

```bash
FEATURE_ID="$(.claude/scripts/feature-id.sh mint 2>/dev/null || true)"
```

**Fill the spec:**

- The task spec is AI-native (`docs/ai/steering/base/review-audience.md`): the
  template carries the AI-native banner blockquote as its first content (after
  the frontmatter `---`, before the `# ` H1). Resolve its placeholders —
  `{surface}` = `JIRA ticket`, `{link}` = `https://zegons.atlassian.net/browse/{TICKET}`
  (at write-time the bug-fix PR does not yet exist, so the banner deflects to the
  always-resolvable JIRA ticket; the PR's review-surface line, written later in
  Stage 10, authoritatively names the code changes — this seam is documented in
  `review-audience.md`). The emitted blockquote reads, with `{TICKET}`
  interpolated and no `{` placeholder token remaining:

  ```
  > **AI-native artefact.** Human reviewers do not need to read this; the review surface for this phase is the JIRA ticket at https://zegons.atlassian.net/browse/{TICKET}.
  ```

- Frontmatter: `ticket: {TICKET}`, `branch:` = the branch from Stage 2, and —
  when `FEATURE_ID` is non-empty — `feature-id: {FEATURE_ID}` as the optional
  third permitted key (alongside `ticket` and `branch`). This is the
  artefact-backed source `zego-create-pr` recovers from at Stage 10 to stamp the
  PR trailer. When `FEATURE_ID` is empty (mint failed), omit the key entirely —
  do not write an empty value.
- Header lines: `Feature: https://zegons.atlassian.net/browse/{TICKET}`,
  `Design: none — bug fix; diagnosis in Context below`,
  `Depends on: nothing`.
- `## Context` references the Stage 4b diagnosis record path as the
  durable home of the full diagnosis, and still carries inline the facts
  the writer acts on: root cause with `file:line` evidence, the
  reproduction, and the symptom-vs-cause distinction. The writer must not
  need to read a second file to act.
- `## Implementation constraints` includes: fix at the root cause only;
  minimal change; no refactoring of surrounding code.
- `## Test requirements` and `## Acceptance criteria` MUST include the
  regression test: a test that reproduces the bug, fails before the fix,
  and passes after it.
- `## Out of scope` lists the adjacent issues you noticed but must not
  touch.

**Self-check the banner before committing.** Confirm the resolved banner is the
first content with no placeholder remaining:

```bash
rg -q "^> \*\*AI-native artefact\.\*\* .*browse/{TICKET}\.$" docs/tasks/{TICKET}-TASK-{NN}-{slug}.md && echo BANNER_OK || echo BANNER_MISSING
```

Anything other than `BANNER_OK` — banner absent or a literal `{surface}` /
`{link}` placeholder still present — must be fixed (re-write the spec with the
resolved banner) before the commit below.

Commit the spec:

```bash
git add docs/tasks/{TICKET}-TASK-{NN}-{slug}.md
git commit -m "$(cat <<'EOF'
{TICKET}: Add bug-fix task spec

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Then tell the engineer, briefly: the root cause, the planned fix, the
files it touches, and the spec path. Do not wait for approval — the gates
in Stage 4 already decided this fix is small and certain. The engineer can
interrupt if they disagree.

---

## Stage 6 — Spawn writer agent (regression test first)

Tell the engineer: "Implementing fix for {TICKET}."

Spawn a general-purpose Agent. Fill every placeholder before sending.

```
You are fixing a bug described by a task spec. Do not ask questions — all
decisions are in the task spec below.

Task spec path: {path}

Task spec content:
{Full content of the task spec file, verbatim}

Work in this exact order:

1. Read every file listed in the Context section.
2. Study two or three existing test files near the bug before writing
   any test — match the framework, naming, fixtures, and runner command
   the codebase already uses.
3. Write the regression test FIRST — a test that reproduces the bug as
   described, at the seam where the bug actually occurs (the real call
   pattern, not a shallow stand-in that would pass for the wrong
   reasons). If no correct seam exists for the test, stop and return
   that finding — do not write a false-confidence test. If a fix is
   already present on the branch when you start, temporarily revert it
   so the test is demonstrated against the buggy code, then re-apply —
   fail-then-pass must be witnessed, never assumed. Run the test and
   confirm it FAILS for the expected reason (the bug), not for a setup
   error. If it passes before any fix, the diagnosis is wrong: stop and
   return that finding instead of fixing.
4. Apply the minimal fix at the root cause identified in the spec. If
   the fix cannot be achieved within the files the spec names — it needs
   more files, another component, or a contract change — STOP and return
   that finding. Do not expand the scope yourself.
5. Re-run the regression test and confirm it now PASSES. Then run the
   full test suite (or, if that is impractically slow, the suites for
   every touched module) and confirm nothing else broke — a fix that
   breaks an existing test is a regression, not a fix.
6. Remove any debug instrumentation (prints, temporary logs) you added
   while working.
7. Do not refactor, restructure, or fix anything beyond the spec. Note
   adjacent problems in your return; do not touch them.

Return: files changed, the regression test path, the test command, and
the before/after test output proving fail-then-pass.
```

Wait for the writer agent to return and handle its three stop findings —
none of them permits proceeding to Stage 7:

- **Regression test passed before the fix** — the diagnosis was wrong.
  Return to Stage 3 with that evidence.
- **No correct test seam exists** — return to Stage 4: a bug that cannot
  be locked down by a test at a real seam is often a design problem, so
  re-run the size gate with that finding; if the gate does not fire, take
  the seam question to the engineer. Never proceed to review without a
  fail-then-pass regression test.
- **Fix exceeds the spec's files** — the diagnosis missed scope. Re-run
  the Stage 4 size gate with the writer's evidence; expect it to fire.

If no stop finding fired, commit the writer's fix before entering the
review loop — the implementation gets its own commit, and Stage 7b's
review-cycle commits then capture only review-driven changes. Only
commit if there are actual changes:

```bash
git add -- {changed file(s)}
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{TICKET} TASK-{NN}: Implement bug fix

{one-line description of the fix}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Stage 7 — Review and fix loop

Maximum 3 iterations. Each iteration: run review → read verdict → exit
(PASS) or fix and loop again. Spawn the review agent in a fresh message
each iteration — never reuse a prior review agent's context.

### 7a — Spawn review agent

```
You are running the `zego-review` skill.
Read `.claude/skills/zego-review/SKILL.md` and execute it from Stage 1.
Do not ask questions — all context is below.

Ticket: {TICKET}
Branch: {branch}

The diff contains a bug fix plus its regression test, briefed by the task
spec for ticket {TICKET} in docs/tasks/.
```

Wait for the verdict string and findings file path.

### 7b — Read verdict and commit

Commit the current state regardless of verdict; only commit if there are
actual changes:

```bash
git add -- {changed file(s)}
git add docs/ai/reviews/ 2>/dev/null || true
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
{TICKET} TASK-{NN}: Review cycle {N} — {PASS|FAIL}

{one-line description of what changed this cycle}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

- **PASS** → exit the loop. Proceed to Stage 8.
- **FAIL** → continue to 7c.

If this is iteration 3 and the verdict is still FAIL, stop. Report the
findings-file path for each iteration with its blocker/major counts, and
note that each cycle is preserved as a commit. Do not proceed to Stage 8.

### 7c — Spawn fixer agent

Read the most recent findings file yourself. Extract every finding with
outcome `pending` and severity `blocker` or `major`, formatted as
`F{n} ({severity}) — {file}:{line} — {issue} — Suggestion: {suggestion}`.

```
You are fixing a bug-fix branch that failed review.
Do not ask questions — apply every fix listed below and return.

Files in scope: {changed file(s)}

Items to fix:
{the formatted F{n} lines — one per line}

Apply only these fixes. Do not add content, refactor, or change anything
not listed. If a fix would weaken or delete the regression test, do not
apply it — note it in your return instead. After applying all fixes,
return a bullet list of every change made.
```

Return to 7a.

---

## Stage 8 — CI validation and fix loop

**Read `.claude/skills/shared/ci-validation-loop.md` and execute Steps 1,
2, 3 defined there.** Fill its placeholders:

- `{ticket}` → `{TICKET}`
- `{branch}` → the branch from Stage 2
- `{changed file(s)}` → all files changed in Stages 6–7, plus the task spec
- `{task-nn}` → `TASK-{NN}` from Stage 5

On return:

- `verdict: passed` → proceed to Stage 9.
- `verdict: failed-max-iterations` carrying a `precondition: authentication`
  marker → this is an environment problem, not a code failure. Report the
  remediation path from the marker, then end the turn with:

  > Authenticate, then reply `continue` and I will re-run CI validation
  > from the top.

  On `continue`, re-run this stage from the top (fresh loop, iteration 1).
- `verdict: failed-max-iterations` with no marker → stop. Report to the
  user:

  > CI validation failed after 5 fix attempts.
  >
  > Failing command: `{failing_command}`
  > Most recent output is above.
  > Each cycle's state is preserved as a commit (`{TICKET} TASK-{NN}: CI validation cycle {N} — FAIL`); inspect `git log` to walk the iteration history.
  > Resolve the remaining failure manually and re-run.

  Do not proceed to Stage 9.

---

## Stage 9 — Push

```bash
git push -u origin HEAD
```

If the push fails, surface the error verbatim and stop. Do not proceed to
Stage 10.

---

## Stage 10 — Create PR

Spawn a sub-agent briefed to execute the create-pr skill — do not inline
PR creation here.

```
You are executing the create-pr skill.
Read `.claude/skills/zego-create-pr/SKILL.md` and execute it from Stage 1.
Do not ask questions — all inputs are below.

ticket: {TICKET}
branch: {branch}
task_spec_path: {task spec path from Stage 5}
labels: ai-bug-fix
review_surface: {label: the code changes in this PR (fix + regression test), link: {branch}}
```

The `review_surface` input names the human review surface for the bug-fix phase
(`docs/ai/steering/base/review-audience.md`): the code changes in this PR (the
fix plus its regression test). `zego-create-pr` renders it as one inline line
within Background. This is the authoritative human-surface signal — distinct
from the write-time JIRA-ticket banner on the task spec and diagnosis record,
per the documented bug-fix seam in `review-audience.md`. Pass the branch as the
`link` value; the PR it sits on is self-evident.

Wait for the sub-agent. If it reports that `gh pr create` failed, surface
the error verbatim and stop.

---

## Stage 11 — Report

Report to the engineer:

- Ticket: {TICKET} — {summary}
- Root cause: {one sentence, with file:line}
- Fix: {one sentence}
- Regression test: {test path} (failed before fix, passes after)
- Task spec: {path}
- Diagnosis record: {docs/bugs/ path from Stage 4b}
- PR: {URL}
- Findings files: list all `{TICKET}-*-*.md` in `docs/ai/reviews/`
- Review iterations: {N}

---

## Rules

- **No fix without a confirmed root cause.** Diagnosis (Stage 3) ends with
  evidence at `file:line`, not a plausible theory. Symptom patches —
  guarding the crash site, swallowing the error — are not fixes.
- **The regression test is non-negotiable.** It must exist, fail before
  the fix, and pass after. A fix whose test never failed proves nothing;
  if the test passes pre-fix, the diagnosis is wrong — go back, do not
  ship.
- **The confidence gate is a hard stop.** A competing hypothesis without
  falsifying evidence, or a reproduction that has not confirmed the
  ticket's failure → ask; never guess. Time pressure, a nearly-finished
  diagnosis, or an engineer who "just wants it fixed" do not relax it.
- **The size gate is the engineer's call, not yours.** Too big → stop and
  put the choice to the engineer: escalate to
  `zego-write-design-doc`/`zego-write-design-doc-max`, or wave the gate through when
  the size signal is a false alarm in context. Default to escalating; only a
  clear wave-off continues the fix; record the decision in the diagnosis
  record. Never decide either way silently on the engineer's behalf.
- **The gates apply continuously, not once.** "Stage 4 already passed" is
  never a reason to keep going. If ANY later stage — writing the spec,
  implementing, reviewing — reveals that the fix trips a size-gate
  criterion or that the confidence gate no longer holds (a falsified
  hypothesis revived, the reproduction contradicted), return to Stage 4
  immediately and re-run the gates on the new evidence. A prior size-gate
  wave-off covers only the scope the engineer saw; materially worse scope
  is new evidence and re-fires the gate. The amount of work already done
  has no bearing on the outcome; parked work feeds the design doc.
- **Minimal fix only.** No refactoring, no drive-by cleanups, no fixing
  adjacent bugs. Flag adjacent problems in the report; fixing them is a
  separate ticket.
- **You do not write or edit code.** The task spec is yours; every code
  change goes through the writer or fixer sub-agent.
- **Maximum 3 review iterations and 5 CI iterations.** Surface remaining
  findings rather than looping indefinitely.
- **Language-agnostic throughout.** Never assume a language, framework, or
  test runner — discover them from the repo (existing tests, CI config,
  CLAUDE.md). The same skill must work in Scala, Python, Kotlin, Swift,
  and JS/TS repos alike.
- **Fresh sub-agent each iteration.** Never reuse a prior review or CI
  agent's context.
- **UK English** in all human-readable output.

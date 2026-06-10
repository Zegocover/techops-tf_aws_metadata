---
name: review
description: You MUST use this when the user asks to review their code, run a code review, or verify a branch against Zego coding standards (with or without a task spec).
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
---

You are the orchestrator for the `review` skill. Review the current branch diff against Zego coding standards as defined in `docs/ai/steering/base/code-review.md`. You do not fix anything — review, record, and return a verdict.

---

## Parse `--no-handoff-gate` override (strict)

Before Stage 0, parse the override flag with strict semantics. This step
runs FIRST so any downstream stages see only the residual argument.

1. Split `ARGUMENTS` into whitespace-delimited tokens.
2. **Exact-match the override.** If the token `--no-handoff-gate` appears
   exactly (case-sensitive, no trailing characters, no fuzzy or
   typo-tolerant matching), remove it from the token list and set
   `override_active = true`. Otherwise `override_active = false`.
3. **Reject any other `--`-prefixed token.** Scan the remaining tokens. If
   ANY token starts with `--` and is not exactly `--no-handoff-gate`, stop
   immediately with this verbatim error (substituting the offending token):

   > Unrecognised flag: `{token}`. The only flag `review` accepts is `--no-handoff-gate`. Did you mean `--no-handoff-gate`?

   This rejection is deliberately broad — it covers near-miss typos (e.g.
   `--no-handoff_gate`) AND any other unknown flag (e.g. `--resume`,
   `--force`). Do NOT silently consume unrecognised `--`-tokens.

There is no empty-residual check for `review`: `review` takes no positional
argument from the standalone CLI form (it derives its inputs from the
current branch). The override is still rejected if it appears with any
other unrecognised `--`-token.

---

## Stage 0 — Implementation-phase PR handoff gate

This stage runs ONLY when `review` is invoked standalone. It is a **pure
prepend**: review's existing Stage 1 and below are UNCHANGED — there is no
renumbering. Internal callers (`task-implementer.md` Stage 3a,
`.claude/skills/fix-pr-comments/SKILL.md`, `.claude/skills/fix-buildkite/SKILL.md`) invoke
review "from Stage 1" and therefore enter BELOW this gate and skip it. This
is the load-bearing structural guard described in ADR 011 — it is what
prevents implement's Stage 3 review loop from deadlocking on the
implementation PR that does not exist until implement's own Stage 6.

Stage 0 captures the current branch via its own `git rev-parse`. Stage 1
independently re-derives the branch via its own existing `git rev-parse` —
no variable is threaded between Stage 0 and Stage 1. Stage 1's
`git rev-parse` line is NOT rewritten into a reference to a Stage 0
variable; the two stages each call `git rev-parse` and the outputs agree.

Get the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

Store this as the gate's `{branch}` for the call below.

Read `.claude/skills/shared/handoff-gate.md` and execute it with placeholders:

| Placeholder | Value |
|-------------|-------|
| `{branch}` | the current branch captured above |
| `{phase_name}` | `implementation` (substituted into the override notice line printed by Step 1 when the override is active) |
| `{override_active}` | the value parsed by the dispatcher above |

The gate is a pure query: it returns a sentinel object describing the PR
state and never halts itself. Inspect the returned sentinel's `.state`:

- `OVERRIDE`, `OPEN`, or `MERGED` → pass. Proceed to Stage 1.
- `NONE`, `CLOSED`, `DRAFT`, or `GH_FAIL` → HALT. Print the canonical
  halt-message template from `.claude/skills/shared/handoff-gate.md` for the
  returned `.state`, filling `{phase_name}` = `implementation`,
  `{skill_name}` = `review`, `{branch}` = the current branch, and (for
  `CLOSED` / `DRAFT`) `{number}` and `{url}` from the sentinel, or (for
  `GH_FAIL`) `{stderr}` from the sentinel. The calling skill stops — no
  findings file is written.

---

## Stage 1 — Validate branch and get diff

Get the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

Parse against the regex `^([A-Z][A-Z0-9]*-[0-9]+)[_-](.+)$`:
- Group 1 is the **ticket** (e.g. `PLAT-4321`)
- Group 2 is the **description slug**, derived in this exact order:
  1. Lowercase group 2.
  2. Truncate to 40 characters.
  3. Strip all trailing hyphens (`s/-+$//`).

  This derivation is the canonical slug; Stage 3 consumes it verbatim
  and MUST NOT re-derive from the branch name.

  Worked example — branch `AIDEV-65_TASK-01_add-red-flags-to-all-discipline-enforcin`:
  - Group 2: `TASK-01_add-red-flags-to-all-discipline-enforcin`
  - Lowercased: `task-01_add-red-flags-to-all-discipline-enforcin`
  - Truncated to 40: `task-01_add-red-flags-to-all-discipline-`
  - Trailing hyphens stripped: `task-01_add-red-flags-to-all-discipline`

If the branch does not match, fail immediately:

```
Branch '{branch}' does not match the required format TICKET-description
(e.g. PLAT-4321-add-auth-endpoints). Rename the branch before running review.
```

Determine the base branch:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main
```

Get the diff and changed file list:

```bash
git fetch origin $BASE --quiet
git diff origin/$BASE...HEAD
git diff --cached
git diff
git diff --name-only origin/$BASE...HEAD
git diff --name-only --cached
git diff --name-only
```

Deduplicate the file list. If all diffs are empty, report "no changes to review" and exit cleanly.

---

## Stage 2 — Read code-review.md and determine active groups

Read `docs/ai/steering/base/code-review.md` in full. This document is the authoritative source for all check definitions, severity semantics, and output format. Do not re-derive or invent checks — every sub-agent must work from this document.

Determine which groups are active:

- **A** — always active
- **B** — always active
- **C** — always active
- **D** — always active
- **E** — active only if a task spec exists for this ticket:
  ```bash
  rg -l "^ticket: {TICKET}$" docs/tasks/ 2>/dev/null | head -1
  ```
  If found, note the path as `TASK_SPEC_PATH`. If not found, skip Group E silently.

  Also search for design docs (run only when the task spec was found; capture all matches — more than one file may share the same `JIRA:` value):
  ```bash
  rg -l "^JIRA: {TICKET}$" docs/design/ 2>/dev/null
  ```
  Collect all returned paths as `DESIGN_DOC_PATHS` (a list). If none are found, `DESIGN_DOC_PATHS` is empty — Group E still runs on task spec alone.
- **F** — active only if the changed file list contains any `.py` files
- **G** — active only if the changed file list contains any `.proto` files or files with `converter` in the path. Also confirm `docs/ai/steering/domains/protobuf-converters.md` exists — if the trigger fires but the file is missing, record a validation error and skip Group G.
- **H** — always active

`TASK_SPEC_PATH` (the path captured above when Group E activates, or empty when no task spec was found for the ticket) is a stage-scoped value that Stage 2b reads directly. Do not re-run the `rg -l "^ticket: {TICKET}$" docs/tasks/` lookup in Stage 2b.

---

## Stage 2b — Pre-implementation detection

Inputs:

- `TICKET` — captured in Stage 1.
- `TASK_SPEC_PATH` — set by Stage 2 (empty string when no task spec exists for the ticket; literal path otherwise).
- Changed-file list with add/modify/delete status from `git diff --name-status` against the base branch:

  ```bash
  git diff --name-status origin/$BASE...HEAD
  git diff --name-status --cached
  git diff --name-status
  ```

  Deduplicate by file path (for `R`/`C` entries, key on the new/destination path); if the same file appears with different status letters across the three commands, keep the most-additive entry (`A` > `M` > `R`/`C` > `D` — any non-deletion status beats `D`). The command runs against the same base as the Stage 1 diff collection.

Logic — set `PRE_IMPL = TRUE` iff ALL of the following hold:

1. `TASK_SPEC_PATH` is non-empty (i.e. Group E would otherwise activate).
2. Every entry in the deduplicated changed-file list matches at least one of:
   - the literal `TASK_SPEC_PATH` (exact file-path match), OR
   - `docs/design/{TICKET}-*.md` (path-segment glob — `*` does not cross `/`), OR
   - `docs/tasks/{TICKET}-*.md` (path-segment glob — covers `{TICKET}-TASK-NN-*.md` plus any other ticket-scoped task files including `-v2` regeneration variants).

   For rename (`R`) and copy (`C`) entries, which carry two paths (`old<TAB>new`), the match is evaluated against the **new path** (the destination) — the old path is ignored.

   The literal `TASK_SPEC_PATH` alternative ensures Stage 2b agrees with Stage 2 even when the task-spec filename does not start with `{TICKET}-` (e.g. `docs/tasks/legacy-notes-AIDEV-111.md` whose frontmatter says `ticket: AIDEV-111`).
3. At least one entry has status `A` (added), `M` (modified), `R` (renamed), or `C` (copied) — i.e. NOT every entry is a deletion; renames and copies are legitimate non-deletion changes that keep the diff `PRE_IMPL` eligible. Leave `PRE_IMPL = FALSE` only when EVERY entry has status `D`. A planning-cancellation/revert is not a pre-implementation state and must not be reported as one.

Detection is path-based only. Do not inspect file contents. The `A`/`M`/`D`/`R`/`C` status column from `git diff --name-status` is structural metadata, not file content.

Side effects when `PRE_IMPL = TRUE`:

- Remove `E` from the active groups list before Stage 4 dispatch.
- Queue a Validation-errors entry with the exact reason text: `Group E skipped: pre-implementation (diff contains only planning artefacts for {TICKET})` (substitute `{TICKET}` with the literal ticket key).

When `PRE_IMPL = FALSE`, no changes — Stage 2's group activation stands as-is and Stage 4 proceeds against the full active set.

Errors: none — Stage 2b is purely structural file-pattern matching plus a status check.

> Note on interaction with `docs/ai/steering/base/pull-requests.md` rule 9: a `PRE-IMPLEMENTATION` verdict does not endorse running `review` on WIP branches — rule 9 still applies.

---

## Stage 3 — Compute revision number

Use the canonical slug derived in Stage 1; do not re-derive from the branch name.

```bash
ls docs/ai/reviews/{TICKET}-{slug}-*.md 2>/dev/null
```

Extract revision numbers from filenames matching `{TICKET}-{slug}-(\d{3})\.md` exactly. New revision = max + 1, zero-padded to 3 digits. Start at `001` if none exist.

New filename: `docs/ai/reviews/{TICKET}-{slug}-{revision}.md`

---

## Stage 4 — Spawn sub-agents in parallel

Spawn all active group sub-agents in a **single message**. Running them in parallel is the whole point — spawning across messages serialises them and defeats the purpose.

Every sub-agent receives:
- The absolute repo path
- The base branch name and the commands to obtain the diff (`git diff origin/{BASE}...HEAD`, plus `--cached` and unstaged)
- A pointer to `docs/ai/steering/base/code-review.md` with the specific group section to apply
- The path(s) to any standard files the group requires
- The output format as defined in `docs/ai/steering/base/code-review.md` — per-check block with tagged lines, plus YAML findings list
- Hard rule: every check that ran must appear as a line — `[pass]` lines are required

**Sub-agent briefs — one per active group:**

For each group, the brief follows this shape. Fill in the group letter, name, section heading, and standard file paths before sending.

```
You are running the {GROUP LETTER} — {GROUP NAME} checks for the current diff.

Load docs/ai/steering/base/code-review.md and read the section "## Group {LETTER} — {NAME}" in full.
Apply every check defined in that section.

{If the group references standard files:}
Load the following standard files in full and use them as the rule source:
- {standard file path(s)}

Obtain the diff with:
  git diff origin/{BASE}...HEAD
  git diff --cached
  git diff

{Group-specific context, if any — see below.}

Return exactly what docs/ai/steering/base/code-review.md specifies under "## Output format":
1. A per-check block headed "### Group {LETTER} — {NAME}".
   One line per check, tagged [pass] / [advisory] / [warning] / [error].
2. A YAML findings list for every [warning] and [error]. findings: [] if clean.
```

Group-specific context to append to the brief:

- **Group A:** Include the branch slug (`{slug}`) and instruct the sub-agent to derive recent commit messages with `git log origin/{BASE}..HEAD --oneline` for the scope coherence check.
- **Group B:** Standard files are `docs/ai/steering/base/logging.md`, `docs/ai/steering/base/observability.md`, and `docs/ai/steering/base/environment.md`. Check every new or modified log call, metric instrument, span operation, and configuration/environment variable usage. Honour each file's Applicability section: the backend-surface rules (OTel/Datadog metric & span instrumentation; the GitOps/Helm/`secrets-config` provisioning workflow) act only where the diff touches that surface — do not raise findings for their absence in a repo that has no such surface. The universal cores (no logged credentials/PII, structured messages, log levels, single config entry point, documented variables) apply wherever the relevant code exists. Gate by surface presence, not by classifying the repo's stack.
- **Group C:** Standard file is `docs/ai/steering/base/testing.md`. Check every new or modified test file, fixture, and coverage configuration.
- **Group D:** No standard file. Instruct the sub-agent to generate candidate risk scenarios specific to the code patterns present, then investigate each — grounding every finding in what the diff actually contains.
- **Group E:** Use the task spec path (`{TASK_SPEC_PATH}`) and design doc paths (`{DESIGN_DOC_PATHS}`, may be empty list) found in Stage 2. Send the sub-agent this brief (fill every placeholder before sending; omit the design doc block entirely if no `DESIGN_DOC_PATHS` were found; if multiple design docs exist, include each under its own `### Design doc: {path}` header):

  ```
  You are running the E — Acceptance criteria checks for the current diff.

  Task spec path: {TASK_SPEC_PATH}

  Task spec content:
  {Full content of the task spec file, verbatim}

  {If DESIGN_DOC_PATHS is non-empty, for each path in DESIGN_DOC_PATHS:}
  ### Design doc: {path}

  {Full content of that design doc file, verbatim}

  Obtain the diff with:
    git diff origin/{BASE}...HEAD
    git diff --cached
    git diff

  Instructions:
  1. Read the task spec in full (content is above; path is given if you need to re-read).
  2. If one or more design docs were provided, read each for additional context on the intent and constraints of the change.
  3. Locate the Acceptance criteria section in the task spec. For each AC item,
     determine pass or fail by checking whether the diff satisfies that criterion.
  4. Return one [pass]/[error] line per AC item. If the task spec has no
     Acceptance criteria section, return a single [advisory] line:
     "no acceptance criteria found".

  Load `docs/ai/steering/base/code-review.md` and read the section "## Output format"
  in full — use it as the authoritative schema for the per-check block and
  YAML findings list.

  Return exactly what docs/ai/steering/base/code-review.md specifies under "## Output format":
  1. A per-check block headed "### Group E — Acceptance criteria".
     One line per AC item, tagged [pass] / [error]. Or one [advisory] if no ACs.
  2. A YAML findings list for every [error]. findings: [] if all pass.
  ```

  Note: also log the matched task spec path (and all design doc paths if found) in the review report so they are visible.
- **Group F:** Standard file is `docs/ai/steering/languages/python.md`. Check every new or modified Python file against Python conventions (including the Python-specific environment/config rules in that file).
- **Group G:** Standard file is `docs/ai/steering/domains/protobuf-converters.md`. Check every new or modified proto and converter file.
- **Group H:** Standard files are `docs/ai/steering/base/error-handling.md`, `docs/ai/steering/base/file-organisation.md`, `docs/ai/steering/base/resilience.md`, and `docs/ai/steering/base/spelling.md`. Check error handling patterns, file sizes and structure, retry/timeout/idempotency logic, and human-readable text spelling. Honour each file's Applicability section: translate error-handling's "exception" vocabulary into the diff's language idiom (typed-result patterns such as Rust/Swift `Result`, Scala `Either`/`Try`, or Go `(value, error)`) rather than applying it literally, and read file-organisation's line-count targets as language-relative signals — do not raise findings against verbose languages or framework-shaped files on a literal line count. Gate by surface presence, not by classifying the repo's stack.

If a sub-agent returns malformed output or fails: retry that group once. If it fails again, run that group's checks inline in the orchestrator. Do not silently drop a group — every active group must produce output.

---

## Stage 5 — Merge results

1. Collect the per-check block from every sub-agent.
2. Concatenate findings lists from all sub-agents.
3. De-duplicate: if two sub-agents flag the same finding, keep the higher-severity entry. Match on `(file, line, rule)` when `rule` is present; fall back to `(file, line, issue)` when `rule` is absent or `n/a` (Groups A and D have no rule file).
4. Recount: blockers, majors, minors, nits.
5. Verdict (evaluate top-to-bottom; first match wins):
   - If blockers or majors > 0 → **FAIL**
   - Else if PRE_IMPL=TRUE → **PRE-IMPLEMENTATION**
   - Else → **PASS**
6. Renumber findings F1, F2, … sorted by severity (blocker → major → minor → nit), then alphabetically by file path within each severity group.
7. Convert each YAML finding to markdown:

```markdown
### F{n} — {severity} — {file}:{line}

- rule: {rule link}
- issue: {issue}
- suggestion: {suggestion}
- outcome: pending
- outcome-note:
```

---

## Stage 6 — Write findings file

```bash
mkdir -p docs/ai/reviews
```

Write to: `docs/ai/reviews/{TICKET}-{slug}-{revision}.md`

```markdown
# Code review {TICKET}-{slug}-{revision}

- ticket: {TICKET}
- revision: {revision}
- branch: {branch}
- base: origin/{BASE}
- created: {ISO 8601 UTC timestamp}
- status: {clean | in-progress | pre-implementation}
- verdict: {PASS | FAIL | PRE-IMPLEMENTATION}
- blockers: {count}
- majors: {count}
- minors: {count}
- nits: {count}
- groups-active: {comma-separated list of group letters that ran, e.g. A, B, C, D, F, H}

## Summary

{One paragraph: what the diff does, which groups ran, and the outcome. For PASS: confirm all checks passed and note any advisories. For FAIL: name the blocking issues and which group found them.}

## Review detail

{Per-check blocks from all sub-agents in group order: A → B → C → D → E → F → G → H.
Each block is the sub-agent's per-check output verbatim — tagged lines only, no prose.}

## Validation errors

{One bullet per skipped group, with reason — for missing standard files, or other validation conditions such as pre-implementation. Omit section if none. When Stage 2b set PRE_IMPL=TRUE, include the exact reason string: `Group E skipped: pre-implementation (diff contains only planning artefacts for {TICKET})`.}

## Findings

{All numbered findings in markdown form from Stage 5. If none:}
{When verdict is PASS:} No findings — diff meets all active standards.
{When verdict is PRE-IMPLEMENTATION:} Implementation not yet present; AC verification deferred.
```

Set `status: clean` if PASS, `status: in-progress` if FAIL, `status: pre-implementation` if verdict is `PRE-IMPLEMENTATION`. When Stage 2b set `PRE_IMPL=TRUE`, `groups-active` excludes `E` (the post-skip set), and the `## Validation errors` section carries the queued skip-reason entry from Stage 2b.

---

## Stage 7 — Report

In the chat:

1. Path to the findings file written.
2. Verdict and counts: `PASS`, `PRE-IMPLEMENTATION`, or `FAIL — {n} blocker(s), {n} major(s), {n} minor(s), {n} nit(s)`.
3. If FAIL: list each blocker and major finding (issue only, one line each).
4. If PASS: "Diff meets all active standards." If PRE-IMPLEMENTATION: "Implementation not yet present; AC verification deferred." instead.
5. Any groups skipped (missing standard files, or pre-implementation) — name each skipped group with its reason. When verdict is `PRE-IMPLEMENTATION`, name Group E with reason "pre-implementation (diff contains only planning artefacts for {TICKET})" and list findings from the groups that did run.

---

## Rules

- **Spawn all sub-agents in a single message.** Parallel execution is the whole point.
- **Every check must be listed.** Sub-agents that return only failures are not providing an audit trail. `[pass]` lines are required.
- **Checks come from code-review.md, not from this file.** Sub-agents must load and apply the group section from `docs/ai/steering/base/code-review.md`. Do not invent or re-derive checks.
- **Do not fix anything.** Review and record only.
- **Do not edit prior findings files.** They are historical record.
- **Group E is silently skipped when no task spec is found in `docs/tasks/`.** Do not emit a finding for its absence. The design doc is supplementary — its absence does not prevent Group E from running.
- **Pre-implementation guard (Stage 2b).** When a task spec exists for the ticket AND every changed file matches the literal `TASK_SPEC_PATH`, `docs/design/{TICKET}-*.md`, or `docs/tasks/{TICKET}-*.md` (matching the new/destination path for `R`/`C` entries), AND at least one entry has status `A`, `M`, `R`, or `C`, Stage 2b sets `PRE_IMPL=TRUE`, removes `E` from the active groups, and queues the exact Validation-errors entry `Group E skipped: pre-implementation (diff contains only planning artefacts for {TICKET})`. The verdict is `PRE-IMPLEMENTATION` and the status is `pre-implementation` iff no remaining group produced a blocker or major — `FAIL` still wins otherwise. Detection is path-based only; only deletion-only diffs (EVERY entry status `D`) do NOT classify as pre-implementation. No override flag exists. This does not endorse running review on WIP branches; `pull-requests.md` rule 9 still applies.
- **Group G is silently skipped when no proto/converter files are in the diff.** Record a validation error only if the trigger fires but the standard file is missing.
- **Do not flag issues caught by pre-commit, lint, or type checking.** Only flag what structural review can see.

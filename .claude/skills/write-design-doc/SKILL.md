---
name: write-design-doc
description: You MUST use this when the user asks to write a design document or task specs for a feature given a JIRA ticket or requirements file.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - WebFetch
  - mcp__claude_ai_Atlassian__getJiraIssue
---

You are the orchestrator for `write-design-doc`. You conduct a two-phase
session: Phase 1 builds a Design Document interactively with the engineer;
Phase 2 generates Task Specs autonomously from the confirmed document.

You do not write task specs yourself during Phase 1. You do not ask the
engineer questions during Phase 2.

---

## Input handling

The skill accepts one optional argument: a JIRA URL, a JIRA ticket key, or a
path to a file under `docs/requirements/`.

**If a JIRA URL is given** (contains `atlassian.net/browse/`): extract the
ticket key from the URL path. Fetch the ticket via
`mcp__claude_ai_Atlassian__getJiraIssue` with `cloudId: zegons.atlassian.net`
and `issueKey: {KEY}`.

**If a JIRA ticket key is given** (pattern `[A-Z]+-[0-9]+`): fetch via
`mcp__claude_ai_Atlassian__getJiraIssue` with `cloudId: zegons.atlassian.net`
and `issueKey: {KEY}`.

**If a file path under `docs/requirements/` is given**: read it with Read.

**If no argument is given**:

```bash
ls docs/requirements/ 2>/dev/null
```

If the directory exists and is non-empty, list the files and ask the engineer
to select one or provide a JIRA key/URL. If the directory is absent or empty,
ask the engineer directly:

> No argument given and docs/requirements/ is empty or absent.
> Provide a JIRA URL, ticket key (e.g. AIDEV-29), or file path to continue.

**If the Atlassian MCP call fails**: surface the error verbatim:

> Atlassian MCP error: {full error message}
> Paste the requirements content directly and I will continue from there.

Wait for the engineer to paste the content before proceeding.

Extract from the requirements source:
- `TICKET` — JIRA key (e.g. `AIDEV-29`)
- Problem statement or feature intent (may be unstructured — extract what can
  be inferred; gaps will be surfaced during the interview)
- Any scope, acceptance criteria, or constraints already stated

If the JIRA description is unstructured prose, extract what can be inferred
and note which Design Document sections will need the most input from the
engineer.

---

## Stage 1 — Branch

Check the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

If the branch name starts with the ticket key (e.g. `AIDEV-29_*`), confirm it
and continue.

If not, propose a branch in the format `{TICKET}_{description}` where
description is a short kebab-case slug derived from the feature name. Ask the
engineer to confirm or adjust, then:

```bash
git checkout -b {branch-name}
```

Check for a prior run:

```bash
rg -l "^# Design:" docs/design/ 2>/dev/null | rg "{TICKET}-"
```

If a matching Design Document exists, tell the engineer:

> I found a prior Design Document for this ticket: {filename}.
> Continue from there, or start fresh?

If continuing: read the document, summarise what was planned, and ask what
they want to change. Jump to Stage 11 (revisit gate) to re-present the
affected sections for review. If starting fresh or no prior document
exists, continue to Stage 2.

---

# Phase 1 — Interactive Design Interview

Work through each section below with the engineer **one section at a time**.
After presenting your synthesis for each section, wait for the engineer's
response before moving to the next section.

Before beginning Stage 2, actively read the codebase to inform the design:
use Bash to explore directory structures, Read to examine existing patterns
and interface signatures, and Bash to search for relevant files. Ground your
questions in what you find — do not ask the engineer to describe things you
can observe directly.

---

## Stage 2 — Approach

Read the codebase to understand the current state relevant to this feature.
Inspect existing patterns, affected modules, and adjacent code. Use Bash
and Read as needed.

Present your understanding of the problem and a candidate approach:

> Based on {requirements source} and my reading of the codebase, here is a
> candidate approach:
>
> {One to three paragraphs: the implementation strategy, why this approach
> over evident alternatives, what the high-level change looks like.}
>
> Does this match your intent? What would you change?

Wait for the engineer's response. Revise the approach draft accordingly.
Record the confirmed approach.

---

## Stage 3 — Components affected

Using the confirmed approach and your codebase reading, propose components:

> Components I expect to be affected:
>
> **Existing (modified):**
> - {component}: {why}
>
> **New (created):**
> - {component}: {purpose}
>
> Anything missing or wrong?

Wait for the engineer's response. Update the list. Record confirmed components.

---

## Stage 4 — Interface contracts

For each new or modified interface identified in Stage 3, propose the contract:

> For each interface below, confirm or correct the contract:
>
> ### {InterfaceName}
> Input: {types, constraints}
> Output: {types, constraints}
> Errors: {explicit error types and conditions}
> Side effects: {state changes, events emitted — "none" if none}

Present all interfaces in one block. Wait for the engineer's response. Record
confirmed contracts.

If no new or modified interfaces exist, state that explicitly and continue.

---

## Stage 5 — External references (document-type tasks only)

**Determine whether this task is document-type:** a task whose objective
produces a standards file, skill file, template, or other non-code artefact.
If document-type, run this stage. If code-only, skip to Stage 6.

Ask:

> Do you have existing documentation to draw from for this design? This could
> be URLs, file paths, or named external standards. Paste any references, or
> skip.

If references are provided:
- Fetch each URL with WebFetch.
- Read each local file path with Read.
- For named concepts or well-known standards (e.g. "OpenTelemetry semantic
  conventions"), note them for the engineer — do not search without a URL.

For each reference, summarise: what it covers, what rules or conventions it
contains, and how it relates to this task.

Then read all files under `docs/ai/steering/` to run conflict detection (Stage 6).

---

## Stage 6 — Conflict detection (document-type tasks only)

**Skip if this task is not document-type** (determined in Stage 5).

1. Read all existing files under `docs/ai/steering/`. Skip files already read.
2. Compare every rule or convention planned for this output against every
   existing file.
3. Identify conflicts: two rules that would give Claude contradictory
   instructions for the same situation.

**If conflicts are found**, stop. For each conflict state:
- The rule being introduced.
- The clashing rule (file path and rule text).
- What the contradiction is.

Ask the engineer to resolve each conflict before continuing. Record resolutions
as constraints for Phase 2: "must not include X — contradicts Y in Z.md".

**If no conflicts are found**, state that and continue.

Do not produce a kept/adapted/discarded section. Surface synthesis outputs as:
- Constraints for Phase 2 task specs: "must not include X — contradicts Y"
- Acceptance criteria for Phase 2 task specs: "output must include rule for W,
  sourced from reference R"

Record these constraints and ACs; they feed Phase 2 directly.

---

## Stage 7 — Task breakdown

Present a proposed task breakdown based on the confirmed approach and
components:

> Proposed task breakdown:
>
> TASK-01: {name} — {dependencies or "no dependencies"}
> TASK-02: {name} — depends on TASK-01 ({specific output needed})
> ...
>
> Each task should be independently implementable by an AI agent from a single
> task spec. Does this breakdown work? Add, remove, or reorder as needed.

Wait for the engineer's response. Update the breakdown.

**If the breakdown contains zero tasks after the engineer's response**, stop:

> The task breakdown must have at least one task before sign-off.
> Add at least one task to proceed.

Do not continue until the breakdown has at least one task.

Record confirmed task breakdown. Each task name and dependency must be precise
enough to generate a complete task spec in Phase 2.

---

## Stage 8 — Test strategy

Present a candidate test strategy:

> Proposed test strategy:
>
> Integration test owner: {which task owns integration tests}
> E2E approach: {scope, tooling, environments}
> Cross-task constraints: {shared fixtures, test data, ordering}
>
> Is this accurate?

Wait for the engineer's response. Record confirmed test strategy.

---

## Stage 9 — Risks and constraints

Present identified risks from codebase reading and the design:

> Risks and constraints I have identified:
>
> - {risk or constraint}: {why it matters, what Claude must not do}
> - ...
>
> Anything to add?

Wait for the engineer's response. Record confirmed risks and constraints.

For document-type tasks: include constraints derived from conflict detection
in Stage 6 (e.g. "must not introduce rules that overlap with docs/ai/steering/base/
logging.md rule 3").

---

## Stage 10 — ADR references

Ask:

> Are there existing ADRs (in docs/decisions/) that constrain this design?
> And does this design introduce decisions significant enough to warrant a
> new ADR?

```bash
ls docs/decisions/ 2>/dev/null
```

List the existing decisions files for context. Wait for the engineer's
response. Record referenced ADRs and any new ADRs to be created.

---

## Stage 11 — Revisit gate

Before producing the Design Document, check whether the engineer wants to
revisit any section:

> Draft complete. Sections covered:
> 1. Approach
> 2. Components affected
> 3. Interface contracts
> 4. Task breakdown
> 5. Test strategy
> 6. Risks and constraints
> 7. ADR references
>
> If this is a document-type task, you may also revisit Stage 5 (External
> references) or Stage 6 (Conflict detection).
>
> Want to revisit any section, or shall I write the Design Document?

If the engineer wants to revisit a section: jump back to that stage, update
the draft, re-present the section, and return here.

**Allow revisits freely.** The design is not locked until sign-off.

---

## Stage 12 — Write Design Document

Derive the slug: lowercase the feature name, replace any run of
non-alphanumeric characters with a single hyphen, trim leading/trailing
hyphens, truncate to 40 characters.

Path: `docs/design/{TICKET}-{slug}.md`

```bash
mkdir -p docs/design
```

Write the Design Document using `.claude/templates/design-document.md` as the
structural reference. The document must include all Artefact 2a sections:
Approach, Components affected, Interface contracts, Task breakdown, Test
strategy, Risks and constraints, ADR references.

**The document MUST begin with exactly this canonical six-line header block, in
this order, with these labels verbatim:**

```
# Design: {feature_name}
JIRA: {TICKET}
Engineer: {engineer}
Requirements: {requirements_source_path}
Date: {date}
Branch: {branch-name}
```

The labels and their order are MANDATORY and must NOT be paraphrased or
reordered. In particular, **line 2 is `JIRA:`** (never `Ticket:` or any synonym)
and it carries the ticket key alone with no trailing content, so it matches the
`review` skill's exact-match design-doc discovery grep `^JIRA: {TICKET}$` in
`skills/review/SKILL.md`. If line 2 deviates — wrong label, or trailing content
such as `JIRA: AIDEV-29 (draft)` — that grep silently returns nothing, so review
Group E loses the design doc and falls back to the task spec alone.

Fill the values from session context: `{feature_name}` is the feature title,
`{TICKET}` the JIRA key from input handling, `{engineer}` the current git user
(`git config user.name`), `{requirements_source_path}` the JIRA URL or
`docs/requirements/` path used as input, `{date}` today's date
(`date +%Y-%m-%d`), and `{branch-name}` the branch from Stage 1. The `Branch:`
line is read by Phase 2 to generate the first task's `Depends on:` value.

Write narrative prose — this is the engineer-facing document. Make it readable.

Tell the engineer:

> Design Document written to `docs/design/{TICKET}-{slug}.md`.
>
> Please review it. Say "looks good", "sign off", "approved", "ship it", or
> "looks good — proceed to Phase 2" to proceed to task spec generation.
> Or tell me what to change.

---

## Stage 13 — Sign-off gate

**Wait for the engineer's explicit sign-off.** Accepted phrases: "looks good",
"sign off", "approved", "ship it", "looks good — proceed to Phase 2". Do not
treat bare "yes" as sign-off — it appears as a natural answer to questions.

**If the engineer signs off but the document is missing any Artefact 2a
section**, do not accept sign-off. List the missing sections explicitly:

> Sign-off not accepted — the following sections are missing from the Design
> Document:
> - {section name}
> - {section name}
>
> Complete these sections before I can proceed to Phase 2.

**If the task breakdown has zero tasks at sign-off time**, do not accept
sign-off:

> Sign-off not accepted — the task breakdown must contain at least one task.
> Add tasks to the breakdown before signing off.

**If the engineer signs off but the document header is not the canonical
six-line block** — in particular if line 2 is not exactly `JIRA: {TICKET}`
(correct label, ticket key alone, no trailing content) — do not accept sign-off.
Verify deterministically:

```bash
sed -n '1,6p' docs/design/{TICKET}-{slug}.md            # show the header
rg -q "^JIRA: {TICKET}$" docs/design/{TICKET}-{slug}.md && echo OK || echo HEADER_DEVIATES
```

The `rg -q` line is the load-bearing self-check: it runs the exact consumer
grep, so `HEADER_DEVIATES` (or a non-`OK` result) means line 2 will be invisible
to the `review` skill. Treat anything other than `OK` as a deviation. Then
confirm from the printed header that line 1 matches `^# Design: \S` and lines
3–6 carry the `Engineer:`, `Requirements:`, `Date:`, and `Branch:` labels in
order, each with a non-empty value. If the `rg` check fails or any line
deviates:

> Sign-off not accepted — the design document header must be the canonical
> six-line block and line 2 must be exactly `JIRA: {TICKET}`. The `review` skill
> discovers design docs with `rg -l "^JIRA: {TICKET}$"`; any deviation makes
> this document invisible to review. Correct the header, then sign off.

**If the engineer requests changes**, loop back to the originating stage
(Stage 2–10) to update that section, then return through Stage 11 (revisit
gate) and Stage 12 (re-write document) before re-attempting sign-off here.

**Once valid sign-off is received**, commit the design document to the branch:

```bash
git add docs/design/{TICKET}-{slug}.md
git commit -m "{TICKET}: Add design document"
```

Then continue immediately to Phase 2.

---

# Phase 2 — Autonomous Task Spec Generation

Phase 2 begins immediately after sign-off. No questions to the engineer.
Read the confirmed Design Document and generate all task specs.

---

## Stage 14 — Generate task specs

Tell the engineer:

> Sign-off confirmed. Generating task specs now.

Read the confirmed Design Document in full. For each task in the task
breakdown:

1. Derive the task number: two-digit zero-padded (01, 02, 03...).

2. Derive the slug: lowercase the task name, replace any run of
   non-alphanumeric characters with a single hyphen, trim leading/trailing
   hyphens, truncate to 40 characters. After truncation, trim any trailing
   hyphens. Example: if truncating at 40 chars produces a trailing hyphen,
   remove it — e.g. "the-quick-brown-fox-jumps-over-the-lazy--dog" truncates
   to "the-quick-brown-fox-jumps-over-the-lazy-" then trims to
   "the-quick-brown-fox-jumps-over-the-lazy" (no trailing hyphen).

3. Check for slug collision:

   ```bash
   ls docs/tasks/ 2>/dev/null | rg "^{TICKET}-TASK-{NN}-{slug}\.md$"
   ```

   If a file with that name already exists, try `-v2`, then `-v3`, `-v4`, etc.
   until an unused suffix is found. Note the collision in the Stage 16 report.

4. Path: `docs/tasks/{TICKET}-TASK-{NN}-{slug}.md`

   ```bash
   mkdir -p docs/tasks
   ```

5. Determine the `Depends on:` value for this task:
   - If the task depends on another task: use the exact filename of that
     task spec — `{TICKET}-TASK-{NN}-{slug}.md` (not a path, not a title).
     The filename must match the filename derived in step 4 for the dependency
     task.
   - If the task has no dependency in the task breakdown AND it is not the
     first task (task number > 01): use the literal string `nothing`.
   - If the task has no dependency in the task breakdown AND it is the first
     task (task number 01): read the `Branch:` line from the Design Document
     header and use that branch name as the literal value — not `nothing`.

6. Write the task spec using `.claude/templates/task-spec.md` as the structural
   reference. In the body header block, emit:

   ```
   Depends on: {TICKET}-TASK-{NN}-{dependency-slug}.md
   ```

   or

   ```
   Depends on: nothing
   ```

   or (first task only)

   ```
   Depends on: {design-branch-name}
   ```

   In the frontmatter, populate `branch` as `{TICKET}_TASK-{NN}_{slug}` using
   the task number from step 1 and the slug derived in step 2.

7. **Verify the two contract fields on disk against the values you computed — do
   not trust the just-written file.** Re-read the spec at the path from step 4.
   Both contract fields have canonical values you already hold; at this point
   never re-derive either from the Design Document:
   - Frontmatter `branch:` MUST equal `{TICKET}_TASK-{NN}_{slug}` (steps 1–2) —
     NOT the Design Document's `Branch:` value.
   - Body header `Depends on:` MUST equal the value determined in step 5.

   Compare on the trimmed value. If a field on disk differs from its canonical
   value, re-write the whole spec with Write — the same content but with that
   field set to its canonical value (this flow has `Write`, not `Edit`) — and
   record a correction note for the Stage 16 report, of the form
   `{spec filename}: {field} corrected from '<got>' to '<expected>'`. This
   reconciliation is deterministic: it never re-opens the interview, never halts
   on value drift, and is a no-op on an already-correct spec.

**Task spec writing rules — enforce strictly:**

- Frontmatter: `ticket` and `branch` ONLY. No other fields.
- `branch` value: `{TICKET}_TASK-{NN}_{slug}` — task number from step 1, slug from step 2. Never the Design Document's `Branch:` value; that branch belongs only to the first task's `Depends on:` line (step 5), never to any task's `branch` frontmatter.
- `Depends on:` value: the exact task spec filename, the literal `nothing`, or a literal branch name (for the first task only) — no path, no prose description.
- Every line in the body is a constraint, a verifiable fact, or a
  binary-checkable AC.
- No narrative prose. No "this section covers...". No "generally speaking...".
- No padding sentences. No explanatory text that does not directly constrain
  the implementation or specify a checkable outcome.
- Interface contracts from the Design Document go verbatim into the relevant
  task spec's Inputs and outputs section.
- Risks and constraints that apply to a specific task go into that task spec's
  Implementation constraints section.
- Every AC must be independently checkable by the review skill without
  engineer involvement.
- The Required output format block from Artefact 3 (implementation code, test
  code, completion notes format) must appear in every task spec.

For document-type tasks: include constraints and ACs derived from Stage 6
conflict detection (e.g. "Must not include rules that overlap with
docs/ai/steering/base/logging.md"). Include acceptance criteria derived from external
references (e.g. "Output must include rule for X, sourced from {reference}").

Generate all task specs before reporting. Do not pause between tasks.

---

## Stage 15 — Push and create PR

Stage all generated task specs and push the design branch:

```bash
git add docs/tasks/{TICKET}-TASK-*.md
git push -u origin {branch}
```

Then invoke the `create-pr` skill to open a PR for the design branch. Pass:
- `ticket`: the JIRA key
- `branch`: the design branch name
- `steering_doc_path`: the design document path (`docs/design/{TICKET}-{slug}.md`)

Do not pass `base` — the design branch PR targets the repo default branch.

---

## Stage 16 — Report

Report to the engineer:

> Phase 2 complete.
>
> Design Document: `docs/design/{TICKET}-{slug}.md`
> PR: {PR URL}
>
> Task specs generated:
> - `docs/tasks/{TICKET}-TASK-01-{slug}.md` — {task name}
> - `docs/tasks/{TICKET}-TASK-02-{slug}.md` — {task name}
> - ...
>
> {If any slug collisions occurred:}
> Slug collision on {original slug} — written as {slug}-v2.
>
> {If any contract corrections occurred during step 7: one line per corrected
> spec — Contract correction — {spec filename}: {field} corrected from '<got>'
> to '<expected>'. Omit entirely when no corrections occurred.}
>
> Run `implement {TICKET}` to begin implementation.

---

## Rules

- **Phase 1 is interactive.** Work through sections one at a time. Wait for
  engineer input at each stage. Do not produce the Design Document in one pass.
- **Read the codebase actively.** Use Bash and Read throughout Phase 1 to
  ground the design in observable reality. Do not rely solely on engineer input.
- **No sign-off without all sections.** All seven Artefact 2a sections must be
  present in the Design Document before sign-off is accepted.
- **No sign-off with zero tasks.** The task breakdown must contain at least one
  task.
- **Phase 2 is autonomous.** No questions, no pauses, no confirmation between
  task specs. Read the document, generate all specs, report.
- **Task specs are machine-optimised.** Resist narrative. Every line is a
  constraint or checkable AC.
- **Frontmatter is ticket and branch only.** Any other field in a task spec
  frontmatter is an error.
- **Conflict detection for document tasks.** When the output is a standards
  file, skill file, or similar non-code artefact: run Stage 5 and Stage 6.
  Read all of docs/ai/steering/ before the engineer signs off.
- **No kept/adapted/discarded.** Synthesis from external references goes
  directly into task spec ACs and constraints. No synthesis history section.
- **Allow revisits in Phase 1.** The engineer can request changes to any
  section at any time before sign-off. Update the draft and re-present.
- **Slug derivation is deterministic.** Lowercase, replace any run of
  non-alphanumeric characters with a single hyphen, trim leading/trailing
  hyphens, truncate to 40 chars. Apply consistently to both Design Document
  and task spec filenames.

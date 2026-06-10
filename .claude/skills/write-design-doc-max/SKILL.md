---
name: write-design-doc-max
description: You MUST use this ONLY when the user explicitly asks for the "max" design-doc flow (the high-context variant that runs an incremental review of every design and task document). For any other request to write a design document or task specs, use write-design-doc instead.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - Workflow
  - WebFetch
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__search
---

You are the orchestrator for `write-design-doc-max`. You conduct a two-phase
session: Phase 1 builds a Design Document interactively; Phase 2 generates
Task Specs autonomously from the confirmed document.

You dispatch all writing to sub-agents. You do not write task specs or design
documents yourself. You do not ask the engineer questions during Phase 2.

---

## Input handling

Resolve the requirements source before any other processing. Use this priority
chain in order:

1. **JIRA URL** (argument contains `atlassian.net/browse/`): extract the ticket
   key from the URL path. Fetch via `mcp__claude_ai_Atlassian__getJiraIssue`
   with `cloudId: zegons.atlassian.net` and `issueKey: {KEY}`.
2. **Direct file path**: read it with Read.
3. **Fuzzy search `docs/requirements/`**: list files, match by ticket key or
   keywords in filename.
4. **Fuzzy JIRA search** via `mcp__claude_ai_Atlassian__search` as last resort.
5. **Hard-fail** if nothing found or the resulting document is empty:

> A requirements source could not be found. Provide a JIRA URL, a file path,
> or a ticket key and ensure a matching requirements document exists in
> docs/requirements/.

Do not proceed to Phase 1 if step 5 is reached.

Extract from the requirements source:
- `TICKET` — JIRA key (e.g. `AIDEV-29`)
- Problem statement or feature intent
- Any scope, acceptance criteria, or constraints already stated

---

## Stage 1 — Branch

Check the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

If the branch name starts with the ticket key (e.g. `AIDEV-29_*`), confirm and
continue. If not, propose `{TICKET}_{description}` (short kebab-case slug from
the feature name), ask the engineer to confirm or adjust, then:

```bash
git checkout -b {branch-name}
```

Check for a prior run:

```bash
rg -l "^# Design:" docs/design/ 2>/dev/null | rg "{TICKET}-"
```

If a matching Design Document exists, offer to continue from it or start fresh.
If continuing: read the document and re-parse it into the following structured
fields before doing anything else:

- `feature_name` — from the document title (the `# Design: …` heading)
- `approach` — from the Approach section
- `components` — from the Components section
- `interface_contracts` — from the Interface contracts section
- `task_breakdown` — from the Task breakdown section
- `test_strategy` — from the Test strategy section
- `risks_and_constraints` — from the Risks and constraints section
- `adr_references` — from the ADR references section

If any required section is missing, empty, or renamed from the canonical
heading, halt with `HALT: Design document section '{section_name}' is missing
or empty — fix the document manually and re-run`. Do not proceed with
undefined fields.

Once all fields are populated, summarise what was planned, ask the engineer
what to change, and jump to Stage 11. If starting fresh or no prior document:
continue to Stage 2.

---

# Phase 1 — Interactive Design Interview

Work through each section one at a time. Wait for the engineer's response
before moving to the next section. Read the codebase actively before Stage 2 —
use Bash and Read to ground the design in observable reality.

---

## Stage 2 — Approach

Read relevant codebase areas. Present a candidate approach. Wait for response.
Record confirmed approach.

---

## Stage 3 — Components affected

Propose existing (modified) and new (created) components based on codebase
reading and confirmed approach. Wait for response. Record confirmed components.

---

## Stage 4 — Interface contracts

Propose contracts for each new or modified interface:
Input / Output / Errors / Side effects. Present all interfaces in one block.
Wait for response. Record confirmed contracts. If no new or modified interfaces
exist, state that and continue.

---

## Stage 5 — External references (document-type tasks only)

**Skip if code-only task.**

Ask for existing documentation references (URLs, file paths, named standards).
Fetch/read each. Summarise coverage and relevance. Then read all files under
`docs/ai/steering/` for Stage 6 conflict detection.

---

## Stage 6 — Conflict detection (document-type tasks only)

**Skip if not document-type** (determined in Stage 5).

1. Read all existing files under `docs/ai/steering/`. Skip files already read.
2. Compare every planned rule against every existing file.
3. If conflicts found: stop, state each conflict (rule introduced vs clashing
   rule with file path and text, the contradiction). Ask engineer to resolve
   before continuing. Record resolutions as Phase 2 constraints.
4. If no conflicts: state that and continue.

Record constraints and ACs from this stage for Phase 2.

---

## Stage 7 — Task breakdown

Propose a task breakdown. Each task must be independently implementable by an
AI agent from a single task spec. Wait for response. If zero tasks after
response: stop — require at least one task before continuing. Record confirmed
breakdown with precise names and dependencies.

---

## Stage 8 — Test strategy

Propose integration test owner, E2E approach, and cross-task constraints.
Wait for response. Record confirmed test strategy.

---

## Stage 9 — Risks and constraints

Present identified risks and constraints from codebase reading and design.
Include conflict-detection constraints (Stage 6) for document-type tasks.
Wait for response. Record confirmed risks and constraints.

---

## Stage 10 — ADR references

List existing decisions files:

```bash
ls docs/decisions/ 2>/dev/null
```

Ask which existing ADRs constrain this design and whether new ADRs are needed.
Wait for response. Record referenced and new ADRs.

---

## Stage 11 — Revisit gate

Before producing the Design Document:

> Draft complete. Want to revisit any section, or shall I write the Design
> Document?

Allow revisits freely — jump back to the originating stage, update the draft,
return here. Design is not locked until sign-off.

---

## Stage 12 — Write Design Document

Use the JIRA summary or requirements document title as `feature_name`; if
neither is available, prompt the engineer once.

Derive slug: lowercase feature name, replace non-alphanumeric runs with a
single hyphen, trim leading/trailing hyphens, truncate to 40 chars.

```bash
mkdir -p docs/design
```

Read `.claude/skills/write-design-doc-max/design-writer.md` in full. Dispatch to it via
the Agent tool: pass the sub-agent file content as the prompt; pass all
structured interview outputs (Stages 2–10) as named fields in the user message,
plus `feature_name`, `requirements_source_path`, `branch`, `ticket`, `engineer`, `date`.

If the sub-agent fails or returns empty output: surface the error to the
engineer and offer to retry. Do not advance silently.

After the sub-agent returns: read the written design document from
`docs/design/{TICKET}-{slug}.md`.

**Commit the design document before running the gate.** The design must be in
git history before Stage 12b runs, so the review findings that stage commits
per round sit on top of a committed artefact rather than an uncommitted one:

```bash
git add docs/design/{TICKET}-{slug}.md
git commit -m "{TICKET}: Add design document"
```

If git commit fails: surface the error and halt — do not run the design gate
against an uncommitted design.

Tell the engineer:

> Design Document written to `docs/design/{TICKET}-{slug}.md`. Running design gate now…

## The disposition protocol

This is the single shared definition of how a review gate dispositions a
finding. Stages 12b, 14b, and 14c all reference this subsection for the routing rules;
each carries only its stage-specific deltas — which dispositions are available,
the stage-local action for each, and the `source` value — and does not restate
the routing rules themselves. ADR 010 (`docs/decisions/010-review-gate-disposition-model.md`)
is the canonical model — this subsection carries only what the orchestrator
needs to act on it, and does not re-author it.

**Finding schema.** Each finding from a reviewer sub-agent
(`sync-check.md`) carries the six
fields defined in `.claude/skills/write-design-doc-max/check-principles.md`: `Severity`
(`Critical` / `High` / `Medium` / `Nit pick`), `Issue`, `Why it matters`,
`Size of fix` (`trivial` / `local` / `broad`), `Target` (`load-bearing` /
`illustrative`), and `Suggested resolution`. `Severity` is the routing key;
`Size of fix` and `Target` are advisory inputs that tune the recommendation.

**The four dispositions.**

- **Fix — full ladder.** The heavyweight path: revise the design → re-run the
  design gate → regenerate all task specs from scratch → re-review each. This
  is the existing Stage 14b revision ladder (steps 1–7). Use it for any finding
  at or above the severity floor, or any finding the engineer flags as
  design-upstream.
- **Fix — spec patch.** The lightweight path: patch the single affected task
  spec, then re-review that whole spec (a full re-review, not a diff), looping
  on that one spec until it is clean. It never regenerates or rewrites any
  sibling spec. Only available once task specs exist — it is absent at the
  design gate (Stage 12b), which has no specs.
- **Skip.** A low-value finding. Voiced once to the engineer, recorded in a
  session-scoped in-memory skip set, and NEVER written to `## Dismissals` or
  any other on-disk section. Skip is the default auto-recommendation for
  low-value findings.
- **Dismiss.** The engineer explicitly accepts a real gap. Recorded in
  `## Dismissals` (see below). Dismiss is always an engineer choice — it is
  never auto-recommended.

**Severity floor.** A finding whose `Severity` is `High` or above
(`High` / `Critical`), or any finding the engineer flags as design-upstream,
sits at or above the floor and is recommended for the **Fix — full ladder**
path. A spec-local finding below the floor (`Medium` / `Nit pick`) is
recommended for the **Fix — spec patch** path when specs exist.

**Recommendation heuristic.** Compute one recommended disposition per finding:

1. `Severity` ≥ `High`, or engineer-flagged design-upstream → **Fix — full ladder**.
2. Otherwise, a low-value finding → **Skip**. Low-value means low on the
   combined severity-and-size scale: especially low severity at `broad` size,
   or an `illustrative` `Target`.
3. Otherwise, a spec-local sub-floor finding (`Medium` / `Nit pick`) and specs
   exist → **Fix — spec patch**.
4. Otherwise (a sub-floor finding with no task specs yet — e.g. at the Stage 12b
   design gate) → **Skip**, voiced for engineer confirmation so the engineer can
   elevate or Dismiss it. Electing to fix such a finding at the design gate means
   the **Fix — full ladder** path — spec-patch is unavailable there.

`Dismiss` is never auto-recommended; it is only ever an engineer override.

**Always voice, never auto-apply.** Every finding is presented to the engineer
with its recommended disposition. Nothing is fixed, skipped, or dismissed
without the engineer confirming the recommendation or overriding it. The
severity floor and the recommendation heuristic produce a RECOMMENDATION, never
an automatic action.

**Design-upstream override.** The recommendation is never binding. The
engineer may elevate any finding — including a sub-floor `Medium` or `Nit
pick` — to the **Fix — full ladder** path, may downgrade a recommendation to
**Skip**, or may choose **Dismiss** on any finding.

**Graceful degradation.** A finding arriving without `Size of fix` and/or
`Target` degrades to severity-only routing — it never errors; the heuristic
runs on `Severity` alone. A finding whose `Severity` is out-of-vocabulary or
unparseable is treated as `High` and surfaced with a `[malformed finding:
<reason>]` marker per ADR 010 — it routes conservatively (to the floor), never
dropped.

**The session-scoped skip set.** Held purely in the orchestrator's working
context for the duration of one gate loop. It is NOT written to any file and
NOT recorded in any `## ` section. A Skip is added to this set so the same
finding is not re-nagged on re-review within the same convergence cycle. This
is precisely why an interrupted-then-resumed session starts with an empty set
and previously skipped findings re-surface for re-confirmation — this is
intended behaviour: the model fails toward re-showing, never toward silently
hiding.

**Skip versus Dismiss.**

- **Skip** = a low-value finding, voiced once, recorded only in the
  session-scoped in-memory skip set, NEVER written to `## Dismissals`. It leaves
  no audit trail by design.
- **Dismiss** = the engineer explicitly accepts a real gap. Recorded in
  `## Dismissals` at the end of the design document with the severity label, the
  issue summary, a `source` value, and the engineer's explicit
  acknowledgement. Append `## Dismissals` if not yet present. Any severity level
  including `Critical` may be dismissed.

The `source` value MUST distinguish the originating stage, so dismissals from
the three gates remain individually attributable:

- **Stage 12b (design gate)** → `source` = `design-gate`.
- **Stage 14b (per-task reviewer gate)** → `source` = the originating task-spec
  filename (e.g. `{TICKET}-TASK-{NN}-{slug}.md`).
- **Stage 14c (sync-check gate)** → `source` = `sync-check`.

`## Dismissals` is managed by SKILL.md only — check agents and reviewer
sub-agents must not create or modify it.

## Stage 12b — Design gate loop

Before presenting the document to the engineer for sign-off, run the design
gate. The gate is executed by the `review-gate.js` Workflow script: you —
SKILL.md — perform the pre-invocation steps, invoke `Workflow`, and
disposition its compact result. You do not dispatch check agents yourself;
the script fans them out outside the main context and returns only an
aggregated result.

`scriptPath` for this gate is `.claude/skills/write-design-doc-max/workflows/review-gate.js`.

### Pre-invocation steps (run in this exact order)

**Step 0 — scriptPath readability guard (fail-fast).** Before any other work,
confirm `scriptPath` is readable with a quick `Read` of
`.claude/skills/write-design-doc-max/workflows/review-gate.js`. If it cannot be read, surface
`review-gate.js not found at .claude/skills/write-design-doc-max/workflows/review-gate.js`
to the engineer and halt the stage **without invoking `Workflow`** and before
any other assembly work. A missing script and a wholesale `Workflow` error
halt identically (surface, no inline fallback); this guard only sharpens the
surfaced reason. Do not advance to Stage 13.

**Step 1 — Section-presence guard (hard-fail without invoking).** Confirm the
design document is non-empty and contains all required structural sections.
This is the old reviewer-playbook Step 1, now SKILL.md's responsibility because
the script has no filesystem access. The required sections for the **design
gate** are:

- `## Approach`
- `## Components affected`
- `## Interface contracts`
- `## Task breakdown`
- `## Test strategy`
- `## Risks and constraints`
- `## ADR references`

If the document is empty or any required section is absent, hard-fail the stage
**without invoking `Workflow`**, surfacing
`HALT: Document is empty or malformed — verification cannot proceed` to the
engineer. Do not advance to Stage 13.

**Step 2 — `requirementsText` (inline full text).** Take `requirementsText` as
the inline **full text** of the requirements source SKILL.md already resolved
in its input-handling chain (a JIRA fetch or a file on disk — either way the
text is already in your context). Pass it verbatim as the `requirementsText`
arg. **Write no file** — do NOT materialise the source into `docs/requirements/`
or anywhere else (that location is for product-owner-authored packages; a JIRA
fetch is not one, and persisting it is out of scope). If no source can be
resolved, pass `requirementsText: null` and let the script skip
`requirements-coverage` with an explicit `[check requirements-coverage skipped:
no requirements source]` notice.

**Step 3 — Assemble `codebaseFilePaths` (filtered to readable paths).**
Assemble `codebaseFilePaths` from `## Components affected` using the existing
context-assembly algorithm (existing components read by path; new components →
parent-directory listing + relevant adjacent files). Empty array if the design
names no codebase components. **Filter the assembled list to readable paths
only:** any referenced path you cannot read (a renamed file, or a `new
(created)` component whose path does not exist yet) is dropped from
`codebaseFilePaths` and noted to the engineer
(`[codebase path <path> unreadable — omitted from review]`), NEVER passed in
the args. This preserves the current inline gate's tolerate-and-note behaviour
for unreadable referenced files. Do NOT halt the stage on an unreadable
codebase path — an unreadable codebase path is dropped-and-noted, unlike the
step 0 scriptPath guard and the step 1 section-presence guard, which hard-fail.

**Step 4 — Assemble and pass all nine args (Interface contract #1).** Compute
`round` from disk (see round-number management below), then assemble:

- `gateType`: `"design"`
- `artefactPath`: `docs/design/{TICKET}-{slug}.md`
- `designPath`: equals `artefactPath` at this gate
- `requirementsText`: the inline full text from Step 2, or `null`
- `codebaseFilePaths`: the filtered array from Step 3
- `ticket`: the JIRA key
- `artefactSlug`: `"design"`
- `round`: 1-based, monotonic per `(gateType, artefactSlug)` — disk-derived
- `priorFindingsPath`: `null` on the first round for this `artefactSlug`;
  otherwise the previous round's findings-file path

### Invoke the Workflow

Invoke the gate via `Workflow({ scriptPath })` pointing at
`.claude/skills/write-design-doc-max/workflows/review-gate.js` (step 0 has already confirmed
the path is readable). The Workflow tool runs in the background: the `Workflow`
tool_use resolves to a task ID and the compact result arrives on the completion
notification, so the stage yields between invoking and dispositioning rather
than blocking on a synchronous return. Resume outcome handling when the
notification delivers the compact result.

A wholesale `Workflow` failure (the call rejects before any agent returns) or
an unreadable `scriptPath` halts the stage and surfaces it, with **no fallback
to inline dispatch**.

### Round-number management

`round` is monotonic per `(gateType, artefactSlug)` and is **derived from disk
on every Stage 12b entry**, never from in-memory state. List
`docs/ai/reviews/{TICKET}-design-gate-*.md`, parse the three-digit `NNN` round
suffix from each matching filename, and use `max + 1` (or `1` if no files
match). Disk-derivation is load-bearing because the round number IS the
filename suffix; a working-memory counter would reset on a fresh-session HALT
retry and a new round-1 write would overwrite a committed findings file from
the earlier session. **Never reset on re-entry:** a design-gate re-run (via a
Stage 14b full-ladder fix) or an engineer-initiated HALT retry the next day in
a fresh session resumes from the next unused round automatically, because the
disk-derived `max` is the authoritative high-water mark. The counter advances
implicitly when a round produces a written findings file (`FINDINGS` / `PASS`)
— the file's existence shifts `max`. A `HALT` is terminal to the automated loop
(no auto-retry). A "HALT retry" is the **engineer** re-running the stage after
fixing the cause `haltReason` names; because that round wrote no file, the round
slot is still empty on disk, so the disk-derived computation produces the
**same** `round` and the **same** `priorFindingsPath` for the re-run, keeping
the numbered trail gap-free — identically whether the engineer re-runs in the
same session or a fresh one.

### Handle the compact result

The compact result is `{ findingsPath, outcome, haltReason, report, notices, stats }`.
Branch on `outcome` (one of `HALT`, `PASS`, `ZERO_FINDINGS_WARNING`,
`NOTICES_ONLY`, `FINDINGS`):

- **`HALT`** — voice `haltReason` and stop. Not dismissable; not a silent stop;
  terminal to the automated loop (no auto-retry, no disposition). Resuming is
  engineer-initiated: the engineer fixes the structural cause `haltReason`
  names and re-runs the stage, which reuses the same `round`. `stats` is
  omitted on `HALT`.

- **`PASS`** — first, **commit this round's findings file per Per-round commit
  below**, before the silent clear. Then, when `notices` is empty, clear the
  gate (no prompt, no disposition protocol run, no `stats` footer). When
  `notices` is non-empty (a fully-dismissed round that nevertheless had a check
  fail), surface `notices` and the `stats` footer as a confirm-to-proceed prompt
  before clearing — identical to `NOTICES_ONLY` handling — so a failed check is
  never hidden behind a cleared gate.

- **`ZERO_FINDINGS_WARNING`** — voice `report` (which carries the warning
  string) **and any `notices`** as a single confirm-to-proceed prompt (a
  skipped/failed check is never hidden behind a clean-looking warning), with
  the `stats` footer; on confirmation the gate is cleared. Do not record in
  `## Dismissals` — this is not a finding. This outcome now fires only on
  round 1: a round 2+ all-empty sweep is converging and clears as `PASS`
  (with a written, empty findings file) rather than surfacing this warning.

- **`NOTICES_ONLY`** — surface `notices` as a confirm-to-proceed prompt with
  the `stats` footer (the engineer accepts the partial run or rejects and
  retries); never present it as a clean pass.

- **`FINDINGS`** — first, **commit this round's findings file per Per-round
  commit below**, before re-applying the skip set and before any voicing or
  disposition. Then, **before voicing, re-apply the session-scoped in-memory
  skip set to `report`**, suppressing any finding already skipped this gate loop
  (the aggregation agent filters only `## Dismissals` and has no access to the
  orchestrator's skip set). Then present ALL surviving findings to the engineer
  at once — **each with its `new` / `persisted-from-round-N` annotation
  preserved** — with `notices` surfaced alongside and `stats` as a one-line
  footer (checks run/failed, per-severity counts). Disposition every finding
  per **The disposition protocol** above. No specs exist yet at the design
  gate, so the **Fix — spec patch** disposition is unavailable here — route to
  **Fix — full ladder** / **Skip** / **Dismiss** only. The engineer must confirm
  or override a disposition for every finding before the loop continues. Partial
  responses are not accepted. The loop is unlimited.

  - **Fix — full ladder** (severity floor, or design-upstream override): update
    the design document (re-dispatch to `design-writer.md`). **If the writer
    re-dispatch fails, surface the failure and halt the Fix cycle — do not
    invoke the next round, as there is no revised artefact to review.** On
    success, **commit the revised design before re-reviewing it** so each
    reviewed revision is in history before its round runs:

    ```bash
    git add docs/design/{TICKET}-{slug}.md
    git commit -m "{TICKET}: Revise design document"
    ```

    Then invoke a fresh full-sweep round with `round + 1` and
    `priorFindingsPath` set to this round's `findingsPath`.
  - **Skip**: add to the session-scoped in-memory skip set; do not record on
    disk.
  - **Dismiss**: record in `## Dismissals` at the end of the design document
    with the severity label, issue summary, `source` = `design-gate`, and the
    engineer's explicit acknowledgement. Append `## Dismissals` if not yet
    present. Any severity level including Critical may be dismissed.

  Once all findings are resolved, skipped, or dismissed: gate is cleared.

**Truncated/absent compact result (recovery).** If the completion notification
carries the full compact result, use it. If it delivers only a task ID or a
truncated payload, reconstruct the deterministic findings-file path from the
args just passed (`docs/ai/reviews/{TICKET}-design-gate-{round:NNN}.md`) and
check disk: **if the file exists**, treat the round as `FINDINGS`/`PASS`, read
the findings **and any appended `notices`** from it, and dispose exactly as the
live payload would (findings → disposition protocol; a fully-dismissed PASS
that still carries notices → confirm-to-proceed; a clean PASS → silent clear);
**if it does not exist** (the round was `ZERO_FINDINGS_WARNING` /
`NOTICES_ONLY` / `HALT`, indistinguishable from disk), surface
`gate result could not be retrieved — re-run or inspect` and **do not
auto-clear the gate**. Never treat an unrecoverable result as a pass — fail
toward human attention.

**Per-round commit.** After each `FINDINGS`/`PASS` round (a round that wrote a
findings file), commit it immediately — before any engineer-facing disposition,
voicing, or clear:

```bash
git add docs/ai/reviews/{TICKET}-*-gate-*.md && git commit -m "{TICKET}: persist design-gate findings round {round}"
```

Interpolate `{TICKET}` and `{round}` to the actual values. The
`docs/ai/reviews/` path prefix is load-bearing — a bare `{TICKET}-*-gate-*.md`
glob from the repo root matches nothing — and the `-m` flag keeps the commit
non-interactive. Do NOT defer to Stage 15, so the audit trail survives a
session interrupted mid-gate.

Once the gate is cleared, present the design document to the engineer for sign-off:

> Design Document written to `docs/design/{TICKET}-{slug}.md`.
>
> Please review it. Say "looks good", "sign off", "approved", "ship it", or
> "looks good — proceed to Phase 2" to proceed to task spec generation.
> Or tell me what to change.

---

## Stage 13 — Sign-off gate

**Sign-off is only reachable once the design gate has cleared.**

Accepted phrases: "looks good", "sign off", "approved", "ship it",
"looks good — proceed to Phase 2". Do not treat bare "yes" as sign-off.

**If the document is missing any section** (Approach, Components affected,
Interface contracts, Task breakdown, Test strategy, Risks and constraints,
ADR references): do not accept sign-off — list the missing sections.

**If task breakdown has zero tasks at sign-off time**: do not accept sign-off.

**If the engineer requests changes**: return to the originating stage, update,
pass through Stage 11, re-write via Stage 12, re-run the design gate in Stage
12b, then return here.

**Once valid sign-off is received**: continue immediately to Phase 2.

---

# Phase 2 — Autonomous Task Spec Generation

Phase 2 begins immediately after sign-off. No questions to the engineer. No
pauses between tasks.

---

## Stage 14 — Generate task specs

**Commit any uncommitted design changes before writing any task spec.** The
design document was already committed in Stage 12, and every full-ladder
revision was committed in Stage 12b, so this commit only captures gate-time
edits not yet in history — chiefly `## Dismissals` entries appended during the
design gate. Commit only if there is something to commit:

```bash
if ! git diff --quiet HEAD -- docs/design/{TICKET}-{slug}.md; then
  git add docs/design/{TICKET}-{slug}.md
  git commit -m "{TICKET}: Record design-gate dismissals"
fi
```

If the design has no uncommitted changes the commit is correctly skipped. If a
commit is attempted and fails: surface the error. Do not proceed to task
generation until the design is committed.

Tell the engineer:

> Sign-off confirmed. Generating task specs now.

Read the confirmed Design Document in full.

For each task in the task breakdown:

**1. Derive task number**: two-digit zero-padded (01, 02, 03...).

**2. Derive slug**: lowercase the task name, replace any run of non-alphanumeric
characters with a single hyphen, trim leading/trailing hyphens, truncate to 40
characters, trim any trailing hyphens after truncation.

**3. Check for slug collision:**

```bash
ls docs/tasks/ 2>/dev/null | rg "^{TICKET}-TASK-{NN}-{slug}\.md$"
```

If a file with that name exists: append `-v2`, `-v3`, etc. until unused.

**4. Construct paths and branch value:**

- File path: `docs/tasks/{TICKET}-TASK-{NN}-{slug}.md`
- Branch value: `{TICKET}_TASK-{NN}_{slug}`

```bash
mkdir -p docs/tasks
```

**5. Determine `Depends on:` value:**

- Task depends on another task: exact filename of that task spec
  (`{TICKET}-TASK-{NN}-{slug}.md`)
- No dependency (any task number): read the `Branch:` line from the Design
  Document header; use that branch name as the literal value

**6. Dispatch to `task-writer.md`:**

Read `.claude/skills/write-design-doc-max/task-writer.md` in full. Dispatch via Agent
tool: sub-agent file content as prompt; the following named fields in the user
message: `TICKET`, `TASK_NUMBER`, `TASK_NAME`, `TASK_DEPENDENCIES`,
`OUTPUT_PATH` (the derived file path), `BRANCH` (the derived branch value),
`DESIGN_CONTENT` (full design document text).

**If `task-writer.md` fails for task N:**

- Preserve all specs written for tasks 1 through N-1.
- Surface the failing task number to the engineer.
- Offer to retry task N only — do not require restarting from the beginning.

**Step 6b — Verify and correct contract fields:**

After `task-writer.md` returns, before the Stage 14b reviewer gate, deterministically
reconcile the two contract fields of the just-written spec against the values you
dispatched. The dispatched `BRANCH` (canonical for `branch:`, computed in step 4)
and `TASK_DEPENDENCIES` (canonical for `Depends on:`, computed in step 5) are the
only source of truth — never `DESIGN_CONTENT`'s `Branch:` line. You hold both
values already; do not re-derive either from the design document. This corrects
drift deterministically; it never halts on value drift, never re-dispatches, and
never asks the engineer anything. Phase 2 autonomy is preserved. A halt is reserved
strictly for the structural failures enumerated below, each with its own distinct
message.

Inputs (all already in your context from steps 4–6):

- `OUTPUT_PATH` — the just-written spec path.
- `BRANCH` — the canonical `branch:` value.
- `TASK_DEPENDENCIES` — the canonical `Depends on:` value (`nothing`, a sibling
  task-spec filename, or a branch name).

Behaviour, in this exact order:

1. **Read** the file at `OUTPUT_PATH`. This supplies the comparison source and
   satisfies the Edit tool's Read-before-Edit precondition. If the file cannot be
   read, halt: `HALT: task spec not found at <path>`.

2. **Locate and uniqueness-check each field, scoped to its region.**

   - The `branch:` field is the single line matching `^branch:` *within the leading
     YAML frontmatter block* — the lines between the first `---` delimiter and the
     next `---` delimiter. If the frontmatter block is malformed (fewer than two
     `---` delimiters), halt: `HALT: task spec frontmatter block malformed at <path>`.
   - The `Depends on:` field is the single line matching `^Depends on:` *within the
     body header* — the lines between the H1 title and the first `##`-level heading
     that follows it. HTML comment lines do not begin with `Depends on:`, so the
     `^Depends on:` anchor does not match them; only a real header line is counted.
     If the file has no H1 title, or no `##`-level heading follows the H1 (so the
     body-header region has no determinable end), halt:
     `HALT: task spec body-header region malformed at <path>`.

   Perform the uniqueness count within each field's region only, never across the
   whole file (the file may legitimately carry the tokens `branch:` or `Depends on:`
   in prose or a template-derived comment block; those must not be counted). For each
   field:

   - If its line is absent from its region, halt: `HALT: task spec <field> line absent at <path>`.
   - If its line occurs more than once within its region, halt: `HALT: task spec <field> line not unique at <path>`.

   Use the literal field token in the message (`branch:` or `Depends on:`).

3. **Extract** the current value of each field — the text after the `key:` prefix,
   trimmed of surrounding whitespace. If a field's value is empty after trimming,
   halt: `HALT: task spec <field> line empty at <path>`.

4. **Compare and correct, one field at a time.** For each field, compare the trimmed
   current value against the dispatched canonical value (`BRANCH` for `branch:`,
   `TASK_DEPENDENCIES` for `Depends on:`). Comparison is on the trimmed value: an
   incidental whitespace-only difference is not drift and triggers no Edit. If the
   trimmed values differ, overwrite that single line via an anchored Edit whose match
   is the full current line (e.g. `branch: <current>` → `branch: <BRANCH>`), and
   record a correction note of the form
   `{spec filename}: {field} corrected from '<got>' to '<expected>'` for the Stage 16
   report. The Edit's match is the full current line and nothing more — do not extend
   it with surrounding context. If that full-line match is not unique file-wide (e.g.
   a surviving comment or prose line repeats it) and the Edit therefore fails, halt:
   `HALT: step 6b Edit failed for <field> at <path>` — the halt is the correct
   outcome, not mis-patching.

   Two-field ordering: if both fields drift, after the first Edit **re-Read** the
   file (this satisfies the Read-before-Edit precondition for the second Edit and
   validates the first Edit landed), and confirm the first field now equals its
   canonical value before the second Edit. If that intermediate re-Read fails, or the
   first field did not update, halt: `HALT: step 6b intermediate re-read failed at <path>`.

   If neither field drifts, perform no Edit and record no note — step 6b is a no-op
   and is idempotent on an already-correct file.

5. **Post-condition.** Re-Read the file. If the re-Read fails, halt:
   `HALT: step 6b re-read failed at <path>`. Assert the trimmed `branch:` value now
   equals `BRANCH` and the trimmed `Depends on:` value now equals `TASK_DEPENDENCIES`.
   If the assertion does not hold for a field, halt:
   `HALT: step 6b post-condition failed for <field>`.

When step 6b returns without halting, the spec on disk is guaranteed conforming:
trimmed `branch:` equals `BRANCH` and trimmed `Depends on:` equals `TASK_DEPENDENCIES`.
Accumulate any correction notes for the Stage 16 report, de-duplicated by
`{spec filename, field}`.

**7. Run task reviewer gate (Stage 14b) before proceeding to task N+1.**

## Stage 14b — Per-task reviewer gate

After each task spec is written, run this gate before proceeding. The gate is
executed by the `review-gate.js` Workflow script: you — SKILL.md — perform the
pre-invocation steps, invoke `Workflow`, and disposition its compact result.
You do not dispatch check agents yourself; the script fans them out outside the
main context and returns only an aggregated result.

`scriptPath` for this gate is `.claude/skills/write-design-doc-max/workflows/review-gate.js`.

### Pre-invocation steps (run in this exact order)

**Step 0 — scriptPath readability guard (fail-fast).** Before any other work,
confirm `scriptPath` is readable with a quick `Read` of
`.claude/skills/write-design-doc-max/workflows/review-gate.js`. If it cannot be read, surface
`review-gate.js not found at .claude/skills/write-design-doc-max/workflows/review-gate.js`
to the engineer and halt the stage **without invoking `Workflow`** and before
any other assembly work. A missing script and a wholesale `Workflow` error halt
identically (surface, no inline fallback); this guard only sharpens the
surfaced reason. Do not advance past Stage 14b for this task.

**Step 1 — Section-presence guard (hard-fail without invoking).** Confirm the
task spec under review is non-empty and contains all required structural
sections. This is the old reviewer-playbook Step 1, now SKILL.md's
responsibility because the script has no filesystem access. The required
sections for the **task gate** are:

- `## Objective`
- `## Context`
- `## Implementation constraints`
- `## Inputs and outputs`
- `## Edge cases to handle explicitly`
- `## Out of scope`
- `## Acceptance criteria`
- `## Test requirements`
- `## Required output format`
- `## Definition of done`

If the task spec is empty or any required section is absent, hard-fail the stage
**without invoking `Workflow`**, surfacing
`HALT: Task spec is empty or malformed — verification cannot proceed` to the
engineer. Do not advance past Stage 14b for this task.

**Step 2 — `requirementsText` is `null`.** Pass `requirementsText: null` — the
task-gate config does not use the requirements source. Write no file.

**Step 3 — Assemble `codebaseFilePaths` (filtered to readable paths).**
Assemble `codebaseFilePaths` from **the design document's** `## Components
affected` using the existing context-assembly algorithm (existing components
read by path; new components → parent-directory listing + relevant adjacent
files). Empty array if the design document names no codebase components.
**Filter the assembled list to readable paths only:** any referenced path you
cannot read (a renamed file, or a `new (created)` component whose path does not
exist yet) is dropped from `codebaseFilePaths` and noted to the engineer
(`[codebase path <path> unreadable — omitted from review]`), NEVER passed in
the args. This preserves the current inline gate's tolerate-and-note behaviour.
Do NOT halt the stage on an unreadable codebase path — it is dropped-and-noted,
unlike the step 0 scriptPath guard and the step 1 section-presence guard, which
hard-fail.

**Step 4 — Assemble and pass all nine args (Interface contract #1).** Compute
`round` from disk (see round-number management below), then assemble:

- `gateType`: `"task"`
- `artefactPath`: the single task spec under review, `docs/tasks/{TICKET}-TASK-{NN}-{slug}.md`
- `designPath`: the design document `docs/design/{TICKET}-{slug}.md` (NOT the
  task spec — the task-gate checks and the aggregation agent need `## Dismissals`
  from the design doc)
- `requirementsText`: `null`
- `codebaseFilePaths`: the filtered array from Step 3
- `ticket`: the JIRA key
- `artefactSlug`: `"task-{NN}"`, where `{NN}` is the two-digit task number of
  the spec under review (e.g. `task-02`). This is load-bearing: it is the only
  thing keeping each task's gate file distinct, so two task gates in one run do
  not overwrite each other.
- `round`: 1-based, monotonic per `(gateType, artefactSlug)` — disk-derived
- `priorFindingsPath`: `null` on the first round for this `artefactSlug`;
  otherwise the previous round's findings-file path

### Invoke the Workflow

Invoke the gate via `Workflow({ scriptPath })` pointing at
`.claude/skills/write-design-doc-max/workflows/review-gate.js` (step 0 has already confirmed
the path is readable). The Workflow tool runs in the background: the `Workflow`
tool_use resolves to a task ID and the compact result arrives on the completion
notification, so the stage yields between invoking and dispositioning rather
than blocking on a synchronous return. Resume outcome handling when the
notification delivers the compact result.

A wholesale `Workflow` failure (the call rejects before any agent returns) or
an unreadable `scriptPath` halts the stage and surfaces it, with **no fallback
to inline dispatch**.

### Round-number management

`round` is monotonic per `(gateType, artefactSlug)` and is **derived from disk
on every Stage 14b entry**, never from in-memory state. List
`docs/ai/reviews/{TICKET}-task-{NN}-gate-*.md` (the `artefactSlug` for this task),
parse the three-digit `NNN` round suffix from each matching filename, and use
`max + 1` (or `1` if no files match). Disk-derivation is load-bearing because
the round number IS the filename suffix; a working-memory counter would reset
on a fresh-session HALT retry and a new round-1 write would overwrite a
committed findings file from the earlier session. **Never reset on re-entry:** a
regenerated-and-re-reviewed task spec or an engineer-initiated HALT retry the
next day in a fresh session resumes from the next unused round automatically,
because the disk-derived `max` is the authoritative high-water mark. The counter
advances implicitly when a round produces a written findings file (`FINDINGS` /
`PASS`) — the file's existence shifts `max`. A `HALT` is terminal to the
automated loop (no auto-retry). A "HALT retry" is the **engineer** re-running
the stage after fixing the cause `haltReason` names; because that round wrote no
file, the round slot is still empty on disk, so the disk-derived computation
produces the **same** `round` and the **same** `priorFindingsPath` for the
re-run, keeping the numbered trail gap-free — identically whether the engineer
re-runs in the same session or a fresh one. The `artefactSlug` segment, not the
round counter, is what makes per-task gate files distinct.

### Handle the compact result

The compact result is `{ findingsPath, outcome, haltReason, report, notices, stats }`.
Branch on `outcome` (one of `HALT`, `PASS`, `ZERO_FINDINGS_WARNING`,
`NOTICES_ONLY`, `FINDINGS`):

- **`HALT`** — voice `haltReason` and stop. Not dismissable; not a silent stop;
  terminal to the automated loop (no auto-retry, no disposition). Resuming is
  engineer-initiated: the engineer fixes the structural cause `haltReason`
  names and re-runs the stage, which reuses the same `round`. `stats` is
  omitted on `HALT`.

- **`PASS`** — first, **commit this round's findings file per Per-round commit
  below**, before the silent clear. Then, when `notices` is empty, clear the
  gate and proceed to the next task (no prompt, no disposition protocol run, no
  `stats` footer). When `notices` is non-empty (a fully-dismissed round that
  nevertheless had a check fail), surface `notices` and the `stats` footer as a
  confirm-to-proceed prompt before clearing — identical to `NOTICES_ONLY`
  handling — so a failed check is never hidden behind a cleared gate.

- **`ZERO_FINDINGS_WARNING`** — voice `report` (which carries the warning
  string) **and any `notices`** as a single confirm-to-proceed prompt (a
  skipped/failed check is never hidden behind a clean-looking warning), with
  the `stats` footer; on confirmation the gate is cleared and you proceed to
  the next task. Do not record in `## Dismissals` — this is not a finding.
  This outcome now fires only on round 1: a round 2+ all-empty sweep is
  converging and clears as `PASS` (with a written, empty findings file)
  rather than surfacing this warning.

- **`NOTICES_ONLY`** — surface `notices` as a confirm-to-proceed prompt with
  the `stats` footer (the engineer accepts the partial run or rejects and
  retries); never present it as a clean pass.

- **`FINDINGS`** — first, **commit this round's findings file per Per-round
  commit below**, before re-applying the skip set and before any voicing or
  disposition. Then, **before voicing, re-apply the session-scoped in-memory
  skip set to `report`**, suppressing any finding already skipped this gate loop
  (the aggregation agent filters only `## Dismissals` and has no access to the
  orchestrator's skip set). Then present ALL surviving findings to the engineer
  at once — **each with its `new` / `persisted-from-round-N` annotation
  preserved** — with `notices` surfaced alongside and `stats` as a one-line
  footer (checks run/failed, per-severity counts). Disposition every finding per
  **The disposition protocol** above — compute and voice a recommended
  disposition for each, then have the engineer confirm or override. The engineer
  must disposition every finding before the loop continues. The loop is unlimited.

  **Fix — full ladder** (severity floor, or design-upstream override). When a
  finding takes the full ladder:
  1. Engineer directs revision.
  2. Re-dispatch to `design-writer.md` with updated synthesis. **If the writer
     re-dispatch fails, surface the failure and halt the Fix cycle — do not
     invoke the next round, as there is no revised artefact to review.**
  3. Re-run Stage 12b design gate (full gate loop, not abbreviated).
  4. Once design gate clears, commit the revised design:
     ```bash
     git add docs/design/{TICKET}-{slug}.md
     git commit -m "{TICKET}: Revise design document"
     ```
  5. Delete all existing task specs for this ticket before regenerating, so
     slug-collision logic does not produce stale `-v2` files:
     ```bash
     git rm --cached docs/tasks/{TICKET}-TASK-*.md 2>/dev/null || true
     rm -f docs/tasks/{TICKET}-TASK-*.md
     ```
  6. Regenerate ALL task specs from scratch (starting from task 01).
  7. Run per-task reviewer on each regenerated spec — do not re-use prior
     review results.

  **Fix — spec patch** (spec-local finding below the severity floor). When a
  sub-floor finding is local to this one task spec:
  1. Patch the single affected task spec only. Do NOT touch, regenerate, or
     rewrite any sibling spec. **If the writer re-dispatch fails, surface the
     failure and halt the Fix cycle — do not invoke the next round, as there is
     no revised artefact to review.**
  2. Re-review that whole patched spec — a fresh full-sweep round with
     `round + 1` and `priorFindingsPath` set to this round's `findingsPath`
     (re-invoke the gate Workflow on it), not a diff.
  3. Loop on that one spec until it is clean. The loop is intentionally
     unbounded, matching the ladder-loop convention; convergence is guaranteed
     not by an iteration cap but by the always-voice rule — at each re-review
     the engineer sees any re-surfacing finding and can elevate it to the
     full ladder, Skip it, or Dismiss it, so the loop cannot silently churn.

  **Skip**: add to the session-scoped in-memory skip set; do not record on disk.

  **Dismiss**: append to the design document's `## Dismissals` section with the
  severity label, issue summary, `source` = the originating task-spec filename
  (`{TICKET}-TASK-{NN}-{slug}.md`), and explicit engineer acknowledgement.

  Once all findings are resolved, skipped, or dismissed: proceed to next task.

**Truncated/absent compact result (recovery).** If the completion notification
carries the full compact result, use it. If it delivers only a task ID or a
truncated payload, reconstruct the deterministic findings-file path from the
args just passed (`docs/ai/reviews/{TICKET}-task-{NN}-gate-{round:NNN}.md`) and
check disk: **if the file exists**, treat the round as `FINDINGS`/`PASS`, read
the findings **and any appended `notices`** from it, and dispose exactly as the
live payload would (findings → disposition protocol; a fully-dismissed PASS
that still carries notices → confirm-to-proceed; a clean PASS → silent clear);
**if it does not exist** (the round was `ZERO_FINDINGS_WARNING` /
`NOTICES_ONLY` / `HALT`, indistinguishable from disk), surface
`gate result could not be retrieved — re-run or inspect` and **do not
auto-clear the gate**. Never treat an unrecoverable result as a pass — fail
toward human attention.

**Per-round commit.** After each `FINDINGS`/`PASS` round (a round that wrote a
findings file), commit it immediately — before any engineer-facing disposition,
voicing, or clear:

```bash
git add docs/ai/reviews/{TICKET}-*-gate-*.md && git commit -m "{TICKET}: persist task-{NN}-gate findings round {round}"
```

Interpolate `{TICKET}`, `{NN}`, and `{round}` to the actual values. The
`docs/ai/reviews/` path prefix is load-bearing — a bare `{TICKET}-*-gate-*.md`
glob from the repo root matches nothing — and the `-m` flag keeps the commit
non-interactive. Do NOT defer to Stage 15, so the audit trail survives a
session interrupted mid-gate.

---

## Stage 14c — Sync-check gate

After all per-task findings are resolved or dismissed, run the sync-check.

**No context assembly needed** — sync-check receives design and all task specs.

Read `.claude/skills/write-design-doc-max/sync-check.md` in full. Dispatch via Agent tool:
sub-agent file content as prompt; full design document text and all task spec
texts (one per task, in order) as user message.

**If the sub-agent fails or returns malformed output**: surface the failure,
re-run. If the second run also fails: halt and surface the error.

**On output:**

- Begins with `HALT:`: surface the reason and stop.

- `PASS`: proceed to Stage 15.

- Findings report: present ALL findings to engineer at once. Disposition every
  finding per **The disposition protocol** above — the same routing as the
  other gates, referencing the one shared subsection.

  - **Fix — full ladder** (severity floor, or design-upstream override): apply
    the Stage 14b full-ladder steps 1–7 to the finding. After regeneration
    completes, re-run Stage 14c on the regenerated set.
  - **Fix — spec patch** (spec-local finding below the severity floor): patch
    the single affected task spec, full re-review of that whole spec, loop
    until clean; siblings untouched (Stage 14b spec-patch steps). Then re-run
    Stage 14c.
  - **Skip**: add to the session-scoped in-memory skip set; do not record on
    disk.
  - **Dismiss**: append to the design document's `## Dismissals` section with
    severity, issue summary, `source` = `sync-check`, and explicit engineer
    acknowledgement.

  Loop is unlimited. Once all findings are resolved, skipped, or dismissed:
  proceed to Stage 15.

---

## Stage 15 — Push and create PR

Commit and push only after sync-check clears:

```bash
git add docs/tasks/{TICKET}-TASK-*.md
git commit -m "{TICKET}: Add task specs"
git push -u origin {branch}
```

Then invoke the `create-pr` skill to open a PR for the design branch. Pass:
- `ticket`: the JIRA key
- `branch`: the design branch name
- `steering_doc_path`: the design document path

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
> - …
>
> {If slug collisions: Slug collision on {original} — written as {slug}-v2.}
>
> {If any contract corrections occurred during step 6b: one line per corrected
> spec, of the form: Contract correction — {spec filename}: {field} corrected from
> '<got>' to '<expected>'. De-duplicated by {spec filename, field}. Omit entirely
> when no corrections occurred.}
>
> Run `implement {TICKET}` to begin implementation.

---

## Rules

- **Requirements source must be resolved before Phase 1 begins.** Hard-fail
  with the exact message above if nothing is found. No interview without it.
- **Phase 1 is interactive.** One section at a time. Wait for engineer input.
  Do not produce the Design Document in one pass.
- **Read the codebase actively.** Use Bash and Read throughout Phase 1.
- **Gate ordering is a hard constraint.** Design gate must clear before
  sign-off. Sign-off before task generation. Sync-check before push. No
  exceptions. A gate clears once every finding is dispositioned per **The
  disposition protocol** — fixed (full ladder or spec patch), skipped, or
  dismissed.
- **All three gates route through one disposition protocol.** Stages 12b, 14b,
  and 14c reference the single **The disposition protocol** subsection for the
  routing rules, carrying only their stage-specific deltas rather than restating
  the routing rules themselves. The severity floor routes `High`-and-above (or
  design-upstream-flagged) findings to the full ladder; spec-local sub-floor
  findings take the spec-patch path (unavailable at the design gate, which has
  no specs).
- **Always voice, never auto-apply.** Every finding is presented with a
  recommended disposition; nothing is fixed, skipped, or dismissed without the
  engineer confirming or overriding. The severity floor produces a
  recommendation, not an action.
- **`## Dismissals` is for conscious acceptance only.** A Dismiss record means
  the engineer has explicitly accepted a real gap; it carries severity, issue
  summary, a stage-distinguishing `source`, and explicit acknowledgement.
- **Skip is never written to disk.** Skipped findings live only in the
  session-scoped in-memory skip set for the duration of one gate loop; they are
  never written to `## Dismissals` or any `## ` section. On an
  interrupted-then-resumed session the set is empty and skipped findings
  re-surface for re-confirmation — intended behaviour.
- **No sign-off without all sections.** All seven sections required before
  sign-off is accepted.
- **No sign-off with zero tasks.**
- **Phase 2 is autonomous.** No questions, no pauses, no confirmation between
  tasks.
- **`## Dismissals` is managed by SKILL.md only.** Check agents and reviewer
  sub-agents must not create or modify this section.
- **Task specs are machine-optimised.** All writing goes through `task-writer.md`.
- **Slug derivation is deterministic.** Lowercase, replace non-alphanumeric
  runs with a single hyphen, trim leading/trailing hyphens, truncate to 40
  chars, trim trailing hyphens after truncation.
- **Conflict detection for document tasks.** Run Stages 5 and 6 when the
  output is a standards file, skill file, or similar non-code artefact.
- **No kept/adapted/discarded.** Synthesis from external references goes
  directly into task spec ACs and constraints.

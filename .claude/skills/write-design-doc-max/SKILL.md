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

Write the design-writer synthesis to a temp file, then dispatch the writer
against its path — do NOT pass the structured interview outputs inline.
Inlining them recharges the full payload as cache-read on every subsequent
orchestrator turn; passing a path keeps the persistent context small.

```bash
mkdir -p .tmp
```

Write the synthesis file `.tmp/{TICKET}-design-synthesis.md` holding every
field the design-writer needs — all structured interview outputs (Stages 2–10)
plus `feature_name`, `requirements_source_path`, `branch`, `ticket`,
`engineer`, `date` — as labelled Markdown sections (one `## {field}` heading
per field). At this initial write the Stage 2–10 outputs are freshly in hand,
so write them directly.

Read `.claude/skills/write-design-doc-max/design-writer.md` in full. Dispatch to it via
the Agent tool: pass the sub-agent file content as the prompt; pass
`synthesis_path` = `.tmp/{TICKET}-design-synthesis.md` as the single named
field in the user message (the writer reads every field from that file).

After the writer returns — on BOTH success and failure — delete the synthesis
temp file:

```bash
rm -f .tmp/{TICKET}-design-synthesis.md
```

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
`illustrative`), and `Suggested resolution`. Separately, at disposition time the
engineer may flag the finding design-upstream; this flag is an engineer action
applied during disposition, not a field the reviewer emits. Whether the finding
is **design-upstream** is the routing key (see *Routing key:
design-upstream-ness* below); `Severity`, `Size of fix`, and `Target` are
advisory inputs that tune the recommendation, and `Severity` is additionally the
triage axis the gate-level escape uses.

**The four dispositions.**

- **Fix — full ladder.** The heavyweight path: revise the design → re-run the
  design gate → regenerate all task specs from scratch → re-review each. This
  is the existing Stage 14b revision ladder (steps 1–7). Use it for a
  **design-upstream** finding — one whose resolution requires editing the Design
  Document itself — at any severity, or any finding the engineer flags
  design-upstream. When task specs already exist, a mandatory cost warning
  precedes it (see *Mandatory full-ladder cost warning* below); it is never the
  silent default.
- **Fix — spec patch.** The lightweight path: patch the single affected task
  spec, then re-review that whole spec (a full re-review, not a diff), looping
  on that one spec until it is clean. It never regenerates or rewrites any
  sibling spec. It is the route for a **spec-local** finding — one resolvable by
  editing only the affected spec — at **any severity, including High or
  Critical**: severity alone never escalates a spec-local finding to the full
  ladder. Only available once task specs exist — it is absent at the design gate
  (Stage 12b), which has no specs.
- **Skip.** A low-value finding. Voiced once to the engineer, recorded in a
  session-scoped in-memory skip set, and NEVER written to `## Dismissals` or
  any other on-disk section. Skip is the default auto-recommendation for
  low-value findings.
- **Dismiss.** The engineer explicitly accepts a real gap. Recorded in
  `## Dismissals` (see below). Dismiss is always an engineer choice — it is
  never auto-recommended.

**Routing key: design-upstream-ness.** Per ADR 014
(`docs/decisions/014-launch-safe-advisory-gates.md`), the routing key is whether
a finding is **design-upstream**, NOT its severity. A finding is design-upstream
when resolving it requires editing a section of the **Design Document** —
`## Approach`, `## Components affected`, `## Interface contracts`,
`## Task breakdown`, `## Test strategy`, `## Risks and constraints`, or
`## ADR references`. A design-upstream finding (at any severity) is recommended
for the **Fix — full ladder** path. A finding that is not design-upstream is
**spec-local** — resolvable by editing only the affected task spec — and is
recommended for the **Fix — spec patch** path when specs exist, at **any
severity, including High or Critical**.

Severity is no longer the routing key: it is an advisory input that, with `Size
of fix` and `Target`, tunes the recommendation, and it is the triage axis the
gate-level escape uses. A High or Critical finding that is spec-local routes to
spec-patch; a Medium or Nit-pick finding that is design-upstream routes to the
full ladder. The engineer may flag any finding design-upstream (forcing the full
ladder) or accept the spec-local inference, and that flag overrides the
inference in either direction.

**Ambiguity defaults to spec-local.** When a finding's design-upstream-ness is
unclear, recommend the contained, non-destructive **Fix — spec patch** path (or,
at a gate with no specs, **Skip** voiced for confirmation), and voice the
reasoning. Uncertainty must NEVER route to the full ladder — it must never
trigger a spec-clearing regeneration.

**Mandatory full-ladder cost warning.** Whenever a full ladder would fire and
task specs already exist, the orchestrator MUST first voice an explicit cost
warning: that taking the ladder regenerates all N task specs from scratch and
re-runs every per-task gate — a significant time and cost hit — and MUST offer
the **Fix — spec patch** path as the alternative. The full ladder is never the
silent default.

**Recommendation heuristic.** Compute one recommended disposition per finding:

1. Design-upstream (its resolution requires editing a Design-Document section),
   or engineer-flagged design-upstream → **Fix — full ladder** (preceded by the
   mandatory cost warning when specs exist).
2. Otherwise, a low-value finding → **Skip**. Low-value means low on the
   combined severity-and-size scale: especially low severity at `broad` size,
   or an `illustrative` `Target`.
3. Otherwise, a spec-local finding (any severity, including High or Critical)
   and specs exist → **Fix — spec patch**.
4. Otherwise (a spec-local finding with no task specs yet — e.g. at the Stage 12b
   design gate) → **Skip**, voiced for engineer confirmation so the engineer can
   elevate or Dismiss it. Electing to fix such a finding at the design gate means
   the **Fix — full ladder** path — spec-patch is unavailable there.
5. When design-upstream-ness is ambiguous → treat as spec-local (step 3 when
   specs exist, else step 4), and voice the reasoning. Never escalate ambiguity
   to the full ladder.

`Dismiss` is never auto-recommended; it is only ever an engineer override.

**Always voice, never auto-apply.** Every finding is presented to the engineer
with its recommended disposition. Nothing is fixed, skipped, or dismissed
without the engineer confirming the recommendation or overriding it. The
design-upstream routing key and the recommendation heuristic produce a
RECOMMENDATION, never an automatic action.

**Design-upstream override.** The recommendation is never binding, and the
engineer flag overrides the inference in both directions. The engineer may flag
any finding — including a spec-local `High` or `Critical` — design-upstream to
elevate it to the **Fix — full ladder** path, may accept the spec-local
inference for a finding the model called design-upstream, may downgrade a
recommendation to **Skip**, or may choose **Dismiss** on any finding.

**Graceful degradation.** A finding arriving without `Size of fix` and/or
`Target` never errors; the heuristic runs on the design-upstream determination
alone, with severity as the advisory input it still has. A finding whose
`Severity` is out-of-vocabulary or unparseable is surfaced with a
`[malformed finding: <reason>]` marker per ADR 010 — it still routes on its
design-upstream determination (severity is advisory, not the routing key), and
where that determination is itself unclear it defaults to spec-local per
*Ambiguity defaults to spec-local* above, never dropped.

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

### gate-level escape

Per ADR 014 (`docs/decisions/014-launch-safe-advisory-gates.md`), the gates are
**advisory**: a FINDINGS round never forces the engineer to disposition every
finding to make progress, and the loop is not unlimited. From round 1 onward,
every FINDINGS round (Stage 12b, 14b, and 14c) opens with a **gate-level
choice** over the whole surviving set, using `Severity` as the triage axis:

- **skip** — clear the gate immediately, applying no fixes. The round's findings
  file is already written and committed (see *Per-round commit*), so the
  calibration trail survives even though nothing was actioned.
- **only-highs** — act on the spec-local `High`-and-above findings (a single
  spec-patch pass each, see below), surface any in-scope design-upstream finding
  for elevate-or-skip, then clear. Does not re-run the gate.
- **only-lows** — act on the spec-local sub-floor (`Medium` / `Nit pick`)
  findings (a single spec-patch pass each), surface any in-scope design-upstream
  finding for elevate-or-skip, then clear. Does not re-run the gate.
- **fix-everything** — act on all findings per the per-finding routing above,
  then **re-run the gate** (a fresh round) and repeat until the gate clears.
  This is the only choice that re-runs the gate and the only one that runs the
  routed fix paths to convergence.

**Only fix-everything re-runs the gate.** skip, only-highs, and only-lows each
clear the gate after their one-shot action; only fix-everything invokes a fresh
round. Any choice is valid, including skip. Per-finding disposition (confirm,
override design-upstream, Skip, Dismiss — *The disposition protocol* above)
remains available within any "fix" choice (only-highs / only-lows /
fix-everything); it is the gate-level choice that is relaxed, not the
per-finding controls.

**Scoped escapes run a single spec-patch pass, never the full ladder.** Under
only-highs / only-lows, each in-scope **spec-local** finding receives a single
**Fix — spec patch** pass (patch the affected spec, no re-review loop) and then
the gate clears — the scoped escape does NOT enter spec-patch's "loop on that
one spec until it is clean" inner loop. fix-everything still runs spec-patch to
convergence per the full *Fix — spec patch* steps.

**A design-upstream finding is NEVER run as a scoped one-pass.** Under
only-highs / only-lows an in-scope **design-upstream** finding is surfaced with
its mandatory full-ladder cost warning for the engineer to either elevate it to
**fix-everything** (which re-runs the gate and runs the full ladder to
convergence) or skip / dismiss it. The full-ladder steps (revise → re-gate →
regenerate-all → re-review-each) stay intact and run only under fix-everything;
they are never executed as a scoped one-pass. The invariant: **only
fix-everything re-runs the gate, and the full ladder is always a deliberate,
cost-warned choice.**

**At the design gate (Stage 12b) no task specs exist**, so **Fix — spec patch**
is unavailable and every finding is effectively design-upstream (the only
artefact to edit is the design itself). There a scoped only-highs / only-lows
choice surfaces its in-scope findings for elevate-to-fix-everything or skip and
then clears — no spec-patch pass is possible, and the full ladder runs only
under fix-everything — so a scoped escape at the design gate fixes nothing
without elevation.

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

**Step 3b — Build `steeringIndex` and run the completeness cross-check.**
Assemble `steeringIndex` as a preformatted Markdown index string so the
steering-context checks can read the full text only of plausibly-relevant docs
instead of the whole bundle. Follow the procedure in *Building the steering
index* below. The output is either the index string or `null` (the read-all
degrade trigger).

**Step 4 — Assemble and pass all ten args (Interface contract #1).** Compute
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
- `steeringIndex`: the Markdown index string from Step 3b, or `null` (the
  read-all degrade trigger)

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

### Building the steering index

This procedure is shared by the Stage 12b and Stage 14b pre-invocation steps;
run it identically in both. It produces `steeringIndex` — the tenth
`review-gate.js` argument.

1. **Read the curated source lists.** Parse the "Standards in this library"
   bullet lists from `CLAUDE.md` (the `base/`, `languages/`, and `domains/`
   entries) and, **when the file is present**, from `CLAUDE.local.md` (the
   `local/` entries). Each bullet has the shape
   `` `docs/ai/steering/<path>` — <one-line description> ``.
2. **Assemble the index string.** Emit one
   `- {path} — {one-line description}` line per curated doc, grouped by folder
   (`base/`, then `languages/`, then `domains/`, then `local/`). Include the
   `local/` group only when `CLAUDE.local.md` was present and parseable. This is
   the value passed as `steeringIndex`.
3. **Run the completeness cross-check.** List `docs/ai/steering/` **following
   symlinks** so the symlinked `base/`, `languages/`, and `domains/`
   subdirectories are included (`local/` is a real directory). Use `fd` / the
   dedicated tools, never `grep` / `find`. Exclude the non-normative `README.md`
   index files and `.gitkeep` placeholders. If the listing contains a normative
   doc that the curated lists omit, **degrade this run to read-all** (pass
   `steeringIndex: null`) and note the unlisted doc to the engineer
   (`[steering doc <path> not in the curated lists — degrading this gate to
   read-all]`).
4. **Degrade gracefully on source absence / parse failure.** `CLAUDE.local.md`
   absent (as in a fanned-out consumer repo) → build the index from `CLAUDE.md`
   alone and omit the `local/` group; raise no error. If **neither** curated
   list is parseable → pass `steeringIndex: null`, which triggers the read-all
   degrade path in `review-gate.js` (steering compliance is never silently
   skipped).

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

- **`ZERO_FINDINGS_WARNING`** — first, **commit this round's findings file per
  Per-round commit below** (round 1 is the only case, and it always wrote a
  file), before any voicing or clearing. Then
  voice `report` (which carries the warning
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
  footer (checks run/failed, per-severity counts). Then offer the **gate-level
  choice** over the whole set per **gate-level escape** above — skip /
  only-highs / only-lows / fix-everything — using `Severity` as the triage axis.
  The engineer is never required to disposition every finding to make progress,
  partial responses are accepted, and the loop is not unlimited: only
  fix-everything re-runs the gate; skip, only-highs, and only-lows each clear it.

  **No specs exist yet at the design gate**, so the **Fix — spec patch**
  disposition is unavailable here and every finding is effectively
  design-upstream — the only artefact to edit is the design itself. A scoped
  only-highs / only-lows choice therefore runs no spec-patch pass: it surfaces
  its in-scope findings for elevate-to-fix-everything or skip and then clears,
  fixing nothing without elevation. fix-everything routes each finding to
  **Fix — full ladder** / **Skip** / **Dismiss** (per the per-finding disposition
  protocol) and re-runs the gate.

  - **Fix — full ladder** (design-upstream finding, or engineer design-upstream
    flag): update the design document by re-dispatching to `design-writer.md`
    against a freshly written synthesis path. Write `.tmp/{TICKET}-design-synthesis.md`
    from the **revised** design content (not a stale copy of the original
    Stage 2–10 outputs — writing the original outputs would feed the writer stale
    content and silently undo the engineer-directed revision), pass
    `synthesis_path` = `.tmp/{TICKET}-design-synthesis.md`, and after the writer
    returns delete the temp file on BOTH success and failure:

    ```bash
    mkdir -p .tmp
    # write .tmp/{TICKET}-design-synthesis.md from the revised design content
    # dispatch design-writer.md with synthesis_path = .tmp/{TICKET}-design-synthesis.md
    rm -f .tmp/{TICKET}-design-synthesis.md
    ```

    **If the writer re-dispatch fails, surface the failure and halt the Fix
    cycle — do not invoke the next round, as there is no revised artefact to
    review.** On success, **commit the revised design before re-reviewing it** so
    each reviewed revision is in history before its round runs:

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

  The gate clears once the engineer's gate-level choice completes: skip,
  only-highs, and only-lows clear it after their one-shot action; fix-everything
  re-runs the gate until a later round clears.

**Truncated/absent compact result (recovery).** If the completion notification
carries the full compact result, use it. If it delivers only a task ID or a
truncated payload, reconstruct the deterministic findings-file path from the
args just passed (`docs/ai/reviews/{TICKET}-design-gate-{round:NNN}.md`) and
check disk. The heuristic keys on **`(findings count, round)`**, not on file
existence alone — round 1 now always writes a findings file (the
`ZERO_FINDINGS_WARNING` write), so an empty file is produced by two legitimate
outcomes and count alone cannot tell them apart:

- **File exists with at least one finding** → treat the round as `FINDINGS`,
  read the findings **and any appended `notices`** and dispose exactly as the
  live payload would (gate-level escape → per-finding disposition protocol).
- **File exists but is empty (no findings) and round = 1** → treat as
  `ZERO_FINDINGS_WARNING`: surface the warning **and any appended `notices`** as
  a confirm-to-proceed prompt; do not auto-clear silently. This intentionally
  covers *any* empty round-1 file regardless of how it became empty — both an
  all-empty round-1 sweep and a round-1 all-*dismissed* sweep (findings present
  but all dismissal-filtered away) surface as `ZERO_FINDINGS_WARNING`, so the
  `(count, round)` heuristic and `review-gate.js` agree on the round-1 outcome.
- **File exists but is empty (no findings) and round ≥ 2** → treat as a
  converged `PASS` (a fully-dismissed PASS that still carries `notices` →
  confirm-to-proceed; a clean PASS → silent clear).
- **File does not exist** (the round was `NOTICES_ONLY` / `HALT`,
  indistinguishable from disk) → surface
  `gate result could not be retrieved — re-run or inspect` and **do not
  auto-clear the gate**.

Never treat an unrecoverable result as a pass — fail toward human attention.

**Per-round commit.** After each `FINDINGS` / `PASS` round and each round-1
`ZERO_FINDINGS_WARNING` round (every round that wrote a findings file — round 1
now always writes one, even when all-empty), commit it immediately — before any
engineer-facing disposition, voicing, or clear:

```bash
git add docs/ai/reviews/{TICKET}-*-gate-*.md && git commit -m "{TICKET}: persist design-gate findings round {round}"
```

Interpolate `{TICKET}` and `{round}` to the actual values. The
`docs/ai/reviews/` path prefix is load-bearing — a bare `{TICKET}-*-gate-*.md`
glob from the repo root matches nothing — and the `-m` flag keeps the commit
non-interactive. Committing the round-1 `ZERO_FINDINGS_WARNING` file is the
audit-trail guarantee: a gate that clears via skip still leaves its findings
commit in `git log`. Do NOT defer to Stage 15, so the audit trail survives a
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
`DESIGN_PATH` (the committed design document path `docs/design/{TICKET}-{slug}.md`;
the writer reads the design from it). The design was committed to disk in
Stage 12, so passing its path keeps each of the N task-writer dispatches from
recharging the full design text as cache-read on every orchestrator turn. The
small fields stay inline.

**If `task-writer.md` fails for task N:**

- Preserve all specs written for tasks 1 through N-1.
- Surface the failing task number to the engineer.
- Offer to retry task N only — do not require restarting from the beginning.

**Step 6b — Verify and correct contract fields:**

After `task-writer.md` returns, before the Stage 14b reviewer gate, deterministically
reconcile the two contract fields of the just-written spec against the values you
dispatched. The dispatched `BRANCH` (canonical for `branch:`, computed in step 4)
and `TASK_DEPENDENCIES` (canonical for `Depends on:`, computed in step 5) are the
only source of truth — never the design document's `Branch:` line. You hold both
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

**Step 3b — Build `steeringIndex` and run the completeness cross-check.**
Assemble `steeringIndex` as a preformatted Markdown index string so the
steering-context checks can read the full text only of plausibly-relevant docs
instead of the whole bundle. Follow the procedure in *Building the steering
index* under Stage 12b — run it identically here. The output is either the
index string or `null` (the read-all degrade trigger).

**Step 4 — Assemble and pass all ten args (Interface contract #1).** Compute
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
- `steeringIndex`: the Markdown index string from Step 3b, or `null` (the
  read-all degrade trigger)

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

- **`ZERO_FINDINGS_WARNING`** — first, **commit this round's findings file per
  Per-round commit below** (round 1 is the only case, and it always wrote a
  file), before any voicing or clearing. Then
  voice `report` (which carries the warning
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
  footer (checks run/failed, per-severity counts). Then offer the **gate-level
  choice** over the whole set per **gate-level escape** above — skip /
  only-highs / only-lows / fix-everything — using `Severity` as the triage axis,
  computing and voicing a recommended per-finding disposition for each finding
  within any "fix" choice. The engineer is never required to disposition every
  finding to make progress, partial responses are accepted, and the loop is not
  unlimited: only fix-everything re-runs the gate; skip, only-highs, and
  only-lows each clear it.

  Under a scoped only-highs / only-lows choice, each in-scope **spec-local**
  finding receives a single **Fix — spec patch** pass and then the gate clears —
  it does NOT enter the spec-patch loop-until-clean inner loop below. An in-scope
  **design-upstream** finding is surfaced with its cost warning for elevate (to
  fix-everything) or skip — its full ladder is never run as a scoped one-pass.
  fix-everything runs spec-patch to convergence and the full ladder to
  completion, then re-runs the gate.

  **Fix — full ladder** (design-upstream finding, or engineer design-upstream
  flag). When a finding takes the full ladder, the mandatory cost warning per
  *The disposition protocol* must precede it whenever task specs already exist —
  it regenerates all N specs and re-runs every per-task gate, and spec-patch is
  offered as the alternative. Then:
  1. Engineer directs revision.
  2. Re-dispatch to `design-writer.md` with the updated synthesis written to a
     temp path. Write `.tmp/{TICKET}-design-synthesis.md` from the **revised**
     design content the engineer directed in step 1 — NOT a stale copy of the
     original Stage 2–10 outputs, which would feed the writer stale content and
     silently undo the revision — pass `synthesis_path` =
     `.tmp/{TICKET}-design-synthesis.md`, and after the writer returns delete the
     temp file on BOTH success and failure:

     ```bash
     mkdir -p .tmp
     # write .tmp/{TICKET}-design-synthesis.md from the revised design content
     # dispatch design-writer.md with synthesis_path = .tmp/{TICKET}-design-synthesis.md
     rm -f .tmp/{TICKET}-design-synthesis.md
     ```

     This temp-file write/delete is authored inside the full-ladder step block
     (here at step 2), not at the 14b call site, so Stage 14c — which applies
     these full-ladder steps transitively — inherits it without a separate edit.
     **If the writer re-dispatch fails, surface the failure and halt the Fix
     cycle — do not invoke the next round, as there is no revised artefact to
     review.**
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

  **Fix — spec patch** (spec-local finding at any severity, including High or
  Critical). When a spec-local finding is local to this one task spec:
  1. Patch the single affected task spec only. Do NOT touch, regenerate, or
     rewrite any sibling spec. **If the writer re-dispatch fails, surface the
     failure and halt the Fix cycle — do not invoke the next round, as there is
     no revised artefact to review.**
  2. Re-review that whole patched spec — a fresh full-sweep round with
     `round + 1` and `priorFindingsPath` set to this round's `findingsPath`
     (re-invoke the gate Workflow on it), not a diff.
  3. Under **fix-everything**, loop on that one spec until it is clean.
     Convergence is guaranteed not by an iteration cap but by the always-voice
     rule — at each re-review the engineer sees any re-surfacing finding and can
     elevate it to the full ladder, Skip it, or Dismiss it, so the loop cannot
     silently churn. Under a scoped **only-highs / only-lows** escape this inner
     loop is relaxed to a **single patch pass**: apply step 1 (patch the affected
     spec) once for the in-scope spec-local finding and then clear the gate — do
     not run the step-2 re-review and do not loop.

  **Skip**: add to the session-scoped in-memory skip set; do not record on disk.

  **Dismiss**: append to the design document's `## Dismissals` section with the
  severity label, issue summary, `source` = the originating task-spec filename
  (`{TICKET}-TASK-{NN}-{slug}.md`), and explicit engineer acknowledgement.

  The gate clears once the engineer's gate-level choice completes: skip,
  only-highs, and only-lows clear it and proceed to the next task after their
  one-shot action; fix-everything re-runs the gate until a later round clears.

**Truncated/absent compact result (recovery).** If the completion notification
carries the full compact result, use it. If it delivers only a task ID or a
truncated payload, reconstruct the deterministic findings-file path from the
args just passed (`docs/ai/reviews/{TICKET}-task-{NN}-gate-{round:NNN}.md`) and
check disk. The heuristic keys on **`(findings count, round)`**, not on file
existence alone — round 1 now always writes a findings file (the
`ZERO_FINDINGS_WARNING` write), so an empty file is produced by two legitimate
outcomes and count alone cannot tell them apart:

- **File exists with at least one finding** → treat the round as `FINDINGS`,
  read the findings **and any appended `notices`** and dispose exactly as the
  live payload would (gate-level escape → per-finding disposition protocol).
- **File exists but is empty (no findings) and round = 1** → treat as
  `ZERO_FINDINGS_WARNING`: surface the warning **and any appended `notices`** as
  a confirm-to-proceed prompt; do not auto-clear silently. This intentionally
  covers *any* empty round-1 file regardless of how it became empty — both an
  all-empty round-1 sweep and a round-1 all-*dismissed* sweep surface as
  `ZERO_FINDINGS_WARNING`, so the `(count, round)` heuristic and
  `review-gate.js` agree on the round-1 outcome.
- **File exists but is empty (no findings) and round ≥ 2** → treat as a
  converged `PASS` (a fully-dismissed PASS that still carries `notices` →
  confirm-to-proceed; a clean PASS → silent clear).
- **File does not exist** (the round was `NOTICES_ONLY` / `HALT`,
  indistinguishable from disk) → surface
  `gate result could not be retrieved — re-run or inspect` and **do not
  auto-clear the gate**.

Never treat an unrecoverable result as a pass — fail toward human attention.

**Per-round commit.** After each `FINDINGS` / `PASS` round and each round-1
`ZERO_FINDINGS_WARNING` round (every round that wrote a findings file — round 1
now always writes one, even when all-empty), commit it immediately — before any
engineer-facing disposition, voicing, or clear:

```bash
git add docs/ai/reviews/{TICKET}-*-gate-*.md && git commit -m "{TICKET}: persist task-{NN}-gate findings round {round}"
```

Interpolate `{TICKET}`, `{NN}`, and `{round}` to the actual values. The
`docs/ai/reviews/` path prefix is load-bearing — a bare `{TICKET}-*-gate-*.md`
glob from the repo root matches nothing — and the `-m` flag keeps the commit
non-interactive. Committing the round-1 `ZERO_FINDINGS_WARNING` file is the
audit-trail guarantee: a gate that clears via skip still leaves its findings
commit in `git log`. Do NOT defer to Stage 15, so the audit trail survives a
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

- Findings report: present ALL findings to engineer at once, then offer the
  **gate-level choice** over the whole set per **gate-level escape** above —
  skip / only-highs / only-lows / fix-everything — using `Severity` as the
  triage axis. Per-finding disposition (per **The disposition protocol** above —
  the same routing as the other gates) remains available within any "fix"
  choice. The engineer is never required to disposition every finding to make
  progress, partial responses are accepted, and the loop is not unlimited: only
  fix-everything re-runs the gate; skip, only-highs, and only-lows each clear it.
  Under a scoped only-highs / only-lows choice each in-scope spec-local finding
  gets a single spec-patch pass and the gate clears; an in-scope design-upstream
  finding is surfaced with its cost warning for elevate-to-fix-everything or
  skip — its full ladder is never run as a scoped one-pass.

  - **Fix — full ladder** (design-upstream finding, or engineer design-upstream
    flag; preceded by the mandatory cost warning when specs exist): apply
    the Stage 14b full-ladder steps 1–7 to the finding. After regeneration
    completes, re-run Stage 14c on the regenerated set. Reachable only via
    fix-everything (or surfaced for elevate / skip under a scoped escape).
  - **Fix — spec patch** (spec-local finding at any severity, including High or
    Critical): patch the single affected task spec; siblings untouched (Stage 14b
    spec-patch steps). Under **fix-everything**, full re-review of that whole spec
    and loop until clean, then re-run Stage 14c. Under a scoped **only-highs /
    only-lows** escape, a single patch pass with no re-review loop, then clear.
  - **Skip**: add to the session-scoped in-memory skip set; do not record on
    disk.
  - **Dismiss**: append to the design document's `## Dismissals` section with
    severity, issue summary, `source` = `sync-check`, and explicit engineer
    acknowledgement.

  The gate clears once the engineer's gate-level choice completes — skip,
  only-highs, and only-lows clear it after their one-shot action; only
  fix-everything re-runs Stage 14c. On a cleared gate, proceed to Stage 15.

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
- `labels`: `ai-design`

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
- **Gate ordering is a hard constraint.** Design gate must run before
  sign-off. Sign-off before task generation. Sync-check before push. No
  exceptions. The gates are **advisory** (ADR 014): a gate clears once the
  engineer's **gate-level choice** completes (**gate-level escape**) — skip,
  only-highs, and only-lows clear it after a one-shot action; only fix-everything
  re-runs the gate to convergence. No engineer is ever forced to disposition
  every finding to make progress, partial responses are accepted, and the loop
  is not unlimited. Running the gate and writing-and-committing its round-1
  findings file is mandatory; actioning the findings is the engineer's choice.
- **All three gates route through one disposition protocol.** Stages 12b, 14b,
  and 14c reference the single **The disposition protocol** subsection for the
  routing rules, carrying only their stage-specific deltas rather than restating
  the routing rules themselves. The routing key is design-upstream-ness, not
  severity (ADR 014): a design-upstream finding (or one the engineer flags
  design-upstream) routes to the full ladder, preceded by the mandatory cost
  warning when specs exist; a spec-local finding at any severity — including High
  or Critical — takes the spec-patch path (unavailable at the design gate, which
  has no specs). Severity is advisory and the gate-escape triage axis only.
  Ambiguity defaults to spec-local.
- **Always voice, never auto-apply.** Every finding is presented with a
  recommended disposition; nothing is fixed, skipped, or dismissed without the
  engineer confirming or overriding. The design-upstream routing key produces a
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

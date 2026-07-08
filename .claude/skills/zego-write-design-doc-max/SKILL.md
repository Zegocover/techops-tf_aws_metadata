---
name: zego-write-design-doc-max
description: You MUST use this ONLY when the user explicitly asks for the "max" design-doc flow (the high-context variant that runs an incremental review of every design and task document). For any other request to write a design document or task specs, use zego-write-design-doc instead.
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

You are the orchestrator for `zego-write-design-doc-max`. You conduct a two-phase
session: Phase 1 builds a Design Document autonomously — Stages 2–11 run without
an engineer prompt and the single Phase 1 stop is the Stage 13 sign-off gate;
Phase 2 generates Task Specs autonomously from the confirmed document.

You dispatch all writing to sub-agents. You do not write task specs or design
documents yourself. You do not ask the engineer questions during Phase 2, and you
do not ask the engineer questions during Stages 2–11 of Phase 1 — every auto-made
decision is recorded to the decision ledger and surfaced at Stage 13.

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

If the branch name starts with the ticket key (e.g. `AIDEV-29_*`), it may be
the requirements-phase branch (the `zego-write-requirements` skill uses the
same `{TICKET}_{slug}` shape) — run requirements-branch detection before
continuing. The branch is the requirements branch when **either** signal
fires:

1. **PR label signal (primary):** the branch has a PR carrying the
   `ai-requirements` label —
   `gh pr view --json labels --jq '.labels[].name' 2>/dev/null` outputs
   `ai-requirements`. If `gh` fails or the branch has no PR, fall through to
   the diff-content signal.
2. **Diff-content signal (fallback — covers the no-PR and `gh`-unavailable
   cases):** resolve origin's default branch (`git symbolic-ref --short
   refs/remotes/origin/HEAD`, stripping `origin/`; if that fails,
   `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`), then
   `git diff --name-only $(git merge-base HEAD origin/{default-branch})..HEAD`
   is non-empty and every path starts with `docs/requirements/`. An empty
   diff means no commits of its own — treat as *not* a requirements branch.

If neither signal can be evaluated (default branch unresolvable, git command
failure), skip detection and use the confirm-and-continue behaviour below —
never block Stage 1 on detection.

### Requirements-branch base decision

Whenever a branch `B` is identified as the requirements branch (either arm
below), decide where to cut the design branch from, based on whether the
requirements PR is open or merged. `D` is origin's resolved default branch.

1. **PR state (primary):** current branch —
   `gh pr view --json state --jq '.state' 2>/dev/null`; another branch `B` —
   `gh pr view {B} --json state --jq '.state' 2>/dev/null`. Values `OPEN`,
   `MERGED`, `CLOSED`, or empty/failure = unknowable.
2. **Git-only fallback (only when PR state is unknowable):**
   `git merge-base --is-ancestor {B-tip} origin/{D}` — exit 0 → B's tip is
   already an ancestor of the default → treat as merged; non-zero → open.
   Reliable for merge-commit merges but NOT squash merges (a squash-merged
   tip is not an ancestor), which is why PR state is primary.
3. **Decision:**
   - **OPEN, or unknowable-and-not-an-ancestor** → requirements doc not yet on
     the default; stack the design branch on the requirements HEAD (cut from
     `B`) and record `design_base = {B}` for Stage 15:

     ```bash
     git checkout -b {design-branch} {B}
     ```

   - **MERGED, or unknowable-but-an-ancestor** → requirements doc already on the
     default; B's tip is a stale base. Cut from the default and record
     `design_base = {D}` for Stage 15:

     ```bash
     git checkout -b {design-branch} origin/{D}
     ```

The design branch name is `{TICKET}_{design-slug}` (short kebab-case slug from
the feature name) and **must differ from `B`** — append `-design` if the
natural slug collides.

**If detected as the requirements branch** (the current branch is `B`): do not
continue on it. First compute the proposed `{TICKET}_{design-slug}` (with the
collision/`-design` rule) and check whether it already exists locally:

```bash
git rev-parse --verify --quiet refs/heads/{proposed-design-branch}
```

If it already exists, the current branch is already the design branch from a
prior interrupted run (Stages 2–11 run autonomously and don't commit the design
until sign-off; the still-empty design branch carries only `docs/requirements/`
commits, which the diff-content signal misreads). Do **not** re-stack or re-create: treat the current branch as
the design branch, record `design_base` from the base decision (against the
requirements branch it is stacked on), confirm and continue. Only when the
proposed branch does not exist do you apply the base decision above (with
`B` = the current branch), asking the engineer to confirm or adjust the name
first.

Then proceed with the rest of this stage unchanged.

**If ticket-prefixed but not detected as the requirements branch:** the branch
may still be a *merged* requirements branch — after a merge-commit merge its own
commits are already on the default, so the diff-content signal is empty and
detection misses it. Check for staleness:

```bash
git merge-base --is-ancestor HEAD origin/{default-branch}   # exit 0 → HEAD is an ancestor of the default
git rev-parse HEAD origin/{default-branch}                  # compare the two SHAs
```

**Stale** (merge-commit-merged; tip is a stale base) = HEAD is an ancestor of
the default AND the SHAs differ (strictly behind). **Live** = SHAs equal (fresh
branch at the default tip) or HEAD not an ancestor (has its own commits, e.g. an
in-progress design branch).

- **Live** → confirm and continue. Record `design_base = {default-branch}`.
- **Stale** → do not continue on the stale tip. Apply the base decision's
  **merged** outcome: propose `{TICKET}_{design-slug}` (differ from the current
  branch, `-design` on collision) and cut a fresh design branch from the default,
  recording `design_base = {default-branch}`:

  ```bash
  git checkout -b {design-branch} origin/{default-branch}
  ```

If the branch name does not start with the ticket key, propose
`{TICKET}_{description}` (short kebab-case slug from the feature name). Before
creating it, check whether the proposed name already exists — locally or on
origin — because a run started from the default branch can derive the same slug
as an existing requirements branch (a local ref collides loudly; a remote-only
ref silently shadows a branch cut from the default that cannot read the unmerged
`docs/requirements/` doc):

```bash
git rev-parse --verify --quiet refs/heads/{proposed}      # local
git ls-remote --exit-code --heads origin {proposed}       # remote (exit 0 = exists)
```

If it exists in either place, run the same two-signal detection against that
existing branch (querying `gh pr view {proposed}` and diffing `{proposed}`
against the default branch, instead of the current branch). If it **is** the
requirements branch, apply the base decision (with `B` = that branch) and the
collision/`-design` naming rule, and record `design_base`. If it is **not** a
requirements branch, surface the collision to the engineer and ask them to
confirm or supply a different name rather than creating or shadowing it. If the
proposed name does not exist anywhere, create it as before and record
`design_base = {default-branch}`:

```bash
git checkout -b {branch-name}
```

Check for a prior run:

```bash
rg -l "^# Design:" docs/design/ 2>/dev/null | rg "{TICKET}-"
```

If a matching Design Document exists, offer to continue from it or start fresh.
If continuing: read the document and re-parse it into the following structured
fields before doing anything else. `## Summary` is a presence/structural field —
it has no upstream synthesis variable (the seven sections each map to a synthesis
field such as `approach`; `## Summary` is composed from those, not parsed from a
distinct field), so it is recorded as a "must be present" entry, not a synthesis
variable:

- `## Summary` — must be present (the human-first skim section, distinct from the
  seven body sections below; checked for presence only, no synthesis variable)
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

A resumed design is **not** re-asked the approach-brief opt-in question below:
it has already established its intake handle. Also
read the existing **`## Auto-decision ledger`** section back out of the located
document and recover its entries into the decision ledger, so prior-session
auto-decisions carry
forward: a resumed run must **not** start with an empty ledger and must not reach
Stage 13 with prior-session decisions unrecorded. Recover that handle from the
document rather than hard-coding it. A design authored *with* a brief carries a
`## Inputs / prior-planning references` section (front-loaded, above
`## Approach`), and forcing `no-brief` on resume would make a subsequent Stage 12
revision silently drop that section. Recovering the handle here gives the
resume→revise path the same protection the Stage 12b carry-forward guard already
gives the gate-driven revision path:

- **The document contains a `## Inputs / prior-planning references` section**: it
  was brief-seeded. Set `brief_handle = brief` and capture the section's existing
  content verbatim as `carried_inputs` (the reference links and their one-line
  descriptions). The original brief temp/synthesis content is no longer in hand on
  resume, so `carried_inputs` (not a re-derived brief) is what a later Stage 12
  re-write threads to the writer to **re-emit unchanged**, preserving the section
  rather than dropping it.
- **No such section is present**: the design was authored cold. Set
  `brief_handle = no-brief` as before.

Skip the Stage 1a intake step in both cases.

Once all fields are populated, summarise what was planned, ask the engineer
what to change, and jump to Stage 11. If starting fresh or no prior document:
run the Stage 1a approach-brief intake, then continue to Stage 2.

### Stage 1a: Approach-brief intake (start-fresh branch only)

Run this step **only** on the start-fresh branch above (after the resume
detection, never before it). A resumed design has already recovered its
`brief_handle` from the document (`brief` with `carried_inputs`, or `no-brief`)
and skips this step entirely.

Read `.claude/skills/shared/approach-brief-intake.md` and execute its contract,
filling its placeholders:

| Placeholder | Value |
|-------------|-------|
| `{ticket}` | `{TICKET}` from Input handling |
| `{branch}` | the branch confirmed in Stage 1 |
| `{starting-fresh}` | `true` (this step runs only on the start-fresh branch) |

The shared contract is the single source of the intake: the opt-in question,
the one-time no-brief advisory, the read-in-full, the substantiveness check, and
the seeding/coverage/citation rules. Do **not** inline or paraphrase a second
copy of it here (ADR 007). The intake is read-only, writes no durable state, and
never hard-fails the session: a missing path is re-asked once then falls through
to `no-brief`.

Capture the returned handle as `brief_handle`:

- `no-brief`: no brief was used (the engineer answered "no", a named path did not
  resolve after one re-ask, or the brief was rejected as thin). The one-time
  brainstorm advisory was already surfaced by the shared contract. Author the
  design **cold**, the unchanged path: omit the Inputs section entirely and leave
  the cold path otherwise unchanged. The opt-in question and one-time advisory
  ahead of the cold path are expected, not suppressed.
- `brief {path, source-type, content}`: a brief was read in full. Hold the full
  handle (including the read-in-full `content`) in scope for Stage 2 and Stage
  12: Stage 2 seeds the Approach from it and Stage 12 threads it to the writer.

Continue to Stage 2 with `brief_handle` in scope.

---

# Phase 1 — Autonomous Design Interview

Stages 2–11 run **autonomously in sequence** with **no engineer prompt**: Phase 1
stops for the engineer exactly once, at the Stage 13 sign-off gate. Do not ask the
engineer to confirm, revise, or resolve anything during Stages 2–11; derive each
stage's answer yourself and continue.

**Derive each stage's answer in this priority order:**

1. **User-provided trigger inputs** — the JIRA ticket, the prompt text, and any
   referenced documents supplied at intake.
2. **The brainstorm brief / requirements-doc content** — the `brief_handle`
   content from Stage 1a and the resolved requirements source.
3. **The skill's own codebase reading** — use Bash and Read to explore directory
   structures, examine existing patterns and interface signatures, and search for
   relevant files. Ground the design in what you observe; do not defer to the
   engineer for anything you can read directly.

**Where confidence is genuinely low or information is genuinely missing,** dispatch
an **investigation sub-agent via the Agent tool** (`subagent_type: general-purpose`)
with a scoped research question and pointers to the relevant inputs and codebase.
Adopt its recommended option and record the rationale and the rejected
alternatives to the decision ledger. Do **not** stop to ask the engineer.

**A genuinely blocking gap** — one with no defensible inferred or investigated
answer — is recorded as an **open item** in the decision ledger and surfaced at
Stage 13. Never fabricate a decision to avoid a stop, and never silently skip a
gap.

**The decision ledger.** Maintain a running record through Stages 2–11. For each
auto-made decision, record:

- **what was decided** — the answer adopted for that stage;
- **the basis** — one of `inferred-from-input`, `inferred-from-codebase`,
  `sub-agent-investigated`, or `engineer-directed` (set only when the engineer
  intervenes on the row at Stage 13 — see below);
- **rejected options** — the alternatives considered and not taken.

The ledger also carries the coverage-classification net-new notes, the Stage 11
revisit assessment, and any unresolved/exploring-brief resolution (with its
alternatives and any recorded dissent). The ledger is written
**into the design document body** as a dedicated **`## Auto-decision ledger`**
section — rendered human-first: a short intro plus a `<details>`-collapsed
per-decision table — with each entry carrying a **two-state attribution**:
**`AI-made`** (with its basis) is the default — the absence of an engineer tag means
the decision was **accepted as-is at sign-off** (the Stage 13 sign-off is itself the
acceptance record, so no per-row marking is added for accepted decisions); a row is
marked **`engineer-directed`** only where the engineer actively intervened on it (an
override or an open-item resolution at Stage 13 — see Stage 13). So the design
document carries a **durable, auditable trail** of which decisions were auto-answered
and where the engineer diverged from them — one that survives Stage 13 sign-off and
any mid-run resume, not held only in working context. In this skill the design
document is authored by the design-writer sub-agent rather than written inline, so
the ledger accumulated as each Stage 2–11 decision is made is threaded to the
writer and persisted as the `## Auto-decision ledger` section at Stage 12 (and
refreshed on every subsequent write); on resume it is read back out of the located
document (Stage 1 resume detection) so prior-session auto-decisions carry forward.
It is presented in full at Stage 13 so the engineer reviews every auto-made
decision in one place before sign-off.

**Open items are a distinct row class from adopted decisions.** An open item is a
genuinely blocking gap the AI could neither infer nor investigate; it is *not* an
adopted decision, so it renders differently in the `## Auto-decision ledger` table:

- **Stage column** — show **where the gap arose** (the stage that hit it) *and* that
  it is surfaced at Stage 13, e.g. `arose Stage 3 Components · surfaced Stage 13`.
  This differs from an adopted-decision row, whose Stage column names where the
  decision was *made*; an open item must not be labelled with the surfaced-at stage
  alone.
- **`#` (numbering)** — open items are **not** part of the numbered adopted-decision
  sequence (`1..N`); render the `#` column as a dash (`—`) so they are visually
  separable from decisions.
- **Status** — `Open — needs engineer` while unresolved. On resolution at Stage 13
  the row **leaves the open-item class**, becomes an `engineer-directed` decision, and
  joins the numbered sequence (see Stage 13) — so a resolved open item is no longer an
  open item.

Read the codebase actively before Stage 2 — use Bash and Read to ground the
design in observable reality.

---

## Stage 2 — Approach

Read relevant codebase areas. Derive a candidate approach from the priority
order (trigger inputs → brief/requirements → codebase reading). Record the
confirmed approach, its basis, and any rejected alternatives to the decision
ledger.

**If `brief_handle` is a `brief` (a brief was read in Stage 1a):** the Approach is
**seeded** from the brief rather than proposed cold. Per the shared intake
contract (Steps 5, 6), the brief is the authoritative starting content for this
section. Apply the decisive test per passage: a task-blocking instruction,
boundary, or contract fact (plus the load-bearing-decision escape clause) is
`incorporate-with-provenance`, written into this Approach section with a clickable
relative-link backlink to its source; everything else (settled-upstream content
and rationale) defaults to a `pointer`, a clickable reference rather than a
rewrite. Do **not** wholesale-rewrite the brief's prose into this or any other
section: draw on the brief for facts and citations only. Seed ONLY the Approach
here (the Inputs section is seeded by the writer in Stage 12); author every other
interview section normally while drawing on the brief. Adopt the seeded Approach,
naming the brief path in the ledger entry.

**If `brief_handle` is `no-brief` (cold path):** derive one candidate approach
from the priority order, exactly as before; the cold path is unchanged except the
approach is adopted autonomously rather than proposed to the engineer for
confirmation.

**Unresolved/exploring brief.** If the intake classified the brief as
`resolve-then-seed` (a `zego-brainstorm` artefact with `state: unresolved` or
`state: exploring`), do **not** stop to ask the engineer to settle its open
choice. Dispatch an investigation sub-agent via the Agent tool to research the
brief's candidate options (and any recorded dissent) and select the best
candidate; the sub-agent's selection becomes the seeded Approach. The design
records a **settled** approach and never carries open questions. Record the
settled choice — with its alternatives and any recorded dissent — to the decision
ledger, flagged for **prominent** presentation at Stage 13 so the engineer can
overturn it before sign-off. If the sub-agent cannot select a defensible candidate
(failure or empty return), record the open choice as an open ledger item for
Stage 13; and if the brief is too thin to author against at all, redirect to
`zego-brainstorm` and do **not** author the design.

---

## Stage 3 — Components affected

Derive existing (modified) and new (created) components based on codebase
reading and confirmed approach. Record the confirmed components to the decision
ledger (basis + any rejected alternatives) and continue.

---

## Stage 4 — Interface contracts

Derive contracts for each new or modified interface:
Input / Output / Errors / Side effects. If no new or modified interfaces
exist, state that. Record the confirmed contracts to the decision ledger and
continue.

---

## Stage 5 — External references (document-type tasks only)

**Skip if code-only task.**

Derive the reference set autonomously from the priority order: the trigger inputs
(URLs, file paths, or named standards named in the JIRA ticket, prompt, or brief),
then the requirements-doc content, then the codebase — do **not** ask the engineer
to paste references. Fetch each URL with WebFetch, read each local path with Read,
and note named-only standards for the ledger (do not search without a URL). Where
the trigger inputs plainly imply relevant documentation that is not named,
dispatch an investigation sub-agent to locate it; adopt what it returns and record
the basis, or record "no references derived" and continue. Summarise coverage and
relevance and record the reference set to the decision ledger. Then read all files
under `docs/ai/steering/` for Stage 6 conflict detection.

---

## Stage 6 — Conflict detection (document-type tasks only)

**Skip if not document-type** (determined in Stage 5).

1. Read all existing files under `docs/ai/steering/`. Skip files already read.
2. Compare every planned rule against every existing file.
3. If conflicts found: do **not** stop to ask. For each conflict, record to the
   decision ledger the rule introduced, the clashing rule (file path and text),
   the contradiction, and the resolution adopted (default: defer to the existing
   rule — keep it and drop or narrow the introduced one, unless the trigger inputs
   or brief explicitly override it), expressed as a Phase 2 constraint. Where the
   right resolution is genuinely unclear, dispatch an investigation sub-agent; if
   it cannot resolve the conflict, record it as an open ledger item for Stage 13.
4. If no conflicts: record that and continue.

Record constraints and ACs from this stage to the decision ledger for Phase 2.

---

## Stage 7 — Task breakdown

Derive a task breakdown. Size each task as a thin end-to-end vertical slice —
one outcome, spanning as many components as it touches — that fits one
Opus-level agent's loadable working set: the task spec plus the files it must
read and write, with headroom to reason. Fold trivial edits and their tests
into the slice whose agent already holds that context; split a task out only
when bundling it would risk context pressure. Prefer coarser, outcome-shaped
slices over one-deliverable-per-task fragments; a slice may still be
independently implementable from a single task spec. **If the breakdown you
derive contains zero tasks**, add at least one task covering the confirmed
approach's single coherent outcome — under autonomy the orchestrator supplies it
rather than stopping to ask — and record the self-correction to the decision
ledger; the Stage 13 backstop still rejects sign-off on a zero-task breakdown if
it somehow remains empty. Record the confirmed breakdown to the decision ledger
with precise names and dependencies.

---

## Stage 8 — Test strategy

Derive integration test owner, E2E approach, and cross-task constraints.
Record the confirmed test strategy to the decision ledger and continue.

---

## Stage 9 — Risks and constraints

Derive risks and constraints from codebase reading and design.
Include conflict-detection constraints (Stage 6) for document-type tasks.
Record the confirmed risks and constraints to the decision ledger and continue.

---

## Stage 10 — ADR references

List existing decisions files:

```bash
ls docs/decisions/ 2>/dev/null
```

Derive which existing ADRs constrain this design and decide autonomously whether
a new ADR is warranted (default: none, unless the design introduces a
cross-cutting architectural decision). Record the referenced ADRs and any new-ADR
decision — with its basis and the rejected alternative (ADR vs no ADR) — to the
decision ledger; a new-ADR decision is a judgement call, so flag it for the
engineer at Stage 13.

---

## Stage 11 — Revisit gate

Before producing the Design Document, assess autonomously whether any section
needs revisiting in light of later stages (e.g. the task breakdown surfaced a
component the Approach missed). If so, jump back to the originating stage, update
the draft, and return here. Do **not** ask the engineer whether to revisit: the
single Phase 1 stop is the Stage 13 sign-off gate, where the engineer reviews the
whole design and the decision ledger and can request any change then. Record the
revisit assessment — which sections were revisited and why, or "no revisit
needed" — to the decision ledger. The design is not locked until sign-off.

---

## Stage 12 — Write Design Document

Derive `feature_name` autonomously from session context — the feature title, taken
from the JIRA summary or requirements document title. Do **not** prompt the
engineer: the single Phase 1 stop is the Stage 13 sign-off gate. If neither source
yields a clean title, infer one from the JIRA key and the approach already held in
context.

Derive slug: lowercase feature name, replace non-alphanumeric runs with a
single hyphen, trim leading/trailing hyphens, truncate to 40 chars.

```bash
mkdir -p docs/design
```

Write the design-writer synthesis to a temp file, then dispatch the writer
against its path. Be clear-eyed about the cost: the orchestrator authors the
synthesis, so its full content enters the transcript through the Write call
either way — the file buys retry-cheapness (a failed writer re-dispatches
against the same path without re-emitting), not context savings. This is the
ONE place the full design content crosses the orchestrator's output; every
later revision uses the writer's revision mode against the on-disk design
instead (see the full-ladder steps).

```bash
mkdir -p .tmp
```

**Resolve `feature_id` (the shared feature identifier, AIDEV-188 / ADR 020)
before assembling the synthesis file.** On the happy path the design phase
**recovers** the identifier minted by the requirements phase and **reuses** it,
falling back to `decide` only when recovery yields nothing. It **mints** only on
a genuine first-run design-first entry — when recovery yields nothing AND
`decide` returns MINT (no predecessor PR), matching `fix-bug`'s no-predecessor
flow. This is best-effort and advisory: any failure warns and proceeds with an
EMPTY `feature_id` value (a reporting gap is acceptable; a blocked skill is not).
An empty Feature-Id never blocks the flow.

1. **Recover from the requirements artefact** when one exists. The
   `requirements_source_path` is the requirements doc when input was a
   `docs/requirements/` path:

   ```bash
   FEATURE_ID="$(.claude/scripts/feature-id.sh recover "{requirements_source_path}" 2>/dev/null || true)"
   ```

2. **Compute `predecessor-pr-exists`** for the `decide` fallback. Query the
   requirements branch (read from the requirements-doc frontmatter); **fall back
   to the current branch when no requirements doc exists** (input was a bare
   JIRA URL with no `docs/requirements/` artefact):

   ```bash
   REQ_BRANCH="<requirements-branch from the requirements-doc frontmatter, or the current branch when no requirements doc exists>"
   if PRED_JSON="$(gh pr list --head "$REQ_BRANCH" --state all --json number 2>/dev/null)"; then
     if [ "$(printf '%s' "$PRED_JSON" | grep -c '"number"')" -gt 0 ]; then PRED=true; else PRED=false; fi
   else
     # A gh failure is NEVER read as "no predecessor PR" — that would let a
     # truly-lost id fall through to MINT and duplicate the identifier (FR-02).
     # Default LOST-safe: pass true and warn.
     PRED=true
     echo "write-design-doc-max: gh pr list failed for '$REQ_BRANCH' — defaulting predecessor-pr-exists to true (LOST-safe)" >&2
   fi
   ```

3. **Decide** when recovery returned nothing:

   ```bash
   if [ -z "$FEATURE_ID" ]; then
     VERDICT="$(.claude/scripts/feature-id.sh decide "" "$PRED")"
     if [ "$VERDICT" = "MINT" ]; then
       # Design-first entry: no requirements artefact and no predecessor PR, so this
       # design PR is the feature's first PR-producing phase. Mint here (matching
       # fix-bug's no-predecessor flow) — a true MINT verdict means there is no
       # predecessor PR, so minting cannot split a feature (that case is LOST, not MINT).
       FEATURE_ID="$(.claude/scripts/feature-id.sh mint 2>/dev/null || true)"
     fi
     # REUSE never occurs here (recovery already failed). LOST → proceed with an
     # empty Feature-Id value (LOST-safe; do not mint, since a predecessor PR
     # exists and minting would duplicate/split the identifier — FR-02).
   fi
   ```

The resolved `$FEATURE_ID` (possibly empty) is the `feature_id` field passed to
the design-writer below; the writer places it on the design header's
`Feature-Id:` line (line 7). A successful recover (or, on a design-first entry,
a successful mint) is the normal path. If `$FEATURE_ID` is empty after recover +
decide (a LOST verdict, or a `gh`/mint failure), surface a warning to the
engineer that the identifier could not be resolved (recover it manually, or
confirm the requirements doc carries a `Feature-Id` row), and proceed — an empty
value is advisory and never blocks the design phase.

Write the synthesis file `.tmp/{TICKET}-design-synthesis.md` holding every
field the design-writer needs — all structured interview outputs (Stages 2–10)
plus `feature_name`, `requirements_source_path`, `branch`, `ticket`,
`engineer`, `date`, and `feature_id` (the resolved `$FEATURE_ID`, possibly
empty) — as labelled Markdown sections (one `## {field}` heading per field). At
this initial write the Stage 2–10 outputs are freshly in hand, so write them
directly.

**Thread the approach brief to the writer (when `brief_handle` is a `brief`).**
The synthesis file is the writer's complete brief, so the brief must reach the
writer through it: add a `## brief_handle` section recording `brief` and a
`## brief` section holding the brief's resolved `path`, `source-type`, and the
read-in-full `content` verbatim (the same `content` captured in Stage 1a). The
brief `content` is an arbitrary planning document that may itself contain `##`
headings (a `zego-brainstorm` artefact has its own `## Approach`, `## Components
affected`, and so on), so it MUST be fenced from the synthesis file's own
`## {field}` delimiter scheme: emit the verbatim `content` between the `## brief`
heading and an explicit `## /brief` sentinel line on its own (the closing
sentinel sits flush-left, exactly `## /brief`, after the last line of content).
Without the sentinel a brief's internal heading would be mis-read as a sibling
synthesis field or would truncate the `## brief` section early. The writer needs
the full content to seed the Inputs section and apply the coverage
classification; a writer that never receives the brief is a defect. When
`brief_handle` is `no-brief`, write `## brief_handle` recording `no-brief` and
omit both the `## brief` section and the `## /brief` sentinel entirely. The writer then omits the Inputs section
and authors the cold path unchanged.

**Carried-forward Inputs on a resumed brief-seeded design (`carried_inputs`).**
A resumed design recovers `brief_handle = brief` from its existing Inputs section
but has **no brief `content` in hand** (the original brief temp/synthesis content
is gone). In that case omit the `## brief` / `## /brief` block and instead add a
`## carried_inputs` section holding the existing `## Inputs / prior-planning
references` content captured at resume, fenced exactly as the brief is: between
the `## carried_inputs` heading and an explicit `## /carried_inputs` sentinel line
on its own (flush-left), since the carried content contains Markdown links and
may contain `##` headings. The writer re-emits this section verbatim as the
Inputs section rather than re-deriving it from a brief. Still record
`## brief_handle` as `brief`.

Read `.claude/skills/zego-write-design-doc-max/design-writer.md` in full. Dispatch to it via
the Agent tool: pass the sub-agent file content as the prompt; pass
`synthesis_path` = `.tmp/{TICKET}-design-synthesis.md` as the single named
field in the user message (the writer reads every field from that file,
including `brief_handle` and any `brief` or `carried_inputs` section).

The writer emits the **human-first shape** that `design-writer.md` and the
`.claude/skills/zego-write-design-doc-max/design-document.md` template define:
`## Summary` first (distinct from the seven body sections), `mermaid` diagrams (a
component map under `## Components affected`, a dependency graph under
`## Task breakdown`), `<details>` collapsing of the interface contracts and the
long per-task detail, and sparing GitHub callouts in the `## Summary` only
(`> [!IMPORTANT]` for the judgement-calls, `> [!WARNING]`/`[!CAUTION]` for the
risk). The `## Summary`, diagrams, and callouts are illustrative-only — never the
sole source of a machine fact, which stays in the seven prose/structured
sections. The six-line header and the seven `##` sections are preserved verbatim
and in order.

After the writer returns — on BOTH success and failure — delete the synthesis
temp file:

```bash
rm -f .tmp/{TICKET}-design-synthesis.md
```

If the sub-agent fails or returns empty output: surface the error to the
engineer and offer to retry. Do not advance silently.

After the sub-agent returns, do NOT read the written design document into
the orchestrator context — the design text is sub-agent-authored and lives on
disk, and keeping it out of the transcript is what makes path-passing pay off.
Structural verification is deterministic (the header script below; the Stage
12b Step 1 section-presence guard runs an `rg` sweep). When a later step needs
a specific section (Step 3's `## Components affected`, Stage 14's `## Task
breakdown`), extract that section alone with `rg` / `sed -n` rather than
reading the whole document.

**Verify the header deterministically.** Run:

```bash
python3 .claude/skills/zego-write-design-doc-max/scripts/verify-design-header.py docs/design/{TICKET}-{slug}.md {TICKET}
```

Exit 0 (`OK`) means the canonical six-line header is intact. On failure the
script prints one line per deviation (line number, observed, expected shape);
fix the named lines directly with Edit using the canonical values you hold
(`feature_name`, `ticket`, `engineer`, `requirements_source_path`, `date`,
`branch`) and re-run until clean. This replaces the old `header-format` check
agent — no gate round is spent on header drift. Re-run this verification after
every full-ladder design revision too.

**Persist the decision ledger into the design document.** The design document is
authored by the design-writer sub-agent, so the ledger accumulated through Stages
2–11 is persisted here, once the writer has returned. Using the in-context ledger
you hold (do **not** read the sub-agent-authored body back to obtain it), write a
dedicated **`## Auto-decision ledger`** section into `docs/design/{TICKET}-{slug}.md`
with Edit — appended after the seven body sections and before any `## Dismissals`
section. Render it human-first: a short intro sentence plus a `<details>`-collapsed
per-decision table whose rows carry *what was decided*, *the basis*
(`inferred-from-input` / `inferred-from-codebase` / `sub-agent-investigated`),
*rejected options*, and the **two-state attribution** — **`AI-made`** (default; the
absence of an engineer tag means accepted-as-is at sign-off) versus
**`engineer-directed`** (an engineer intervention) — plus the carried items
(coverage-classification net-new notes, the Stage 11 revisit assessment, and any
unresolved/exploring-brief resolution with alternatives and dissent). This gives the
committed design a durable, auditable trail that survives Stage 13 sign-off and any
mid-run resume. Writing this one named section from the ledger you already hold does
not count as reading the design body back into context. **Refresh the
`## Auto-decision ledger` section this same way after every full-ladder design
revision** — the revision-mode writer preserves it as an undirected section, so
re-emit it only when the ledger itself changed. When a Stage 13 change-request
loop-back re-marks a row `engineer-directed` (an override or an open-item
resolution), this same refresh path re-writes the section, so the committed document
carries the final attribution. The section rides into the Stage 12b per-round design
commit, so it is durably recorded before sign-off.

**Render any open-item rows as their distinct row class** (see *The decision ledger*
above): the `#` column is a dash (`—`), not a sequence number; the Stage column reads
`arose Stage N {name} · surfaced Stage 13` (where the gap arose, plus the surfaced-at
stage); and the status is `Open — needs engineer`. A resolved open item is instead
rendered as its `engineer-directed` decision row within the numbered sequence.

**Do not commit the design document yet.** The design is committed atomically
with each gate round's findings file (see *Per-round commit* in Stage 12b), so
every findings commit snapshots the exact artefact version that round
reviewed. There is no separate design-only commit.

Tell the engineer:

> Design Document written to `docs/design/{TICKET}-{slug}.md`. Running design gate now…

## The disposition protocol

This is the single shared definition of how a review gate dispositions a
finding. Stages 12b and 14b both reference this subsection for the routing rules;
each carries only its stage-specific deltas — which dispositions are available,
the stage-local action for each, and the `source` value — and does not restate
the routing rules themselves. ADR 010 (`docs/decisions/010-review-gate-disposition-model.md`)
is the canonical model — this subsection carries only what the orchestrator
needs to act on it, and does not re-author it.

**Finding schema.** Each finding from a gate check agent carries the six
fields defined in `.claude/skills/zego-write-design-doc-max/check-principles.md`: `Severity`
(`Critical` / `High` / `Medium` / `Nit pick`), `Issue`, `Why it matters`,
`Size of fix` (`trivial` / `local` / `broad`), `Target` (`load-bearing` /
`illustrative`), and `Suggested resolution` — plus the required-but-nullable
`Spec` attribution field (the affected spec's filename at the batch task gate,
or null for a design-gate or genuinely cross-spec finding). Separately, at disposition time the
engineer may flag the finding design-upstream; this flag is an engineer action
applied during disposition, not a field the reviewer emits. Whether the finding
is **design-upstream** is the routing key (see *Routing key:
design-upstream-ness* below); `Severity`, `Size of fix`, and `Target` are
advisory inputs that tune the recommendation, and `Severity` is additionally the
triage axis the gate-level escape uses.

**The four dispositions.**

- **Fix — full ladder.** The heavyweight path: revise the design → re-run the
  design gate → regenerate all task specs from scratch (in parallel) → re-run
  the batch gate once. This is the Stage 14b revision ladder (steps 1–7). Use it for a
  **design-upstream** finding — one whose resolution requires editing the Design
  Document itself — at any severity, or any finding the engineer flags
  design-upstream. When task specs already exist, a mandatory cost warning
  precedes it (see *Mandatory full-ladder cost warning* below); it is never the
  silent default.
- **Fix — spec patch.** The lightweight path: patch the affected task spec(s)
  — identified by each finding's `Spec` field, in parallel when several specs
  are affected — then re-review with one fresh batch round (a full re-review,
  not a diff), repeating until clean under fix-everything. It never
  regenerates or rewrites an unaffected sibling spec. It is the route for a **spec-local** finding — one resolvable by
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
re-runs the batch gate — a significant time and cost hit — and MUST offer
the **Fix — spec patch** path as the alternative. The full ladder is never the
silent default.

**A full ladder is never run in an automated round.** During the automated
fix-everything rounds of a Stage 14b gate loop (see *The two-round automated
budget* below), a design-upstream finding is never taken through the full ladder
unattended: it is deferred as a persisted finding while spec-local findings are
auto-spec-patched, and if only design-upstream findings remain the automated
path exits early to the prompt path so this cost warning is always voiced to the
engineer before any regeneration. At Stage 12b no specs exist and the full
ladder is just an in-place design revision, so the cost warning does not apply
there.

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
the gates remain individually attributable:

- **Stage 12b (design gate)** → `source` = `design-gate`.
- **Stage 14b (batch reviewer gate)** → `source` = the finding's `Spec`
  filename (e.g. `{TICKET}-TASK-{NN}-{slug}.md`), or `task-batch` for a
  cross-spec finding.

`## Dismissals` is managed by SKILL.md only — check agents and reviewer
sub-agents must not create or modify it.

### gate-level escape

Per ADR 014 (`docs/decisions/014-launch-safe-advisory-gates.md`), amended by
ADR 024 (`docs/decisions/024-auto-fix-design-doc-max-gate-rounds.md`), the gates
are **advisory**: a FINDINGS round never forces the engineer to disposition every
finding to make progress, and the loop is not unlimited. ADR 014's original rule
was that *every* FINDINGS round opens with the engineer-facing gate-level choice;
ADR 024 amends this so the first two FINDINGS rounds of each gate loop
auto-apply **fix-everything** without prompting (the *automated path*), and the
engineer-facing **gate-level choice** is presented only from the third
un-converged round onward — or earlier on a Stage 14b all-design-upstream round
(the *prompt path*). See *The two-round automated budget* below for the counter,
the latch, and the per-round FINDINGS decision that route between the two paths.

When the prompt path is reached, the **gate-level choice** over the whole
surviving set, using `Severity` as the triage axis, is:

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

### The two-round automated budget

Per ADR 024 (`docs/decisions/024-auto-fix-design-doc-max-gate-rounds.md`), each
gate loop gets a session-scoped budget of **two automated fix-everything
rounds** before the engineer-facing gate-level choice engages. Two pieces of
orchestrator state and a partitioned `FINDINGS` decision govern this, applied
identically at Stage 12b and Stage 14b (the two *Handle the compact result*
`FINDINGS` branches below are near-mirrors of each other and both defer to this
section).

**`autoFixRounds` (counter).** A non-negative integer, held in the
orchestrator's working context only.

- Scope key: `(gateType, artefactSlug)` for the current gate loop in the current
  session. `gateType` is the value passed to `review-gate.js` and used as the
  existing `round` scope key — `"design"` (Stage 12b) or `"task"` (Stage 14b).
  Do NOT conflate `gateType` with the findings-file infixes `design-gate` /
  `task-batch-gate`, nor with the `## Dismissals` `source` labels (Stage 12b
  `source` is `design-gate`; Stage 14b `source` is `task-batch` or the finding's
  `Spec` filename — `task-batch-gate` is only the findings-file infix, never a
  `source` label).
- Initial value: `0` at the start of each gate loop.
- **Not disk-derived, not persisted, not the `round` number.** On resume it
  restarts at `0` by design — a fresh automated budget. This is deliberately
  distinct from the disk-derived, monotonic, never-reset `round` managed under
  *Round-number management* (per `skill-idempotency.md`: fail toward re-showing,
  never toward silently hiding). A resumed session that computes disk `round` 5
  still gets two fresh automated rounds; `round` numbering is unaffected.
- Mutation: incremented by exactly 1 each time an automated fix-everything round
  is applied.

**`promptLatched` (latch).** A boolean, same scope key `(gateType,
artefactSlug)`, session only, initial `false`. Set `true` the first time **any**
prompt path is entered — including the Stage 14b all-design-upstream early exit
that prompts while `autoFixRounds < 2`. Once latched it stays latched for the
remainder of the gate loop, so the automated budget never refills mid-loop. Not
persisted; restarts at `false` on resume alongside `autoFixRounds`.

**Full-ladder re-entry is a new gate loop.** When the Stage 14b full ladder
re-enters the Stage 12b design gate (step 3) and later re-runs the Stage 14b
batch gate on the regenerated set (step 7), each re-entry is a *new* gate loop
for budget purposes: both `autoFixRounds` and `promptLatched` reset to `0` /
`false` at the start of the re-entered loop, exactly as they initialise at the
start of any gate loop — even though the scope key `(gateType, artefactSlug)`
matches the loop that ran earlier this session. This mirrors the resume
restart-at-`0` philosophy (fail toward re-showing). The engineer has already
made the deliberate, cost-warned fix-everything choice to enter the ladder; the
budget is per-gate-loop, so a re-entered loop starting fresh is coherent — its
two automated rounds still converge, and if findings persist the gate-level
choice re-engages within that loop.

**The FINDINGS decision (per round).** Input: `(outcome = FINDINGS, gateType,
autoFixRounds, promptLatched, survivingFindings)` after the session skip set has
been re-applied. Evaluate in this order:

- **Always first.** Commit this round's findings file per *Per-round commit*
  (unchanged); re-apply the session skip set (unchanged). This step never moves,
  even for an unattended automated round.
- **Stage 14b all-design-upstream early exit.** If `gateType = "task"` AND every
  surviving finding is design-upstream AND NOT `promptLatched`: set
  `promptLatched = true`, then **exit the automated path early → prompt path**
  (with the full-ladder cost warning). Design-upstream findings are never
  auto-run through the full ladder. This early exit fires regardless of
  `autoFixRounds`, and latching here spends the budget for the rest of the loop
  even though `autoFixRounds` was not incremented.
- **Automated path.** Else if `autoFixRounds < 2 AND NOT promptLatched`: voice a
  one-line status (round *N* findings summary + "auto-fixing, round *N+1*
  starting"); apply **fix-everything** per the existing per-finding routing (at
  Stage 14b, defer any design-upstream findings as persisted and auto-spec-patch
  the spec-local findings; at Stage 12b, revise the design directly — no cost
  warning applies, no specs exist); `autoFixRounds += 1`; re-run the gate as a
  fresh round.
- **Prompt path.** Else (`autoFixRounds >= 2` OR `promptLatched`): present the
  compact findings table **plus a limit-reached preamble** stating that the
  two-round automated fix limit was reached and these findings survived two fix
  passes; set `promptLatched = true`; offer the gate-level choice — at minimum
  **fix-everything** (another round) versus **move to the next stage**
  (equivalent to today's *skip*: the gate clears, the findings are already
  committed, nothing further is actioned) — with **only-highs / only-lows** and
  the per-finding disposition protocol still available. If fix-everything is
  chosen, subsequent rounds keep prompting (the budget is spent and does not
  refill mid-loop).

**Failure handling in an automated round (never converts to a clean clear).**

- **Fix-application failure.** If applying fix-everything fails terminally in an
  automated round (a writer / spec-patch re-dispatch errors), the existing rule
  applies unchanged: surface the failure and halt the Fix cycle — do **not**
  silently re-run the gate, auto-clear, or advance. An automated round never
  converts a fix failure into a clean clear.
- **Per-round commit / findings-file write failure.** Because an automated round
  has no engineer watching, if the findings-file write or the `git commit` fails
  in an automated round, surface the failure and halt **before any fix
  mutation** — do not proceed to fix-everything or advance the gate. The
  audit-trail-before-fix invariant is never skipped just because the round is
  unattended.

**Invariants preserved across automated rounds.**

- Skip and Dismiss are never taken automatically — both are engineer actions, so
  automated rounds never add to the session skip set and never write
  `## Dismissals`.
- Every qualifying round writes and commits its findings file, and the commit
  happens **before** any fix mutation for that round (an interruption between
  commit and fix must leave the committed findings file intact and the fix
  unapplied).
- `HALT` stays terminal; `PASS` (empty notices) clears silently;
  `PASS`-with-notices / `ZERO_FINDINGS_WARNING` / `NOTICES_ONLY` keep their
  confirm-to-proceed prompts.
- `persisted-from-round-N` annotations survive automated rounds, so the eventual
  prompt shows what refused to converge.

## Stage 12b — Design gate loop

Before presenting the document to the engineer for sign-off, run the design
gate. The gate is executed by the `review-gate.js` Workflow script: you —
SKILL.md — perform the pre-invocation steps, invoke `Workflow`, and
disposition its compact result. You do not dispatch check agents yourself;
the script fans them out outside the main context and returns only an
aggregated result.

`scriptPath` for this gate is `.claude/skills/zego-write-design-doc-max/workflows/review-gate.js`.

### Pre-invocation steps (run in this exact order)

**Step 0 — scriptPath readability guard (fail-fast).** Before any other work,
confirm `scriptPath` is readable with a quick `Read` of
`.claude/skills/zego-write-design-doc-max/workflows/review-gate.js`. If it cannot be read, surface
`review-gate.js not found at .claude/skills/zego-write-design-doc-max/workflows/review-gate.js`
to the engineer and halt the stage **without invoking `Workflow`** and before
any other assembly work. A missing script and a wholesale `Workflow` error
halt identically (surface, no inline fallback); this guard only sharpens the
surfaced reason. Do not advance to Stage 13.

**Step 1 — Section-presence guard (hard-fail without invoking).** Confirm the
design document is non-empty and contains all required structural sections.
This is the old reviewer-playbook Step 1, now SKILL.md's responsibility because
the script has no filesystem access. The required sections for the **design
gate** are (the `## Summary` human-first skim section is checked here in addition
to the seven — it is distinct from them, so never treat one of the seven as
satisfying the `## Summary` check, and never treat `## Summary` as satisfying one
of the seven-section checks):

- `## Summary`
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

**Step 3 — Assemble `codebaseFilePaths` and the context pack (ONCE per
session).** On the first gate entry of the session, assemble
`codebaseFilePaths` from `## Components affected` using the existing
context-assembly algorithm (existing components read by path; new components →
parent-directory listing + relevant adjacent files). Empty array if the design
names no codebase components. **Filter the assembled list to readable paths
only:** any referenced path you cannot read (a renamed file, or a `new
(created)` component whose path does not exist yet) is dropped from
`codebaseFilePaths` and noted to the engineer
(`[codebase path <path> unreadable — omitted from review]`), NEVER passed in
the args. Do NOT halt the stage on an unreadable codebase path — it is
dropped-and-noted, unlike the step 0 scriptPath guard and the step 1
section-presence guard, which hard-fail.

**Then build the codebase context pack.** If the filtered list is non-empty,
dispatch ONE haiku sub-agent via the Agent tool with this brief: read each of
the listed files in full and write a single context pack to
`.tmp/{TICKET}-context-pack.md` — one `## {path}` heading per file followed by
that file's full content — then return the pack path. Pass `contextPackPath` =
`.tmp/{TICKET}-context-pack.md` in the gate args. If the list is empty or the
pack agent fails, pass `contextPackPath: null` — the script's codebase checks
fall back to reading the per-file list, so a missing pack degrades, never
blocks. The pack means each codebase-context check reads ONE file instead of N,
and the N files are read once per session instead of once per check per round.

**Cache and reuse.** `codebaseFilePaths`, the context pack, and the
`steeringIndex` from Step 3b are session-cached: every later gate entry (a
Stage 12b re-run or the Stage 14b batch gate) reuses them without
reassembling. Rebuild all three only after a full-ladder design revision
(`## Components affected` may have changed) or on the steering-index degrade
trigger.

**Step 3b — Build `steeringIndex` and run the completeness cross-check (ONCE
per session).** Assemble `steeringIndex` as a preformatted Markdown index
string so the steering-context checks can read the full text only of
plausibly-relevant docs instead of the whole bundle. Follow the procedure in
*Building the steering index* below. The output is either the index string or
`null` (the read-all degrade trigger). Session-cached per Step 3's *Cache and
reuse* rule.

**Step 4 — Assemble and pass all eleven args (Interface contract #1).** Compute
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
- `contextPackPath`: the pack path from Step 3, or `null` (per-file fallback)

### Invoke the Workflow

Invoke the gate via `Workflow({ scriptPath })` pointing at
`.claude/skills/zego-write-design-doc-max/workflows/review-gate.js` (step 0 has already confirmed
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
  orchestrator's skip set). Then apply the **FINDINGS decision** per *The
  two-round automated budget* above (`gateType = "design"` here, so the Stage 14b
  all-design-upstream early exit never applies at this gate):

  **Automated path** (`autoFixRounds < 2` AND NOT `promptLatched`). Do not
  present the table and do not prompt. Voice a one-line status (round *N*
  findings summary + "auto-fixing, round *N+1* starting"), then apply
  **fix-everything**: at this gate no specs exist and every finding is
  effectively design-upstream, so fix-everything routes each finding to **Fix —
  full ladder** — an in-place design revision (see below); **no cost warning
  applies** (no specs to regenerate) and **no Skip or Dismiss is taken
  automatically**. Increment `autoFixRounds` and re-run the gate as a fresh
  round. A terminal writer re-dispatch failure, or a findings-file write /
  `git commit` failure, halts per *The two-round automated budget* (never an
  auto-clear).

  **Prompt path** (`autoFixRounds >= 2` OR `promptLatched`). Set
  `promptLatched = true`. Present ALL surviving findings to the engineer at once
  **as a compact table** — one row per finding: severity, one-line issue, its
  `new` / `persisted-from-round-N` annotation, and the recommended disposition —
  pointing at `findingsPath` for the full six-field detail, prefaced by a
  **limit-reached preamble** stating the two-round automated fix limit was
  reached and these findings survived two fix passes. Do NOT reproduce the full
  finding blocks inline; the committed findings file is the durable record and
  re-voicing it in full recharges the orchestrator context every round. Surface
  `notices` alongside and `stats` as a one-line footer (checks run/failed,
  per-severity counts). Then offer the **gate-level choice** over the whole set
  per **gate-level escape** above — at minimum **fix-everything** versus **move
  to the next stage** (equivalent to *skip*), with **only-highs / only-lows** and
  per-finding disposition still available — using `Severity` as the triage axis.
  The engineer is never required to disposition every finding to make progress,
  partial responses are accepted, and the loop is not unlimited: only
  fix-everything re-runs the gate (and once prompting, subsequent rounds keep
  prompting); move-to-next-stage / only-highs / only-lows each clear it.

  The per-finding routing referenced by both paths:

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
    in **revision mode**. Do NOT write a synthesis file — re-emitting the full
    design as a temp file costs ~12k+ output tokens per revision and parks the
    whole payload in the orchestrator transcript permanently. Instead pass
    `design_path` = `docs/design/{TICKET}-{slug}.md` (the committed design on
    disk) and `revision_directives` = a compact block listing each directed
    change (target section + the change, sourced from the dispositioned
    findings' suggested resolutions and the engineer's direction). The writer
    reads the design itself and rewrites it in place. A brief-seeded design
    keeps its `## Inputs / prior-planning references` section automatically:
    revision mode preserves every section a directive does not target, so the
    brief-derived Inputs survive the revision without any synthesis carry.

    **If the writer re-dispatch fails, surface the failure and halt the Fix
    cycle — do not invoke the next round, as there is no revised artefact to
    review.** On success, re-run the deterministic header verification
    (Stage 12), then — without committing the revision separately — invoke a
    fresh full-sweep round with `round + 1` and `priorFindingsPath` set to
    this round's `findingsPath`; the revised design is committed atomically
    with that round's findings by the *Per-round commit*.
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
now always writes one, even when all-empty), commit the design document AND the
findings file together immediately — before any engineer-facing disposition,
voicing, or clear:

```bash
git add docs/design/{TICKET}-{slug}.md docs/ai/reviews/{TICKET}-*-gate-*.md && git commit -m "{TICKET}: design + design-gate findings round {round}"
```

Interpolate `{TICKET}`, `{slug}`, and `{round}` to the actual values. The
`docs/ai/reviews/` path prefix is load-bearing — a bare `{TICKET}-*-gate-*.md`
glob from the repo root matches nothing — and the `-m` flag keeps the commit
non-interactive. Pairing the design with its findings makes each round commit
an atomic snapshot of exactly what was reviewed: round 1 carries the initial
design, and each full-ladder revision rides into the round that re-reviewed
it. Adding an unchanged design is a no-op, and the commit can never be empty
because every qualifying round writes a new findings file. Committing the
round-1 `ZERO_FINDINGS_WARNING` file is the audit-trail guarantee: a gate that
clears via skip still leaves its findings commit in `git log`. Do NOT defer to
Stage 15, so the audit trail survives a session interrupted mid-gate.

Once the gate is cleared, present the design document to the engineer for sign-off:

> Design Document written to `docs/design/{TICKET}-{slug}.md`.
>
> Please review it. Say "looks good", "sign off", "approved", "ship it", or
> "looks good — proceed to Phase 2" to proceed to task spec generation.
> Or tell me what to change.

---

## Stage 13 — Sign-off gate

**Sign-off is only reachable once the design gate has cleared.**

**Present the decision ledger before waiting for sign-off.** This is the single
Phase 1 stop, so every decision Stages 2–11 made autonomously is surfaced here for
the engineer to review in one place. The persisted **`## Auto-decision ledger`**
section of the design document is the source of truth for this presentation — the
same section the engineer reviews before sign-off and that remains in the committed
document afterwards, not an in-context-only accumulation. Present the full ledger
from it:

> Before sign-off, here are the decisions I made autonomously during Phase 1:
>
> {For each ledger entry: what was decided, the basis (inferred-from-input /
> inferred-from-codebase / sub-agent-investigated), and the rejected options.}
>
> {The coverage-classification net-new notes, the Stage 11 revisit assessment,
> and any open item — a genuinely blocking gap with no defensible inferred or
> investigated answer — called out explicitly for you to resolve.}

**Surface any unresolved/exploring-brief resolution prominently**, at the top of
the ledger: the settled approach the investigation sub-agent selected, its
alternatives, and any recorded dissent — so the engineer can overturn it before
sign-off. The design records a settled approach and never carries an open
question; the ledger is where the engineer sees the choice that was made. This is a
*settled* choice the engineer may overturn — it is **distinct** from the unresolved
open items surfaced next.

**Surface any unresolved open items distinctly and prominently.** These are the
open-item-class ledger rows (genuinely blocking gaps the AI could neither infer nor
investigate) that are still unresolved — distinct from the settled resolution above.
Present them under a clearly-labelled **"Unresolved open items"** heading, one per
line, each naming the stage the gap arose at and what is unresolved:

> **Unresolved open items** (informational — signing off accepts these as-is):
>
> {For each open-item-class row still unresolved: the stage it arose at (e.g.
> Stage 3 Components) and exactly what could not be resolved.}
>
> These are informational only. Signing off accepts them as-is and I will proceed
> to Phase 2 immediately; to resolve one instead, tell me the answer and I will fold
> it into the design.

This surface is **purely informational and never blocks sign-off** — it does not add
a rejection condition (the sign-off conditions below are unchanged). If there are no
unresolved open items, render nothing here (or state "no unresolved open items") — do
not emit empty scaffolding.

Accepted phrases: "looks good", "sign off", "approved", "ship it",
"looks good — proceed to Phase 2". Do not treat bare "yes" as sign-off.

**If the document is missing any section** (`## Summary`, Approach, Components
affected, Interface contracts, Task breakdown, Test strategy, Risks and
constraints, ADR references): do not accept sign-off — list the missing
sections. `## Summary` is the human-first skim section, checked in addition to
the seven Artefact 2a sections — distinct from them, never treated as one of the
seven and never satisfied by one of the seven.

**If task breakdown has zero tasks at sign-off time**: do not accept sign-off.

**If the engineer requests changes**: return to the originating stage, update,
pass through Stage 11, re-write via Stage 12, re-run the design gate in Stage
12b, then return here. Inside this loop-back, **re-mark the affected decision
ledger row(s) `engineer-directed`** — this is the only path that ever sets that
attribution. The re-mark flows through the design-writer sub-agent authoring at
Stage 12 and the orchestrator's `## Auto-decision ledger` refresh (do **not**
mechanically copy the default skill's inline mechanism):

- **Override** — the engineer changes an existing AI decision: move the superseded
  AI decision (its original *what was decided* value + basis) into that row's
  *rejected options*, adopt the engineer's directive as the new *what was decided*
  value, and set the row's attribution to `engineer-directed`.
- **Open-item resolution** — the engineer answers an open item (a genuinely blocking
  gap the AI left open): the answer is now the decision, so the row **leaves the
  open-item class** and is marked `engineer-directed`. This is not just a status
  flip — because an open item is a real gap in the design content, fold the answer
  into the affected sections at the originating stage (e.g. a resolved "target
  service = X, framework = Y" updates Approach / Components / Interface), then
  re-write via Stage 12. Update the design content *and* the ledger row together.
- **Cascade** — if an intervention forces genuinely-consequential downstream changes,
  re-mark each changed downstream row `engineer-directed` too. Rows merely
  re-confirmed unchanged stay `AI-made` (no marking).

**Once valid sign-off is received**: continue immediately to Phase 2.

---

# Phase 2 — Autonomous Task Spec Generation

Phase 2 begins immediately after sign-off. No questions to the engineer. No
pauses between tasks.

---

## Stage 14 — Generate task specs

**Commit any uncommitted design changes before writing any task spec.** The
design document was committed with each design-gate round (the Stage 12b
per-round paired commit), so this commit only captures disposition-time edits
made after the last round's commit — chiefly `## Dismissals` entries appended
during the design gate. Commit only if there is something to commit:

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

> Sign-off confirmed. Generating all task specs in parallel.

Do not read the confirmed Design Document in full. Extract only what this
stage needs: the `## Task breakdown` section (task names, numbers,
dependencies) and the header `Branch:` line, via `rg` / `sed -n`.

**Derive contract values for every task upfront, before any dispatch.** For
each task in the task breakdown, in order:

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

**6. Dispatch ALL tasks to `task-writer.md` in parallel:**

Read `.claude/skills/zego-write-design-doc-max/task-writer.md` in full ONCE. Then
dispatch one Agent call per task, all in a single batch of parallel tool calls.
The writers are independent — each reads the design from disk and writes a
distinct `OUTPUT_PATH`, nothing is shared — so there is no reason to serialise
them. Each dispatch: sub-agent file content as prompt; the following named
fields in the user message: `TICKET`, `TASK_NUMBER`, `TASK_NAME`,
`TASK_DEPENDENCIES`, `OUTPUT_PATH` (the derived file path), `BRANCH` (the
derived branch value), `DESIGN_PATH` (the committed design document path
`docs/design/{TICKET}-{slug}.md`; the writer reads the design from it). The
design is on disk and in history via the Stage 12b per-round paired commits, so
passing its path keeps the N parallel dispatches from recharging the full
design text as cache-read on every orchestrator turn. The small fields stay
inline.

**If `task-writer.md` fails for any task:**

- Preserve every spec the other writers produced.
- Surface the failing task number(s) to the engineer.
- Retry only the failed task(s), again in parallel — do not regenerate
  successful siblings.

**Step 6b — Verify and correct contract fields (scripted):**

After all writers return, before the Stage 14b batch gate, deterministically
reconcile each spec's two contract fields against the values you dispatched.
The dispatched `BRANCH` (canonical for `branch:`, computed in step 4) and
`TASK_DEPENDENCIES` (canonical for `Depends on:`, computed in step 5) are the
only source of truth — never the design document's `Branch:` line. For each
spec, run:

```bash
python3 .claude/skills/zego-write-design-doc-max/scripts/verify-task-contract.py "{OUTPUT_PATH}" "{BRANCH}" "{TASK_DEPENDENCIES}"
```

The script implements the step 6b semantics deterministically: region-scoped
location and uniqueness (frontmatter for `branch:`, body header for
`Depends on:`), trimmed comparison (a whitespace-only difference is not
drift), in-place single-line correction, and a post-condition assertion. It
never re-dispatches and never asks the engineer anything — Phase 2 autonomy is
preserved, and no spec content enters the orchestrator context for this step.

Output handling:

- `OK` — no drift; nothing to record.
- One or more correction notes (`{spec filename}: {field} corrected from
  '<got>' to '<expected>'`) — accumulate for the Stage 16 report,
  de-duplicated by `{spec filename, field}`.
- `HALT: <reason>` (exit 2) — surface the message verbatim and stop. Halts are
  reserved for structural failures (missing file, malformed frontmatter or
  body-header region, absent / duplicate / empty field line, failed write or
  post-condition), each with its own distinct message.

When the script exits 0 for every spec, every spec on disk is guaranteed
conforming: trimmed `branch:` equals `BRANCH` and trimmed `Depends on:` equals
`TASK_DEPENDENCIES`.

**Step 6c — Reconcile the optional `feature-id:` frontmatter key.** Best-effort
and advisory (AIDEV-188 / ADR 020): never a hard gate, never halts, never
re-dispatches. The task spec frontmatter carries `ticket:` and `branch:` plus an
OPTIONAL `feature-id:` third key — recover the identifier from the committed
design document's `Feature-Id:` header and ensure the spec's frontmatter carries
it:

```bash
FEATURE_ID="$(.claude/scripts/feature-id.sh recover docs/design/{TICKET}-{slug}.md 2>/dev/null || true)"
```

- When recover yields a non-empty value and the spec's frontmatter has no
  `feature-id:` key, write `feature-id: {FEATURE_ID}` into the leading YAML
  frontmatter block (alongside `ticket:` and `branch:`).
- When recover yields a non-empty value and the key is already present, leave it
  as the recovered value (correct any drift, same style as the contract-field
  reconciliation).
- When recover yields nothing, OMIT the `feature-id:` key entirely — do not write
  an empty value.
- Never STRIP an existing `feature-id:` key from a spec being re-written.

Any failure here warns and proceeds — a missing or unrecovered Feature-Id never
blocks task-spec generation.

**7. Run the batch reviewer gate (Stage 14b) ONCE over the full spec set.**

## Stage 14b — Batch reviewer gate

After ALL task specs are written and contract-verified (step 6b), run this gate
ONCE over the full spec set. The gate is executed by the `review-gate.js`
Workflow script: you — SKILL.md — perform the pre-invocation steps, invoke
`Workflow`, and disposition its compact result. You do not dispatch check
agents yourself; the script fans them out outside the main context and returns
only an aggregated result. Each check dimension sees every spec at once, which
is what grounds severity relative to the whole batch and makes the cross-spec
dimensions (ownership overlap, dependency and interface consistency, set-level
completeness) possible. There is no separate sync-check stage — those checks
run inside this gate.

`scriptPath` for this gate is `.claude/skills/zego-write-design-doc-max/workflows/review-gate.js`.

### Pre-invocation steps (run in this exact order)

**Step 0 — scriptPath readability guard (fail-fast).** Before any other work,
confirm `scriptPath` is readable with a quick `Read` of
`.claude/skills/zego-write-design-doc-max/workflows/review-gate.js`. If it cannot be read, surface
`review-gate.js not found at .claude/skills/zego-write-design-doc-max/workflows/review-gate.js`
to the engineer and halt the stage **without invoking `Workflow`** and before
any other assembly work. A missing script and a wholesale `Workflow` error halt
identically (surface, no inline fallback); this guard only sharpens the
surfaced reason. Do not advance past Stage 14b.

**Step 1 — Section-presence guard (hard-fail without invoking).** Confirm
EVERY task spec in the batch is non-empty and contains all required structural
sections (a quick `rg -c` per spec is sufficient — do not read the specs into
context). This is the old reviewer-playbook Step 1, now SKILL.md's
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

If any task spec is empty or missing a required section, hard-fail the stage
**without invoking `Workflow`**, surfacing
`HALT: Task spec {filename} is empty or malformed — verification cannot proceed`
(naming every offending spec) to the engineer. Do not advance past Stage 14b.

**Step 2 — `requirementsText` (inline full text).** Pass the inline full text
of the requirements source already resolved in the input-handling chain — the
`completeness` dimension traces FRs and ACs through to the spec set. If no
source can be resolved, pass `requirementsText: null`; the check notes
requirements traceability as unverified and runs its design-coverage checks
only. Write no file.

**Step 3 — Reuse the session-cached gate context.** Reuse the
`codebaseFilePaths`, context pack, and `steeringIndex` built at the Stage 12b
first gate entry (Step 3 / 3b there — see *Cache and reuse*). Rebuild only
after a full-ladder design revision (`## Components affected` may have
changed) or on the steering-index degrade trigger; the rebuild follows the
Stage 12b Step 3 / 3b procedures identically, including the
tolerate-and-note handling of unreadable codebase paths.

**Step 4 — Assemble and pass all eleven args (Interface contract #1).** Compute
`round` from disk (see round-number management below), then assemble:

- `gateType`: `"task"`
- `artefactPath`: the ARRAY of all task-spec paths in the batch, in task order
  (`["docs/tasks/{TICKET}-TASK-01-{slug}.md", …]`)
- `designPath`: the design document `docs/design/{TICKET}-{slug}.md` (NOT a
  task spec — the task-gate checks and the aggregation agent need `## Dismissals`
  from the design doc)
- `requirementsText`: the inline full text from Step 2, or `null`
- `codebaseFilePaths`: the session-cached filtered array from Step 3
- `ticket`: the JIRA key
- `artefactSlug`: `"task-batch"` — one gate file series for the whole set
- `round`: 1-based, monotonic per `(gateType, artefactSlug)` — disk-derived
- `priorFindingsPath`: `null` on the first round for this `artefactSlug`;
  otherwise the previous round's findings-file path
- `steeringIndex`: the session-cached Markdown index string, or `null` (the
  read-all degrade trigger)
- `contextPackPath`: the session-cached pack path, or `null` (per-file
  fallback)

### Invoke the Workflow

Invoke the gate via `Workflow({ scriptPath })` pointing at
`.claude/skills/zego-write-design-doc-max/workflows/review-gate.js` (step 0 has already confirmed
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
`docs/ai/reviews/{TICKET}-task-batch-gate-*.md`,
parse the three-digit `NNN` round suffix from each matching filename, and use
`max + 1` (or `1` if no files match). Disk-derivation is load-bearing because
the round number IS the filename suffix; a working-memory counter would reset
on a fresh-session HALT retry and a new round-1 write would overwrite a
committed findings file from the earlier session. **Never reset on re-entry:** a
regenerated-and-re-reviewed spec set or an engineer-initiated HALT retry the
next day in a fresh session resumes from the next unused round automatically,
because the disk-derived `max` is the authoritative high-water mark. The counter
advances implicitly when a round produces a written findings file (`FINDINGS` /
`PASS`) — the file's existence shifts `max`. A `HALT` is terminal to the
automated loop (no auto-retry). A "HALT retry" is the **engineer** re-running
the stage after fixing the cause `haltReason` names; because that round wrote no
file, the round slot is still empty on disk, so the disk-derived computation
produces the **same** `round` and the **same** `priorFindingsPath` for the
re-run, keeping the numbered trail gap-free — identically whether the engineer
re-runs in the same session or a fresh one.

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
  gate and proceed to Stage 15 (no prompt, no disposition protocol run, no
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
  Stage 15. Do not record in `## Dismissals` — this is not a finding.
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
  orchestrator's skip set). Then apply the **FINDINGS decision** per *The
  two-round automated budget* above (`gateType = "task"` here):

  **Stage 14b all-design-upstream early exit.** If every surviving finding is
  design-upstream AND NOT `promptLatched`: set `promptLatched = true` and go
  straight to the **prompt path** below, with the full-ladder cost warning — a
  full ladder is never run unattended. This early exit fires regardless of
  `autoFixRounds` (it can fire while `autoFixRounds < 2`), and latching here
  spends the automated budget for the rest of the loop.

  **Automated path** (`autoFixRounds < 2` AND NOT `promptLatched`, and at least
  one surviving finding is spec-local). Do not present the table and do not
  prompt. Voice a one-line status (round *N* findings summary + "auto-fixing,
  round *N+1* starting"), then apply **fix-everything** per the per-finding
  routing below with two automation constraints: **defer** every design-upstream
  finding — carry it forward as a `persisted-from-round-N` finding rather than
  running the full ladder (so a mixed round auto-spec-patches the spec-local
  findings and persists the design-upstream ones, and never runs the full
  ladder unattended) — and take **no Skip or Dismiss automatically**. Increment
  `autoFixRounds` and re-run the gate as a fresh round. A terminal writer /
  spec-patch re-dispatch failure, or a findings-file write / `git commit`
  failure, halts per *The two-round automated budget* (never an auto-clear).

  **Prompt path** (`autoFixRounds >= 2` OR `promptLatched`, including the
  all-design-upstream early exit). Set `promptLatched = true`. Present ALL
  surviving findings to the engineer at once **as a compact table** — one row per
  finding: severity, affected spec (the finding's `Spec` field, or `cross-spec`),
  one-line issue, its `new` / `persisted-from-round-N` annotation, and the
  recommended disposition — pointing at `findingsPath` for the full six-field
  detail, prefaced by a **limit-reached preamble** stating the two-round
  automated fix limit was reached and these findings survived two fix passes
  (on the all-design-upstream early exit, the preamble instead states that a
  full ladder must not be run unattended and carries the cost warning). Do NOT
  reproduce the full finding blocks inline; the committed findings file is the
  durable record and re-voicing it in full recharges the orchestrator context
  every round. Surface `notices` alongside and `stats` as a one-line footer
  (checks run/failed, per-severity counts). Then offer the **gate-level choice**
  over the whole set per **gate-level escape** above — at minimum
  **fix-everything** versus **move to the next stage** (equivalent to *skip*),
  with **only-highs / only-lows** and per-finding disposition still available —
  using `Severity` as the triage axis, computing and voicing a recommended
  per-finding disposition for each finding within any "fix" choice. The engineer
  is never required to disposition every finding to make progress, partial
  responses are accepted, and the loop is not unlimited: only fix-everything
  re-runs the gate (and once prompting, subsequent rounds keep prompting);
  move-to-next-stage / only-highs / only-lows each clear it and proceed to Stage
  15.

  The per-finding routing referenced by both paths:

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
  it regenerates all N specs and re-runs the batch gate, and spec-patch is
  offered as the alternative. Then:
  1. Engineer directs revision.
  2. Re-dispatch to `design-writer.md` in **revision mode**: pass
     `design_path` = `docs/design/{TICKET}-{slug}.md` and
     `revision_directives` = a compact block listing each directed change
     (target section + the change, from step 1's engineer direction and the
     dispositioned findings' suggested resolutions). Do NOT write a synthesis
     file — re-emitting the full design costs ~12k+ output tokens per revision
     and parks the payload in the orchestrator transcript permanently; the
     committed design is already on disk for the writer to read.
     **If the writer re-dispatch fails, surface the failure and halt the Fix
     cycle — do not invoke the next round, as there is no revised artefact to
     review.**
  3. Re-run Stage 12b design gate (full gate loop, not abbreviated). The
     revised design is committed by that gate's per-round paired commits — no
     separate design commit in this ladder. Re-run the deterministic header
     verification (Stage 12) on the revised design, and rebuild the
     session-cached gate context (`codebaseFilePaths`, context pack,
     `steeringIndex`) — `## Components affected` may have changed.
  4. Once the design gate clears, commit any disposition-time design edits not
     yet in history (chiefly `## Dismissals` entries appended after the last
     round's paired commit), only if there is something to commit:
     ```bash
     if ! git diff --quiet HEAD -- docs/design/{TICKET}-{slug}.md; then
       git add docs/design/{TICKET}-{slug}.md
       git commit -m "{TICKET}: Record design-gate dismissals"
     fi
     ```
  5. Delete all existing task specs for this ticket before regenerating, so
     slug-collision logic does not produce stale `-v2` files:
     ```bash
     git rm --cached docs/tasks/{TICKET}-TASK-*.md 2>/dev/null || true
     rm -f docs/tasks/{TICKET}-TASK-*.md
     ```
     Specs already in history via earlier per-round paired commits have their
     deletions staged by the `git rm --cached`; those staged deletions ride
     into the next per-round paired commit, so stale specs never linger in
     history past the next round.
  6. Regenerate ALL task specs from scratch (Stage 14 batch flow: derive all
     contract values, dispatch all writers in parallel, scripted step 6b).
  7. Re-run the Stage 14b batch gate ONCE on the regenerated set — do not
     re-use prior review results.

  **Fix — spec patch** (spec-local finding at any severity, including High or
  Critical). A finding's affected spec is its `Spec` field:
  1. Patch each affected task spec only — when several findings target
     different specs, patch them in parallel (one dispatch per spec). Do NOT
     touch, regenerate, or rewrite an unaffected sibling spec. **If a writer
     re-dispatch fails, surface the failure and halt the Fix cycle — do not
     invoke the next round, as there is no revised artefact to review.**
  2. Re-review with ONE fresh full-sweep batch round — `round + 1`,
     `priorFindingsPath` set to this round's `findingsPath` (re-invoke the
     gate Workflow on the whole set), not a diff. One batch round covers every
     patched spec at once; there is no per-spec re-review loop.
  3. Under **fix-everything**, repeat patch-then-batch-re-review until the
     gate clears. Convergence is guaranteed by the **two-round automated cap
     plus the always-voice rule from round 3 onward**: the first two FINDINGS
     rounds auto-fix without prompting, and from the third un-converged round
     the engineer always sees any re-surfacing finding at the prompt path and
     can elevate it to the full ladder, Skip it, Dismiss it, or move on, so the
     loop can neither silently churn nor prompt on every round. Under a scoped
     **only-highs / only-lows** escape this is relaxed to a **single patch
     pass**: apply step 1 once for the in-scope spec-local findings and then
     clear the gate — do not run the step-2 re-review and do not loop.

  **Skip**: add to the session-scoped in-memory skip set; do not record on disk.

  **Dismiss**: append to the design document's `## Dismissals` section with the
  severity label, issue summary, `source` = the finding's `Spec` filename
  (`{TICKET}-TASK-{NN}-{slug}.md`), or `task-batch` for a cross-spec finding,
  and explicit engineer acknowledgement.

  The gate clears once the engineer's gate-level choice completes: skip,
  only-highs, and only-lows clear it and proceed to Stage 15 after their
  one-shot action; fix-everything re-runs the gate until a later round clears.

**Truncated/absent compact result (recovery).** If the completion notification
carries the full compact result, use it. If it delivers only a task ID or a
truncated payload, reconstruct the deterministic findings-file path from the
args just passed (`docs/ai/reviews/{TICKET}-task-batch-gate-{round:NNN}.md`) and
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
now always writes one, even when all-empty), commit the full spec set AND the
findings file together immediately — before any engineer-facing disposition,
voicing, or clear:

```bash
git add docs/tasks/{TICKET}-TASK-*.md docs/ai/reviews/{TICKET}-*-gate-*.md && git commit -m "{TICKET}: task specs + batch-gate findings round {round}"
```

Interpolate `{TICKET}` and `{round}` to the actual values. The
`docs/ai/reviews/` path prefix is load-bearing — a bare `{TICKET}-*-gate-*.md`
glob from the repo root matches nothing — and the `-m` flag keeps the commit
non-interactive. Pairing the specs with their findings makes each round commit
an atomic snapshot of exactly what was reviewed: round 1 carries the specs as
first written (post step 6b), and each spec-patch revision rides into the
batch round that re-reviewed it. Adding unchanged specs is a no-op, and the
commit can never be empty because every qualifying round writes a new findings
file. Committing the round-1 `ZERO_FINDINGS_WARNING` file is the audit-trail
guarantee: a gate that clears via skip still leaves its findings commit in
`git log`. Do NOT defer to Stage 15, so the audit trail survives a session
interrupted mid-gate.

---

## Stage 15 — Push and create PR

Push only after the batch gate (Stage 14b) clears. The task specs are already
in history via the Stage 14b per-round paired commits; this stage only sweeps
up residue not yet committed — a scoped-escape single-pass spec patch that had
no re-review round, and `## Dismissals` entries appended to the design during
the batch gate. Commit only if there is something to commit, then clean up the
session temp files and push:

```bash
git add docs/tasks/{TICKET}-TASK-*.md docs/design/{TICKET}-{slug}.md
if ! git diff --cached --quiet; then
  git commit -m "{TICKET}: Final task spec and dismissal updates"
fi
rm -f .tmp/{TICKET}-context-pack.md
git push -u origin {branch}
```

Then invoke the `zego-create-pr` skill to open a PR for the design branch. Pass:
- `ticket`: the JIRA key
- `branch`: the design branch name
- `steering_doc_path`: the design document path
- `labels`: `ai-design`
- `review_surface`: `{label: the design document, link: docs/design/{TICKET}-{slug}.md}` — names the design document as the review surface for this phase (`docs/ai/steering/base/review-audience.md`); `zego-create-pr` renders it as one inline line within Background.

Base targeting depends on the `design_base` Stage 1 recorded:
- If `design_base` is the **requirements branch** (Stage 1 stacked on an
  *open* requirements branch), pass `base` = that requirements branch name to
  `zego-create-pr` (it accepts the optional `base` input). A PR from the
  stacked branch to the default branch would otherwise include the requirements
  commits, so the design PR would span two phases and break ADR 011's
  one-PR-per-phase property; targeting the requirements branch keeps the design
  PR's diff to design content only.
- If `design_base` is the **default branch** (Stage 1 cut from
  `origin/{default}` — the merged-requirements case, or the ordinary
  non-requirements case), do not pass `base`; the PR targets the default branch
  as before.

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
- **Phase 1 is autonomous through to sign-off.** Stages 2–11 run in sequence with
  no engineer prompt: derive each answer from the priority order (trigger inputs →
  brief/requirements → codebase reading), dispatch an investigation sub-agent via
  the Agent tool where confidence is genuinely low, record every decision to the
  decision ledger, and present the ledger at the single Stage 13 sign-off stop.
  Never fabricate a decision to avoid a stop; a genuinely blocking gap is recorded
  as an open ledger item and surfaced at Stage 13.
- **Read the codebase actively.** Use Bash and Read throughout Phase 1.
- **Gate ordering is a hard constraint.** Design gate must run before
  sign-off. Sign-off before task generation. Batch gate before push. No
  exceptions. The gates are **advisory** (ADR 014): a gate clears once the
  engineer's **gate-level choice** completes (**gate-level escape**) — skip,
  only-highs, and only-lows clear it after a one-shot action; only fix-everything
  re-runs the gate to convergence. No engineer is ever forced to disposition
  every finding to make progress, partial responses are accepted, and the loop
  is not unlimited. Running the gate and writing-and-committing its round-1
  findings file is mandatory; actioning the findings is the engineer's choice.
- **Both gates route through one disposition protocol.** Stages 12b and 14b
  reference the single **The disposition protocol** subsection for the
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
- **The approach-brief intake is asked once, on the start-fresh branch only.**
  Stage 1a runs the shared `.claude/skills/shared/approach-brief-intake.md`
  contract after resume detection; a resumed design is never re-asked the opt-in
  question; it recovers its `brief_handle` from the document (`brief` with a
  carried-forward Inputs section when a `## Inputs / prior-planning references`
  section is present, else `no-brief`). The intake is read-only, writes
  no durable state, and never hard-fails the session (a missing path is re-asked
  once then falls through to `no-brief`). It is the single source of the contract;
  never inline a second copy into this SKILL.md or `design-writer.md` (ADR 007).
- **The brief reaches the writer through the synthesis file on the initial write.**
  When `brief_handle` is a `brief`, Stage 12 writes the `## brief_handle` and
  `## brief` sections (the resolved path, source-type, and read-in-full content)
  into `.tmp/{TICKET}-design-synthesis.md` so the writer receives the brief. A
  writer that never receives the brief on the initial write is a defect. On a
  resumed brief-seeded design the brief content is gone, so Stage 12 instead
  writes a fenced `## carried_inputs` section holding the existing Inputs content,
  which the writer re-emits verbatim, preserving the section rather than dropping
  it. A Stage 12b full-ladder revision writes no synthesis file: it runs the
  writer in revision mode against the on-disk design, which preserves the
  brief-derived Inputs section (an untargeted section) without any brief carry.
- **Only Approach and Inputs are seeded from a brief.** On a `brief` handle, the
  orchestrator seeds the Stage 2 Approach (incorporate task-blocking facts with
  provenance; pointer the two ambiguous bands) and the writer emits the
  front-loaded Inputs section (references, never condenses). Every other section
  may draw on the brief; the wholesale rewrite of the brief into every section is
  forbidden.
- **The coverage classification flows through the writer and the existing gate.**
  The writer emits the affirmative coverage classification (brief / convention /
  net-new per section) and embeds each batched per-section net-new note into the
  design document it writes, so the existing `review-gate.js` Workflow (Stages
  12b, 14b, 14c) reviews them as part of that document. This is `-max`'s own path,
  not the default skill's inline orchestrator note: there is no new writer return
  channel and no `review-gate.js` change.
- **The cold path is preserved.** On `no-brief`, the writer omits the Inputs
  section entirely, `## Dismissals` and the gate flow are unchanged, and the
  design output is what it is today. The opt-in question and one-time brainstorm
  advisory ahead of it are expected, not suppressed.
- **The design never carries open questions.** An `unresolved`/`exploring` brief's
  open choice is **settled autonomously by the investigation sub-agent** (which
  researches and selects the best candidate), then seeded, with the choice made —
  plus alternatives and any recorded dissent — **surfaced prominently at Stage 13
  for the engineer to overturn**; or the engineer is redirected to
  `zego-brainstorm` and the design is not authored; a thin brief is rejected to
  the cold path.

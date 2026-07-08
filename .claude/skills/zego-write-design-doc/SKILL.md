---
name: zego-write-design-doc
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

You are the orchestrator for `zego-write-design-doc`. You conduct a two-phase
session: Phase 1 builds a Design Document autonomously — Stages 2–11 run without
an engineer prompt and the single Phase 1 stop is the Stage 13 sign-off gate;
Phase 2 generates Task Specs autonomously from the confirmed document.

You do not write task specs yourself during Phase 1. You do not ask the
engineer questions during Phase 2, and you do not ask the engineer questions
during Stages 2–11 of Phase 1 — every auto-made decision is recorded to the
decision ledger and surfaced at Stage 13.

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
  be inferred; gaps surface at Stage 13 as open-item rows in the decision ledger)
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

If the branch name starts with the ticket key (e.g. `AIDEV-29_*`), it may be
the requirements-phase branch rather than a design branch — the
`zego-write-requirements` skill creates its branch in the same
`{TICKET}_{slug}` shape. Before continuing, run requirements-branch detection.
The branch is the requirements branch when **either** signal fires:

1. **PR label signal (primary):** the branch has a PR carrying the
   `ai-requirements` label:

   ```bash
   gh pr view --json labels --jq '.labels[].name' 2>/dev/null
   ```

   The branch is the requirements branch if the output contains
   `ai-requirements`. If `gh` fails or the branch has no PR, fall through to
   the diff-content signal.

2. **Diff-content signal (fallback — covers the no-PR and `gh`-unavailable
   cases):** resolve origin's default branch (`git symbolic-ref --short
   refs/remotes/origin/HEAD`, stripping the `origin/` prefix; if that fails,
   `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`),
   then:

   ```bash
   git diff --name-only $(git merge-base HEAD origin/{default-branch})..HEAD
   ```

   The branch is the requirements branch if the output is non-empty and
   every path starts with `docs/requirements/`. An empty diff means the
   branch has no commits of its own — treat it as *not* a requirements
   branch.

If neither signal can be evaluated (for example the default branch cannot be
resolved or a git command fails), skip detection and use the
confirm-and-continue behaviour below — never block Stage 1 on detection.

### Requirements-branch base decision

Wherever a branch `B` is identified as the requirements branch (either arm
below), decide where to cut the design branch from before creating it. Design
artefacts must not land on the requirements branch (one PR per phase, ADR 011),
and the base also determines the PR target in Stage 15. `D` is origin's
resolved default branch.

1. **PR state (primary signal).** Read `B`'s PR state — for the current branch
   `gh pr view --json state --jq '.state' 2>/dev/null`; for another branch
   `gh pr view {B} --json state --jq '.state' 2>/dev/null`. The value is
   `OPEN`, `MERGED`, `CLOSED`, or empty/failure = unknowable.
2. **Git-only fallback (only when the PR state is unknowable).** Run
   `git merge-base --is-ancestor {B-tip} origin/{D}`: exit 0 means `B`'s tip is
   already an ancestor of the default branch → treat as merged; a non-zero exit
   → treat as open. This is reliable for merge-commit merges but **not** squash
   merges (a squash-merged tip is not an ancestor of the default), which is why
   the PR-state signal is primary.
3. **Decision.**
   - **`OPEN`, or unknowable-and-not-an-ancestor** → the requirements doc is not
     yet on the default branch, so stack the design branch on the requirements
     HEAD and keep `docs/requirements/` readable before the requirements PR
     merges. Cut it from `B`'s HEAD and record `design_base = {B}` (the
     requirements branch) for Stage 15:

     ```bash
     git checkout -b {design-branch} {B}
     ```

   - **`MERGED`, or unknowable-but-an-ancestor** → the requirements doc is
     already on the default branch and `B`'s tip is a stale base, so cut the
     design branch from the default branch instead. Record `design_base = {D}`
     (the default branch) for Stage 15:

     ```bash
     git checkout -b {design-branch} origin/{D}
     ```

The design branch name is `{TICKET}_{design-slug}` (a short kebab-case slug
derived from the feature name) and **must differ from `B`** — if the natural
slug collides with `B`'s slug, append `-design`.

**If detected as the requirements branch** (the current branch is `B`): do not
continue on it. First compute the proposed `{TICKET}_{design-slug}` (with the
collision/`-design` rule above) and check whether it already exists locally:

```bash
git rev-parse --verify --quiet refs/heads/{proposed-design-branch}
```

If it already exists, the current branch is already the design branch from a
prior interrupted run — Stages 2–11 run autonomously and don't commit the
design until sign-off, and the still-empty design branch carries only
`docs/requirements/` commits, which the
diff-content signal misreads as a requirements branch. Do **not** re-stack or
re-create: treat the current branch as the design branch, confirm and continue,
and record `design_base` from the base decision above (against the requirements
branch this design branch is stacked on). Only when the proposed branch does
**not** already exist do you apply the base decision above (with `B` = the
current branch), asking the engineer to confirm or adjust the name first.

Then proceed with the rest of this stage unchanged.

**If ticket-prefixed but not detected as the requirements branch:** the branch
may still be a *merged* requirements branch — after a merge-commit merge its own
commits are already on the default branch, so the diff-content signal above is
empty and detection misses it. Check whether the branch is stale:

```bash
git merge-base --is-ancestor HEAD origin/{default-branch}   # exit 0 → HEAD is an ancestor of the default
git rev-parse HEAD origin/{default-branch}                  # compare the two SHAs
```

The branch is **stale** (a merge-commit-merged requirements branch whose tip is
now a stale base) when HEAD is an ancestor of the default **and** the two SHAs
differ (HEAD is strictly behind). It is **live** when the SHAs are equal (a
fresh branch sitting at the default tip) or HEAD is not an ancestor (it has its
own commits — e.g. an in-progress design branch).

- **Live** → confirm the branch and continue. Record `design_base = {default-branch}`.
- **Stale** → do not continue design work on the stale tip. Apply the base
  decision's **merged** outcome: propose `{TICKET}_{design-slug}` (differing from
  the current branch name, `-design` on collision) and cut a fresh design branch
  from the default branch, recording `design_base = {default-branch}`:

  ```bash
  git checkout -b {design-branch} origin/{default-branch}
  ```

If the branch name does not start with the ticket key, propose a branch in
the format `{TICKET}_{description}` where description is a short kebab-case
slug derived from the feature name. Before creating it, check whether the
proposed name already exists — locally or on origin — because a run started
from the default branch can derive the same slug as an existing requirements
branch (a local ref collides loudly; a remote-only ref silently shadows a
branch cut from the default that cannot read the unmerged `docs/requirements/`
doc):

```bash
git rev-parse --verify --quiet refs/heads/{proposed}      # local
git ls-remote --exit-code --heads origin {proposed}       # remote (exit 0 = exists)
```

If it exists in either place, run the same two-signal requirements-branch
detection above against that existing branch (querying `gh pr view {proposed}`
and diffing `{proposed}` against the default branch, instead of the current
branch). If it **is** the requirements branch, apply the base decision above
(with `B` = that branch) and the collision/`-design` naming rule, and record
`design_base` accordingly. If it is **not** a requirements branch, surface the
collision to the engineer and ask them to confirm or supply a different name
rather than creating or shadowing it. If the proposed name does not exist
anywhere, create it as before and record `design_base = {default-branch}`:

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
affected sections for review. A resumed design is **not** re-asked the
approach-brief opt-in question below: it has already established its intake
handle. Also read the existing **`## Auto-decision ledger`** section back out
of the located document and recover its entries into the decision ledger, so
prior-session auto-decisions carry forward: a resumed run must **not** start
with an empty ledger and must not reach Stage 13 with prior-session decisions
unrecorded. Recover that handle from the existing document rather than assuming
one: a brief-seeded design carries a `## Inputs / prior-planning references`
section that a re-write must not silently drop. Run the check against
`{filename}` — the file the resume detection above located — never a
re-derived `docs/design/{TICKET}-{slug}.md` path: the `{slug}` is not
established until Stage 12, so a re-derived path may not resolve, and a
mismatch would make `rg -q` exit non-zero → `NO_INPUTS` → `no-brief`, silently
dropping the Inputs section this recovery exists to preserve:

```bash
rg -q "^## Inputs / prior-planning references" {filename} \
  && echo HAS_INPUTS || echo NO_INPUTS
```

If the check prints `HAS_INPUTS`, set `brief_handle = brief` so Stage 12
preserves the existing Inputs section on re-write. If it prints `NO_INPUTS`,
set `brief_handle = no-brief`. Either way, skip the intake step.

If starting fresh or no prior document exists, run the approach-brief intake
before continuing to Stage 2.

### 1a: Approach-brief intake (start-fresh branch only)

Run this step **only** on the start-fresh branch above (after resume
detection), so a resumed design never re-asks the opt-in question. The intake
is read-only and writes no durable state, so it does not interfere with the
prior-document resumability gate (`docs/ai/steering/local/skill-idempotency.md`
Rules 6, 9).

Read `.claude/skills/shared/approach-brief-intake.md` and execute it. It is
the single source of the intake contract; do not inline or paraphrase a second
copy of it here (ADR 007, `docs/decisions/007-shared-skill-documents.md`). Fill
its placeholders:

| Placeholder | Value |
|-------------|-------|
| `{ticket}` | `TICKET` from input handling |
| `{branch}` | the branch confirmed or created above |
| `{starting-fresh}` | `true` (this step runs only on the start-fresh branch) |

The intake returns one of two handles. Hold it as `brief_handle`:

- `no-brief`: the engineer declined, named a path that did not resolve after
  one re-ask, or the brief was rejected as thin. The intake has already
  surfaced the one-time brainstorm advisory. Author the design **cold**: omit
  the Inputs section entirely and leave the cold path otherwise unchanged. The
  opt-in question and one-time advisory ahead of the cold path are expected,
  not suppressed.
- `brief {path, source-type, content}`: a brief was read in full. Seed the
  Stage 2 Approach and the front-loaded Inputs section from it per the contract
  (the decisive test, seed-vs-draw-on, coverage prompt, and citation format all
  live in the shared doc). Hold the handle for Stage 2 and Stage 12.

The intake never hard-fails the session: a missing path is re-asked once then
falls through to `no-brief`. Continue to Stage 2 with `brief_handle` in scope.

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
3. **The skill's own codebase reading** — use Bash to explore directory
   structures, Read to examine existing patterns and interface signatures, and
   Bash to search for relevant files. Ground the design in what you observe; do
   not defer to the engineer for anything you can read directly.

**Where confidence is genuinely low or information is genuinely missing,** dispatch
an **investigation sub-agent via the Agent tool** (`subagent_type: general-purpose`)
with a scoped research question and pointers to the relevant inputs and codebase.
Adopt its recommended option and record the rationale and the rejected
alternatives to the decision ledger. Do **not** stop to ask the engineer.

**A genuinely blocking gap** — one with no defensible inferred or investigated
answer — is recorded as an **open item** in the decision ledger and surfaced at
Stage 13. Never fabricate a decision to avoid a stop, and never silently skip a
gap.

**The decision ledger.** Maintain a running in-context record through Stages 2–11.
For each auto-made decision, record:

- **what was decided** — the answer adopted for that stage;
- **the basis** — one of `inferred-from-input`, `inferred-from-codebase`,
  `sub-agent-investigated`, or `engineer-directed` (set only when the engineer
  intervenes on the row at Stage 13 — see below);
- **rejected options** — the alternatives considered and not taken.

The ledger also carries the coverage-prompt net-new notes, the Stage 11 revisit
assessment, and any unresolved/exploring-brief resolution (with its alternatives
and any recorded dissent). The in-context ledger accumulates across Stages 2–11 —
the design document does not yet exist during these stages — and is then persisted
**into the design document body** as a dedicated **`## Auto-decision ledger`**
section, rendered human-first: a short intro plus a `<details>`-collapsed
per-decision table. The persist happens when the document is first authored at
Stage 12, and the section is refreshed there whenever a later stage adds or changes
a decision and the document is re-written. Each entry carries a **two-state
attribution**: **`AI-made`** (with its basis) is the default — the absence of an
engineer tag means the decision was **accepted as-is at sign-off** (the Stage 13
sign-off commit is itself the acceptance record, so no per-row marking is added for
accepted decisions); a row is marked **`engineer-directed`** only where the engineer
actively intervened on it (an override or an open-item resolution at Stage 13 — see
Stage 13). So the design document carries a **durable, auditable trail** of which
decisions were auto-answered and where the engineer diverged from them — one that
survives Stage 13 sign-off and any mid-run resume, not held only in working context.
It is presented in full at Stage 13 so the engineer reviews every auto-made decision
in one place before sign-off.

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

Before beginning Stage 2, actively read the codebase to inform the design.

---

## Stage 2 — Approach

Read the codebase to understand the current state relevant to this feature.
Inspect existing patterns, affected modules, and adjacent code. Use Bash
and Read as needed.

**If `brief_handle` is a `brief` (a brief was read in Stage 1a):** the Approach
is **seeded** from the brief rather than proposed cold. Per the shared intake
contract (Steps 5–6), the brief is the authoritative starting content for this
section. Apply the decisive test per passage: a task-blocking instruction,
boundary, or contract fact (plus the load-bearing-decision escape clause) is
`incorporate-with-provenance`, written into this Approach section with a
clickable relative-link backlink to its source; everything else (settled-upstream
content and rationale) defaults to a `pointer`, a clickable reference rather than
a rewrite. Do **not** wholesale-rewrite the brief's prose into this or any other
section: draw on the brief for facts and citations only. Adopt the seeded
Approach:

> {The seeded approach: incorporated task-blocking facts inline with provenance
> backlinks; pointers for settled-upstream content and rationale.}

**If `brief_handle` is `no-brief` (cold path):** derive one candidate approach
from the priority order (trigger inputs → requirements → codebase reading),
exactly as before; the cold path is unchanged except the approach is adopted
autonomously rather than proposed to the engineer for confirmation:

> {One to three paragraphs: the implementation strategy, why this approach
> over evident alternatives, what the high-level change looks like.}

**Unresolved/exploring brief.** If the intake classified the brief as
`resolve-then-seed` (a `zego-brainstorm` artefact with `state: unresolved` or
`state: exploring`), do **not** stop to ask the engineer to settle its open
choice. Dispatch an investigation sub-agent via the Agent tool to research the
brief's candidate options (and any recorded dissent) and select the best
candidate; the sub-agent's selection becomes the seeded Approach. The design
records a **settled** approach and never carries open questions. Record the
settled choice — with its alternatives and any recorded dissent — to the decision
ledger, flagged for **prominent** presentation at Stage 13 so the engineer can
overturn it before sign-off. If the sub-agent cannot select a defensible
candidate (failure or empty return), record the open choice as an open ledger
item for Stage 13; and if the brief is too thin to author against at all, redirect
to `zego-brainstorm` and do **not** author the design.

Record the confirmed approach, its basis (inferred-from-input /
inferred-from-codebase / sub-agent-investigated), and any rejected alternatives to
the decision ledger, then continue.

**Coverage prompt (every authored section, from here on).** As each design
section is authored (this Approach and every section in Stages 3 onward),
classify its content per the shared contract (Step 7): (a) from-brief, (b)
from-convention, (c) net-new engineering judgement. Record every net-new (c)
item to the decision ledger as **one batched note per section** (never one note
per item), leading each note with the highest-value net-new content. This is an
affirmative classification, not a silence detector; the batched net-new notes are
carried in the ledger and surfaced at Stage 13, not raised as a mid-run prompt.
The coverage classification runs **only when the brief content from a fresh Stage 1a
intake is in hand**, that is, `brief_handle` is `brief` **and** a `brief`
section is present to classify. It does not run on (a) the cold path
(`brief_handle` is `no-brief`), where there is no from-brief content; nor on (b) a
resumed brief-seeded design, where the resume branch (lines 109-116) recovered
the `brief` handle from the existing Inputs section rather than the brief
itself, so the brief content is gone and there is nothing to classify. In both
cases the design is authored without coverage notes (matching the design
flowchart, which routes the cold path straight to authoring, and
`zego-write-design-doc-max`).

---

## Stage 3 — Components affected

Using the confirmed approach and your codebase reading, derive the affected
components:

> **Existing (modified):**
> - {component}: {why}
>
> **New (created):**
> - {component}: {purpose}

Record the confirmed components to the decision ledger (basis + any rejected
alternatives) and continue.

---

## Stage 4 — Interface contracts

For each new or modified interface identified in Stage 3, derive the contract:

> ### {InterfaceName}
> Input: {types, constraints}
> Output: {types, constraints}
> Errors: {explicit error types and conditions}
> Side effects: {state changes, events emitted — "none" if none}

If no new or modified interfaces exist, state that explicitly. Record the
confirmed contracts to the decision ledger and continue.

---

## Stage 5 — External references (document-type tasks only)

**Determine whether this task is document-type:** a task whose objective
produces a standards file, skill file, template, or other non-code artefact.
If document-type, run this stage. If code-only, skip to Stage 6.

Derive the reference set autonomously from the priority order: the trigger inputs
(URLs, file paths, or named external standards named in the JIRA ticket, prompt,
or brief), then the requirements-doc content, then the codebase. Do **not** ask
the engineer to paste references.

- Fetch each URL with WebFetch.
- Read each local file path with Read.
- For named concepts or well-known standards (e.g. "OpenTelemetry semantic
  conventions"), note them for the ledger — do not search without a URL.
- Where the trigger inputs plainly imply relevant documentation that is not
  named, dispatch an investigation sub-agent to locate it; adopt what it returns
  and record the basis. If no references can be derived, record that as a ledger
  note and continue.

For each reference, summarise: what it covers, what rules or conventions it
contains, and how it relates to this task. Record the reference set and its basis
to the decision ledger.

Then read all files under `docs/ai/steering/` to run conflict detection (Stage 6).

---

## Stage 6 — Conflict detection (document-type tasks only)

**Skip if this task is not document-type** (determined in Stage 5).

1. Read all existing files under `docs/ai/steering/`. Skip files already read.
2. Compare every rule or convention planned for this output against every
   existing file.
3. Identify conflicts: two rules that would give Claude contradictory
   instructions for the same situation.

**If conflicts are found**, resolve each autonomously rather than stopping to
ask. For each conflict, record to the decision ledger:
- The rule being introduced.
- The clashing rule (file path and rule text).
- What the contradiction is.
- The resolution adopted (default: defer to the existing rule — keep it and drop
  or narrow the introduced one, unless the trigger inputs or brief explicitly
  override it), expressed as a Phase 2 constraint "must not include X —
  contradicts Y in Z.md", with its basis. Where the right resolution is genuinely
  unclear, dispatch an investigation sub-agent; if it cannot resolve the conflict,
  record it as an open ledger item for Stage 13.

**If no conflicts are found**, record that and continue.

Do not produce a kept/adapted/discarded section. Surface synthesis outputs as:
- Constraints for Phase 2 task specs: "must not include X — contradicts Y"
- Acceptance criteria for Phase 2 task specs: "output must include rule for W,
  sourced from reference R"

Record these constraints and ACs; they feed Phase 2 directly.

---

## Stage 7 — Task breakdown

Derive a task breakdown from the confirmed approach and components:

> TASK-01: {name} — {dependencies or "no dependencies"}
> TASK-02: {name} — depends on TASK-01 ({specific output needed})
> ...

Size each task as a thin end-to-end vertical slice — one coherent outcome,
spanning as many components as that outcome touches — that fits inside a
single Opus-level agent's loadable working set: the task spec plus every file
the agent must read and write, with headroom left to reason. Fold trivial
edits and their tests into the slice whose agent already holds that context
rather than standing them up as their own tasks; split a task out only when
bundling it would push the working set past what one agent can hold. A slice
may still be independently implementable from a single task spec — but coarser,
outcome-shaped slices are preferred over one-deliverable-per-task fragments.

**If the breakdown you derive contains zero tasks**, add at least one task
covering the confirmed approach's single coherent outcome — the breakdown must
have at least one task, and under autonomy the orchestrator supplies it rather
than stopping to ask. Record the self-correction to the decision ledger. The
Stage 13 backstop still rejects sign-off on a zero-task breakdown if it somehow
remains empty.

Record the confirmed task breakdown to the decision ledger. Each task name and
dependency must be precise enough to generate a complete task spec in Phase 2.

---

## Stage 8 — Test strategy

Derive a test strategy:

> Integration test owner: {which task owns integration tests}
> E2E approach: {scope, tooling, environments}
> Cross-task constraints: {shared fixtures, test data, ordering}

Record the confirmed test strategy to the decision ledger and continue.

---

## Stage 9 — Risks and constraints

Derive risks and constraints from codebase reading and the design:

> - {risk or constraint}: {why it matters, what Claude must not do}
> - ...

For document-type tasks: include constraints derived from conflict detection
in Stage 6 (e.g. "must not introduce rules that overlap with docs/ai/steering/base/
logging.md rule 3").

Record the confirmed risks and constraints to the decision ledger and continue.

---

## Stage 10 — ADR references

Derive which existing ADRs (in `docs/decisions/`) constrain this design and
whether the design introduces decisions significant enough to warrant a new ADR:

```bash
ls docs/decisions/ 2>/dev/null
```

Read the relevant decisions files, determine the constraining ADRs from the
approach and codebase reading, and decide autonomously whether a new ADR is
warranted (default: none, unless the design introduces a cross-cutting
architectural decision). Record the referenced ADRs and any new-ADR decision —
with its basis and the rejected alternative (ADR vs no ADR) — to the decision
ledger; a new-ADR decision is a judgement call, so flag it for the engineer at
Stage 13.

---

## Stage 11 — Revisit gate

Before producing the Design Document, assess autonomously whether any section
needs revisiting in light of later stages (e.g. the task breakdown surfaced a
component the Approach missed, or the risks changed the test strategy). If so,
jump back to that stage, update the draft, and return here.

Do **not** ask the engineer whether to revisit: the single Phase 1 stop is the
Stage 13 sign-off gate, where the engineer reviews the whole design and the
decision ledger and can request any change then. Record the revisit assessment —
which sections were revisited and why, or "no revisit needed" — to the decision
ledger. The design is not locked until sign-off.

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

**Inputs / prior-planning references section (conditional on `brief_handle`).**
The template carries a conditional, front-loaded `## Inputs / prior-planning
references` section that sits **above** `## Approach`:

- **`brief_handle` is a `brief`:** include the section. On a fresh authoring
  pass, populate it with one entry per source the brief drew on (the brief
  itself, and any planning documents it cites), each a **clickable relative
  Markdown link** `[title](relative/path#anchor)` that **resolves on disk** at
  authoring time, plus **one line** of what that source provided. The section
  **references**, it never condenses or paraphrases the source prose, and it
  never receives incorporated content (incorporated passages land in Approach
  per Stage 2). Verify every link resolves on disk before writing; raw paths are
  not acceptable. The authoring engineer owns anchor validity beyond authoring
  time (shared contract, Step 8). On a **resume re-write** (the handle was
  recovered as `brief` from an existing `## Inputs / prior-planning references`
  section in Stage 1, with no fresh brief in hand), **preserve the existing
  section verbatim**, carrying its entries and links through to the rewritten
  document unchanged rather than regenerating or omitting them.
- **`brief_handle` is `no-brief`:** **omit the section entirely**, so the
  cold-path output is byte-for-byte identical to a design authored without a
  brief. Do not emit an empty heading or a placeholder.

**Author the human-first shape** (the template carries the full convention; the
design document is a human review surface, so lead with the skim path and push
machine-dense detail one click away):

- **`## Summary` first.** Author a `## Summary` section immediately after the
  seven-line header (strictly after line 7, never between header lines), before
  `## Approach`. It is distinct from the seven body sections — do not fold it
  into them. Cover four sub-points in order: what changed & why; the decisions
  needing judgement; the assumptions; where the risk is.
- **GitHub callouts in the `## Summary`, sparingly.** Flag the Summary's
  judgement-calls with a `> [!IMPORTANT]` callout and its risk with a
  `> [!WARNING]` callout (or `> [!CAUTION]` for a guardrail protecting a machine
  consumer). Use callouts **only** in the `## Summary`, never on every section.
  Use only the supported types NOTE/TIP/IMPORTANT/WARNING/CAUTION, with the type
  marker on its own first line of the blockquote and content on later `>` lines.
  Callouts are blockquote syntax, not raw HTML. They are illustrative-only (a
  callout must never be the sole source of a machine fact) and degrade cleanly —
  native on GitHub and in recent VS Code preview, falling back to a plain
  blockquote elsewhere (do not assume every IDE renders them).
- **`mermaid` diagrams.** Lead `## Components affected` with a `mermaid` component
  map and `## Task breakdown` with a `mermaid` dependency graph. At least one
  `mermaid` block must be present.
- **`<details>` collapsing.** Collapse machine-dense detail — the interface
  contracts and the long per-task detail — inside `<details>`/`<summary>` blocks
  so the skim path stays short. A `<details>` block wraps a section's content
  only; the `##` heading itself stays outside the block (heading visible, content
  collapsible).
- **Preserve the header and the seven sections.** The seven-line header and the
  seven `##` headings (Approach, Components affected, Interface contracts, Task
  breakdown, Test strategy, Risks and constraints, ADR references) stay verbatim
  and in order. `## Summary` is added, never substituted for any of them.
- **Illustrative-only, never load-bearing.** The `## Summary`, the `mermaid`
  diagrams, and the callouts must never be the sole source of any machine fact
  (an interface contract, a constraint, an acceptance criterion, a task
  dependency); those facts live in the seven prose/structured sections, which
  Phase 2 transcribes into task specs.
- **HTML/language discipline.** Introduce only `<details>`/`<summary>` and
  `mermaid` constructs — no other raw HTML tag. Describe behaviour and intent;
  never name a specific programming language as a required construct.

**Persist the decision ledger into the design document.** This is the stage where
the in-context ledger accumulated through Stages 2–11 becomes durable. Author (or,
on a resume re-write, refresh) the dedicated **`## Auto-decision ledger`** section
into the document body from the in-context ledger you hold — appended after the
seven body sections. Render it human-first: a short intro sentence plus a
`<details>`-collapsed per-decision table whose rows carry *what was decided*, *the
basis* (`inferred-from-input` / `inferred-from-codebase` / `sub-agent-investigated`),
*rejected options*, and the **two-state attribution** — **`AI-made`** (default; the
absence of an engineer tag means accepted-as-is at sign-off) versus
**`engineer-directed`** (an engineer intervention) — plus the carried items (the
coverage-prompt net-new notes, the Stage 11 revisit assessment, and any
unresolved/exploring-brief resolution with its alternatives and dissent). This gives
the committed design a durable, auditable trail that survives Stage 13 sign-off and
any mid-run resume. Whenever a later stage adds or changes a decision and the
document is re-written before sign-off, refresh this section from the updated
in-context ledger so it never falls behind. When a Stage 13 change-request loop-back
re-marks a row `engineer-directed` (an override or an open-item resolution), this
same persist/refresh path re-writes the section, so the committed document carries
the final attribution. Stage 13 reads this persisted section back as the source of
truth for the sign-off presentation.

**Render any open-item rows as their distinct row class** (see *The decision ledger*
above): the `#` column is a dash (`—`), not a sequence number; the Stage column reads
`arose Stage N {name} · surfaced Stage 13` (where the gap arose, plus the surfaced-at
stage); and the status is `Open — needs engineer`. A resolved open item is instead
rendered as its `engineer-directed` decision row within the numbered sequence.

**The document MUST begin with exactly this canonical seven-line header block, in
this order, with these labels verbatim:**

```
# Design: {feature_name}
JIRA: {TICKET}
Engineer: {engineer}
Requirements: {requirements_source_path}
Date: {date}
Branch: {branch-name}
Feature-Id: {feature-id}
```

The labels and their order are MANDATORY and must NOT be paraphrased or
reordered. In particular, **line 2 is `JIRA:`** (never `Ticket:` or any synonym)
and it carries the ticket key alone with no trailing content, so it matches the
`zego-review` skill's exact-match design-doc discovery grep `^JIRA: {TICKET}$` in
`skills/zego-review/SKILL.md`. If line 2 deviates — wrong label, or trailing content
such as `JIRA: AIDEV-29 (draft)` — that grep silently returns nothing, so review
Group E loses the design doc and falls back to the task spec alone.

Fill the values from session context: `{feature_name}` is the feature title,
`{TICKET}` the JIRA key from input handling, `{engineer}` the current git user
(`git config user.name`), `{requirements_source_path}` the JIRA URL or
`docs/requirements/` path used as input, `{date}` today's date
(`date +%Y-%m-%d`), and `{branch-name}` the branch from Stage 1. The `Branch:`
line is read by Phase 2 to generate the first task's `Depends on:` value.

**Resolve `{feature-id}` (the shared feature identifier, AIDEV-188 / ADR 020).**
On the happy path the design phase **recovers** the identifier minted by the
requirements phase and **reuses** it. It **mints** only on a genuine first-run
design-first entry — when recovery yields nothing AND `decide` returns MINT (no
predecessor PR), matching `fix-bug`'s no-predecessor flow. This is best-effort:
any failure warns and proceeds with an empty `Feature-Id:` value (a reporting
gap is acceptable; a blocked skill is not).

1. **Recover from the requirements artefact** when one exists. The
   `{requirements_source_path}` is the requirements doc when input was a
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
     echo "write-design-doc: gh pr list failed for '$REQ_BRANCH' — defaulting predecessor-pr-exists to true (LOST-safe)" >&2
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

Substitute the resolved `$FEATURE_ID` for `{feature-id}` in the header block.
Stage 13 keeps the `Feature-Id:` line itself (the label on line 7) as a hard
structural requirement, but an empty value is advisory — a successful recover
(or, on a design-first entry, a successful mint) is the normal path, not a
precondition for sign-off. If `$FEATURE_ID` is empty after recover + decide
(a LOST verdict, or a `gh`/mint failure), surface a warning to the engineer that
the identifier could not be resolved (recover it manually, or confirm the
requirements doc carries a `Feature-Id` row); the gate warns on the empty value
but does not reject, so the design phase still proceeds. The `JIRA:` header line
is left untouched throughout so the `^JIRA: {TICKET}$` discovery grep is
unaffected.

Write narrative prose — this is the engineer-facing document. Make it readable.

Tell the engineer:

> Design Document written to `docs/design/{TICKET}-{slug}.md`.

Then continue to Stage 13 to present the decision ledger and wait for sign-off.

---

## Stage 13 — Sign-off gate

**Present the decision ledger before waiting for sign-off.** This is the single
Phase 1 stop, so every decision Stages 2–11 made autonomously is surfaced here for
the engineer to review in one place. The persisted **`## Auto-decision ledger`**
section of the design document is the source of truth for this presentation — the
same section the engineer reviews before sign-off and that remains in the committed
document afterwards. Present the full ledger from it:

> Design Document written to `docs/design/{TICKET}-{slug}.md`. Before sign-off,
> here are the decisions I made autonomously during Phase 1:
>
> {For each ledger entry: what was decided, the basis (inferred-from-input /
> inferred-from-codebase / sub-agent-investigated), and the rejected options.}
>
> {The coverage-prompt net-new notes, one batched note per section.}
>
> {The Stage 11 revisit assessment.}
>
> {Any open item — a genuinely blocking gap with no defensible inferred or
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
a rejection condition (see the sign-off conditions below, which are unchanged). If
there are no unresolved open items, render nothing here (or state "no unresolved open
items") — do not emit empty scaffolding.

**Wait for the engineer's explicit sign-off.** Accepted phrases: "looks good",
"sign off", "approved", "ship it", "looks good — proceed to Phase 2". Do not
treat bare "yes" as sign-off — it appears as a natural answer to questions.

**If the engineer signs off but the document is missing any Artefact 2a
section, or is missing the `## Summary` section**, do not accept sign-off. The
seven Artefact 2a sections (Approach, Components affected, Interface contracts,
Task breakdown, Test strategy, Risks and constraints, ADR references) are
checked verbatim AND, in addition, `## Summary` must be present (it is the
human-first skim section, distinct from the seven — never treat one of the seven
as satisfying the `## Summary` check, and never treat `## Summary` as satisfying
a seven-section check). List the missing sections explicitly:

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
seven-line block** — in particular if line 2 is not exactly `JIRA: {TICKET}`
(correct label, ticket key alone, no trailing content) — do not accept sign-off.
Verify deterministically:

```bash
sed -n '1,7p' docs/design/{TICKET}-{slug}.md            # show the header
rg -q "^JIRA: {TICKET}$" docs/design/{TICKET}-{slug}.md && echo OK || echo HEADER_DEVIATES
```

The `rg -q` line is the load-bearing self-check: it runs the exact consumer
grep, so `HEADER_DEVIATES` (or a non-`OK` result) means line 2 will be invisible
to the `zego-review` skill. Treat anything other than `OK` as a deviation. Then
confirm from the printed header that line 1 matches `^# Design: \S` and lines
3–7 carry the `Engineer:`, `Requirements:`, `Date:`, `Branch:`, and
`Feature-Id:` labels in order. The header *shape* is fixed: the `Feature-Id:`
label must be present on line 7. Its *value*, however, is advisory — consistent
with ADR 014's launch-safe advisory-gate direction, an empty or unrecovered
`Feature-Id:` value is a reporting gap, not a gate failure. The `Feature-Id:`
line is the AIDEV-188 identifier recovered in Stage 12; if line 7 carries the
label but the value is empty, do not reject — accept sign-off and surface a
non-blocking warning instead:

> Note — the `Feature-Id:` value on line 7 is empty: the identifier could not be
> recovered from the requirements artefact. Sign-off still proceeds. Recover it
> manually (or confirm the requirements doc carries a `Feature-Id` row) to close
> the value-stream link.

Sign-off is rejected only on a *structural* header deviation — the `rg` check
failing (line 2 not exactly `JIRA: {TICKET}`), line 1 not matching `^# Design: \S`,
or lines 3–7 missing their labels or out of order. If the `rg` check fails or any
line deviates structurally:

> Sign-off not accepted — the design document header must be the canonical
> seven-line block (line 2 exactly `JIRA: {TICKET}`, with lines 3–7 carrying the
> `Engineer:`, `Requirements:`, `Date:`, `Branch:`, and `Feature-Id:` labels in
> order). The `zego-review` skill discovers design docs with
> `rg -l "^JIRA: {TICKET}$"`; any deviation makes this document invisible to
> review. Correct the header, then sign off.

**If the engineer requests changes**, loop back to the originating stage
(Stage 2–10) to update that section, then return through Stage 11 (revisit
gate) and Stage 12 (re-write document) before re-attempting sign-off here.
Inside this loop-back, **re-mark the affected decision ledger row(s)
`engineer-directed`** — this is the only path that ever sets that attribution:

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
  re-write at Stage 12. Update the design content *and* the ledger row together.
- **Cascade** — if an intervention forces genuinely-consequential downstream changes,
  re-mark each changed downstream row `engineer-directed` too. Rows merely
  re-confirmed unchanged stay `AI-made` (no marking).

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
   reference. The template carries the AI-native banner blockquote as its first
   content (immediately after the frontmatter `---`, before the `# ` H1).
   Resolve its placeholders per `docs/ai/steering/base/review-audience.md`:
   `{surface}` = `design document`, `{link}` = the design document path
   `docs/design/{TICKET}-{slug}.md`. The emitted blockquote must read, with
   `{TICKET}` and `{slug}` interpolated to actual values and no `{` placeholder
   token remaining:

   ```
   > **AI-native artefact.** Human reviewers do not need to read this; the review surface for this phase is the design document at docs/design/{TICKET}-{slug}.md.
   ```

   In the body header block, emit:

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

7. **Verify the two contract fields and the AI-native banner on disk against the
   values you computed — do not trust the just-written file.** Re-read the spec
   at the path from step 4. Both contract fields have canonical values you
   already hold; at this point never re-derive either from the Design Document:
   - Frontmatter `branch:` MUST equal `{TICKET}_TASK-{NN}_{slug}` (steps 1–2) —
     NOT the Design Document's `Branch:` value.
   - Body header `Depends on:` MUST equal the value determined in step 5.
   - The AI-native banner blockquote MUST be present as the first content (the
     first non-blank line after the frontmatter `---`, before the `# ` H1) and
     MUST carry the resolved link with no `{` placeholder token remaining.
     Verify deterministically:

     ```bash
     rg -q "^> \*\*AI-native artefact\.\*\* .*docs/design/{TICKET}-{slug}\.md\.$" docs/tasks/{TICKET}-TASK-{NN}-{slug}.md && echo BANNER_OK || echo BANNER_MISSING
     ```

     Anything other than `BANNER_OK` — banner absent, or a literal `{surface}` /
     `{link}` placeholder still present — is a defect.

   Compare on the trimmed value. If a field on disk differs from its canonical
   value, or the banner is missing or carries an unresolved placeholder, re-write
   the whole spec with Write — the same content but with that field set to its
   canonical value and the banner present with the resolved link (this flow has
   `Write`, not `Edit`) — and record a correction note for the Stage 16 report,
   of the form `{spec filename}: {field} corrected from '<got>' to '<expected>'`
   (use `banner` as the field name for a banner correction). This reconciliation
   is deterministic: it never re-prompts, never halts on value drift,
   and is a no-op on an already-correct spec.

**Task spec writing rules — enforce strictly:**

- Frontmatter: `ticket` and `branch`, plus an OPTIONAL `feature-id:` third key
  (AIDEV-188 / ADR 020). No other fields. When the design doc's `Feature-Id:`
  header carries an identifier, recover it and write it into every task spec's
  frontmatter as `feature-id: {id}` so the per-task implementation PR can stamp
  the same value:

  ```bash
  FEATURE_ID="$(.claude/scripts/feature-id.sh recover docs/design/{TICKET}-{slug}.md 2>/dev/null || true)"
  ```

  When recover yields nothing, omit the `feature-id:` key entirely (do not write
  an empty value). This is best-effort and never blocks task-spec generation.
  Do NOT strip a `feature-id:` key when re-writing a spec in step 7.
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

Then invoke the `zego-create-pr` skill to open a PR for the design branch. Pass:
- `ticket`: the JIRA key
- `branch`: the design branch name
- `task_spec_path`: the design document path (`docs/design/{TICKET}-{slug}.md`).
  `zego-create-pr`'s `task_spec_path` input is widened to accept a design doc:
  having no `ticket:` frontmatter key, the design doc is recognised as such and
  its ticket is read from the `JIRA:` header line. The design doc carries the
  `Feature-Id:` header line, so `zego-create-pr` recovers and stamps the same
  identifier onto the design-phase PR.
- `labels`: `ai-design`
- `review_surface`: `{label: the design document, link: docs/design/{TICKET}-{slug}.md}` — names the design document as the review surface for this phase (`docs/ai/steering/base/review-audience.md`); `zego-create-pr` renders it as one inline line within Background.

Base targeting depends on the `design_base` Stage 1 recorded:
- If `design_base` is the **requirements branch** (Stage 1 stacked the design
  branch on an *open* requirements branch), pass `base` = that requirements
  branch name to `zego-create-pr` (it accepts the optional `base` input). A PR
  from the stacked branch to the default branch would otherwise include the
  requirements commits, so the design PR would span two phases and break
  ADR 011's one-PR-per-phase property; targeting the requirements branch keeps
  the design PR's diff to design content only.
- If `design_base` is the **default branch** (Stage 1 cut the design branch
  from `origin/{default}` — the merged-requirements case, or the ordinary
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

- **Phase 1 is autonomous through to sign-off.** Stages 2–11 run in sequence with
  no engineer prompt: derive each answer from the priority order (trigger inputs →
  brief/requirements → codebase reading), dispatch an investigation sub-agent via
  the Agent tool where confidence is genuinely low, record every decision to the
  decision ledger, and present the ledger at the single Stage 13 sign-off stop.
  Never fabricate a decision to avoid a stop; a genuinely blocking gap is recorded
  as an open ledger item and surfaced at Stage 13.
- **Read the codebase actively.** Use Bash and Read throughout Phase 1 to
  ground the design in observable reality. Do not rely solely on engineer input.
- **No sign-off without all sections.** All seven Artefact 2a sections plus the
  human-first `## Summary` section must be present in the Design Document before
  sign-off is accepted. `## Summary` is checked in addition to the seven, never
  in place of one of them.
- **No sign-off with zero tasks.** The task breakdown must contain at least one
  task.
- **Phase 2 is autonomous.** No questions, no pauses, no confirmation between
  task specs. Read the document, generate all specs, report.
- **Task specs are machine-optimised.** Resist narrative. Every line is a
  constraint or checkable AC.
- **Frontmatter is ticket and branch, plus an optional `feature-id`.** A task
  spec's frontmatter permits exactly three keys: `ticket`, `branch`, and the
  optional `feature-id` (the AIDEV-188 / ADR 020 identifier). Any other field is
  an error. Never strip a `feature-id:` key when re-writing a spec.
- **Conflict detection for document tasks.** When the output is a standards
  file, skill file, or similar non-code artefact: run Stage 5 and Stage 6.
  Read all of docs/ai/steering/ before the engineer signs off.
- **No kept/adapted/discarded.** Synthesis from external references goes
  directly into task spec ACs and constraints. No synthesis history section.
- **Revisits happen at Stage 13.** Phase 1 is autonomous, so the engineer
  requests changes at the Stage 13 sign-off gate (the single stop), not mid-run.
  On a change request, loop back to the originating stage, update the draft, and
  re-present at Stage 13.
- **Slug derivation is deterministic.** Lowercase, replace any run of
  non-alphanumeric characters with a single hyphen, trim leading/trailing
  hyphens, truncate to 40 chars. Apply consistently to both Design Document
  and task spec filenames.
- **The approach-brief intake is asked once, on the start-fresh branch only.**
  Stage 1a runs the shared `.claude/skills/shared/approach-brief-intake.md`
  contract after resume detection; a resumed design is never re-asked the
  opt-in question. The intake is read-only, writes no durable state, and never
  hard-fails the session (a missing path is re-asked once then falls through to
  `no-brief`). It is the single source of the contract; never inline a second
  copy (ADR 007).
- **Only Approach and Inputs are seeded from a brief.** On a `brief` handle,
  seed the Stage 2 Approach (incorporate task-blocking facts with provenance;
  pointer the two ambiguous bands) and the front-loaded Inputs section
  (references, never condenses). Every other section may draw on the brief; the
  wholesale rewrite of the brief into every section is forbidden.
- **The cold path is preserved byte-for-byte.** On `no-brief`, the Inputs
  section is omitted entirely and the design output is what it is today. The
  opt-in question and one-time brainstorm advisory ahead of it are expected, not
  suppressed.
- **The coverage prompt is affirmative, batched, and brief-path only.** On a
  `brief` handle, one note per authored section classifying content as brief /
  convention / net-new, recording every net-new item to the decision ledger for
  Stage 13 presentation; never a silence detector, never one note per item, never
  a mid-run engineer prompt. On the cold path (`no-brief`) it does not run, so a
  cold design is authored without coverage notes (matching the design flowchart
  and `zego-write-design-doc-max`).

# Approach-brief intake (shared across skills)

This file is referenced by the design-doc calling skills: the default
`.claude/skills/zego-write-design-doc/SKILL.md` calls it directly, and
`.claude/skills/zego-write-design-doc-max/SKILL.md` calls it and threads the
brief through its `design-writer.md` sub-agent. It is the single home of the
upstream approach-brief intake contract: the read-and-fill instructions a
design-doc
skill follows to accept a prior-planning brief (a `zego-brainstorm` artefact or
any other planning document) and let it feed the design, turning the skill from
a discovery process into a formalisation process when a brief is present.

The contract is read-only: nothing here commits, opens a PR, or writes durable
state. The intake step is trivially resumable. A named brief that does not exist
is re-asked once and then the run proceeds cold; the intake never hard-fails the
design session.

This document is the authoritative specification of the intake contract. ADR 023
(`docs/decisions/023-design-doc-approach-brief-intake.md`) records the decision
and rationale and points here; it does not restate the contract.

## Caller contract

The calling skill must fill the following placeholders before executing:

| Placeholder | Required | Description |
|-------------|----------|-------------|
| `{ticket}` | yes | JIRA ticket key (e.g. `AIDEV-172`). Orchestrator context at skill start. |
| `{branch}` | yes | Git branch name. Orchestrator context at skill start. |
| `{starting-fresh}` | yes | Boolean. True only when the skill has determined it is starting a fresh design, NOT resuming an existing one. The caller sets this from its own prior-document / resume check. |

### Return

The intake returns one of two handles to the caller:

| Handle | Meaning | Caller action |
|--------|---------|---------------|
| `no-brief` | No brief was used. The engineer answered "no", or named a path that did not resolve after one re-ask, or the brief was rejected as thin. | Author the design **cold**, the unchanged path. Omit the Inputs section entirely. |
| `brief {path, source-type, content}` | A brief was read in full. `path` is the resolved relative path, `source-type` is `brainstorm` or `other`, `content` is the full text read from disk. | Seed the Approach and Inputs sections from the brief per the rules below. |

The intake never returns an error handle and never halts the calling skill. A
missing path, a thin brief, and a declined opt-in all resolve to `no-brief`.

---

## Step 1: opt-in question (entry point)

Ask this question **once**, and only when `{starting-fresh}` is true. When the
caller is resuming an existing design, `{starting-fresh}` is false: skip this
step entirely. The intake writes no durable state, so there is no stored handle
to return; the resume handle is the **caller's** to re-derive each invocation
from the design it is resuming
(`docs/ai/steering/local/skill-idempotency.md` Rule 4). A design authored cold
re-derives `no-brief`; a design authored warm re-derives its `brief` handle from
its own Inputs section. The intake itself does not recover that handle, and a
resumed design is never re-asked the opt-in question.

- **Input:** orchestrator context (`{ticket}`, `{branch}`). No brief is assumed.
- **Output:** `no-brief`, or a `brief` handle `{path, source-type, content}`.
- **Side effects:** none. Read-only; no commits; no durable state written.

Ask the engineer:

> Do you have any prior planning, spikes, or homework for this design, such as a
> `zego-brainstorm` artefact or any other planning document? If so, give me the
> path and I will read it in full and formalise it. If not, I will start cold.

Resolve the answer:

- **"No" / no path given:** run Step 2 (the no-brief advisory), then return
  `no-brief`.
- **"Yes" with a path:** check the path resolves on disk.
  - Resolves: proceed to Step 3 with that path.
  - Does not resolve: re-ask **once** for the correct path. If the re-asked path
    also does not resolve, run Step 2 (the no-brief advisory) and return
    `no-brief`. A missing path is never a hard failure; it falls through to the
    cold path after exactly one re-ask.

---

## Step 2: no-brief advisory

Surface this advisory **once**, on a "no" answer (or a path that did not resolve
after the single re-ask). It is advisory, never a gate: it does not block,
auto-fire, or halt, consistent with `docs/ai/steering/base/skill-pipeline.md`
Rule 7. The engineer may continue cold without penalty.

Print, once:

> `zego-write-design-doc` formalises a chosen approach; it is not built to
> explore or find the solution. If you have not settled on an approach yet,
> `zego-brainstorm` is the tool for that: it runs a council of advocate lenses
> plus a Skeptic and recommends a route. You can run brainstorm first, or
> continue cold now. Either is fine.

Do not wait for a decision and do not re-prompt. After printing the advisory,
return `no-brief` and let the caller author cold.

---

## Step 3: read the brief in full

On a "yes" with a resolving path, read the named brief **in full** from its
source. The source may be **any** planning document: a `zego-brainstorm`
exploration artefact under `docs/exploration/`, or any other planning document
in any location. There is **no fixed schema and no required front-matter** (AC3).
The intake reads whatever the file holds.

Record the `source-type`:

- `brainstorm`: the file carries `zego-brainstorm` front-matter (it has the
  machine scalars `state` and `choice`, per
  `docs/decisions/018-single-layer-markdown-exploration-artefact.md`).
- `other`: any other planning document, with no brainstorm front-matter.

Hold the full text as `content`. Proceed to Step 4.

---

## Step 4: substantiveness check

Classify the brief into exactly one of three outcomes. The check decides whether
the brief carries a usable approach and how to seed from it.

- **`accept`**: the brief has an identifiable, settled approach. Either:
  - a `zego-brainstorm` artefact with `state: converged`, or
  - a non-brainstorm source (no `state`/`choice`) that contains an identifiable
    approach.

  Proceed to seed (Step 5) directly.

- **`resolve-then-seed`**: the brief has substance but no settled approach. A
  `zego-brainstorm` artefact with `state: unresolved` or `state: exploring`
  falls here: it has real content but the route is not yet chosen. Do **not**
  print its open choice as a settled approach. Instead, surface the open choice
  to the engineer during the Approach interview and have them settle it; the
  resolved decision becomes the seeded Approach. If the engineer cannot settle
  it, redirect them to `zego-brainstorm` and do **not** author the design. **The
  design never carries open questions**: a design doc records a chosen approach,
  not an unresolved one. Once (and only once) the choice is settled, seed per
  Step 5. For a non-brainstorm (`other`) source with no `state`/`choice` scalar,
  detect this outcome when the document has real substance but enumerates options
  without choosing one; surface the open choice by asking the engineer to pick
  among the options the document lists, then proceed as above.

- **`reject`**: the brief is thin, with no identifiable approach. Emit a one-line
  recovery message naming the file and explaining it carried no usable approach,
  then fall through to the cold path. Return `no-brief`.

---

## Step 5: seed (incorporate vs pointer, the decisive test)

For an `accept` brief (or a `resolve-then-seed` brief whose choice has been
settled), seed the design from the brief. Seeding is governed by two rules: the
**decisive test** (this step) and **seed-vs-draw-on** (Step 6).

### The decisive test (per passage)

For each passage of the brief, decide between `incorporate-with-provenance` and
`pointer`:

- **`incorporate-with-provenance`**: only for a passage that is a **task-blocking
  instruction, boundary, or contract fact**, OR a **genuinely task-blocking
  decision even when it reads as rationale** (the load-bearing-decision escape
  clause). An incorporated passage is written into the seeded **Stage 2 Approach**
  section, carrying a clickable relative-link provenance backlink to its source.
  It **never** lands in the Inputs section, which is reference-only.
- **`pointer`**: **the default** for both ambiguous bands, namely
  settled-but-upstream content and rationale / "why". A pointer is a clickable
  reference, not a rewrite.

The pointer default is the safe-biased default because **a pointer never loses
content**, so a misclassification is cheap. Both ambiguous bands
(settled-upstream content and rationale) route to a pointer unless the explicit
escape clause (a genuinely task-blocking decision) overrides. Do not leave the
default unspecified: when in doubt, pointer.

---

## Step 6: seed vs draw-on

Only **two** sections are **seeded** from the brief, where the brief is their
authoritative starting content:

1. the **Stage 2 Approach** section, and
2. the front-loaded **Inputs / prior-planning references** section.

**Every** other section may still **draw on** the brief: it pulls in
task-blocking facts and cites the brief where relevant. The brief is never
ignored elsewhere.

What is **forbidden** is the **wholesale rewrite** of the brief's prose into
every section. That is where nuance dies and `-max` context is wasted. Draw on
the brief for facts and citations; do not transcribe it section by section.

### References, never condenses (the Inputs section)

The **Inputs / prior-planning references** section **references** the source via
a clickable link and **never condenses or paraphrases** its prose. This makes
nuance survival a guarantee rather than a discipline: the full reasoning stays at
the source, reached by following the link. The Inputs section never receives
incorporated content (incorporated passages land in Approach, per Step 5).

---

## Step 7: coverage prompt (per authored section)

The per-section gate is an **affirmative classification, not a silence
detector**. For each design section authored, tag its content:

- **(a) from-brief**: content seeded from or drawn from the brief.
- **(b) from-convention**: content from standing convention or steering docs.
- **(c) net-new engineering judgement**: content that is neither, a decision
  made fresh while authoring.

Surface **every (c) item** to the engineer as **one batched note per section**
(not per item). Lead each note with the highest-value net-new content (e.g. a
large net-new block) so the notes invite reading rather than skimming. This
catches the cold-authored sections (failure contracts, interfaces, test suites)
that a thin brief never raises, the cases a silence detector misses entirely.

---

## Step 8: citation / link format

Every reference (in the Inputs section, in incorporated-passage provenance
backlinks, and anywhere the brief is cited) is a **clickable relative Markdown
link** of the form `[title](relative/path#anchor)` that **resolves on disk** at
authoring time, **plus one line** of what the source provided. Raw paths (a bare
`docs/exploration/foo.md` with no link syntax) are **not acceptable**.

### Anchor validity beyond authoring time

`resolves on disk` guarantees a link only at **authoring time**. A brief may be
an uncommitted AI-native `docs/exploration/*.md` artefact that later moves or is
never committed, after which the link can break. **The engineer who authors the
design owns anchor validity from authoring time onward.** The intake's
responsibility ends at authoring time: it MUST verify every link resolves on
disk when the design is written, and that is its whole guarantee. Beyond that
moment, a link into an uncommitted or later-moved source is the authoring
engineer's to keep valid, either by committing the source alongside the design,
or by accepting that an uncommitted AI-native source is a best-effort reference
whose breakage is theirs to repair. The intake does not chase moved sources,
does not rewrite links after the fact, and does not block on a source being
uncommitted. This ownership rule is stated here so it is explicit rather than
implicit.

---

## Rules

- **The intake is read-only.** It never commits, opens a PR, or writes durable
  state. The opt-in step is trivially resumable
  (`docs/ai/steering/local/skill-idempotency.md` Rules 6, 9).
- **The opt-in question is asked once, on a fresh design only.** When
  `{starting-fresh}` is false (a resume), the question is skipped and never
  re-asked.
- **A missing path is never a hard failure.** It is re-asked once, then falls
  through to `no-brief`.
- **The no-brief advisory is advisory, never a gate.** It does not block,
  auto-fire, or halt (`docs/ai/steering/base/skill-pipeline.md` Rule 7). It is
  surfaced once.
- **The design never carries open questions.** A `resolve-then-seed` brief's
  open choice is settled with the engineer during the Approach interview (then
  seeded), or the engineer is redirected to `zego-brainstorm` and the design is
  not authored.
- **Pointer is the default for both ambiguous bands.** Settled-upstream content
  and rationale default to a pointer; only the load-bearing-decision escape
  clause routes a passage to `incorporate-with-provenance`.
- **Only Approach and Inputs are seeded.** Every other section may draw on the
  brief; the wholesale rewrite of the brief into every section is forbidden.
- **The Inputs section references, never condenses.** Nuance survives at the
  source.
- **The coverage prompt is affirmative, batched one note per section.** It tags
  brief / convention / net-new and surfaces every net-new item.
- **Every citation is a clickable relative link that resolves on disk, plus one
  line of provenance.** Raw paths are not acceptable.
- **The authoring engineer owns anchor validity beyond authoring time.** The
  intake guarantees links resolve at authoring time only.
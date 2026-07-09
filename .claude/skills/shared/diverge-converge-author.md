# Diverge/converge authoring sub-agent — shared across skills

This file is the dispatch prompt for the authoring sub-agent of the
diverge/converge engine (`.claude/skills/shared/diverge-converge-engine.md`). The
engine dispatches a sub-agent and points it at this file; the sub-agent reads it,
fills the placeholders the engine passes, writes the Markdown artefact to disk,
and returns **only a compact sentinel** — no prose.

The sub-agent exists to keep the verbose artefact body out of the orchestrator's
context (rolling-context discipline). It is the only writing role in the engine.
Everything else (grounding, advocates, Skeptic) is read-only.

The sub-agent has **two modes**: **full-write** (author the whole artefact body
from the council payload plus the synthesised recommendation) and **redirect**
(write or replace one named approach section, reading only the targeted slice from
disk). The engine tells the sub-agent which mode to run.

---

## Contract

| Aspect | Rule |
|--------|------|
| Writes | By **overwrite** only — never append. Full-write overwrites `{artefact_path}` whole; redirect writes (inserts) or overwrites exactly one approach section. |
| Reads | Full-write reads nothing it was not passed. Redirect reads **only** the targeted approach section's slice from `{artefact_path}` — never the whole file, never the council payload. |
| Returns | A compact sentinel only — `WROTE {artefact_path}` (full-write) or `WROTE-SECTION {id}` (redirect). No prose, no body, no summary. |
| On failure | An explicit error sentinel — `ERROR full-write: {reason}` or `ERROR redirect: {reason}`. Never a partial silent success. |
| Side effects | Writes/edits the Markdown on disk only. Never commits, never opens a PR, never runs any other mutation. |
| Spelling | UK English in all human-readable text in the artefact. |

---

## Mode: full-write

The engine passes:

- The machine scalars: `{ticket}`, `{ticket_url}`, `{title}`, `{date}`, `{mode}`.
- `{requirements}` — the confirmed brief.
- The grounding digest (summary, findings, decided-against constraints).
- The surviving advocate summaries (one per lens: name, summary, touches, reuses,
  pros, optional sketch).
- The Skeptic's per-approach cons and the overall dissent.
- The orchestrator-synthesised recommendation: `choice`, `headline`, `rationale`,
  `pick_instead_if`.
- The open questions.
- `{artefact_path}`.

Write the full artefact to `{artefact_path}` by overwrite, exactly matching the
Interface 4 schema below. Set front-matter `state: exploring` and
`choice: null` (the engineer has not yet converged). Initialise `converge_log` as
an empty YAML list (`converge_log: []`) **unless** the engine passed an existing
log to preserve, in which case write it verbatim.

Return `WROTE {artefact_path}` and nothing else. On any write failure, return
`ERROR full-write: {reason}`.

---

## Mode: redirect

The engine passes **only**:

- `{artefact_path}`.
- The target approach section id (e.g. `D`).
- The one new approach (a genuinely new hybrid the engineer invented): its name,
  summary, touches/reuses, pros, and — if supplied — Skeptic cons, sketch, and
  rubric verdicts.

The target id may already exist on disk or be genuinely new. Handle two cases
under the same dispatch:

- **REPLACE** — the `### {id} — …` block already exists. Read **only** that
  slice from `{artefact_path}`. Do **not** read the rest of the file and do
  **not** expect the council payload. Overwrite that one section in place with
  the new approach, matching the per-approach sub-schema below.
- **INSERT** — the `### {id} — …` block does not yet exist (the new-hybrid case).
  There is no slice to read. Read **only** the `## Candidate approaches` boundary
  needed to locate the insertion point: the last existing `### {id}` approach
  block and the following `## Skeptic's dissent` heading. Never read the whole
  file, never read the council payload. Insert the new section under
  `## Candidate approaches`, after the last existing `### {id}` approach block and
  before the `## Skeptic's dissent` heading, matching the per-approach sub-schema
  below. This insertion is **permitted** and is **not** the forbidden "append":
  the no-append rule forbids appending content to an existing section or to the
  file tail, not inserting a new approach block at its schema-defined position.

In both cases leave every other byte of the file unchanged.

Return `WROTE-SECTION {id}` and nothing else. On any write failure, return
`ERROR redirect: {reason}`.

---

## Interface 4 — the Markdown artefact schema (pin exactly)

The artefact at `{artefact_path}` is a single front-mattered Markdown file.

### Front-matter (machine scalars only — nothing else)

```yaml
---
ticket: {ticket}
ticket_url: {ticket_url}
title: {title}
date: {date}
mode: {mode}
state: exploring        # one of: exploring | converged | unresolved
choice: null            # chosen approach id or hybrid handle; null until converged
converge_log: []        # YAML list of one-line steer notes (append-only)
---
```

`state` is one of `exploring`, `converged`, `unresolved`. `choice` is `null`
until the engineer converges. `converge_log` is a YAML list of one-line strings —
an append-only accumulator; never re-initialise it if one was passed.

### Body (required sections, in this exact order)

The outer fence below is `~~~markdown` so the inner ```mermaid block reads
unambiguously. Write a normal Markdown file (the inner triple-backtick fences are
literal in the artefact).

~~~markdown
# Approaches: {title} ({ticket})

## Recommendation

**{headline}**

{rationale}

**Pick instead if:** {pick_instead_if}

## Requirements

{the confirmed brief, as a bulleted list}

## Grounding

{one-paragraph visible summary of the relevant area}

<details>
<summary>Findings and decided-against constraints</summary>

**Findings**

- {finding — evidence (path) — consequence}

**Decided-against**

- {constraint the council must respect}

</details>

## Candidate approaches

### A — {lens}: {name}

{summary, 2-4 sentences}

- **Touches:** {files/modules/components, with paths}
- **Reuses:** {existing code/pattern it leans on}

**Pros**

- {pro}

**Skeptic cons**

- {con, tied to evidence}

```mermaid
{optional one diagram for this approach; omit the block entirely if none}
```

<details>
<summary>Rubric verdicts</summary>

| Dimension | Verdict |
|-----------|---------|
| Requirements fit | {one-line verdict} |
| Codebase fit | {one-line verdict} |
| Effort & complexity | {one-line verdict} |
| Risk & reversibility | {one-line verdict} |
| Durability | {one-line verdict} |
| Standards & decided-against | {one-line verdict} |

</details>

### B — {lens}: {name}

{…same per-approach sub-schema as A…}

### C — {lens}: {name}

{…same per-approach sub-schema as A…}

## Skeptic's dissent

{the Skeptic's sharpest unresolved risk, preserved verbatim}

## Open questions

- {open question}
~~~

### Schema rules

- **Front-matter holds machine scalars only** — the eight keys above and nothing
  else. All human content lives in the body.
- **Sections appear in the listed order**, all seven present: the `# Approaches:`
  title, then `## Recommendation`, `## Requirements`, `## Grounding`,
  `## Candidate approaches`, `## Skeptic's dissent`, `## Open questions`.
- **One `### {id} — {lens}: {name}` per approach** under `## Candidate
  approaches`, each carrying summary, touches/reuses, pros, Skeptic cons, an
  optional `mermaid` sketch, and rubric verdicts inside a `<details>` table.
- **Diagrams are `mermaid` fenced blocks.** No CDN dependency, no renderer script.
  Omit the block entirely when an approach has no useful sketch.
- **No numeric or percentage scores anywhere.** Rubric verdicts are one-line
  prose, not numbers.
- A degraded run (one advocate lost) simply has fewer `### {id}` sections — write
  only the surviving approaches. The engine records the gap in `converge_log`.

# design-writer

You are a sub-agent invoked by `.claude/skills/zego-write-design-doc-max/SKILL.md` to write a design document.

## Modes

SKILL.md dispatches this writer in one of two modes, distinguished by which input fields are present:

- **Initial mode** — `synthesis_path` is provided. Write the complete design document from the synthesis file, per the Inputs and Constraints below.
- **Revision mode** — `design_path` and `revision_directives` are provided (no synthesis file). Read the design document at `design_path` in full, apply each directive, and rewrite the document in place at `design_path`. Each directive names a target section and the change to make. Apply directives exactly: make no undirected changes, do not drop or reorder sections, preserve the canonical six-line header verbatim except where a directive targets it, and never create or modify `## Dismissals`. If `design_path` cannot be read, or a directive names a section that does not exist, fail and report which input was unusable — SKILL.md surfaces the failure and halts the fix cycle. All Constraints below apply equally in revision mode.

## Inputs (received from SKILL.md)

- `synthesis_path` (initial mode): path to a synthesis file (`.tmp/{TICKET}-design-synthesis.md`) that holds every field this writer needs as labelled Markdown sections. Read it first — it is your complete brief. SKILL.md writes it before dispatching and deletes it after this writer returns; it carries:
  - `feature_name`: the human-readable feature name (used as the `# Design:` title and as the source for slug derivation)
  - `approach`: confirmed approach text (Stage 2 output)
  - `components`: confirmed components list — existing (modified) and new (created) with descriptions (Stage 3 output)
  - `interface_contracts`: confirmed interface contracts for all new or modified interfaces (Stage 4 output); "No new or modified interfaces" if none
  - `task_breakdown`: confirmed task breakdown — ordered list of tasks with names, numbers, and dependencies (Stage 7 output)
  - `test_strategy`: confirmed test strategy — integration test owner, E2E approach, cross-task constraints (Stage 8 output)
  - `risks_and_constraints`: confirmed risks and constraints — each risk with why it matters and mitigation (Stage 9 output)
  - `adr_references`: confirmed ADR references — existing ADRs that constrain the design, plus any new ADRs to create (Stage 10 output); "No ADR references" if none
  - `requirements_source_path`: path to the requirements source file (e.g. `docs/requirements/AIDEV-82-foo.md` or JIRA key)
  - `branch`: branch name established in SKILL.md Stage 1
  - `ticket`: JIRA ticket key (e.g. `AIDEV-82`)
  - `engineer`: engineer name
  - `date`: ISO 8601 date
  - `feature_id`: the resolved AIDEV-188 / ADR 020 shared identifier (may be empty when recovery failed; that is acceptable)
  - `brief_handle`: the approach-brief intake handle, `brief` or `no-brief` (SKILL.md Stage 1a). Absent is equivalent to `no-brief`
  - `brief`: present only when `brief_handle` is `brief` **and** the brief content is in hand (an initial write or a same-session revision). Holds the brief's resolved `path`, `source-type` (`brainstorm` or `other`), and the read-in-full `content`. The `content` is fenced: it spans every line between the `## brief` heading and the explicit `## /brief` sentinel line, and the sentinel (not the next `##`) marks its end. Read the content up to the **last** `## /brief` line, not the first, since SKILL.md writes the real terminator last, after the content, so an `other` brief that itself contains a flush-left `## /brief` line is not truncated early. The brief may itself contain `##` headings (a brainstorm artefact has its own `## Approach` etc.), and those are part of the brief content, NOT synthesis fields. This is the brief the shared intake contract (`.claude/skills/shared/approach-brief-intake.md`) read; it is your authoritative source for the Inputs section and for tagging from-brief content. Do NOT re-read or re-resolve it; use the content as given
  - `carried_inputs`: present only when `brief_handle` is `brief` and the brief content is **no longer in hand**: a resumed brief-seeded design carried forward by SKILL.md (Stage 12). Holds the already-rendered `## Inputs / prior-planning references` content (the reference links and one-line descriptions) captured from the existing document. Like `brief`, it is fenced: it spans every line between the `## carried_inputs` heading and the explicit `## /carried_inputs` sentinel line, and the sentinel marks its end. Read the content up to the **last** `## /carried_inputs` line, not the first, since SKILL.md writes the real terminator last, after the content, so content that itself contains a flush-left `## /carried_inputs` line is not truncated early. Re-emit this content **verbatim** as the Inputs section; do NOT re-derive, re-resolve, or re-link it. A `brief_handle` of `brief` with neither a `brief` section nor a `carried_inputs` section is a defect: fail and report it rather than authoring cold

Read `synthesis_path` in full before writing. If it cannot be read, fail and report the unreadable path — SKILL.md surfaces the failure and offers to retry.

## Constraints

- Write to `docs/design/{ticket}-{slug}.md` where `{slug}` is derived from `feature_name`: lowercase, replace runs of non-alphanumeric characters with a single hyphen, trim leading/trailing hyphens, truncate to 40 characters
- Conformance target: the canonical seven-line header block specified below, plus the seven body sections listed in the "All seven body sections" constraint below; use `feature_name` as the value for the `# Design:` header. `## Dismissals` is not part of the conformance target — it is appended by SKILL.md on first dismissal
- The document MUST begin with exactly this canonical seven-line header block, in this order, with these labels verbatim:

  ```
  # Design: {feature_name}
  JIRA: {ticket}
  Engineer: {engineer}
  Requirements: {requirements_source_path}
  Date: {date}
  Branch: {branch}
  Feature-Id: {feature_id}
  ```

  The labels and their order are MANDATORY and must NOT be paraphrased or reordered. In particular: line 2 is `JIRA:` (never `Ticket:` or any synonym), the seven lines appear in the order above, and line 2 carries the ticket key alone with no trailing content (so it matches the `zego-review` skill's exact-match discovery grep `^JIRA: {TICKET}$`). Substitute the passed `feature_id` value for `{feature_id}` on line 7; if `feature_id` is empty, still emit the `Feature-Id:` label with an empty value (the label is structural; an empty value is advisory). This header is identical in shape to the template at `.claude/skills/zego-write-design-doc-max/design-document.md`; SKILL.md verifies it deterministically after this writer returns (`.claude/skills/zego-write-design-doc-max/scripts/verify-design-header.py`) and corrects any deviation. That check validates the first six lines (through `Branch:`); the line-7 `Feature-Id:` value is advisory and not enforced by it
- Write narrative prose — this is the engineer-facing document; make it readable
- `## Summary` is the first section, placed immediately after line 7 of the header and before `## Approach`. It is distinct from the seven body sections — author it separately, never as one of them. Cover four sub-points in order: what changed & why; the decisions needing judgement; the assumptions; where the risk is. It is illustrative-only — every fact it states also appears in the body section that owns it
- In the `## Summary` only, use GitHub callouts sparingly: `> [!IMPORTANT]` for the judgement-calls and `> [!WARNING]` (or `> [!CAUTION]` for a guardrail protecting a machine consumer) for the risk. Never use callouts on every section. Use only the supported types NOTE/TIP/IMPORTANT/WARNING/CAUTION, with the type marker on its own first line of the blockquote and content on later `>` lines. Callouts are blockquote syntax, not raw HTML; they are illustrative-only (never the sole source of a machine fact) and degrade cleanly — native on GitHub and in recent VS Code preview, falling back to a plain blockquote elsewhere (do not assume every IDE renders them)
- Lead `## Components affected` with a `mermaid` component map and `## Task breakdown` with a `mermaid` dependency graph; at least one `mermaid` block must be present. The diagrams are illustrative — the binding facts are the prose/structured lists they visualise
- Collapse machine-dense detail (the interface contracts, the long per-task detail) inside `<details>`/`<summary>` blocks so the skim path stays short. A `<details>` block wraps a section's content only — the `##` heading stays outside the block (heading visible, content collapsible)
- Introduce only `<details>`/`<summary>` and `mermaid` constructs — no other raw HTML tag. Describe behaviour and intent; never name a specific programming language as a required construct or example
- All seven body sections must be present: Approach, Components affected, Interface contracts, Task breakdown, Test strategy, Risks and constraints, ADR references
- **Inputs / prior-planning references section (conditional on `brief_handle`).** The template at `.claude/skills/zego-write-design-doc-max/design-document.md` carries a conditional, front-loaded `## Inputs / prior-planning references` section that sits ABOVE `## Approach` (and after `## Summary`):
  - **`brief_handle` is `brief` with a `brief` section:** emit the section. Populate it with one entry per source the brief drew on (the brief itself at `brief.path`, and any planning documents it cites), each a clickable relative Markdown link `[title](relative/path#anchor)` that resolves on disk at authoring time, plus one line of what that source provided. The section references; it never condenses or paraphrases the source prose, and it never receives incorporated content (incorporated passages land in Approach, which SKILL.md Stage 2 seeded). Verify every link resolves on disk before writing; raw paths are not acceptable. The authoring engineer owns anchor validity beyond authoring time (shared contract, `.claude/skills/shared/approach-brief-intake.md` Step 8)
  - **`brief_handle` is `brief` with a `carried_inputs` section (resumed design):** emit the section by re-emitting the fenced `carried_inputs` content verbatim; the links and descriptions were already authored and link-verified on the original write. Do not re-derive entries from a brief (none is in hand) and do not re-verify or re-write the links
  - **`brief_handle` is `no-brief` (or absent):** omit the section entirely, so the cold-path output is byte-for-byte identical to a design authored without a brief. Do not emit an empty heading or a placeholder
- **Coverage classification (affirmative, embedded per section).** When `brief_handle` is `brief` **and a `brief` section is in hand** (not the `carried_inputs` resume path, where the brief content needed for classification is gone), classify each section's content per the shared contract (`.claude/skills/shared/approach-brief-intake.md` Step 7): (a) from-brief, (b) from-convention, (c) net-new engineering judgement. For every section that contains net-new (c) content, embed ONE batched per-section note (never one note per item) into the design document recording that net-new content, leading each note with its highest-value net-new block so it invites reading. Embed the notes in the document you write so the existing `review-gate.js` Workflow reviews them as part of that document; this is an affirmative classification, not a silence detector. Do NOT add a new return-value channel for the classification and do NOT depend on any `review-gate.js` change. On the `no-brief` cold path there is no from-brief content and no Inputs section; do not emit coverage notes. The coverage prompt is brief-path only: it does not run cold, avoiding embedding net-new notes into every section of every cold design. This matches the design flowchart (which routes the cold path straight to authoring, bypassing coverage) and the default `zego-write-design-doc` skill, which skips cold-path coverage the same way
- Do not add a `## Dismissals` section — SKILL.md manages that section
- Do not add YAML frontmatter

- `design_path` (revision mode): path to the committed design document to revise in place
- `revision_directives` (revision mode): compact list of directed changes, each naming a target section and the change

## Output

Write the complete design document to `docs/design/{ticket}-{slug}.md` (initial mode), or rewrite it in place at `design_path` (revision mode).

Return:
- The path written
- A one-sentence summary of what was produced (initial) or of the directives applied (revision)

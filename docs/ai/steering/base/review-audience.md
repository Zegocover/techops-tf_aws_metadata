---
version: 1.0
last_reviewed: 2026-06-23
---

# Review Audience Standards

Conventions for signalling who an artefact is *for* — the governing principle is that every artefact the pipeline produces is either a **human review surface** (a human reads it and the flow waits on that reading) or an **AI-native reference** (an agent produces and consumes it, and the flow never gates on a human reading it), and each kind must say which it is so reviewer attention lands on the artefacts that matter. Engineers under-review the design that decides the change and over-review the task specs an agent generated from it, because nothing on an artefact or its PR signals its audience. This standard fixes that with two signals: a deflecting banner on every AI-native artefact, and a single review-surface line on every phase PR. Apply these rules whenever producing a pipeline artefact or opening a phase PR. This is a content convention, not a mechanically gated one — the rules describe how artefacts and PRs are authored; enforcement is the producing skills' own self-verification (banner) and the two PR mechanisms below (review-surface line).

## Rules at a Glance

1. **Classify by one test.** An artefact is a **human review surface** if the flow is gated on a human reviewing it before continuing; it is **AI-native** if the agent always continues without a human-review gate. Severity, length, and effort do not enter into it — only whether a human-review gate exists.
2. **Each artefact has a fixed bucket.** Requirements package, design document, implementation PR (diff + completion notes), and acceptance handoff are human review surfaces. Task specs, `zego-review` findings files, and `zego-fix-bug` diagnosis records are AI-native.
3. **Every AI-native artefact carries the deflecting banner.** A Markdown blockquote, verbatim text below, placed as the first rendered content — immediately after any YAML frontmatter and before the `# ` H1 title.
4. **The banner names a real, resolvable surface.** The producing skill resolves `{surface}` and `{link}` per the link-resolution rules below; the link is always a repo path or a full URL that resolves, never a placeholder.
5. **Every phase PR names its single review surface.** Exactly one bolded inline line within the PR body's Background section — never a new `##` heading. This is the resolution of the conflict against `pull-requests.md` rule 8; it adds no section.
6. **The "implementation summary" is the implementation PR.** The pipeline produces no standalone implementation-summary file; the human review surface for the implementation phase is the implementation PR itself — its diff plus its completion notes.

## The classification test

The split is a strict binary, resolved by one question: **is the artefact gated on a human reviewing it before the flow continues?**

- **Yes — a human-review gate exists.** It is a **human review surface**. The requirements package waits on Engineering sign-off; the design document waits on the engineer's explicit sign-off before Phase 2; the implementation PR waits on code review before merge; the acceptance handoff waits on Product sign-off.
- **No — the agent always continues.** It is **AI-native**. Task specs are generated autonomously in Phase 2 and consumed by `zego-implement` with no review gate between them. `zego-review` findings files are written and read inside the pipeline. `zego-fix-bug` diagnosis records are written and the flow proceeds — Stage 5 of `zego-fix-bug` continues without approval, and its size gate is a scope/escalation decision, not a document review.

The test keys on the *gate*, not on whether a human ever opens the artefact. A human may open an AI-native artefact deliberately (e.g. running `zego-review` standalone and reading the findings file); the banner is at worst redundant there, never harmful, because the classification is about where the pipeline *requires* attention, not where it *permits* it.

## Per-artefact buckets

| Artefact | Review audience | Why |
|---|---|---|
| Requirements package | Human review surface | Gated on Engineering sign-off before design begins. |
| Design document | Human review surface | Gated on the engineer's explicit sign-off before Phase 2. |
| Implementation PR (diff + completion notes) | Human review surface | Gated on code review before merge; this is the "implementation summary" the ticket names (see below). |
| Acceptance handoff | Human review surface | Gated on Product sign-off. |
| Task spec | AI-native | Generated autonomously and consumed by `zego-implement`; no human-review gate. |
| `zego-review` findings file | AI-native | Produced and consumed inside the pipeline; no human-review gate. |
| `zego-fix-bug` diagnosis record | AI-native | Written as institutional memory; the flow continues without review. |

### The "implementation summary" maps to the implementation PR

The originating ticket names an "implementation summary" as a human review surface. No standalone summary file is produced: `zego-implement` surfaces its completion notes within the implementation PR rather than writing a separate document. The human review surface for the implementation phase is therefore **the implementation PR itself — its diff plus the completion notes carried in its body**. This mapping is recorded explicitly so the ticket's named surface is visibly honoured and no one looks for a missing file.

## The AI-native banner

Every AI-native artefact carries this banner, verbatim, with `{surface}` and `{link}` resolved by the producing skill:

```
> **AI-native artefact.** Human reviewers do not need to read this; the review surface for this phase is the {surface} at {link}.
```

The banner names human reviewers explicitly because the primary readers of these artefacts are AI agents — task specs feed `zego-implement`, findings files are produced and read inside the pipeline, and `zego-review` reviews task specs in pre-implementation mode. A generic "you do not need to review this" could be read by an agent as an instruction to itself; naming human reviewers keeps the intent about human attention allocation. The banner is inert text — it has no side effects.

### Placement

The banner is a Markdown blockquote that is the **first rendered content** of the artefact:

- Immediately after the closing `---` of any YAML frontmatter, and
- Before the `# ` H1 title.

When the artefact has no YAML frontmatter (a `zego-review` findings file is written without frontmatter, beginning with its `# Code review …` H1), the banner is the **first line of the file**, still before the H1.

Placement is parse-safe and must be re-verified against the actual parsing in each consumer:

- It must not be read as a body header line (`Feature:`, `Design:`, `Depends on:`) — those match a `^Label:` line prefix, never a leading blockquote.
- It must not be matched as a `##`-section placeholder by `zego-implement`'s checks — those key off `##` headings, never a blockquote.
- It must not be matched as a finding line by `zego-fix-bug` Stage 7's extraction — that keys off the `### F{n} —` / `F{n} ({severity}) —` shape, never a blockquote.

### Link resolution per producing skill

| Producing skill | Artefact | `{surface}` | `{link}` |
|---|---|---|---|
| `zego-write-design-doc` / `zego-write-design-doc-max` | task spec | `design document` | `docs/design/{TICKET}-{slug}.md` |
| `zego-fix-bug` | task spec and diagnosis record | `JIRA ticket` | `https://zegons.atlassian.net/browse/{TICKET}` |
| `zego-review` | findings file | `design document` (when a `docs/design/` file matching the ticket key exists) else `JIRA ticket` | the matching `docs/design/{TICKET}-{slug}.md`, else the full JIRA URL |

For `zego-fix-bug` and the design-less `zego-review` path the link is the full JIRA URL, which is always resolvable since no design document exists.

## The PR review-surface line

Every phase PR names its single review surface as **exactly one bolded inline line within the PR body's Background section**:

```
**Review surface for this phase:** {label} — {link}.
```

It is **never a new `##` heading**. `pull-requests.md` rule 8 forbids adding top-level sections beyond the template's, because extra sections fragment the reviewer's reading path; the review-surface signal therefore lives as one inline line inside Background. When the PR template has no Background-equivalent section, the line goes under the template's first section rather than under a new heading. This rule is consistent with rule 8 and does not weaken it.

### Two enforcement mechanisms, one rule

The review-surface line is identical wherever it appears, but it is emitted by two mechanisms because not every phase PR is opened through `zego-create-pr`:

1. **Via the `zego-create-pr` `review_surface` input.** `zego-write-design-doc` / `zego-write-design-doc-max`, `zego-implement`, and `zego-fix-bug` open their PR through `zego-create-pr` and pass an optional `review_surface` object `{label, link}`. When supplied, `zego-create-pr` renders the single inline line within Background; when absent (standalone use), it renders no line and the PR body is otherwise unchanged. The caller values are:
   - `zego-write-design-doc` / `-max` (design PR) → the design document.
   - `zego-implement` (implementation PR) → `the code changes in this PR`.
   - `zego-fix-bug` (bug-fix PR) → `the code changes in this PR (fix + regression test)`.
2. **Via inline composition.** `zego-write-requirements` composes its PR body inline (Stage 13, `req-pr.sh`) and never calls `zego-create-pr`. It adds the line directly within Background, naming `the requirements package` as the review surface.

`zego-write-acceptance-handoff` opens no PR and produces a human-surface document that needs no banner — it is outside this rule.

## The bug-fix banner-vs-PR-line seam

`zego-fix-bug` produces two signals that name different surfaces, deliberately, because they are written at different times:

- **At write-time the bug-fix PR does not yet exist.** The banner on the task spec and the diagnosis record therefore points at the **JIRA ticket** — its sole purpose is to deflect human review away from the AI-native document, and the JIRA ticket is the only always-resolvable surface at that point.
- **Later, the bug-fix PR's review-surface line** — written by `zego-create-pr` from the `review_surface` input — authoritatively names the real human surface: `the code changes in this PR (fix + regression test)`.

This two-mechanism split is intentional, not a contradiction: the banner deflects at write-time using the durable JIRA link, and the PR line names the human surface once the PR exists.

## See Also

- [pull-requests.md](pull-requests.md) — PR body structure and rule 8 (no extra top-level sections), which the review-surface line is consistent with.
- [skill-pipeline.md](skill-pipeline.md) — the development pipeline that produces each classified artefact.

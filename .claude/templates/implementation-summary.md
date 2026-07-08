Ticket: [TICKET]
Task: [TASK-NN]
Branch: [branch the work was implemented on]
Date: [ISO 8601 date — preserved from any existing artefact, else `date -u +%Y-%m-%d` on first creation]
Status: [Implemented / Partial / Deferred]

<!-- This is the canonical structure for the durable implementation-summary
     artefact emitted by `zego-implement` after CI passes. It is written by the
     `summary-writer` sub-agent (`.claude/skills/zego-implement/summary-writer.md`)
     and lives at `docs/ai/implementations/{TICKET}-TASK-NN-{slug}.md`.

     The five header lines above (Ticket, Task, Branch, Date, Status) are body
     header lines, not YAML frontmatter — no `---` fences. The five `##` body
     sections below are all required and appear in this order. Each run
     overwrites the artefact wholesale; never append or merge. The one value
     carried forward across runs is `Date`: reuse the `Date:` line from an
     existing artefact at this path, and only stamp `date -u +%Y-%m-%d` (UTC)
     on first creation, so a same-input resume stays byte-identical.

     This artefact is human-first. Write plain-language prose an engineer can
     skim. It is language-agnostic — describe the change in terms of behaviour
     and intent, not the implementation language. -->

## What was done

[Plain-language account of the change, synthesised from the task spec and the
run diff (`base..HEAD`). What now exists that did not before. If the diff was
unavailable, say so and synthesise from the task spec and completion notes
alone.]

## Assumptions and guesses

[The low-confidence calls flagged for attention — decisions made where the spec
did not specify, ambiguities resolved by a judgement call. Quote the doer's
completion notes verbatim, attributed to the doer; synthesise only for status
or framing, never paraphrase the notes themselves. If completion notes are
absent or empty, write `unavailable — completion notes were not captured for
this run` and note that this section could not be populated. Do not invent
assumptions.]

## Where it struggled

[Dual-source: drawn from BOTH the doer's completion notes (quoted verbatim,
attributed to the doer — the agent's lived experience, the paths it went down
and abandoned) AND the review and CI iterations and what needed fixing (sourced
from the review findings files). Quote the completion notes verbatim; synthesise
only for status or framing. When both completion notes and review findings are
absent, write `No review iterations.` A review-findings path that could not be
read is noted as `review data was unavailable` rather than omitted.]

## What looks risky

[Adjacent issues spotted during the work — things that look wrong or fragile but
were deliberately left untouched (flag, do not fix). Empty if nothing was
flagged.]

## Status

[Overall status — `Implemented`, `Partial`, or `Deferred` — derived from
acceptance-criteria coverage assessed against the run diff: `Implemented` when
all acceptance criteria are met, `Partial` when some are met and some deferred,
`Deferred` when work is predominantly deferred or blocked. Follow with a
per-area / per-acceptance-criterion breakdown. This status is NOT a function of
the CI outcome (CI has always passed by the time this artefact is written) and
is never coupled to the availability or quality of the completion notes.]

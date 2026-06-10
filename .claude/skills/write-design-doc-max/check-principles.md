# check-principles

Shared principles, severity vocabulary, emission gate, and finding schema for every `write-design-doc-max` check agent. The `review-gate.js` workflow script's check agents each Read the full contents of this document themselves, ahead of their own rubric file and the assembled context. Apply these principles whether the artefact under review is a design document or a task spec.

## Standing principles

1. Read actual code before accepting claims about what exists.
2. Calibrate scepticism to the current review round (the per-round check-agent prompt declares which round you are on):
   - **Round 1** — bias toward finding problems. A review that finds nothing is suspicious; question harder and treat an empty return as a signal you have not looked hard enough.
   - **Round 2 or later** — the artefact has been revised in response to earlier rounds and should be converging. An empty findings array is valid and expected when the revisions genuinely resolved the earlier concerns; do not manufacture findings to avoid an empty return.
3. Be specific — "error handling might be incomplete" is useless; "the artefact doesn't address what happens when X returns Y" is actionable.
4. If you generated this artefact, be especially critical — an AI reviewer of its own output will find it harder to spot implicit assumptions baked in at generation time.

## Severity labels

Allowed: `Critical` / `High` / `Medium` / `Nit pick`
No other labels.

## Emission gate

Investigate as critically as the standing principles demand, but only **emit** a finding if fixing it would change the artefact the implementer produces. A finding that cannot state an artefact-affecting change in its `Why it matters` field is suppressed at source — do not emit it. This keys on artefact impact, not on severity: a substantive omission still emits, because it does change what the implementer builds; a prose-precision or enumeration-completeness nit that would not change the produced artefact does not.

## Load-bearing versus illustrative

Classify what a finding targets:

- **Load-bearing** — content the implementer acts on directly: a line range, a contract, a `Depends on:` clause, an acceptance criterion.
- **Illustrative** — content that explains or exemplifies: an enumeration, an example, prose.

A gap in load-bearing content is more likely to change the produced artefact than a gap in illustrative content. Use this distinction to populate the `Target` field of each finding.

## Routing heuristics

Two heuristics inform how a finding is weighted downstream. They are advisory inputs to the orchestrator's recommendation; a check agent only reports them, it never routes:

- **Severity** — `Critical` / `High` / `Medium` / `Nit pick`, per the severity vocabulary above.
- **Size of fix** — the agent's estimate of its own suggested resolution: `trivial` (one line/word) / `local` (one section) / `broad` (multi-section or structural). It is advisory: it never gates anything on its own, and only combines with severity to tune a recommendation.

## Output

List of findings. Each finding has these six fields, in this order:

- `Severity`: `Critical` / `High` / `Medium` / `Nit pick` — no other labels.
- `Issue`: the specific gap named — not a general concern.
- `Why it matters`: what changes in the artefact the implementer produces if the finding is fixed. If you cannot state an artefact-affecting change here, do not emit the finding (see the emission gate above).
- `Size of fix`: `trivial` (one line/word) / `local` (one section) / `broad` (multi-section or structural).
- `Target`: `load-bearing` (line range, contract, dependency, acceptance criterion) or `illustrative` (enumeration, example, prose).
- `Suggested resolution`: the actionable change.

Or empty list if no findings.

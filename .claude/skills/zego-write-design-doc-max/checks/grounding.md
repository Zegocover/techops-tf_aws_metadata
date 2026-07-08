# grounding

Check: every claim the document makes about the codebase is verified against the actual code; the approach fits the existing architecture and patterns; assumptions are identified, validated, and impact-assessed.

Steering compliance is NOT part of this check — it is owned by `steering-compliance`. Do not read or assess steering docs here.

## Primary document disambiguation

If task specs are present in the input alongside a design document:
- The task specs are the primary documents.
- Apply all criteria to every task spec; attribute each finding to the affected spec via the `Spec` field (the spec filename).
- Treat the design document as context only.

If only a design document is present (no task specs):
- The design document is the primary document.
- Apply all criteria to the design document. Leave `Spec` null.

## Inputs

- `requirements_source`: full text of the requirements source (context only)
- Primary document(s): full text of the document(s) under review (including `## Dismissals` if present)
- Codebase context: either a single context pack file (one `## {path}` heading per file, full content beneath) or an explicit list of codebase file paths — read it before assessing any claim about existing code

## Checks

**Codebase fit:**
- For every file, function, interface, or pattern the primary document references: confirm it exists and behaves as claimed, using the codebase context. Read before accepting any claim.
- Non-existent reference: raise Critical, naming the reference and the claim made about it.
- Interface mismatch (claimed vs actual signature or behaviour): raise Critical, naming both.
- Does the proposed approach fit the existing architecture and patterns? Name specific inconsistencies.
- Are there existing abstractions the document should reuse but doesn't? Name them.
- Does the approach introduce a pattern that conflicts with an established pattern in the codebase? Name both.

**Assumptions:**
- Enumerate every claim that depends on something being true that is not verified by the document itself: codebase claims ("X already exists", "Y behaves as Z"), environment claims, ordering claims ("A happens before B"), and external-party claims ("the API returns T").
- Implicit assumptions (implied by prose without acknowledgement) are higher-risk: raise a finding for each, regardless of whether it appears correct.
- Validate each assumption against the codebase context. If a referenced file supports it, state that it was verified. If it cannot be validated or is refuted, raise a finding naming the assumption and what was checked.
- For each assumption: what specifically breaks if it is wrong? Name the component, flow, and failure mode. An assumption whose failure mode is "undefined" is a finding.
- For every "X happens before Y" claim: is the ordering enforced, or just expected? Unenforced ordering is an implicit assumption — name the constraint and what enforces (or fails to enforce) it.

**Edge cases and interactions (design document only):**
- For each flow described in the design: are there edge cases (empty inputs, boundary values, concurrent operations, partial failures) not addressed? Name each one.
- Are there interactions between components in `## Components affected` that could produce unexpected states? Name them.
- Are there concerns or risks omitted from `## Risks and constraints`? Is each listed risk specific enough to act on? Vague risks that name no concrete failure mode are findings.

**Technical soundness (task specs only):**
- Race conditions: concurrent operations on shared state without stated synchronisation.
- Breaking changes: modifying an interface consumed by other components without flagging the breaking change.
- Severity: Critical for data loss/corruption risk, High for behavioural correctness, Medium for robustness gaps, Nit pick for style.

## Dismissals

Check the `## Dismissals` section of the design document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific gap in the same component. If the document or the relevant component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

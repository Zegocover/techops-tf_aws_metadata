# assumption-identification

Check: every assumption in the document under review is identified; implicit assumptions are flagged; each assumption's impact if wrong is assessed; ordering assumptions are explicitly called out.

## Primary document disambiguation

If a task spec is present in the input alongside a design document:
- The task spec is the primary document.
- Apply all criteria to the task spec.
- Treat the design document as context only.

If only a design document is present (no task spec):
- The design document is the primary document.
- Apply all criteria to the design document.

## Inputs

- `requirements_source`: full text of the requirements source (context only)
- Primary document: full text of the document under review (including `## Dismissals` if present)
- Codebase context files passed from SKILL.md — read them to validate specific claims before raising a finding

## Checks

**Enumerate all assumptions:**
- Read the primary document in full. Identify every claim that depends on something being true that is not verified by the document itself.
- Include: claims about the codebase ("X already exists", "Y behaves as Z"), claims about the environment ("the system will always have access to W"), claims about ordering ("A happens before B"), and claims about external parties ("the API returns T").

**Explicit vs implicit:**
- For each assumption: is it explicitly stated in the primary document, or is it implied by the prose without acknowledgement?
- Implicit assumptions are higher-risk. Raise a finding for every implicit assumption, regardless of whether it appears correct.

**Validation:**
- For each assumption: use the codebase context files to confirm or refute it.
- If a referenced file exists and supports the assumption: state that it was verified.
- If a referenced file cannot be read or does not support the assumption: raise a finding naming the unvalidated assumption and what was checked.

**Impact assessment:**
- For each assumption: what specifically breaks if the assumption is wrong? Name the component, the flow, and the failure mode.
- An assumption whose failure mode is "undefined" is a finding.

**Ordering assumptions:**
- For every "X happens before Y" claim in the primary document: is this ordering enforced by the design/implementation, or is it just expected?
- If just expected (no enforcement mechanism stated): it is an implicit assumption. Raise a finding naming the specific ordering constraint and what enforces (or fails to enforce) it.

## Dismissals

Check the `## Dismissals` section of the primary document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific assumption in the same component. If the primary document or the relevant component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

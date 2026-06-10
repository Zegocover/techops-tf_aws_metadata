# failure-handling

Check: every external call in the document under review has defined failure behaviour; retryable vs terminal failures are distinguished; no stuck states exist; all error types are handled distinctly.

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

## Checks

**External call coverage:**
- Enumerate every external call in the primary document: API calls, database operations, file system operations, message queue interactions, sub-agent invocations, and any operation that can fail independently of the calling code.
- For each: does the primary document state what happens when it fails? If not, raise a finding naming the specific call and the missing failure behaviour.

**Retryable vs terminal:**
- For each external call with a defined failure path: does the primary document distinguish between retryable failures (transient, safe to retry) and terminal failures (non-retryable, must surface to the caller)?
- If not distinguished: raise a finding naming the call and why the distinction matters.

**Stuck states:**
- Is there any flow where a failure leaves the system in a state from which neither the user nor an automated process can proceed without manual intervention?
- Name every such state explicitly.
- "Rollback on failure" is not sufficient — does the rollback itself have a defined failure path?

**Distinct error handling:**
- Are all error types and codes handled distinctly, or are multiple different errors lumped into a single catch-all handler?
- A catch-all that swallows errors without logging or surfacing them is always a finding.
- Name every case where two distinct error types are handled identically when they should have different recovery paths.

## Dismissals

Check the `## Dismissals` section of the primary document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific missing failure behaviour for the same external call. If the primary document or the relevant component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

# robustness-verifiability

Check: every external call has defined failure behaviour; retryable and terminal failures are distinguished; no stuck states exist; and every flow path and error case has a sound, order-aware, correctly-asserted test scenario.

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

## Checks

**Failure handling:**
- Enumerate every external call in the primary document: API calls, database operations, filesystem operations, message queue interactions, sub-agent invocations — any operation that can fail independently of the calling code. For each: is the failure behaviour stated? If not, raise a finding naming the call.
- For each call with a defined failure path: are retryable (transient) and terminal (must surface) failures distinguished? If not, name the call and why the distinction matters.
- Stuck states: is there any flow where a failure leaves the system unable to proceed without manual intervention? Name every such state. "Rollback on failure" is not sufficient — does the rollback itself have a defined failure path?
- A catch-all that swallows errors without logging or surfacing them is always a finding. Name every case where two distinct error types are handled identically when they need different recovery paths.

**Testability:**
- Enumerate every flow path (happy path, alternative paths, branching conditions). Each must be covered by a named test scenario; raise a finding per uncovered path.
- Every error case (failed external calls, invalid inputs, boundary conditions, partial failures) needs its own dedicated scenario — one scenario covering several error cases under one name is not adequate.
- Test soundness: could a scenario be satisfied by a stub or no-op, or pass for an incorrect implementation? Name it. Are any scenarios vague enough that multiple incorrect implementations would pass?
- Ordering constraints ("A must be called before B") need order-verifying scenarios — asserting "A and B were both called" does not verify order.
- Assertion correctness: assertions must verify the defined outcome, not a proxy ("function was called" when the outcome is "state X written to Y"; "non-null" when the outcome is "field Z = W"). Name every scenario whose assertions would pass for an incorrect implementation.

## Dismissals

Check the `## Dismissals` section of the design document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific missing failure behaviour or unsound scenario for the same call, flow, or error case. If the document or the relevant component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

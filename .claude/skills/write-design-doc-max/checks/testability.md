# testability

Check: every flow path has a named test scenario; every error case has its own test scenario; tests are sound; ordering constraints are testable; each test scenario's assertions verify the correct outcome.

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

**Flow path coverage:**
- Enumerate every flow path described in the primary document (happy path, alternative paths, branching conditions).
- For each: does the `## Test strategy` section (or equivalent testing section) name a test scenario that covers it?
- If any flow path has no named test scenario: raise a finding naming the specific path.

**Error case coverage:**
- Enumerate every error case defined in the primary document: failed external calls, invalid inputs, boundary conditions, partial failures.
- For each error case: does the testing section name a dedicated test scenario for it?
- A test scenario that tests multiple error cases under one name is not adequate — each distinct error case requires its own scenario.
- Raise a finding for every error case with no dedicated scenario.

**Test soundness:**
- For each named test scenario: could it be misconstrued — i.e., could an implementer write a test that satisfies the scenario description but does not actually verify the behaviour it claims to test?
- Could any scenario be trivially satisfied by a stub or no-op implementation? Name it.
- Are any scenarios so vague that multiple different (and possibly incorrect) implementations would pass?

**Ordering constraints:**
- For every ordering constraint in the primary document ("A must be called before B", "X must complete before Y begins"): is there a named test scenario that verifies the ordering specifically — not just that both were called, but that they were called in the correct order?
- A test that asserts "A and B were both called" does not verify ordering. Name every ordering constraint that has no order-verifying test.

**Assertion correctness:**
- For each named test scenario: do the described assertions verify the correct outcome as defined by the primary document?
- An assertion that checks "function was called" when the expected outcome is "state X was written to Y" is not correct.
- An assertion that checks "return value is non-null" when the expected outcome is "return value has field Z with value W" is not correct.
- Name every scenario where the assertions would pass for an incorrect implementation.

## Dismissals

Check the `## Dismissals` section of the primary document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific missing or unsound test scenario for the same flow or error case. If the primary document or the relevant component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

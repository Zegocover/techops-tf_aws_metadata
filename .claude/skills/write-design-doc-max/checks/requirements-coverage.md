# requirements-coverage

Check: every FR and AC in the requirements source is addressed in the design and covered in the testing strategy.

## Inputs

- `requirements_source`: full text of the requirements source (FRs, ACs, constraints)
- `design_document`: full text of the design document (including `## Dismissals`)

## Checks

For every functional requirement (FR) in `requirements_source`:
- Is it addressed somewhere in `design_document`? Name the FR and the design section that addresses it.
- If not addressed: raise a finding naming the specific FR.
- If only partially addressed: is this explicitly called out and justified in the design? If not, raise a finding.

For every acceptance criterion (AC) in `requirements_source`:
- Is it addressed in `design_document`?
- Is it covered in the `## Test strategy` section of `design_document`? A test scenario that does not reference the AC by name or substance is not coverage.
- If not addressed: raise a finding naming the specific AC.
- If not covered by test strategy: raise a finding naming the specific AC and the missing test scenario.

If `requirements_source` contains no explicitly labelled FRs or ACs, identify the functional obligations and acceptance expectations from the prose and apply the same checks.

## Dismissals

Check the `## Dismissals` section of `design_document`. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific gap in the same component. If the design or component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

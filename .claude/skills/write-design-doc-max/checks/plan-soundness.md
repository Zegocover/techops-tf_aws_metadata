# plan-soundness

Check: the approach fits the existing codebase, follows steering, edge cases are considered, and risks are documented.

## Inputs

- `requirements_source`: full text of the requirements source
- `design_document`: full text of the design document (including `## Dismissals`)
- Codebase context files: relevant files identified by SKILL.md — read them before assessing any claim about existing patterns or interfaces

## Checks

**Codebase fit:**
- For every component listed in `## Components affected` of `design_document`: read the referenced file or directory before accepting any claim about what it contains or how it behaves.
- Does the proposed approach fit the existing architecture and patterns? Name specific inconsistencies.
- Are there existing abstractions the design should reuse but doesn't? Name them.
- Does the approach introduce a pattern that conflicts with an established pattern in the codebase? Name both.

**Steering compliance:**
- Does the approach follow existing steering docs passed as context? Check each steering doc for rules the design approach would violate.
- Is there anything the design proposes that should be extracted as a new steering doc because it introduces a reusable pattern? Name it.

**Edge cases:**
- For each flow described in the design: are there edge cases (empty inputs, boundary values, concurrent operations, partial failures) not addressed? Name each one.
- Are there interactions between components described in `## Components affected` that could produce unexpected states? Name them.

**Risk documentation:**
- Are there concerns or risks the design omits from `## Risks and constraints`? Name each one.
- Is each risk in `## Risks and constraints` specific enough to act on? Vague risks that name no concrete failure mode are not useful.

## Dismissals

Check the `## Dismissals` section of `design_document`. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific gap in the same component. If the design or component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

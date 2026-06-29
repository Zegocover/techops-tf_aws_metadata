---
ticket: [TICKET]
branch: {TICKET}_{slug}
---

# Task: [TASK-NN] [Name]
Feature: [JIRA ticket or link to requirements]
Design: [docs/design/TICKET-slug.md]
Depends on: nothing / TICKET-TASK-NN-slug.md

<!-- Feature, Design, and Depends on are required header lines in the body,
     not frontmatter. They are enforced by convention, not by YAML parsing.
     Depends on: valid values:
       - The literal string "nothing" (no dependency)
       - The exact filename (not path) of a task spec in docs/tasks/,
         e.g. AIDEV-70-TASK-01-reformat-depends-on-header-in-template.md
     Any other value is an error. Do not use prose descriptions.
     branch: derived as {TICKET}_{slug} where slug is: lowercase task name,
     replace any run of non-alphanumeric characters with a single hyphen,
     trim leading/trailing hyphens, truncate to 40 characters (trim trailing
     hyphens after truncation). Example: "the-quick-brown-fox-jumps-over-the-lazy--dog"
     truncates to "the-quick-brown-fox-jumps-over-the-lazy-" then trims to
     "the-quick-brown-fox-jumps-over-the-lazy" (no trailing hyphen). -->

## Objective

[One sentence. What exists after this task that did not exist before.]

## Context

- [Where this task fits in the system — specific location, not general description]
- [Relevant existing pattern to follow — name file or function, not "follow conventions"]
- [Interface contract this task implements or consumes — reference Design Document section]
- [Any output from a dependency task that this task consumes — specific file or function]

## Implementation constraints

- Must follow [specific pattern] — see [file or ADR]
- Must not modify [specific file or component]
- Error handling: [specific approach — exception type, return value, or propagation rule]
- Logging: [what to log at which level; what must not be logged]
- PII: [specific handling rule, or "no PII in scope"]
- [Any constraint derived from conflict detection against existing standards]
- [Any constraint derived from external reference synthesis]

## Inputs and outputs

Inputs:
- [name]: [type] — [valid range or constraint; null handling; required vs optional]

Outputs:
- [name]: [type] — [what it contains; what "correct" looks like]

Errors:
- [ErrorType]: [condition that triggers it]

## Edge cases to handle explicitly

- [Edge case]: [required behaviour — not "handle gracefully", but the exact outcome]
- [Edge case]: [required behaviour]

## Out of scope

- [Thing Claude might reasonably add but must not]
- [Adjacent concern that belongs to a different task]

## Acceptance criteria

- [ ] [Binary-checkable criterion — passes or fails, no judgment required]
- [ ] [Binary-checkable criterion]
- [ ] [Criterion derived from external reference: output includes rule for X sourced from Y]
- [ ] [Criterion derived from conflict detection: output does not include rule that contradicts Z]

## Test requirements

- Unit tests: [specific functions or behaviours that must have unit test coverage]
- Edge cases: [which edge cases listed above require explicit test cases]
- [Do not write integration tests — those are TASK-XX] / [Integration tests: owned by this task]

## Definition of done

- Implementation passes all unit tests
- No hardcoded values
- Passes all language-specific linting and type-checking rules defined in CLAUDE.md
- Consistent with [specific pattern referenced in Context]

## Required output format

1. Implementation code
2. Test code
3. Completion notes:
   - What decisions were made that were not specified in this task spec
   - Any constraints in the spec that were ambiguous
   - Anything that could not be implemented as specified and why
   - Anything that looks wrong in adjacent code (flag, do not fix)

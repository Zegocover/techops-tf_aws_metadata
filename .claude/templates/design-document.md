# Design: [Feature name]
JIRA: [ticket]
Engineer: [name]
Requirements: [link to Artefact 1 — JIRA ticket, docs/requirements/ path, or "N/A"]
Date: [ISO 8601 date]
Branch: [branch name]

## Approach

High-level description of the implementation strategy. One to three paragraphs.

Explain why this approach was chosen over evident alternatives. What problem
does it solve and how? What is the high-level shape of the change?

This section should give a reader who knows the codebase enough context to
understand every subsequent section without needing to look things up.

## Components affected

**Existing (modified):**
- `path/to/component` — brief description of what changes and why

**New (created):**
- `path/to/new/component` — purpose and responsibility

List all services, modules, classes, and files that will be touched or created.
Be specific enough that the task breakdown can reference them by name.

## Interface contracts

For each new or modified interface:

### [InterfaceName]

Input: [types, valid ranges, null handling, required vs optional]
Output: [types, constraints, what "success" looks like]
Errors: [explicit error types and the conditions that trigger them]
Side effects: [state changes, events emitted, external calls made — "none" if none]

Repeat this block for every interface. If no interfaces are new or modified,
write "No new or modified interfaces."

## Task breakdown

Ordered list of tasks with dependencies. Each task must be independently
implementable by an AI agent from a single task spec.

TASK-01: [name] — no dependencies
TASK-02: [name] — depends on TASK-01 (needs [specific output or artefact])
TASK-03: [name] — depends on TASK-01, parallel with TASK-02

Rules:
- Each task name is specific enough to derive a unique slug.
- Dependencies name the specific output or artefact needed, not just the task.
- At least one task is required.

## Test strategy

Integration test owner: [which task or tasks own integration tests]
E2E approach: [scope, tooling, environments — "N/A" if no E2E tests]
Cross-task constraints: [shared fixtures, test data, ordering — "none" if none]

Describe how the tasks fit together in the test picture. Which task is
responsible for ensuring the whole feature works end-to-end? Are there
ordering constraints between test suites?

## Risks and constraints

What could go wrong. What Claude must not do. Anything that needs extra
attention during implementation or validation.

- [Risk or constraint]: [why it matters and what the mitigation or rule is]
- [Risk or constraint]: [why it matters and what the mitigation or rule is]

Include external interface risks, behavioural constraints inherited from
product requirements, and any "must not touch" boundaries.

## ADR references

Existing decisions that constrain this design:
- [docs/decisions/NNN-name.md] — [one sentence on how it constrains this design]

New decisions being made (create ADR if significant):
- [proposed ADR title] — [one sentence on the decision being recorded]

If no ADR references apply, write "No ADR references."

# Feature: {Feature Name}

| Field   | Value          |
|---------|----------------|
| JIRA    | {TICKET-NNN}   |
| Author  | {product owner} |
| Date    | {YYYY-MM-DD}   |

## Problem statement

{What user need does this address? One paragraph, no solution language.}

## Scope

### Included

{What is in scope for this feature. Bullet list of capabilities being delivered.}

### Excluded

{What is explicitly not in scope. Bullet list of things that might be assumed but are not part of this work.}

## User journey

{Narrative description of the experience from the user's perspective. No implementation language — behaviour only. Walk through the flow step by step, describing what the user sees and does at each point.}

## Functional requirements

{Numbered requirements. Each requirement starts with a verb, is independently testable, and makes no implementation assumptions.}

- **FR-01:** {Verb-first, specific, testable requirement}
- **FR-02:** {Verb-first, specific, testable requirement}

## Acceptance criteria

{Gherkin format. Each criterion is linked to a functional requirement by ID.}

- **AC-01 (FR-01):** Given {context}, when {action}, then {outcome}
- **AC-02 (FR-01):** Given {context}, when {action}, then {outcome}
- **AC-03 (FR-02):** Given {context}, when {action}, then {outcome}

## Edge cases and error states

{Explicit enumeration of non-happy-path scenarios. Each with expected behaviour.}

| # | Scenario | Expected behaviour |
|---|----------|--------------------|
| 1 | {Description of edge case or error state} | {What the system does} |
| 2 | {Description of edge case or error state} | {What the system does} |

## Non-functional requirements

{Performance, security, compliance constraints. Specific and measurable — not "it should be fast."}

- **NFR-01:** {Specific, measurable non-functional requirement}
- **NFR-02:** {Specific, measurable non-functional requirement}

## Open questions

{Anything product hasn't resolved yet. Engineering should not start design until these are closed or explicitly acknowledged as blockers.}

| # | Question | Status | Resolution |
|---|----------|--------|------------|
| 1 | {Unresolved question} | Open | — |
| 2 | {Unresolved question} | Open | — |

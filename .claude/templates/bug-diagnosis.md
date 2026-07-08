---
ticket: [TICKET]
---

> **AI-native artefact.** Human reviewers do not need to read this; the review surface for this phase is the {surface} at {link}.

# Bug diagnosis: [TICKET] [Ticket summary]

JIRA: https://zegons.atlassian.net/browse/[TICKET]

<!-- Lightweight institutional memory, nothing more. Records in docs/bugs/
     are durable: exempt from the periodic task-spec collapse policy and
     never reaped with the spec. Interface contracts, alternatives, and
     trade-off analysis belong to write-design-doc, not here — a record
     that seems to need them suggests the fix trips a fix-bug size-gate
     criterion: return to Stage 4 and re-run the gates. If no criterion
     fires on re-run, cut the record to this template's sections and
     proceed. -->

## Root cause

[The specific defect at a specific location, with file:line evidence.
Explain why the invalid state arises, not merely where it is observed —
a symptom description is not a root cause.]

## Reproduction

[The test name or command that demonstrates the failure, and the failure
it produces. This must be the failure the ticket describes, watched
failing — not assumed.]

## Hypotheses

- **Surviving:** [The hypothesis the evidence confirmed.]
- **Falsified:** [Each competing hypothesis, with the specific evidence
  that falsified it — "we already ruled out X for this class of failure"
  is the forward-looking value of this record.]

## Size gate

<!-- Only when the fix-bug size gate fired. Delete this section if it never
     fired. -->

[The size-gate criterion that fired and the evidence behind it, and the
outcome: awaiting the engineer's decision (recorded when the gate fires,
before they reply); escalated to write-design-doc — note any work parked
uncommitted on the branch for the design doc to draw on; or waved through
by the engineer, who judged the size signal a false alarm in context.]

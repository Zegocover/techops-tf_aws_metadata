---
version: 1.0
last_reviewed: 2026-05-18
---

# Frontend Ticket Specification Standards

Conventions for writing frontend Jira tickets that an autonomous AI agent can implement end-to-end without human steering during development. The governing philosophy is: every ambiguity that is not resolved before the agent starts is a context switch waiting to happen — resolve it upfront. Apply these rules when writing or refining any frontend ticket in `zego-web` (onboarding-web), `customer-acquisition` (acquisition-web), `checkout-mfe`, `my-zego`, or `zego-utils`, before the ticket moves to In Progress. Ticket authoring conventions that apply to all teams are not covered here.

## Rules at a Glance

1. **Figma node ID before In Progress.** Every ticket that touches UI must reference the exact Figma node ID(s) before the agent starts — a vague Figma link is not sufficient; the agent cannot resolve design ambiguity mid-implementation without stalling.
2. **Scope boundary is surgical.** State explicitly what this ticket covers and what it does not, including things the agent might reasonably add but must not — routing changes, adjacent screens, API integration if not in scope — because agents are thorough by default.
3. **Data contract fully specified.** Every field the UI must render must have a source path, type, and null-handling rule — agents must not guess data shapes, invent fallbacks, or default to hardcoded values when session data is absent.
4. **Acceptance criteria are binary.** Each criterion must pass or fail without human judgment — "looks good" and "matches design" are not valid criteria; "matches Figma node 6554-63136 at breakpoints 375px and 1280px" is.
5. **Existing components named explicitly.** When the ticket requires reusing or extending an existing component, name it by its exact import path — agents waste cycles discovering the component tree if this is omitted.
6. **No open questions at start.** Any open question in the ticket description must be resolved and the answer recorded in the ticket before the agent picks it up — an unresolved question is a guaranteed mid-implementation stall.
7. **One screen or one component per ticket.** Tickets that span multiple screens or introduce multiple independent components must be split — a ticket the agent cannot complete in a single uninterrupted session will produce a stalled or oversized PR.
8. **Test requirement is explicit.** State exactly which behaviours require test coverage and at which level (unit / component / e2e:mock) — "add tests" is not sufficient; the agent needs to know what to test, not just that tests are expected.

## Figma node ID before In Progress

A Figma link to the file root gives the agent the entire file to navigate, which is expensive and imprecise. A node ID (`?node-id=6554-63136`) pins the agent to the exact frame — spacing, token usage, responsive behaviour, and component hierarchy are all unambiguous. Without it, the agent must infer design intent from context, which produces inconsistency.

```markdown
# good
**Figma:** https://www.figma.com/design/I2sehqDcrR3XrKaBj2LHxe/...?node-id=6554-63136

# bad — agent must navigate the entire file to find the relevant frame
**Figma:** https://www.figma.com/design/I2sehqDcrR3XrKaBj2LHxe/Renewals
```

## Scope boundary is surgical

An agent that is not given an explicit boundary will implement everything that seems related. This is not a bug — it is the agent doing its job correctly given incomplete information. The out-of-scope list is the mechanism for communicating the boundary, not a formality. Be specific about adjacent concerns an agent is likely to reach for: routing wires itself up naturally from a new screen, API calls seem necessary once a data shape exists, adjacent components look incomplete without the new one.

```markdown
# good
**In scope:** Add the review section above the existing `<Section>` for card details.
**Out of scope:** Changes to the Stripe form, submit logic, routing, or any screen other than `payment-single-screen.svelte`.

# bad — no boundary stated; agent may refactor adjacent code, add a route, or extend the API call
**What:** Implement the review premium section.
```

## Data contract fully specified

The frontend often renders data that comes from a session envelope or API response. An agent that is not told the exact source path will either hardcode a value, render nothing, or write a best-guess accessor that breaks at runtime. Hardcoded display values are a silent bug: the component passes visual review but fails the moment real data differs from the placeholder. Specify the path, the TypeScript type, and what to do when the value is absent.

```markdown
# good
| Field          | Path                                              | Type              | Null handling                               |
| -------------- | ------------------------------------------------- | ----------------- | ------------------------------------------- |
| Annual premium | `envelope.data.quotes?.[0]?.price?.annual?.total` | `Money`           | Omit section if absent; do not default to 0 |
| Start date     | `envelope.data.cover?.startDate`                  | `string` (ISO date) | Omit row if absent                        |

# bad — agent must guess the shape or may default to a hardcoded fallback
Display the annual premium and start date from the session data.
```

## Acceptance criteria are binary

Criteria that require judgment introduce a review cycle. The reviewer has to decide whether the criterion is met; if they decide it is not, the agent gets a `CHANGES_REQUESTED` and another round begins. Criteria that are objectively checkable close that loop before it opens.

```markdown
# good
- [ ] Section is absent (not an error state) when `cover` or `quotes` is null or empty
- [ ] Annual premium rendered using `formatCurrencyLabel` — not a raw number
- [ ] Layout matches Figma node 6554-63136 at 375px and 1280px viewport widths

# bad — requires human judgment to evaluate
- [ ] Section looks correct
- [ ] Premium is displayed properly
```

## Existing components named explicitly

The component tree in these repos is large. An agent asked to "use the existing summary card" will search, find multiple candidates, and either pick the wrong one or ask a clarifying question mid-task. Name the component by its import path — the agent can then open the file, read its interface, and use it correctly on the first attempt.

```markdown
# good
Reuse `src/components/policy/PolicySummaryCard.svelte` for the summary block.
Extend `src/components/shared/FormField/FormField.svelte` — do not create a new wrapper.

# bad — agent must guess which component is intended
Use the existing summary card component.
Add a form field using the shared component.
```

## No open questions at start

An open question in a ticket is a mid-implementation interrupt waiting to happen. When the agent hits it, work stops: the agent either blocks (best case) or makes an assumption that requires a rework cycle to correct (common case). Every question in the description must have a recorded answer before the ticket moves to In Progress — not "to be confirmed", not "ask design".

```markdown
# good
**Q: Should the section be shown for monthly policies as well?**
**A: Yes — show for all payment frequencies. Confirmed with design 2026-05-14.**

# bad — agent must either block or guess
**Open question:** Should this section be shown for monthly policies too?
```

## One screen or one component per ticket

Tickets that span two screens or introduce two independent components create PRs that reviewers cannot meaningfully approve in a single pass. The reviewer has to context-switch between concerns, which increases the chance of missed issues and extends the review cycle. Split the ticket — the overhead of an extra ticket is lower than the overhead of a bloated PR.

If two tickets have a dependency (component B needs component A to exist), express it in the `Depends on:` field of the task spec, not by combining them into one ticket.

## Test requirement is explicit

"Add tests" tells the agent nothing about what to verify, at which layer, or what coverage is considered complete. An agent left to decide this autonomously will either under-test (only the happy path) or over-test (snapshot tests for every state). State the behaviours to cover and the level at which to cover them.

```markdown
# good
- Unit: `formatPremiumSection` returns `null` when `quotes` is empty or absent
- Component: section renders with correct label and formatted value when data is present
- Component: section is absent (not hidden, not zero) when `quotes[0].price` is null
- e2e:mock: full payment screen renders without the section when the session fixture has no quotes

# bad — agent decides scope and level
Add tests for the premium section.
```

## See Also

- [../base/pull-requests.md](../base/pull-requests.md) — PR conventions that apply once the agent has implemented the ticket.
- [../base/testing.md](../base/testing.md) — testing principles that inform the test requirement field.

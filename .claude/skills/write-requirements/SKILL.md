---
name: write-requirements
description: You MUST use this when the user asks to collect or document requirements from a product owner or PM.
model: claude-opus-4-8
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - mcp__claude_ai_Atlassian__getJiraIssue
---

You are the orchestrator for `/write-requirements`. Collect requirements
from the user and produce a structured Requirements Package. When a Jira
ticket is provided, pre-populate sections from the ticket description,
assess extraction quality per section, and only skip the interview for
sections with solid, directly-stated content. Sections that are thin
(inferred from unstructured prose) or empty are routed into the interview
so that gaps are surfaced rather than silently accepted.

---

## Stage 1 — Ticket, metadata, and branch setup

Ask:

> What is the JIRA ticket for this feature? (e.g. PROJ-123)

Record the ticket.

Ask:

> What is the feature name? (short, descriptive — e.g. "Driver onboarding
> redesign")

Record the feature name. Derive a kebab-case slug from it (e.g.
`driver-onboarding-redesign`). The output path will be
`docs/requirements/{TICKET}-{feature-slug}.md`.

Ask:

> Who is the author of this requirements package? (e.g. "Jane Smith,
> Product Manager")

Record the author.

**Branch setup.** Check the current branch:

```bash
git branch --show-current
```

Match the branch name against `^{TICKET}[_-]` (anchored with a separator
to avoid partial matches like `AIDEV-2` matching `AIDEV-28_…`). If it
matches, confirm and continue.

If it does not match, offer to create or switch to the correct branch:

> The current branch is `{branch}`, which doesn't match ticket `{TICKET}`.
> I can create or switch to `{TICKET}_{feature-slug}`. Proceed? [y/n]

If the user confirms, run:

```bash
.claude/scripts/req-branch.sh {TICKET} {feature-slug}
```

If the user declines, continue on the current branch without switching.

**Prior-run check.** Check whether a requirements package already exists
at the output path:

```bash
test -f docs/requirements/{TICKET}-{feature-slug}.md && echo "EXISTS" || echo "NEW"
```

If it exists, tell the user:

> I found an existing requirements package at
> `docs/requirements/{TICKET}-{feature-slug}.md`. Start fresh
> (overwrite), or continue from the existing content?

If continuing: read the existing file, summarise what it contains, and
ask what they want to change. Skip to Stage 11 to re-confirm.
If starting fresh: continue to Stage 2.

---

## Stage 2 — Pre-populate from Jira

Attempt to fetch the Jira ticket description. Use the Atlassian MCP
tools if available (`getJiraIssue` with `responseContentFormat: markdown`).
If the fetch fails (network error, authentication failure, or ticket
does not exist), continue to Stage 3 for the full interview.
If the fetch succeeds but the description is empty, null, or not
substantive, continue to Stage 3 for the full interview.
If MCP tools are not available, ask the user:

> Can you paste the Jira ticket description? Or type "skip" to go
> through the full interview instead.

If the user types "skip" or pastes content that is not substantive,
continue to Stage 3 for the full interview. If the pasted content is
substantive, treat it as the ticket description and proceed with
extraction below.

A description is **substantive** if it contains identifiable
requirements, user flows, or structured content that maps to at least
one section of the Requirements Package. A title restatement, a single
vague sentence, or boilerplate with no actionable content is not
substantive.

If the description is substantive, extract what you can into each
section of the Requirements Package:

- **Problem statement** (Stage 3) — opening paragraph or summary,
  stripped of solution language
- **Scope** (Stage 4) — any included/excluded items mentioned
- **User journey** (Stage 5) — any step-by-step flow described. Strip
  implementation language (API endpoints, database tables, service
  names) during extraction, as in Stage 5.
- **Functional requirements** (Stage 6) — testable statements, bullet
  points, or numbered items. Number them FR-01, FR-02, etc. Rewrite to
  start with a verb if needed and strip implementation assumptions, as
  in Stage 6.
- **Acceptance criteria** (Stage 7) — any Gherkin or Given/When/Then
  patterns. Link each to an FR. If the ticket has no explicit ACs, or
  if Functional requirements extraction produced no content, leave this
  section empty — the completeness gate will flag missing ACs.
- **Edge cases and error states** (Stage 8) — any error or boundary
  scenarios mentioned
- **Non-functional requirements** (Stage 9) — any performance, security,
  or compliance constraints
- **Open questions** (Stage 10) — any items marked as TBD, unresolved,
  or needing input

Apply the same quality checks as the interview stages during extraction:
each FR must be independently testable (Stage 6 criteria) and each NFR
must be specific and measurable (Stage 9 criteria). FRs or NFRs that are
directly stated in the ticket but fail these checks should be classified
as Thin rather than Solid during the gap assessment.

**Gap assessment.** After extraction, classify every section into one
of three tiers:

| Tier | Meaning | Action |
|------|---------|--------|
| **Solid** | Section has specific, testable content directly stated in the ticket | Present as-is for confirmation |
| **Thin** | Content was inferred or paraphrased from unstructured prose — plausible but not explicitly stated | Present with a ⚠ marker and flag for interview |
| **Empty** | Nothing in the ticket maps to this section | Flag for interview |

If a section has mixed quality (e.g. Scope with solid inclusions but no
exclusions, or Functional requirements where some items are explicit and
others reverse-engineered), classify the entire section as Thin and note
which sub-parts need attention during the interview. This is
intentionally conservative — it is better to re-confirm solid sub-parts
than to skip review of thin ones.

Section-specific guidance for Solid vs Thin:
- **Problem statement** — Solid if it clearly articulates a user need
  without solution language. Thin if the problem had to be inferred
  from solution-oriented or implementation-focused text.
- **Scope** — Solid if both inclusions and exclusions are explicitly
  listed. Thin if only one side is stated or items had to be inferred
  from a general description.
- **User journey** — Solid if the ticket describes the flow step by
  step with enough detail to reproduce. Thin if the journey had to be
  reconstructed from scattered references across the ticket.
- **Functional requirements** — Solid if the ticket lists explicit,
  verb-first, independently testable requirements. Thin if requirements
  had to be reverse-engineered from a narrative description.
- **Acceptance criteria** — Solid if the ticket contains explicit
  Gherkin or Given/When/Then blocks linked to requirements. Thin if
  ACs had to be inferred, or if their linked FRs are Thin. Empty if
  the ticket contains no AC-like content, or if FRs are Empty.
- **Edge cases and error states** — Solid if the ticket enumerates
  specific scenarios with expected behaviour. Thin if edge cases had
  to be inferred from the happy-path description.
- **Non-functional requirements** — Solid if the ticket states specific,
  measurable constraints (e.g. "p95 < 200ms"). Thin if constraints are
  vague or inferred from context.
- **Open questions** — Solid if the ticket explicitly marks items as
  TBD or unresolved. Thin if questions had to be inferred from gaps
  or ambiguities in the description.

In addition to the section-specific criteria above, the following
cross-cutting rules apply:

- A section is **Thin** when the ticket description is unstructured
  prose and the section content was inferred rather than directly
  stated, or when the extracted content is a single vague sentence that
  would fail the quality checks applied during extraction.
- **FR → AC dependency:** if Functional requirements are Thin, any
  acceptance criteria linked to those requirements are also Thin,
  regardless of whether the ACs were explicitly stated in the ticket,
  because the underlying requirements may change during the interview.
  If some ACs are linked to Solid FRs and others to Thin FRs, the
  mixed-quality rule applies — classify the entire AC section as Thin.
- **FR Empty → AC Empty:** if Functional requirements are Empty, any
  extracted acceptance criteria are also Empty, since there are no
  confirmed requirements to link them to.

If all sections are Empty after classification (unlikely if the
substantive check passed, but guards against extraction producing no
content that survives quality checks), skip the presentation and
extraction summary — continue to Stage 3 for the full interview.

Otherwise, present the pre-populated draft section by section. For each
section, show the extracted content and the tier label. After all
sections, show a summary:

> **Extraction summary**
>
> Solid: {list of solid sections}
> Thin (draft content to review and expand): {list of thin sections}
> Empty (will interview from scratch): {list of empty sections}

Omit any tier line that has no sections.

If there are gaps (any section is Thin or Empty), add:

> I'll confirm the solid sections with you, then we'll interview for
> the gaps.

If there are no gaps, add:

> All sections look solid. I'll ask you to review and confirm.

If there are **no gaps** (every section is Solid):

- Ask the user to review and confirm or flag changes.
- If the user **confirms**: run the completeness gates — verify every
  FR has at least one linked AC (Stage 7 gate) and classify any open
  questions as blocker or informational (Stage 10 classification).
  Completeness gates apply even to Solid sections — a gate failure
  means the section needs more content regardless of its tier.
  If all gates pass, skip to Stage 11 for final review. If any gate
  fails (e.g. FRs without ACs), jump to the relevant interview stage
  to collect the missing content, re-run the completeness gates, then
  return to Stage 11 for final review.
- If sections **need changes**: jump to the relevant interview stage
  (3–10), collect changes, re-run the completeness gates, then return
  to Stage 11 for final review.

If there **are gaps** (any section is Thin or Empty):

- Ask the user to review the Solid sections and confirm each is correct
  or note changes needed. If the user requests changes to a Solid
  section, add it to the gap list as Thin (with the existing content as
  the starting point) and interview for it in stage order with the
  other gaps.
- Then, enter the interview for **each gap section in stage order**
  (Stages 3–10). For **Thin** sections, present the inferred content
  as a starting point and ask the user to confirm, correct, expand, or
  replace entirely. If replacing, run the full interview prompt for that
  stage as if it were Empty.
  For **Empty** sections, run the full interview prompt for that stage.
  If Functional requirements are Solid but Acceptance criteria are a
  gap, the FRs will already be confirmed during the Solid-section
  review above — proceed directly to Stage 7 to iterate over those
  finalised requirements.
- After all gaps are covered, run the completeness gates (Stage 7:
  every FR has at least one AC; Stage 10: blocker classification), then
  proceed to Stage 11.

---

## Stage 3 — Problem statement

Ask:

> Describe the user need this feature addresses. Focus on the problem, not
> the solution. One paragraph, no implementation language.

Record the response. If it contains solution language (mentions specific
technologies, UI components, or implementation details), point out the
solution language and ask the user to restate in terms of the user's need.

---

## Stage 4 — Scope

Ask:

> What is in scope for this feature? List the capabilities being delivered.

Then:

> What is explicitly out of scope? List things that might be assumed but
> are not part of this work.

Record both lists. If the exclusion list is empty, prompt:

> Are there any adjacent features or capabilities that someone might
> expect but are not part of this work? Explicit exclusions prevent
> scope creep.

---

## Stage 5 — User journey

Ask:

> Walk me through the user journey step by step. Describe what the user
> sees and does at each point — behaviour only, no implementation
> language.

Record the narrative. If it contains implementation language (API
endpoints, database tables, service names), point it out and ask the user
to restate in behavioural terms.

---

## Stage 6 — Functional requirements

Ask:

> List the functional requirements. Each requirement should:
> - Start with a verb (display, calculate, store, return, prevent)
> - Be independently testable
> - Make no implementation assumptions
>
> I will number them FR-01, FR-02, etc.

Record each requirement. Number them sequentially. For each one, check:

1. Does it start with a verb? If not, suggest a rewrite.
2. Is it testable? If it is vague (e.g. "handle errors gracefully"),
   ask for specifics.
3. Does it assume implementation? If it names a technology or internal
   component, ask the user to restate without that assumption.

When the user indicates they are done, confirm:

> I have {N} functional requirements (FR-01 through FR-{NN}). Are these
> complete, or do you want to add more?

---

## Stage 7 — Acceptance criteria

For each functional requirement, ask:

> For FR-{NN} ("{requirement text}"), what are the acceptance criteria?
> Use Gherkin format:
>   Given [context], when [action], then [outcome]
>
> Each FR needs at least one AC. Multiple ACs per FR are encouraged for
> complex requirements.

Number them AC-01, AC-02, etc., with the linked FR in parentheses:
`AC-01 (FR-01)`.

**Completeness gate:** Every FR must have at least one linked AC. If any
FR is missing an AC after the user indicates they are done, list the
uncovered FRs and ask:

> The following functional requirements do not have acceptance criteria
> yet:
> {list of uncovered FRs}
>
> Each FR needs at least one AC before I can produce the document.
> Let's cover them now.

Do not proceed to the next stage until every FR has at least one AC.

---

## Stage 8 — Edge cases and error states

Ask:

> What are the edge cases and error states? For each non-happy-path
> scenario, describe:
> 1. The scenario
> 2. The expected behaviour
>
> Think about: invalid input, missing data, concurrent access, timeouts,
> permission boundaries, and boundary values.

Record each edge case with its expected behaviour. If the user provides
fewer than two, prompt:

> Most features have several edge cases. Consider what happens when:
> - Required data is missing or malformed
> - The user does not have permission
> - An external dependency is unavailable
> - Values are at their boundaries (zero, maximum, empty)
>
> Any of these apply?

---

## Stage 9 — Non-functional requirements

Ask:

> Are there non-functional requirements? These cover performance,
> security, compliance, scalability, or availability constraints.
>
> Each should be specific and measurable — "response time under 200ms at
> p95" not "it should be fast."

Record each NFR. Number them NFR-01, NFR-02, etc. If any are vague,
ask for a specific, measurable threshold.

If the user has none, record the section as "None identified." and
continue.

---

## Stage 10 — Open questions

Ask:

> Are there any unresolved questions? These are items product hasn't
> decided yet, or areas where engineering input is needed before design
> can start.

Record each open question with status "Open".

Then ask:

> For each open question, is it a blocker (engineering cannot start
> design without an answer) or informational (nice to resolve but not
> blocking)?

Mark blockers explicitly. If there are no open questions, record the
section as "None." and continue.

**Completeness gate:** If any open question is marked as a blocker, warn:

> There are {N} blocking open questions. The requirements package will
> include them, but engineering should not start design until they are
> resolved or explicitly acknowledged.

---

## Stage 11 — Review and confirm

Present a summary of everything collected:

> **Requirements Package Summary**
>
> **Feature:** {feature name}
> **Ticket:** {ticket}
> **Output path:** `docs/requirements/{TICKET}-{feature-slug}.md`
>
> **Problem statement:** {first sentence}...
> **Scope:** {N} inclusions, {N} exclusions
> **Functional requirements:** FR-01 through FR-{NN}
> **Acceptance criteria:** {N} ACs covering all {N} FRs
> **Edge cases:** {N} scenarios
> **Non-functional requirements:** {N} NFRs (or "None identified")
> **Open questions:** {N} ({M} blockers)
>
> Ready to generate the document? (yes / no — let me change something)

If the user wants changes, return to the relevant stage, collect the
changes, then **re-run all completeness gates** before regenerating the
summary:

- If FRs were added or removed: re-enter Stage 7 to ensure every FR
  (including new ones) has at least one linked AC, and remove any ACs
  whose FR no longer exists.
- If ACs were added or removed: re-check the Stage 7 completeness gate.
- If open questions were added, removed, or changed: re-run the
  Stage 10 blocker classification.

Present the summary again once all gates pass.

---

## Stage 12 — Generate the document

Read the template at `.claude/templates/requirements-package.md`.

Create the directory if it does not exist:

```bash
mkdir -p docs/requirements
```

Produce the Requirements Package at `docs/requirements/{TICKET}-{feature-slug}.md`
using the template structure. Fill every section with the collected
content. Do not leave any placeholder text — every section must contain
the actual content from the interview.

Metadata fields:
- Feature name from Stage 1
- JIRA ticket from Stage 1
- Author from Stage 1
- Date: today's date in YYYY-MM-DD format

Tell the user:

> Requirements package written to `docs/requirements/{TICKET}-{feature-slug}.md`.

---

## Stage 13 — Commit, push, and open PR

Ask the user:

> Requirements package is ready. Would you like me to commit it, push the
> branch, and open a PR for Engineering to review? (yes / no)

If the user declines, stop — the document is already written to disk.

If the user confirms:

**Step 1 — Confirm pending changes.** Run:

```bash
git status --porcelain
```

Print the output and ask:

> The requirements file at `docs/requirements/{TICKET}-{feature-slug}.md`
> will be committed and pushed. Any other pending changes shown above
> will NOT be included. Confirm to proceed, or stop if anything looks
> unexpected.

Wait for the user's response. If the user stops, halt and report which
files were pending. If the user confirms, continue.

**Step 2 — Compose the commit message.** Write a prose commit message to
a temporary file:

```bash
cat > /tmp/req-commit-msg-{TICKET}.txt <<'MSG'
{TICKET}: Add requirements package for {feature name}

Requirements package covering {N} functional requirements, {N} acceptance
criteria, and {N} edge cases for {feature name}. Collected via the
/write-requirements skill for Engineering review and sign-off.

Co-Authored-By: Claude <noreply@anthropic.com>
MSG
```

The first line is the subject (`{TICKET}: Add requirements package for
{feature name}`, ≤70 characters). The body is a prose paragraph
describing the artefact's scope — not a bullet list.

**Step 3 — Derive the Changes section.** Use the `git status --porcelain`
output from Step 1 to write one verb-first bullet per meaningful change.
Each bullet opens with an imperative verb (Add, Remove, Update). For a
single requirements file, this will typically be:

```
- Add requirements package at `docs/requirements/{TICKET}-{feature-slug}.md`
```

**Step 4 — Check for a PR template.** Run:

```bash
test -f .github/PULL_REQUEST_TEMPLATE.md && echo "PRESENT" || echo "ABSENT"
```

- **PRESENT** — read `.github/PULL_REQUEST_TEMPLATE.md`. Use its section
  headings as the skeleton for the PR body. Fill in each section with the
  content below. Discard any template sections not covered by the three
  standard sections (Background, Changes, Jira Ticket/s).
- **ABSENT** — use the three-section structure directly.

**Step 5 — Write the PR body.** Write the PR body to a temporary file.
The body must contain **exactly three sections**:

1. `## Background` — one or two sentences: why this requirements package
   exists and that it was collected via `/write-requirements`.
2. `## Changes` — the verb-first bullet list from Step 3.
3. `## Jira Ticket/s` — one bullet: `https://zegons.atlassian.net/browse/{TICKET}`

```bash
cat > /tmp/req-pr-body-{TICKET}.md <<'BODY'
## Background

Requirements package for {feature name}, collected via the `/write-requirements` skill for Engineering review and sign-off.

## Changes

{verb-first bullet list from Step 3}

## Jira Ticket/s

- https://zegons.atlassian.net/browse/{TICKET}
BODY
```

**Step 6 — Run the PR script.**

```bash
.claude/scripts/req-pr.sh {TICKET} docs/requirements/{TICKET}-{feature-slug}.md /tmp/req-pr-body-{TICKET}.md /tmp/req-commit-msg-{TICKET}.txt
```

**Step 7 — Report the result.**

> PR opened: {PR URL}
>
> Engineering can review the requirements package and sign off before
> design begins.

If the script exits with a non-zero status, report the error verbatim.
Do not retry. If the error is from `gh pr create` (the commit and push
already succeeded), tell the user they can open the PR manually from
the branch.

---

## Rules

- **Do not generate the document until all completeness gates pass.**
  Every FR must have at least one linked AC. Every open question must
  be either resolved or explicitly acknowledged.
- **Do not invent content.** Every section comes from the user — either
  via the Jira ticket they provided or from the interview. If
  information is missing, ask for it — do not fill in defaults or make
  assumptions beyond what the ticket description contains.
- **Challenge solution language.** Problem statements, scope, and user
  journeys must describe behaviour, not implementation. Push back when
  the user uses technology names, API endpoints, or database concepts.
- **Challenge vague requirements.** "Handle errors gracefully" is not
  testable. "Return a 404 response when the resource does not exist" is.
  Ask for specifics when requirements are not independently testable.
- **Challenge vague NFRs.** "It should be fast" is not measurable.
  "Response time under 200ms at p95" is. Ask for thresholds.
- **Number everything consistently.** FR-01, FR-02; AC-01 (FR-01),
  AC-02 (FR-01); NFR-01, NFR-02. Sequential, no gaps.
- **Use the template.** The output must follow the structure in
  `.claude/templates/requirements-package.md` exactly. Do not add or remove
  sections.

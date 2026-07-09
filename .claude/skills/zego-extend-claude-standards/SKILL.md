---
name: zego-extend-claude-standards
description: You MUST use this when the user asks to deepen, update, or fill gaps in the repository context section of CLAUDE.local.md.
model: claude-opus-4-8
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

You are running the `zego-extend-claude-standards` skill. You read an existing
`CLAUDE.local.md`, classify the 10 canonical repository context topics as
present, thin, or absent, present a gap summary, interview the engineer for
thin and absent topics, and merge confirmed answers back into the file.

This skill is collaborative, not adversarial. You ask, record, and format.
You do not challenge the engineer's answers or verify claims against the
codebase.

---

## Stage 1 — Validate input

Check whether `CLAUDE.local.md` exists at the repository root:

```bash
test -f CLAUDE.local.md && echo "EXISTS" || echo "ABSENT"
```

- **ABSENT**: display the following error and stop. Do not create the file.

  > No `CLAUDE.local.md` found. Run `init-claude-standards` first to
  > bootstrap this repository, or create `CLAUDE.local.md` manually.

- **EXISTS**: read the file in full with the Read tool.

Check whether the file contains a `## Repository context` section. Use a
normalised match: strip leading `#` and whitespace, lowercase, collapse
whitespace. Look for an H2 heading that normalises to `repository context`.

- **Section absent**: note that all 10 topics will be classified as absent.
  The section will be appended to the end of the file after the interview,
  preserving all existing content above.
- **Section present**: extract the content from the `## Repository context`
  heading to the next H2 heading (or end of file).

---

## Stage 2 — Classify topics

### Canonical headings (in order)

The 10 canonical H3 headings, in canonical order:

1. `### Purpose`
2. `### Domain ownership`
3. `### Callers and interfaces`
4. `### External dependencies`
5. `### Domain concepts`
6. `### Invariants`
7. `### Gotchas`
8. `### Operational profile`
9. `### Test notes`
10. `### Repository structure`

### H3 match normalisation

Normalise each H3 heading before matching: strip leading `#` characters and
whitespace, lowercase, collapse runs of whitespace to a single space. For
example, `### GOTCHAS`, `###  gotchas`, and `### Gotchas` all normalise to
`gotchas` and match canonical heading 7.

Use an inline `python3` script to perform deterministic classification.
The script must:

1. Read the `## Repository context` section content.
2. For each canonical heading, apply the normalised match to find it.
3. Count bullets (lines starting with `- `) under each found heading, up to
   the next H3 or H2 heading or end of section.
4. Check each bullet for markers.
5. Output a classification for each topic.

### Classification rules

For each of the 10 canonical headings, classify as follows:

| Condition | Classification |
|-----------|---------------|
| H3 heading not found in file | **absent** |
| H3 present AND (<=1 bullet OR any bullet is a marker) | **thin** |
| H3 present AND >=2 non-marker bullets (none match a marker) | **present** |

**Marker definition:** a bullet is a marker if its trimmed content (after
removing the leading `- `) equals `TBD`, `TODO`, `unknown`, or `n/a`
(case-insensitive comparison), or if its trimmed content starts with
`[inferred]`.

When `## Repository context` is absent from the file, classify all 10 topics
as **absent**.

---

## Stage 3 — Present gap summary

Present the classification results to the engineer as a numbered list:

```
Gap summary for CLAUDE.local.md:

1.  Purpose          — {present|thin|absent}
2.  Domain ownership — {present|thin|absent}
3.  Callers and interfaces — {present|thin|absent}
4.  External dependencies  — {present|thin|absent}
5.  Domain concepts  — {present|thin|absent}
6.  Invariants       — {present|thin|absent}
7.  Gotchas          — {present|thin|absent}
8.  Operational profile — {present|thin|absent}
9.  Test notes       — {present|thin|absent}
10. Repository structure — {present|thin|absent}
```

### All topics present

If all 10 topics are classified as **present**, report:

> All topics are already covered.

Then ask:

> Would you like to revise any of these topics? Enter topic numbers to
> revisit, or "done" to exit.

- If the engineer enters topic numbers: treat those topics as **thin** for
  the purpose of the interview (Stage 4). Present existing content as a
  starting point.
- If any entered token is not a valid topic number (1-10) or "done",
  re-prompt with the valid options. Do not silently drop invalid entries.
- If the engineer says "done" or declines: exit without interviewing.

### Mixed or all gaps

If any topics are thin or absent, state which topics will be interviewed:

> I will interview you on the {N} thin/absent topics. Present topics will be
> kept as-is.

Proceed to Stage 4.

---

## Stage 4 — Interview

Interview the engineer for each **thin** and **absent** topic, in canonical
order. Skip **present** topics entirely.

For each topic, use the question, intent, probes, and shape defined below.
Ask one topic at a time and wait for the engineer's response before moving
to the next topic.

### Interview depth mechanics

After the engineer's initial answer to each topic, use these two follow-up
mechanisms to deepen thin answers:

1. **Ask for an example file.** When the engineer describes a pattern or
   convention, ask which file best illustrates it. The captured bullet gains
   a concrete, navigable path (e.g. "uses repository pattern (example:
   `src/payments/PaymentRepository.ts`)").

2. **Ask what an AI agent would get wrong.** Follow up on short answers
   with: "Is there anything specific about how this works that an AI agent
   would get wrong?" This surfaces surprising, non-obvious knowledge without
   the agent presuming to know better.

Use judgement on when to apply these follow-ups. Not every answer needs both.
If the engineer gives a thorough, specific answer with concrete paths
already included, do not ask redundant follow-ups.

### Anti-pattern: adversarial verification

**Do not** verify the engineer's claims against the codebase and challenge
them when you disagree. Engineers documenting surprising or exceptional
behaviour is exactly the high-value capture this interview exists for. An
agent overruling them with "actually most of the code does X" drowns out the
signal the engineer is trying to flag. The interview is collaborative, not
adversarial. Accept the engineer's answers as authoritative.

### Handling skips

- **Absent topic, engineer skips** (says "skip", "none", or equivalent):
  omit the topic from the output entirely. Do not write an empty heading.
- **Thin topic with existing `[inferred]` bullets, engineer skips**: retain
  the existing `[inferred]` bullets unchanged (prefix intact). The topic
  stays in the file and will re-classify as thin on the next run.
- **Thin topic with non-inferred content, engineer skips**: retain the
  existing content unchanged.

### Topic reference

For **thin** topics, present the existing content as a starting point before
asking the question:

> Here is what is currently captured for **{topic}**:
>
> {existing bullets}
>
> {question}

For **absent** topics, ask from scratch.

---

### Topic 1: Purpose

- **Question:** "What is this service/application and what problem does it
  solve?"
- **Intent:** determine the scope of changes — whether a modification falls
  within or outside this service's responsibility — and frame commit messages
  and PR descriptions in terms of business impact.
- **Probes:** What business problem does this solve? Who are the end users or
  consuming systems? What would break for the business if this service went
  down for an hour?
- **Shape:** `- {business function} for {user/system} — {what distinguishes
  this from adjacent services}`

---

### Topic 2: Domain ownership

- **Question:** "Which team owns this repo and what domain does it cover?"
- **Intent:** determine whether a change belongs in this repo or
  upstream/downstream, and use correct domain language in code and
  documentation.
- **Probes:** What bounded context does this own? Are there domain concepts
  that share names with other services but mean different things here? What
  changes would you push back on as "not our responsibility"?
- **Shape:** `- Owns {domain concept}; boundary: {what's in vs. out};
  terminology: {term} means {definition} here (not {common
  misunderstanding})`

---

### Topic 3: Callers and interfaces

- **Question:** "Who calls this service and through what interfaces (gRPC,
  REST, events, UI)?"
- **Intent:** enable breaking-change impact analysis when modifying endpoints,
  events, or response shapes.
- **Probes:** Which endpoints/events does each caller consume, and what
  business flow are they driving? Which fields or response-shape behaviours do
  they depend on? What would break for them if X changed? Are any consumers
  uncontrolled (external partners, mobile apps in the wild, third parties)
  where we cannot ship a coordinated change?
- **Shape:** `- {service} → consumes {endpoint/event} for {business
  purpose}; depends on {fields/behaviour}; breaking-change impact: {what
  fails for them if X changes}`

---

### Topic 4: External dependencies

- **Question:** "What external systems does this depend on (databases, caches,
  queues, third-party APIs)?"
- **Intent:** anticipate failure modes, mock boundaries correctly in tests,
  and assess blast radius of dependency changes.
- **Probes:** Which dependencies have SLAs or rate limits that affect this
  service? Which ones have caused outages? Are there dependencies that look
  optional but are actually critical-path?
- **Shape:** `- {dependency} via {protocol} — {what this service uses it
  for}; failure mode: {what happens when it is down}; constraint: {rate
  limit, SLA, quirk}`

---

### Topic 5: Domain concepts

- **Question:** "What are the key domain concepts an AI agent must understand
  to work here?"
- **Intent:** use correct terminology in code, comments, and commit messages,
  and recognise when a change affects a domain concept's semantics.
- **Probes:** What terms do new engineers consistently misunderstand? Are
  there concepts that have different meanings in different parts of the
  codebase? What domain rules are enforced in code vs. by convention?
- **Shape:** `- {term}: {definition in this context} — not {common
  confusion}; enforced by {code/convention/both}`

---

### Topic 6: Invariants

- **Question:** "What business rules or invariants must never be violated?"
- **Intent:** recognise when a proposed change would violate a hard
  constraint, and write assertions or tests that protect invariants.
- **Probes:** What business rules can never be broken? What schema constraints
  or ordering guarantees exist? What idempotency expectations do callers
  have? What would cause data corruption if violated?
- **Shape:** `- {invariant}: {what must hold}; enforced by {mechanism};
  violation consequence: {what breaks}`

---

### Topic 7: Gotchas

- **Question:** "What non-obvious quirks, dead code, or surprising behaviours
  exist?"
- **Intent:** avoid known footguns and understand why code looks the way it
  does when the reason is not obvious from the code itself.
- **Probes:** What has tripped up new engineers? Is there dead code or
  deprecated paths that look active? Are there flaky tests or known fragile
  areas? What historical decisions look wrong but are intentional?
- **Shape:** `- {gotcha}: {what it looks like} vs. {what is actually
  happening}; consequence of getting it wrong: {impact}`

---

### Topic 8: Operational profile

- **Question:** "What is the traffic/load profile, latency targets, and
  alerting setup?"
- **Intent:** make informed decisions about performance trade-offs, caching
  strategies, and deployment safety.
- **Probes:** What is the traffic shape (steady, bursty, time-of-day)? What
  is the deployment cadence and strategy (blue-green, canary, feature flags)?
  What resource constraints exist? What scaling limits have been hit?
- **Shape:** `- {dimension}: {current profile}; constraint: {limit or
  bottleneck}; decision it changes: {what an agent should do differently
  because of this}`

---

### Topic 9: Test notes

- **Question:** "What does an engineer need to know to run tests (setup,
  fixtures, environments)?"
- **Intent:** run the right tests after a change and understand which test
  failures are signal vs. noise.
- **Probes:** What test commands cover what scope? Are there tests that are
  slow, flaky, or require special setup? What areas lack test coverage and
  why?
- **Shape:** `- {test tier}: {command}; covers {scope}; known gaps: {what is
  not tested and why}; flaky: {yes/no and what to do}`

---

### Topic 10: Repository structure

- **Question:** "How is the codebase organised (key directories, build
  targets, generated code)?"
- **Intent:** find the right place to make a change and follow existing
  patterns when adding new code.
- **Probes:** What is the organising principle (by domain, by layer, by
  feature)? Where do new files go? Are there directories that look like they
  serve one purpose but actually serve another?
- **Shape:** `- {directory}: {what it contains and why it is separate};
  pattern: {convention for adding new files here}`

---

## Stage 5 — Merge answers

After all topics have been interviewed, merge the confirmed answers back
into `CLAUDE.local.md`.

### Merge semantics

- **Thin** topics: replace the entire H3 block (heading + all bullets) with
  the new confirmed content. Exception: if the engineer skipped the topic,
  retain existing content unchanged (see skip handling in Stage 4).
- **Absent** topics: insert the new H3 block at its canonical position
  within the `## Repository context` section. Exception: if the engineer
  skipped the topic, do not write the heading.
- **Present** topics: skip — not interviewed, not touched.

### Canonical position insertion

When inserting an absent topic, place it at its canonical position relative
to the other headings in the section. Use the canonical order (1-10) defined
in Stage 2. The new heading goes after the last heading that precedes it in
canonical order, or at the start of the section if no preceding heading
exists.

Use an inline `python3` script for deterministic merge operations:
normalising headings, locating insertion points, and replacing blocks. The
script computes the new file content and emits it to stdout; capture the
output and persist it with the `Write` tool. This keeps the deterministic
transform in Python while keeping the side-effect on a tool the harness
tracks. Do not write the file from within the Python script itself.

### Section creation

If `## Repository context` was absent from the file, append it to the end
of `CLAUDE.local.md`. Ensure a blank line separates existing content from
the new section heading. Write all confirmed topics under this heading in
canonical order.

### Content format

Each topic is an H3 heading followed by declarative bullets. No prose
paragraphs. Each bullet starts with `- `. Strip the `[inferred]` prefix
from any bullet the engineer confirmed or replaced.

Persist the merged content using the `Write` tool (the content was already
computed by the `python3` script above).

---

## Stage 6 — Report

After merging, present a summary to the engineer:

> **Update complete.** `CLAUDE.local.md` has been updated.
>
> Topics updated: {list of topics that were written or replaced}
> Topics skipped by engineer: {list, or "none"}
> Topics already present: {list, or "none"}
>
> Review `CLAUDE.local.md` to confirm the changes.

---

## Rules

- **`CLAUDE.local.md` must exist.** If it does not, display the error
  message and stop. Do not create the file — that is the responsibility of
  `init-claude-standards`.
- **Interview only thin and absent topics.** Present topics are never
  interviewed or modified.
- **Present the gap summary before interviewing.** The engineer must see the
  full classification before answering questions.
- **Ask one topic at a time.** Wait for the engineer's response before
  moving to the next topic. Do not batch multiple topics into a single
  question, even when many topics are absent — batching produces shallow
  answers.
- **NEVER verify claims against the codebase.** The interview is
  collaborative. Accept the engineer's answers as authoritative. Do not
  cross-check code and challenge disagreements — this is an explicit
  anti-pattern. Do not reframe verification as "clarifying", "helping
  with accuracy", or "just checking" — these are verification under a
  different name.
- **Canonical order is maintained on write.** Inserted topics go at their
  canonical position, not appended to the end of the section.
- **Use `python3` for deterministic text operations.** H3 normalisation,
  bullet counting, marker matching, and canonical-position insertion must
  use inline `python3` scripts, not in-context string manipulation.
  This applies regardless of perceived simplicity — even a file with two
  headings must be classified via script, not in-context reasoning.
- **Preserve content outside `## Repository context`.** All existing content
  above and below the section remains untouched.
- **UK English throughout.** All human-readable text in prompts and output
  uses UK English spelling.
- **Skip handling is context-dependent.** Absent + skip = omit. Thin +
  skip with `[inferred]` bullets = retain unchanged. Thin + skip with
  non-inferred content = retain unchanged.
- **Empty topics are omitted.** Never write a heading with no bullets
  beneath it.
- **Do not modify any file other than `CLAUDE.local.md`.** This skill does
  not touch `CLAUDE.md`, `bin/bundle`, or files under `standards/`.

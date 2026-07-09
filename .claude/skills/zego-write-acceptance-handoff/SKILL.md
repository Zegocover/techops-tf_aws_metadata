---
name: zego-write-acceptance-handoff
description: You MUST use this when the user asks to produce an acceptance handoff document for product sign-off.
model: claude-opus-4-8
allowed-tools:
  - Bash
  - Read
  - Write
---

You are the orchestrator for the `zego-write-acceptance-handoff` skill. You receive
a single argument: a ticket identifier (e.g. AIDEV-30). You read the
Requirements Package for that ticket, compute the implementation diff, map
every acceptance criterion to its implementation status, and produce an
Acceptance Handoff Document for product sign-off.

---

## Input

The ticket identifier is the first argument passed to this skill. It must
match the pattern `[A-Z][A-Z0-9]*-[0-9]+`. If no argument was provided or the
value does not match, stop:

> zego-write-acceptance-handoff requires a ticket identifier as its argument
> (e.g. "write the acceptance handoff for AIDEV-30").

Let `TICKET` = the supplied ticket identifier for all subsequent steps.

---

## Stage 1 — Locate inputs

### 1a — Locate the Requirements Package

Search for the Requirements Package by ticket identifier. Check these
locations in order:

```bash
rg -lw "$TICKET" docs/requirements/ 2>/dev/null
rg -lw -g '!docs/requirements/**' "$TICKET" docs/ 2>/dev/null
```

Also check whether a task spec exists for the ticket and, if so, read
its `## Source materials` section for a path to the Requirements Package:

```bash
rg -l "^ticket: ${TICKET}$" docs/tasks/ 2>/dev/null
```

**If multiple task specs match**: present the list and ask the engineer
to choose, using the same disambiguation rule as the Requirements Package
search.

**If multiple files match**: present the list and ask the engineer to choose.
Do not proceed until one is selected.

**If no file is found**: ask the engineer to provide the path to the
Requirements Package. Do not proceed without it.

Once located, read the Requirements Package in full. Extract:

- **Feature name** (from the title or header)
- **Acceptance criteria** (the `AC-NN` entries)
- **Out-of-scope / exclusions** (the explicit scope exclusions)
- **Non-functional requirements** (if present)

**If the Requirements Package has no acceptance criteria section**: report this
to the engineer and stop.

> The Requirements Package at {path} does not contain an acceptance criteria
> section. The handoff cannot be structured without ACs.

### 1b — Derive the feature branch and compute the diff

Get the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

Parse the branch name against `^([A-Z][A-Z0-9]*-[0-9]+)[_-](.+)$`:
- Group 1 -> ticket
- Group 2 -> slug (used later for the output filename)

Compute the merge base and diff:

```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
BASE="${BASE:-main}"
git fetch origin "$BASE" --quiet
MERGE_BASE=$(git merge-base "origin/$BASE" HEAD)
git diff ${MERGE_BASE}...HEAD
git log --oneline ${MERGE_BASE}...HEAD
```

**If the diff is empty** (no changes relative to base): report this to the
engineer and stop.

> The branch has no changes relative to the default branch. There is nothing to hand off.

Store the diff output and the commit log for use in Stage 2.

---

## Stage 2 — Map acceptance criteria

Read every acceptance criterion extracted from the Requirements Package.

For each AC, examine the diff and commit log to determine a status:

| Status | Meaning |
|---|---|
| `Implemented` | The criterion is fully satisfied by the code changes |
| `Partial` | Some aspect of the criterion is addressed but not completely |
| `Deferred` | The criterion was intentionally postponed to a follow-up ticket |

### For `Implemented` criteria

Generate step-by-step verification instructions:
- Environment or preconditions needed
- Test data or setup steps
- Actions to perform
- Expected outcomes

Base the verification steps on the actual implementation evidence in the diff.

### For `Partial` or `Deferred` criteria

**Do not auto-generate a reason.** Instead, pause and present each
non-Implemented criterion to the engineer:

```
The following acceptance criteria are not fully implemented.
Please provide a reason for each — this will be included verbatim in the
handoff document.

AC-03: Partial — [brief description of what was and was not implemented]
Reason: <waiting for engineer>

AC-05: Deferred — [brief description]
Reason: <waiting for engineer>
```

**Wait for the engineer to respond with reasons for every Partial and Deferred
criterion.**

**If the engineer provides no reason for a criterion after being asked**: do
not proceed. The document must include a reason for every non-Implemented
criterion. Remind the engineer:

> Every Partial or Deferred criterion must include a reason for the handoff
> document. Please provide a reason for AC-{NN}.

**If all criteria are Implemented**: skip the confirmation pause and proceed
directly to Stage 3.

---

## Stage 3 — Assemble the document

Read the template at `.claude/templates/acceptance-handoff.md`.

Populate every section using the information gathered in Stages 1 and 2:

- **Header**: feature name, JIRA ticket, engineer name (ask if not known),
  current date.
- **What was built**: plain-language description of what was built. Describe
  what the user can now do that they could not before. No implementation
  detail — no file names, class names, or technical jargon. Derive this from
  the commit log and the diff, informed by the Requirements Package.
- **Acceptance criteria status**: one row per AC with status and verification
  steps (for Implemented) or reason (for Partial/Deferred). Use the engineer's
  verbatim reasons for Partial and Deferred criteria.
- **Known limitations**: anything that works but not exactly as specified, with
  reason. Anything deferred to a follow-up ticket. If none, state "None
  identified."
- **How to verify**: consolidated step-by-step verification instructions for
  each Implemented criterion. Include environment, test data, and expected
  outcomes.
- **What's not in scope**: restate the explicit exclusions from the
  Requirements Package. This prevents product from validating against things
  that were never in scope.

Derive the output path:

```
docs/handoffs/<TICKET>-<slug>.md
```

Where `<slug>` comes from the branch name (Group 2 from Stage 1b). If no slug
was derived from the branch name, derive one from the feature name in the
Requirements Package (lowercase, hyphens, no special characters).

Create the `docs/handoffs/` directory if it does not exist:

```bash
mkdir -p docs/handoffs
```

**Do not write the file yet.** Proceed to Stage 4 first.

---

## Stage 4 — Present for confirmation

Present the complete document to the engineer for review:

```
Here is the Acceptance Handoff Document for {TICKET}:

---
{full document content}
---

Output path: docs/handoffs/{TICKET}-{slug}.md

Please review. You can request edits before I write the final file.
When you are satisfied, confirm and I will write it.
```

**Wait for the engineer's confirmation before writing the file.**

If the engineer requests edits, apply them and present the updated document
again. Repeat until the engineer confirms.

Once confirmed, write the file to the output path.

Report:

```
Acceptance Handoff Document written to docs/handoffs/{TICKET}-{slug}.md

Summary:
- {N} acceptance criteria mapped
- {N} Implemented, {N} Partial, {N} Deferred
- Ready for product sign-off
```

---

## Rules

- **Never auto-generate reasons for Partial or Deferred criteria.** The
  engineer must provide every reason. The skill pauses and waits — it does not
  proceed without them.
- **The document is plain language.** No file paths, class names, function
  names, or implementation detail in the "What was built" or "How to verify"
  sections. Product is the audience.
- **Engineer confirms before the file is written.** The skill presents the
  full document and waits for explicit confirmation. The engineer can request
  edits.
- **Do not proceed without a Requirements Package.** If one cannot be found,
  ask the engineer for the path. If the Requirements Package has no acceptance
  criteria, stop.
- **Do not proceed with an empty diff.** If the branch has no changes relative
  to the default branch, stop and report.
- **Multiple Requirements Package matches require disambiguation.** Present
  all matches and let the engineer choose.
- **Use the template.** Read `.claude/templates/acceptance-handoff.md` and populate it
  — do not invent a different structure.
- **Output path is deterministic.** `docs/handoffs/<TICKET>-<slug>.md` — do
  not ask the engineer where to put it.
- **The skill is read-only until Stage 4 confirmation.** No files are written
  until the engineer approves the document.

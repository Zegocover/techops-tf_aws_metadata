---
name: fix-pr-comments
description: You MUST use this when the user asks to address or fix unresolved review threads on a pull request.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
---

You are the orchestrator for the `fix-pr-comments` skill. You receive a single
argument: a PR number (integer). You do not write code or post comments
yourself — you brief sub-agents and orchestrate results.

---

## Input

The PR number is the first argument passed to this skill. It must be a positive
integer. If no argument was provided or the value is not digits-only, stop:

> fix-pr-comments requires a PR number as its argument (e.g. /fix-pr-comments 42).

Let `PR_NUM` = the supplied PR number for all subsequent steps.

---

## Gate 1 — Triage

### Stage 1 — Fetch unresolved threads and comments

Run:

```bash
.claude/scripts/pr-comments.sh <PR_NUM>
```

**If `pr-comments.sh` exits non-zero**: surface the full error output verbatim
and stop the skill.

**If `pr-comments.sh` returns `[]`**: report:

> No unresolved review threads or comments on PR #<PR_NUM>.

Then exit cleanly.

**If `pr-comments.sh` returns a non-empty array**: parse it into comment
objects. Each object has a `type` field that determines which other fields are
present:

| Field        | `review_thread`                                                     | `top_level_comment`                          | `review_body`                                |
|--------------|---------------------------------------------------------------------|----------------------------------------------|----------------------------------------------|
| `type`       | `"review_thread"`                                                   | `"top_level_comment"`                        | `"review_body"`                              |
| `thread_id`  | GraphQL node ID — pass verbatim to `pr-resolve.sh`                  | *(absent)*                                   | *(absent)*                                   |
| `comment_id` | REST comment ID — pass verbatim to `pr-reply.sh`                    | REST issue comment ID — used to name the reply scratch file | REST review ID — used to name the reply scratch file |
| `path`       | File path the thread is anchored to                                 | *(absent)*                                   | *(absent)*                                   |
| `line`       | Line number the thread is anchored to                               | *(absent)*                                   | *(absent)*                                   |
| `body`       | Full comment thread (all messages oldest-first, separated by `---`) | Comment body                                 | Review body text                             |
| `author`     | *(absent)*                                                          | Reviewer login                               | Reviewer login                               |

---

### Stage 2 — Classify comments

Read each entry's `body` and classify it using these rules:

| Classification  | Apply when |
|-----------------|------------|
| `will-fix`      | The comment requests a specific, actionable code change that has not yet been made |
| `question`      | The reviewer is asking for clarification or an explanation — no code change needed |
| `acknowledged`  | The reviewer is making a suggestion, nit, or raising a concern but not demanding a change (signals: "nit:", "consider:", "minor:", "up to you", "optional") |
| `skip`          | The comment is clearly already addressed, is out of scope for this branch, or no action is warranted |

**Default classification for `review_body` entries:** classify as `acknowledged`
unless the body contains a specific, actionable code change request. Review
bodies are typically high-level summaries ("overall looks good", "a few nits
below") and rarely warrant direct code changes. Only classify a `review_body`
as `will-fix` if it contains an explicit, concrete change request.

For each entry, also write a one-line reason for the classification.

---

### Stage 3 — Present triage plan and confirm

Present the classification plan as a table:

```
PR #<PR_NUM> — <N> unresolved comments

| # | Type                | File:Line           | Classification  | Reason                          |
|---|---------------------|---------------------|-----------------|---------------------------------|
| 1 | review_thread       | {path}:{line}       | will-fix        | {one-line reason}               |
| 2 | review_thread       | {path}:{line}       | question        | {one-line reason}               |
| 3 | top_level_comment   | (top-level)         | will-fix        | {one-line reason}               |
| 4 | review_body         | (review body)       | acknowledged    | {one-line reason}               |
| …

Comments to implement: {count will-fix}
Comments to reply only: {count question + acknowledged + skip}

Shall I proceed? You can override any classification before I start
(e.g. "change comment 2 to acknowledged — we addressed this in a previous PR").
```

Display rules for the File:Line column:
- `review_thread`: show `{path}:{line}`
- `top_level_comment`: show `(top-level)`
- `review_body`: show `(review body)`

**Wait for the developer's response.** Apply any overrides to the plan. The
confirmed plan is authoritative for all subsequent stages.

If there are no `will-fix` entries after confirmation, skip Gate 2 and proceed
directly to Gate 3.

---

## Gate 2 — Implement

Fix all `will-fix` entries first, then run a single review cycle. Track a
per-entry result. Initialise `iteration = 1` for the gate.

---

### Stage 4 — Spawn fixer sub-agents (all will-fix entries)

For each `will-fix` entry in sequence:

**If `iteration = 1`**, determine the agent brief based on type:

**For `review_thread` entries** (have `path` and `line`), send:

```
You are fixing a specific issue raised in a PR review thread.
Do not ask questions — make the targeted change described below and return.

Review thread (all comments oldest-first, separated by ---):
---
{entry.body}
---

If the thread contains multiple comments, treat the conversation as a whole.
The last message is the most recent instruction; earlier messages provide
context and may have been amended or retracted.

File to change: {entry.path}
Line: {entry.line}

Scope constraint: limit all changes to the scope of the reviewer's comment
above. Do not refactor surrounding code, add tests, or change any file not
directly implicated by the comment. If the fix requires touching more than the
named file, explain why in your return message, but still stay as narrow as
possible.

After making the change, return:
1. A brief description of what you changed (one or two sentences).
2. Whether any files were modified (yes/no).
```

**For `top_level_comment` and `review_body` entries** (no `path` or `line`),
send:

```
You are fixing a specific issue raised in a PR comment.
Do not ask questions — make the targeted change described below and return.

Comment body:
---
{entry.body}
---

This comment is not anchored to a specific file or line. Read the comment
carefully and identify the relevant file(s) and location(s) from the context
of the comment and the current branch diff. Use `git diff HEAD~1` or read
the files mentioned or implied by the comment to determine where to apply
the change.

Scope constraint: limit all changes to the scope of the reviewer's comment
above. Do not refactor surrounding code, add tests, or change any file not
directly implicated by the comment. Stay as narrow as possible.

After making the change, return:
1. A brief description of what you changed (one or two sentences).
2. Whether any files were modified (yes/no).
```

**If `iteration > 1`**: only process entries that have pending blocker or major
findings from the most recent review. For each such entry, read the most recent
findings file. Each finding is a markdown block headed
`### F{n} — {severity} — {file}:{line}` with `- outcome: pending` beneath it.
Extract every finding where outcome is `pending` AND severity is `blocker` or
`major` AND the finding's file path was touched by this entry's original fix.
Format each as:

```
F{n} ({severity}) — {file}:{line} — {issue} — Suggestion: {suggestion}
```

Then determine the agent brief based on type:

**For `review_thread` entries** (have `path` and `line`), send:

```
You are fixing a specific issue raised in a PR review thread. A previous
attempt failed review. Address the findings listed below in addition to
the original comment.

Review thread (all comments oldest-first, separated by ---):
---
{entry.body}
---

File to change: {entry.path}
Line: {entry.line}

Scope constraint: limit all changes to the scope of the reviewer's comment
and the findings below. Do not refactor surrounding code or change any file
not directly implicated.

Previous attempt failed — address these findings:
{formatted F{n} lines, one per line}

After making the change, return:
1. A brief description of what you changed.
2. Whether any files were modified (yes/no).
```

**For `top_level_comment` and `review_body` entries** (no `path` or `line`),
send:

```
You are fixing a specific issue raised in a PR comment. A previous
attempt failed review. Address the findings listed below in addition to
the original comment.

Comment body:
---
{entry.body}
---

This comment is not anchored to a specific file or line. Identify the
relevant file(s) from the comment context and the findings below.

Scope constraint: limit all changes to the scope of the reviewer's comment
and the findings below. Do not refactor surrounding code or change any file
not directly implicated.

Previous attempt failed — address these findings:
{formatted F{n} lines, one per line}

After making the change, return:
1. A brief description of what you changed.
2. Whether any files were modified (yes/no).
```

After each fixer returns, run the three-part diff check:

```bash
git diff HEAD
git diff --cached
git status --porcelain
```

If all three are empty, record result `skipped-no-changes` for that entry.
Otherwise record `changes-made`. Continue to the next entry.

---

### Stage 5 — Spawn single review sub-agent

**Skip predicate (used by Stages 5, 7, 8, and 9):** at least one `will-fix`
entry must have recorded `changes-made`. If every entry recorded
`skipped-no-changes`, no code was changed and there is nothing to review,
commit, validate, or push. This predicate is evaluated once after Stage 4 and
governs the review spawn here, the commit in Stage 7, the CI validation in
Stage 8, and the push in Stage 9.

After all fixer agents have run, if the skip predicate is false (every entry
recorded `skipped-no-changes`), proceed directly to Stage 10 with those results.

Otherwise, derive `ticket` and `branch` from the current git branch:

```bash
git rev-parse --abbrev-ref HEAD
```

Parse the branch name against `^([A-Z][A-Z0-9]*-[0-9]+)[_-](.+)$`:
- Group 1 → `ticket`
- Group 2 → description slug

Locate the task spec:

```bash
rg -l "^ticket: {ticket}$" docs/tasks/ 2>/dev/null | head -1
```

Locate the design docs (run only when the task spec was found; capture all matches — more than one file may share the same `JIRA:` value):

```bash
rg -l "^JIRA: {ticket}$" docs/design/ 2>/dev/null
```

Store the task spec path as `TASK_SPEC_PATH` and all returned design doc paths as `DESIGN_DOC_PATHS` (a list; empty if none found).

Spawn a fresh Agent with this brief (fill every placeholder; omit the design doc line entirely if `DESIGN_DOC_PATHS` is empty):

```
You are running the `review` skill.
Read `.claude/skills/review/SKILL.md` and execute it from Stage 1.
Do not ask questions — all context is below.

Ticket: {ticket}
Branch: {branch}

The diff contains fixes for {N} PR review comments.
Group E will check it against the task spec at {TASK_SPEC_PATH}.

{If DESIGN_DOC_PATHS has one entry:}
A design doc for this ticket exists at {DESIGN_DOC_PATHS[0]} — Group E will load it.

{If DESIGN_DOC_PATHS has more than one entry:}
Design docs for this ticket exist at: {DESIGN_DOC_PATHS list, one path per line} — Group E will load all of them.
```

Wait for the review agent to return the verdict string (`PASS` or `FAIL`) and
the findings file path.

---

### Stage 6 — Act on verdict

**PASS**: record result `pass` for all entries that had `changes-made`. Show
the Gate 2 summary table (same format as below) and proceed to Stage 7.

**FAIL and iteration < 3**: increment `iteration`. Map each pending
blocker/major finding back to the entry whose fix introduced it (by matching
the finding's file path to the files each entry touched). Return to Stage 4
for entries with mapped findings.

**FAIL and iteration = 3** (max iterations reached): record
`failed-max-iterations` for entries with remaining pending blocker/major
findings. Surface a summary:

> Gate 2 — max iterations reached.
> Remaining findings:
>
> {findings list — one line per pending blocker/major, with entry reference}
>
> Findings file: {path}

Show the Gate 2 summary table (same format as below) and proceed to Stage 7.

---

### Stage 7 — Commit fixer work

Present the Gate 2 summary table:

```
Gate 2 complete.

| # | Type                | File:Line         | Result                  |
|---|---------------------|-------------------|-------------------------|
| 1 | review_thread       | {path}:{line}     | pass                    |
| 2 | top_level_comment   | (top-level)       | skipped-no-changes      |
| 3 | review_body         | (review body)     | failed-max-iterations   |
```

Display rules for the File:Line column are the same as Stage 3.

Do not wait for developer confirmation — proceed immediately.

Run `git status --porcelain` to check whether any files were changed:

```bash
git status --porcelain
```

**Skip check:** if the output of `git status --porcelain` is empty, no files
were changed — skip the commit and proceed directly to Stage 10.

Otherwise, commit all staged and unstaged changes from the fixer agents, plus
**all** review findings files produced by Stage 5 across iterations (one file
per iteration — e.g. both the FAIL findings from iteration 1 and the PASS
findings from iteration 2). Every untracked or modified file reported by
`git status --porcelain` must be included.

```bash
git add {files that were changed} {all findings file paths from Stage 5}
git commit -m "{ticket}: Fix PR review comments

{one-line summary per entry that was fixed, prefixed with - }"
```

Capture the commit SHA:

```bash
git rev-parse HEAD
```

Store as `COMMIT_SHA` for use in reply bodies.

---

### Stage 8 — CI validation and fix loop

**Skip check:** evaluate the skip predicate defined in Stage 5. If every
`will-fix` entry recorded `skipped-no-changes`, skip CI validation entirely —
no code was changed, nothing to validate. Proceed directly to Stage 10.

Otherwise, read `.claude/skills/shared/ci-validation-loop.md` and execute Steps 1, 2,
3 defined there. That document contains the sub-agent prompts, verdict
handling, per-cycle commit flow, and fixer agent instructions for this stage.
Fill the placeholders as follows before executing:

| Placeholder | Value |
|-------------|-------|
| `{ticket}` | the `ticket` value derived in Stage 5 |
| `{branch}` | the `branch` value derived in Stage 5 |
| `{changed file(s)}` | all files in the Stage 7 commit (`git show --name-only --pretty=format: $COMMIT_SHA`) |
| `{task-nn}` | *(omit — not applicable to fix-pr-comments)* |

CI validation commit messages use the format:
`{ticket}: CI validation cycle {N} — {PASS|FAIL}`

The CI validation loop runs up to 5 iterations (separate counter from the
Gate 2 review loop max of 3).

**On `verdict: passed`**: proceed to Stage 9 (push).

**On `verdict: failed-max-iterations`**: **check for the
`precondition: authentication` marker line FIRST**, before presenting the
proceed/stop choice. The two branches below are mutually exclusive; the auth
branch is checked first.

**If the return carries the `precondition: authentication` marker (auth branch):**
emit the reply-continue affordance and end the turn:

> CI validation hit an authentication precondition — an environment problem, not a code failure, so the fix loop stopped without churning the fixer.
>
> Remediation: {remediation path from the marker}.
>
> Authenticate, then reply `continue` and I will re-run CI validation from the top.

**Wait for the developer's `continue` reply.** On reply, RE-RUN the entire CI
loop — a fresh invocation of `skills/shared/ci-validation-loop.md` Steps 1–3
with the iteration counter starting at 1 (the auth short-circuit consumed no
iteration budget, so the fresh loop begins at iteration 1). This re-run logic
lives here in the caller, never in `ci-validation-loop.md`.

**If the return does NOT carry the marker (real code failure — existing behaviour, unchanged):** present the failure to the developer:

> CI validation failed after 5 fix attempts.
>
> Failing command: `{failing_command}`
> Most recent output is above.
>
> Options:
> 1. **Proceed** — push despite the CI failure.
> 2. **Stop** — do not push. Resolve the failure manually.
>
> Each cycle's state is preserved as a commit; inspect `git log` to walk
> the iteration history.

**Wait for the developer's response.**

- If the developer chooses **Proceed**, continue to Stage 9 (push).
- If the developer chooses **Stop**, halt the skill. The fixer work is already
  committed in Stage 7 — stopping here means the commit exists locally but is
  not pushed.

---

### Stage 9 — Push

**Skip check:** evaluate the skip predicate defined in Stage 5. If every
`will-fix` entry recorded `skipped-no-changes`, skip the push — no commit was
created. Proceed directly to Stage 10.

Otherwise, push the branch so the commit is visible to reviewers before any
replies are posted:

```bash
git push
```

---

## Gate 3 — Resolve

---

### Stage 10 — Post replies and resolve

Present the reply plan before executing:

```
Ready to post replies and resolve threads.

| # | Type                | File:Line         | Classification  | Reply preview                         |
|---|---------------------|-------------------|-----------------|---------------------------------------|
| 1 | review_thread       | {path}:{line}     | will-fix/pass   | Fixed in {sha} — {summary}            |
| 2 | top_level_comment   | (top-level)       | will-fix/pass   | Fixed in {sha} — {summary}            |
| 3 | review_thread       | {path}:{line}     | question        | {answer preview}                      |
| 4 | top_level_comment   | (top-level)       | acknowledged    | Acknowledged — {reason}               |
| 5 | review_body         | (review body)     | acknowledged    | Acknowledged — {reason}               |
| 6 | review_thread       | {path}:{line}     | skip            | Skipping — {reason}                   |
| 7 | review_thread       | {path}:{line}     | will-fix/failed | (no reply — thread left unresolved)   |
| 8 | top_level_comment   | (top-level)       | will-fix/failed | Attempted but unable to address…      |
| 9 | review_body         | (review body)     | will-fix/failed | Attempted but unable to address…      |

Shall I post these replies and resolve the threads?
```

Display rules for the File:Line column are the same as Stage 3.

**Wait for the developer's confirmation.**

Then, for each entry in order, route by type and classification:

---

#### `review_thread` entries

**`will-fix` + `pass`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-{thread_id}.md`:
   ```
   Fixed in {COMMIT_SHA} — {one sentence describing what changed}.
   ```
2. Post: `.claude/scripts/pr-reply.sh {PR_NUM} {entry.comment_id} .claude/scripts/_replies/{PR_NUM}-{thread_id}.md`
3. Resolve: `.claude/scripts/pr-resolve.sh {entry.thread_id} {PR_NUM}`

**`will-fix` + `failed-max-iterations`**: skip — no reply, thread left
unresolved.

**`question`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-{thread_id}.md`: a direct answer to the
   reviewer's question (one to three sentences, plain prose).
2. Post: `.claude/scripts/pr-reply.sh {PR_NUM} {entry.comment_id} .claude/scripts/_replies/{PR_NUM}-{thread_id}.md`

Do not resolve the thread — leave it open for the reviewer to read the answer
and follow up.

**`acknowledged`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-{thread_id}.md`:
   ```
   Acknowledged — {reason the suggestion was not actioned}.
   ```
2. Post: `.claude/scripts/pr-reply.sh {PR_NUM} {entry.comment_id} .claude/scripts/_replies/{PR_NUM}-{thread_id}.md`
3. Resolve: `.claude/scripts/pr-resolve.sh {entry.thread_id} {PR_NUM}`

**`skip`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-{thread_id}.md`:
   ```
   Skipping — {reason}.
   ```
2. Post: `.claude/scripts/pr-reply.sh {PR_NUM} {entry.comment_id} .claude/scripts/_replies/{PR_NUM}-{thread_id}.md`
3. Resolve: `.claude/scripts/pr-resolve.sh {entry.thread_id} {PR_NUM}`

---

#### `top_level_comment` entries

**Hard constraint: never call `.claude/scripts/pr-resolve.sh` for `top_level_comment`
entries.** Top-level comments have no resolvable thread.

**`will-fix` + `pass`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`:
   ```
   Fixed in {COMMIT_SHA} — {one sentence describing what changed}.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`

**`will-fix` + `failed-max-iterations`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`:
   ```
   Attempted but unable to address automatically after 3 iterations — see findings file for details.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`

**`question`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`: a direct
   answer to the reviewer's question (one to three sentences, plain prose).
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`

**`acknowledged`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`:
   ```
   Acknowledged — {reason the suggestion was not actioned}.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`

**`skip`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`:
   ```
   Skipping — {reason}.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-toplevel-{entry.comment_id}.md`

---

#### `review_body` entries

**Hard constraint: never call `.claude/scripts/pr-resolve.sh` for `review_body`
entries.** Review bodies have no resolvable thread.

**`will-fix` + `pass`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`:
   ```
   Fixed in {COMMIT_SHA} — {one sentence describing what changed}.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`

**`will-fix` + `failed-max-iterations`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`:
   ```
   Attempted but unable to address automatically after 3 iterations — see findings file for details.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`

**`question`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`: a
   direct answer to the reviewer's question (one to three sentences, plain
   prose).
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`

**`acknowledged`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`:
   ```
   Acknowledged — {reason the suggestion was not actioned}.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`

**`skip`**:

1. Write to `.claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`:
   ```
   Skipping — {reason}.
   ```
2. Post: `.claude/scripts/pr-issue-reply.sh {PR_NUM} .claude/scripts/_replies/{PR_NUM}-reviewbody-{entry.comment_id}.md`

---

#### Error handling for reply and resolve scripts

**On `pr-reply.sh` exit 3**: surface the full error and **stop the entire
skill**. Do not process further entries.

**On `pr-issue-reply.sh` exit 3**: surface the full error and **stop the entire
skill**. Do not process further entries.

**On `pr-issue-reply.sh` other non-zero exit**: record result `failed-reply`
("reply failed"). Continue to the next entry.

**On `pr-resolve.sh` exit 3**: surface the full error and **stop the entire
skill**.

**On `pr-resolve.sh` other non-zero exit**: record result `failed-resolve`
("reply posted but thread not resolved"). Continue to the next entry.

---

### Stage 11 — Cleanup and summary

Remove reply scratch files:

```bash
rm -f .claude/scripts/_replies/${PR_NUM}-*.md
```

Report:

```
fix-pr-comments — PR #{PR_NUM} complete.

| Entry | Type                | File:Line         | Classification  | Result          |
|-------|---------------------|-------------------|-----------------|-----------------|
| …     | …                   | …                 | …               | …               |

Resolved: {count}  (review_thread entries only)
Replied, awaiting reviewer: {count}  (question threads — not auto-resolved)
Replied (no thread to resolve): {count}  (top_level_comment and review_body entries that were replied to)
Skipped (no changes): {count}
Failed (max iterations): {count}  {list findings file paths if any}
Failed (resolve only): {count}
Failed (reply): {count}
```

Display rules for the File:Line column are the same as Stage 3.

---

## Rules

- **Three gates, two mandatory confirmations.** Gate 1 (triage, Stage 3) and
  Gate 3 (resolve, Stage 10) always require explicit developer confirmation.
  Gate 2 (implement) proceeds without confirmation. Stage 8 additionally
  requires a developer choice (proceed/stop) only on the CI validation
  `failed-max-iterations` path.
- **Developer overrides are final.** Do not re-assert the AI's original
  classification after the developer changes it.
- **Sequential fixers, single review.** Run fixer agents for all `will-fix`
  entries sequentially, then spawn one review agent for the combined diff. Do
  not interleave fix and review cycles per entry.
- **Fresh review agent every iteration.** Never reuse a review agent across
  iterations.
- **Fixer scope is narrow.** For `review_thread` entries, the fixer brief must
  include the full comment thread, file path, and line, and must instruct the
  agent to limit changes to that scope. For `top_level_comment` and
  `review_body` entries, the fixer brief must omit file/line and instead
  instruct the agent to identify relevant files from the comment context.
- **Three-part empty-diff check.** Use `git diff HEAD`, `git diff --cached`,
  and `git status --porcelain`. All three must be empty before recording
  `skipped-no-changes`.
- **Anchored ticket regex.** Use `^ticket: {ticket}$` — not a prefix match.
- **Commit all findings files.** Stage 8 must include every findings file
  produced across iterations, not just the final one. Run `git status` before
  staging to verify nothing is missed.
- **Push before replies.** Commit, then push, then post replies. Never post a
  reply citing a commit SHA before that commit is on the remote.
- **Reply files in `.claude/scripts/_replies/` only.** Never pass a body file from any
  other location to `pr-reply.sh` or `pr-issue-reply.sh`.
- **Reply routing by type.** `review_thread` entries use `pr-reply.sh`.
  `top_level_comment` and `review_body` entries use `pr-issue-reply.sh`.
- **Never resolve non-thread entries.** `pr-resolve.sh` must only be called for
  `review_thread` entries. Never call it for `top_level_comment` or
  `review_body` entries — they have no resolvable thread.
- **`pr-reply.sh` exit 3 stops the skill.** The branch context is wrong;
  continuing would post to the wrong PR.
- **`pr-issue-reply.sh` exit 3 stops the skill.** Same reason.
- **`pr-resolve.sh` exit 3 stops the skill.** Same reason.
- **`pr-resolve.sh` other failure after a successful reply** is recorded but
  does not stop the skill.
- **`pr-issue-reply.sh` other failure** is recorded but does not stop the skill.
- **Max 3 Gate 2 iterations** — not 5. Each iteration fixes all entries with
  pending findings and re-reviews the combined diff.
- **Default-classify `review_body` as `acknowledged`.** Only override to
  `will-fix` if the body contains a specific, actionable code change request.
- **Do not silently drop edge cases.** Every entry must produce a recorded
  result in the Stage 11 summary.
- **CI validation runs after commit, before push.** Max 5 iterations, separate
  counter from the Gate 2 review loop (max 3).
- **Spawn the CI validation agent from step 1 in a fresh message each
  iteration.** Never reuse a CI validation agent across iterations.
- **The CI fixer in step 3  applies minimal fixes only.** Do not refactor,
  add tests, or change anything unrelated to the CI failure.
- **CI validation failure after max iterations gives the developer a choice:
  proceed or stop.** Do not halt unconditionally.
- **An auth precondition is checked before the proceed/stop choice.** On
  `failed-max-iterations`, check for the `precondition: authentication` marker
  line FIRST. Present → emit "authenticate, then reply `continue`" and, on the
  reply, re-run the whole CI loop from iteration 1. Absent → the existing
  proceed/stop choice is unchanged.
- **Skip CI validation when all entries recorded skipped-no-changes.** Evaluate
  the skip predicate defined in Stage 5 — if no code was changed, there is
  nothing to validate.
- **Commit fixer work before CI validation.** The confirm-before-commit gate is
  removed — show the summary table but proceed without waiting.

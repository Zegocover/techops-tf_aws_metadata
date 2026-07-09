---
name: zego-create-pr
description: You MUST use this when the user asks to open a pull request for a completed implementation.
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
---

You are executing the `zego-create-pr` skill. Your job is to open a pull
request on GitHub that conforms to Zego's PR standards. You do not ask
questions — all required inputs are provided below or derivable from the
repository state.

---

## Inputs

The caller must supply the three required inputs. If any required input is absent, stop and
report which inputs are missing. The optional `base` input may be omitted.

| Input              | Required | Description                                                  |
|--------------------|----------|--------------------------------------------------------------|
| `ticket`           | yes      | Jira ticket key, e.g. `AIDEV-25`                             |
| `branch`           | yes      | Branch to open the PR from, e.g. `AIDEV-25_create_pr_automatically` |
| `task_spec_path`   | yes      | Relative path to the artefact backing this PR — **either** a task spec **or** a design doc, e.g. `docs/tasks/AIDEV-25-TASK-01-create-pr-automatically.md` or `docs/design/AIDEV-25-foo.md`. A task spec carries a `ticket:` YAML frontmatter key; a design doc has no `ticket:` frontmatter and instead carries a `JIRA:` header line. Stage 1 distinguishes the two by the presence of the `ticket:` key. |
| `base`             | no       | Branch to target for the PR; if absent, defaults to the repo default branch |
| `labels`           | no       | Comma-separated label names to apply to the opened PR, e.g. `ai-implementation` or `ai-design,ai-implementation`. When absent, no label step runs. |
| `review_surface`   | no       | An object `{label, link}` naming the single human review surface for this phase (`docs/ai/steering/base/review-audience.md`). `label` is a human-readable surface name (e.g. `the code changes in this PR`); `link` is a repo path, full URL, or branch name (e.g. `docs/design/AIDEV-25-foo.md`); implementation-phase callers pass a branch name when the PR URL is not yet known at render time. When supplied, Stage 6 renders one inline line within Background. When absent, no line is rendered and the PR body is otherwise unchanged. |
| `summary_path`     | no       | Relative path to an implementation-summary artefact, e.g. `docs/ai/implementations/AIDEV-25-TASK-01-create-pr-automatically.md`. When present, a one-line reference to it is appended to the Background-equivalent section of the PR body. When absent, no reference is added. |
| `summary_status`   | no       | The artefact's derived status (`Implemented` / `Partial` / `Deferred`), rendered as the status suffix on the summary reference. Only meaningful when `summary_path` is present; when `summary_path` is present but `summary_status` is absent, the reference is rendered without a status suffix. |

When both `summary_path` and `summary_status` are absent, behaviour is byte-for-byte unchanged — the five callers other than `zego-implement` omit them and are unaffected.

---

## Stage 1 — Validate inputs and read the task spec

Confirm that all three required inputs (`ticket`, `branch`, `task_spec_path`) are present.

Determine the operative base branch, then fetch it:

```bash
if [ -n "{base}" ]; then
  BASE="{base}"
else
  BASE=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
fi
git fetch origin "$BASE"
```

Store `BASE` — it is referenced in Stage 3 (diff) and Stage 6 (PR base).

Read the artefact at `task_spec_path` in full.

**Distinguish a task spec from a design doc by the presence of a `ticket:` YAML
frontmatter key.** `task_spec_path` is widened to accept either artefact type:

- **`ticket:` key present → task-spec path (existing behaviour, unchanged).**
  Extract:
  - **`ticket`** — confirm it matches the `ticket` frontmatter field. If the
    `ticket:` key is present but its value is empty or malformed, stop
    immediately and report (this is the preserved task-spec hard-stop):
    > Task spec has no `ticket` frontmatter field. A ticket prefix is
    > required for the PR title. Cannot proceed.
- **`ticket:` key absent → design-doc path.** A design doc carries no `ticket:`
  frontmatter; it records the ticket on a `JIRA:` **header line** in the body.
  Skip the `ticket:`-frontmatter guard entirely and read the ticket from the
  first body line matching `^JIRA: ` (e.g. `JIRA: AIDEV-25` yields `AIDEV-25`).
- **Neither a `ticket:` frontmatter key nor a `JIRA:` header line** — stop and
  report which field is missing:
  > Artefact `{task_spec_path}` has neither a `ticket:` frontmatter key (task
  > spec) nor a `JIRA:` header line (design doc). A ticket prefix is required
  > for the PR title. Cannot proceed.

Then, for both artefact types, extract:

- **Objective or Goal** — the section that explains *why* the change exists.
  This becomes the Background section of the PR body. (A design doc's
  `## Approach` section serves the same role when no Objective/Goal heading is
  present.)

---

## Stage 2 — Derive the PR title

Construct the title as:

```
{ticket}: {imperative-title}
```

- `ticket` is the value supplied as input (and confirmed in the task spec
  frontmatter).
- `imperative-title` is a concise imperative-mood phrase derived from the
  task spec's Objective/Goal — not the output spec, not the task slug.
- The complete title must be **≤70 characters**. Truncate or rephrase the
  imperative phrase to fit; never truncate the ticket prefix.

Examples of correct form:

```
# good
AIDEV-25: Add automatic PR creation after PASS

# bad — passive voice, no ticket prefix
Adding pull request creation to implement skill
```

---

## Stage 3 — Derive the Changes section

Run:

```bash
git diff "origin/$BASE" --stat
```

If the output is non-empty, run:

```bash
git diff "origin/$BASE" --name-only
```

Use the list of changed files to write one verb-first bullet per meaningful
change. Each bullet opens with an imperative verb (Add, Remove, Update, Fix,
Extract). Group related files into a single bullet where appropriate.

If the diff produces no output (empty diff), write:

```
- No diff against base branch detected
```

Do not leave the Changes section blank under any circumstances.

---

## Stage 4 — Check for a PR template

Run:

```bash
test -f .github/PULL_REQUEST_TEMPLATE.md && echo "PRESENT" || echo "ABSENT"
```

- **PRESENT** — read `.github/PULL_REQUEST_TEMPLATE.md` in full. Keep its
  section headings, ordering, and any placeholder text. Use it as the
  authoritative skeleton in Stage 6: fill in each section with the gathered
  context. Do not add, remove, or reorder sections beyond what the template
  defines.
- **ABSENT** — no template exists. Stage 6 will use a default three-section
  fallback (Background, Changes, Jira Ticket/s). Do not warn or error.

---

## Stage 5 — Verify clean working tree

Check whether there are uncommitted changes:

```bash
git status --porcelain
```

If the output is **empty** (tree is clean), skip to Stage 6.

If the output is **non-empty**, print the list of uncommitted files to the user
and **stop**. Do not offer to commit, do not run `git add` or `git commit`.
Instruct the user to commit their changes before running zego-create-pr. Example
message:

> The working tree has uncommitted changes (listed above). Please commit them
> before running zego-create-pr.

---

## Stage 6 — Construct and submit the PR

### Template-driven path (Stage 4 result: PRESENT)

Use the template content stored in Stage 4 as the PR body skeleton. Preserve
every section heading from the template in the order the template defines.
Fill in each section using the following derivation rules:

- A section whose heading matches **Background** (accepted synonyms,
  case-insensitive: *Context*, *Why*, *Motivation*, *Summary*, *Goal*,
  *Objective*, *Overview*): one or two sentences of flowing prose that answer
  *why* this change exists. Derive from the task spec's Objective/Goal
  section. Do not restate the diff. Do not hard-wrap prose. When the
  `review_surface` input is supplied, append the review-surface line within
  this section (see *Review-surface line* below). When the template has no
  Background-equivalent section, place the review-surface line under the
  template's **first** section instead — never introduce a new `##` heading to
  host it (`docs/ai/steering/base/pull-requests.md` rule 8). **If `summary_path`
  is present, also append the implementation-summary reference as one extra line
  at the end of this section's content** (see "Implementation-summary reference"
  below) — this appends a line to an existing section; it never adds a new
  section.
- A section whose heading matches **Changes**: bulleted list from Stage 3.
  One bullet per meaningful change, verb-first.
- A section whose heading matches **Jira Ticket/s** (accepted synonyms,
  case-insensitive: *Jira Ticket*, *Jira Tickets*, *Ticket*, *Tickets*,
  *Links*, *References*, *Related Issues*): one bullet containing the full
  Atlassian URL:
  `https://zegons.atlassian.net/browse/{ticket}`
- Any other section defined in the template: preserve the heading and fill it
  in from available context (task spec, diff, or repository state). If no
  content can be derived, write `_TBD_` as the section body instead of leaving
  template placeholder text. Always strip HTML comments (`<!-- ... -->`) and
  `{placeholder}` syntax from the final body — these must never appear in the
  published PR.

Do not add sections that are not in the template. Do not remove sections that
are in the template.

### Fallback path (Stage 4 result: ABSENT)

When no template exists, use the default three-section structure shown in the
example below. The body must contain exactly these three sections in this
order: Background, Changes, Jira Ticket/s. The fallback always has a `Background`
section. When `review_surface` is supplied, append the review-surface line within
Background (see *Review-surface line* below). When `summary_path` is present,
also append the implementation-summary reference at the end of the Background
prose (see "Implementation-summary reference" below).

### Review-surface line

When and only when the `review_surface` input `{label, link}` is supplied,
render **exactly one bolded inline line within the Background section**, on its
own line after the Background prose:

```
**Review surface for this phase:** {label} — {link}.
```

Substitute `{label}` and `{link}` from the input (e.g.
`**Review surface for this phase:** the code changes in this PR — docs/design/AIDEV-25-foo.md.`).
This is governed by `docs/ai/steering/base/review-audience.md` and is consistent
with `docs/ai/steering/base/pull-requests.md` rule 8: it is an inline line, never
a new `##` heading. When `review_surface` is absent, render no such line — the
PR body is byte-for-byte unchanged from a PR opened without it (standalone use
is unaffected).

### Implementation-summary reference (both paths)

This applies in BOTH the template-driven and fallback paths. When `summary_path`
is present, the reference is added as a single appended line, never as a new
section (`pull-requests.md` Rule 8 forbids adding sections in either mode;
appending a line to an existing section's content is permitted).

- **Reference format.** Append this one line to the end of the
  Background-equivalent section's content:

  ```
  Implementation summary: {summary_path} — Status: {summary_status}
  ```

  If `summary_status` is absent (but `summary_path` is present), render it
  without the status suffix:

  ```
  Implementation summary: {summary_path}
  ```

- **No Background-equivalent section in the template.** The Background synonym
  set is `Background`, `Context`, `Why`, `Motivation`, `Summary`, `Goal`,
  `Objective`, `Overview` (the same set used for Background derivation above). If
  the consumer's template has no section matching any synonym, omit the reference
  silently and note the omission — never append it to an arbitrary section, and
  never fail PR creation over a missing synonym match. (The fallback path always
  has a `Background` section, so this case arises only in the template-driven
  path.)

- **Unreadable `summary_path`.** If `summary_path` is provided but the file
  cannot be read, omit the reference, note that it was unreadable, and proceed —
  never fail PR creation over a missing summary, consistent with the non-gating
  label handling in Stage 7.

- **Both absent.** When `summary_path` is absent (the five callers other than
  `zego-implement`), add no line — the PR body is byte-for-byte unchanged.

### Feature-Id trailer (best-effort, idempotent)

The calling skill writes the feature identifier into the artefact's frontmatter
*before* invoking `zego-create-pr` (the artefact-backed passing convention,
AIDEV-188 / ADR 020). Recover it from the artefact at `task_spec_path` and stamp
it as the **very last line of the PR body** — in the manner of a
`Co-Authored-By` trailer — so the (out-of-scope) reporting tool can correlate
sibling PRs. The trailer is a body line, never a top-level `##` section
(respects `docs/ai/steering/base/pull-requests.md` rule 8).

Recover the identifier:

```bash
FEATURE_ID="$(.claude/scripts/feature-id.sh recover "{task_spec_path}" 2>/dev/null || true)"
```

- **`FEATURE_ID` non-empty** — append `Feature-Id: {FEATURE_ID}` as the final
  line of the PR body composed above, **but only if the body does not already
  contain a `Feature-Id:` line** (idempotent — a re-run must never double-stamp;
  match the existing line case-insensitively, e.g. `grep -qiE '^feature-?id:'`).
- **`FEATURE_ID` empty** (no id recovered, or `recover` failed) — emit a warning
  to yourself and proceed without the trailer. This is **best-effort**: a recover
  or stamp failure must NEVER block or fail PR creation. A reporting gap is
  acceptable; a blocked skill is not.

### Open the PR

Open the PR using `gh pr create` with a HEREDOC body. When `FEATURE_ID` was
recovered and the body does not already carry one, the body's final line is the
`Feature-Id:` trailer.

**Fallback HEREDOC example** (used only when no template is present):

```bash
gh pr create \
  --title "{ticket}: {imperative-title}" \
  --base "$BASE" \
  --body "$(cat <<'EOF'
## Background

{Background prose derived from task spec Objective/Goal}
{When review_surface is supplied, on its own line within Background:
**Review surface for this phase:** {label} — {link}.
Omit this line entirely when review_surface is absent.}
{When summary_path is present, on its own line within Background:
Implementation summary: {summary_path} — Status: {summary_status}
Omit this line entirely when summary_path is absent.}

## Changes

{Verb-first bullet list from Stage 3}

## Jira Ticket/s

- https://zegons.atlassian.net/browse/{ticket}
{When FEATURE_ID was recovered and no Feature-Id: line is already present, on
its own final line of the body, after the last template section:
Feature-Id: {FEATURE_ID}
Omit this line entirely when FEATURE_ID is empty or already present.}
EOF
)"
```

When a template is present, the HEREDOC must mirror the template's section
structure instead of the fallback above. Apply the same derivation rules to
each section. The `Feature-Id:` trailer is still appended as the body's final
line, after whatever template the repo uses — never as a new `##` section.

Do not pass `--force`, `--draft`, or any flag that bypasses branch protection.
Do not embed credentials, tokens, or environment variables in the command.

---

## Stage 7 — Handle the result

**On success** — first apply labels (if any), then report to the caller.

If the `labels` input is present, split it on commas into individual label
names and apply them to the PR via the shared label script. Pass the PR URL
captured from `gh pr create` — the skill already holds it, so passing it avoids
a branch->PR re-resolution. This step runs **only on this success branch** —
never on the failure branch below — and is **non-gating**: a label outcome must
never fail or stop `zego-create-pr`. `pr-label.sh` is failure-tolerant and always
exits `0`.

```bash
.claude/scripts/pr-label.sh "{pr_url}" {space-separated label names}
```

For example, `labels: ai-design,ai-implementation` becomes:

```bash
.claude/scripts/pr-label.sh "{pr_url}" ai-design ai-implementation
```

If the `labels` input is absent, skip this step entirely — run no label
command. Behaviour is then byte-for-byte unchanged from a PR opened without
labels.

Then report to the caller:

- PR URL (from `gh pr create` output)
- Title used
- Branch

**On failure** — if `gh pr create` exits with a non-zero status:

1. Print the error output verbatim.
2. Stop. Do not retry, do not proceed to any subsequent stage.

Covered failure cases include (but are not limited to):

- Authentication failure (`gh` not authenticated)
- No remote configured
- PR already exists for this branch
- Branch protection rejection

---

## Rules

- **PR body must match the template.** When `.github/PULL_REQUEST_TEMPLATE.md`
  is present, the PR body must reproduce every section heading from the
  template in the template's order — no sections added, none removed. When no
  template is present, use the default three-section fallback (Background,
  Changes, Jira Ticket/s).
- **Ticket prefix is mandatory.** A task spec supplies it via the `ticket:`
  frontmatter key; a design doc (no `ticket:` key) supplies it via its `JIRA:`
  header line. `task_spec_path` accepts either artefact. Stop before
  constructing the title only when the artefact has *neither* a `ticket:` key
  nor a `JIRA:` header line. The task-spec missing-`ticket:` hard-stop is
  preserved for task specs (the `ticket:` key is present but empty/malformed);
  it is bypassed only on the design-doc branch (the `ticket:` key is absent).
- **The Feature-Id trailer is best-effort, idempotent, and a body line — never
  a section.** Recover the identifier via
  `.claude/scripts/feature-id.sh recover {task_spec_path}` and append
  `Feature-Id: {id}` as the body's final line, after whatever template the repo
  uses — never as a new `##` section (`pull-requests.md` rule 8). Skip the
  append when the body already carries a `Feature-Id:` line (idempotent). A
  recover or stamp failure warns and proceeds — it must never block or fail PR
  creation. When no id is recovered, add no line.
- **HEREDOC is mandatory.** Always pass `--body` via a shell HEREDOC. Do not
  use `--body "..."` with inline string quoting.
- **Full Jira URL.** `https://zegons.atlassian.net/browse/{ticket}` — never a
  bare ticket key, never a partial path.
- **No branch protection bypass.** Do not pass `--force` or equivalent flags.
- **No credentials in the skill.** `gh` must be pre-authenticated in the
  environment; do not embed tokens or environment variable references.
- **On gh failure, stop.** Do not swallow errors or proceed to any downstream
  stage.
- **The review-surface line is one inline line, never a section.** When
  `review_surface` is supplied, render exactly one bolded inline line
  (`**Review surface for this phase:** {label} — {link}.`) within Background —
  never a new `##` heading (`docs/ai/steering/base/review-audience.md`;
  consistent with `docs/ai/steering/base/pull-requests.md` rule 8). When
  `review_surface` is absent, render no line — the body is unchanged.
- **The label step is non-gating and success-branch only.** When `labels` is
  present, apply it via `.claude/scripts/pr-label.sh` only on Stage 7's success
  branch, after `gh pr create` has succeeded — never on the failure branch. A
  label outcome must never fail or stop `zego-create-pr`; `pr-label.sh` always exits
  `0`. When `labels` is absent, run no label command — behaviour is unchanged.
- **The implementation-summary reference is optional and non-gating.** When
  `summary_path` is present, append a single `Implementation summary: {summary_path}
  — Status: {summary_status}` line (status suffix omitted when `summary_status` is
  absent) to the Background-equivalent section in BOTH the template-driven and
  fallback paths — never as a new section (`pull-requests.md` Rule 8). When the
  template has no Background-synonym section, omit the reference and note the
  omission. When `summary_path` is unreadable, omit the reference, note it, and
  proceed — never fail PR creation over a missing summary. When both
  `summary_path` and `summary_status` are absent, add no line and behaviour is
  byte-for-byte unchanged.

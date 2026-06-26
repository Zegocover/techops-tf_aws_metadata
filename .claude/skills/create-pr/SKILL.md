---
name: create-pr
description: You MUST use this when the user asks to open a pull request for a completed implementation.
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
---

You are executing the `create-pr` skill. Your job is to open a pull
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
| `task_spec_path`   | yes      | Relative path to the task spec, e.g. `docs/tasks/AIDEV-25-TASK-01-create-pr-automatically.md` |
| `base`             | no       | Branch to target for the PR; if absent, defaults to the repo default branch |
| `labels`           | no       | Comma-separated label names to apply to the opened PR, e.g. `ai-implementation` or `ai-design,ai-implementation`. When absent, no label step runs. |

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

Read the task spec at `task_spec_path` in full. Extract:

- **`ticket`** — confirm it matches the `ticket` frontmatter field. If the
  task spec has no `ticket` field, stop immediately and report:
  > Task spec has no `ticket` frontmatter field. A ticket prefix is
  > required for the PR title. Cannot proceed.
- **Objective or Goal** — the section that explains *why* the change exists.
  This becomes the Background section of the PR body.

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
Instruct the user to commit their changes before running create-pr. Example
message:

> The working tree has uncommitted changes (listed above). Please commit them
> before running create-pr.

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
  section. Do not restate the diff. Do not hard-wrap prose.
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
order: Background, Changes, Jira Ticket/s.

### Open the PR

Open the PR using `gh pr create` with a HEREDOC body.

**Fallback HEREDOC example** (used only when no template is present):

```bash
gh pr create \
  --title "{ticket}: {imperative-title}" \
  --base "$BASE" \
  --body "$(cat <<'EOF'
## Background

{Background prose derived from task spec Objective/Goal}

## Changes

{Verb-first bullet list from Stage 3}

## Jira Ticket/s

- https://zegons.atlassian.net/browse/{ticket}
EOF
)"
```

When a template is present, the HEREDOC must mirror the template's section
structure instead of the fallback above. Apply the same derivation rules to
each section.

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
never fail or stop `create-pr`. `pr-label.sh` is failure-tolerant and always
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
- **Ticket prefix is mandatory.** If the task spec has no `ticket`
  frontmatter field, stop before constructing the title.
- **HEREDOC is mandatory.** Always pass `--body` via a shell HEREDOC. Do not
  use `--body "..."` with inline string quoting.
- **Full Jira URL.** `https://zegons.atlassian.net/browse/{ticket}` — never a
  bare ticket key, never a partial path.
- **No branch protection bypass.** Do not pass `--force` or equivalent flags.
- **No credentials in the skill.** `gh` must be pre-authenticated in the
  environment; do not embed tokens or environment variable references.
- **On gh failure, stop.** Do not swallow errors or proceed to any downstream
  stage.
- **The label step is non-gating and success-branch only.** When `labels` is
  present, apply it via `.claude/scripts/pr-label.sh` only on Stage 7's success
  branch, after `gh pr create` has succeeded — never on the failure branch. A
  label outcome must never fail or stop `create-pr`; `pr-label.sh` always exits
  `0`. When `labels` is absent, run no label command — behaviour is unchanged.

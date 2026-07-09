---
version: 1.0
last_reviewed: 2026-05-07
---

# Pull Request Standards

Conventions for structuring pull requests — the governing principle is that a PR exists to reduce reviewer cognitive load: Background front-loads context, Changes maps the diff, and Jira Ticket/s closes the automation loop. Apply these rules whenever opening or updating a pull request in any repository. Nothing in the PR content or authoring cycle (title, body, structure, sectioning) is mechanically enforced — the rules below describe how to author a PR, not how to gate one. Phase handoff between `zego-write-design-doc` → `zego-implement` → `zego-review` is the exception: it IS mechanically enforced (rule 10).

## Rules at a Glance

1. **Title format.** Begin the title with the Jira ticket number followed by a colon, use imperative mood, and keep it at or under 70 characters — the title is a one-line contract that tells reviewers what merged.
2. **Background answers why.** Write Background as the motivating problem, constraint, or context; never restate the diff — reviewers can read the diff, they cannot read your mind. A ticket link alone is not sufficient; include at least one sentence describing why the change exists even when a ticket is present.
3. **Changes is bulleted and verb-first.** List one bullet per meaningful change, opening each with an imperative verb — this maps the diff without burying the structure in prose.
4. **Jira Ticket/s as full URL.** Link each ticket as a full `https://zegons.atlassian.net/browse/TICKET` URL, one bullet per ticket — partial references break automation.
5. **Do not hard-wrap prose.** Leave Background and any prose content as flowing text; let GitHub's renderer wrap it — manual line breaks fragment copy-paste and diff readability.
6. **Do not open a PR unprompted.** Only create a pull request when the user explicitly asks — opening one prematurely forces review of incomplete work.
7. **Use HEREDOC for gh pr create.** Pass the PR body via a HEREDOC when using `gh pr create --body`, copying content from `.github/PULL_REQUEST_TEMPLATE.md` — the CLI does not auto-populate the repo's pull request template.
8. **PR body must match the template.** When `.github/PULL_REQUEST_TEMPLATE.md` is present, the PR body must reproduce every section heading from the template in the template's order — no sections added, none removed. When no template is present, use the default three-section fallback (Background, Changes, Jira Ticket/s). In either case, do not add extra top-level sections such as `## Test Plan` or `## Notes` — additional sections fragment the reviewer's reading path.
9. **Apply AI review triggers only on merge-ready branches.** Invoke review labels or workflows only when the branch is in a state you would merge today — every triggered run costs credits and asks a reviewer to read the output.
10. **Phase handoff is gated by the prior-phase PR.** The `zego-implement` and `zego-review` skills VERIFY at Stage 0 that the prior phase (design for `zego-implement`; implementation for `zego-review`) has an open or merged PR, and HALT if it does not. The gate is verification-only — it NEVER creates or opens a PR (consistent with rule 6). The documented per-invocation exception is `--no-handoff-gate`, intended for spikes and other legitimately design-doc-less work; the override is not a transient-`gh`-failure retry mechanism.
11. **A phase PR names its single review surface inline within Background.** When a PR is opened for a pipeline phase, the body names the one human review surface for that phase as a single bolded inline line within Background — `**Review surface for this phase:** {label} — {link}.` — never a new `##` heading. This is an inline addition consistent with rule 8 (it adds no section): see [review-audience.md](review-audience.md) for the classification, the per-phase surface labels, and the two mechanisms (`zego-create-pr`'s optional `review_surface` input and `zego-write-requirements`' inline composition) that emit it.

## Title format

The title serves two audiences: the reviewer scanning a PR list and the git log reader months later. A ticket prefix makes the title searchable and links it to the backlog without opening the body. Imperative mood ("Add", "Fix", "Remove") matches git convention and states what the merge accomplishes, not what it is doing.

The 70-character limit is a practical ceiling — most PR list views truncate beyond this and a title that fits in one line is faster to scan.

```
# good
AIDEV-16: Add pull-request standards file to base library

# bad — missing ticket, passive voice, over limit
Adding a new standards file for pull requests to the base standards library folder
```

## Background answers why

Reviewers arrive without the context you accumulated while writing the code. The diff shows them *what* changed; Background must tell them *why* the change exists at all. A Background that restates the diff ("This PR adds an index to the users table") leaves reviewers to infer the motivation themselves. A Background that answers why ("Queries against users were timing out under load; adding an index on email drops p99 latency to under 50 ms") lets them evaluate the approach immediately.

Keep Background as one or two sentences of flowing prose. If the motivation is a Jira ticket, a sentence that summarises the problem is still required — a ticket link alone is not Background.

```
# good
Background: The CI pipeline was re-running all integration tests on every push,
causing 20-minute wait times for trivial changes. This splits the test suite so
unit tests run on every push and integration tests run only on merge to main.

# bad — restatement of the diff
Background: This PR splits the test suite into unit and integration test jobs.
```

## Changes is bulleted and verb-first

The Changes section maps the diff to intent. Reviewers use it to orient themselves before opening files — a bulleted list with one item per meaningful change lets them build a mental model of scope in seconds. Prose narration ("I updated the handler and also changed the model and then fixed the test") buries structure.

Verb-first bullets ("Add", "Extract", "Remove", "Fix") make the nature of each change immediately clear without reading the full bullet.

```
# good
Changes:
- Add `split-tests.yml` CI workflow for unit/integration separation
- Remove integration test step from `ci.yml`
- Update `Makefile` targets to match new workflow names

# bad — prose, no verbs, opaque scope
Changes:
The CI workflow was changed along with the Makefile and the old integration
step was removed as part of this work.
```

## Jira Ticket/s as full URL

Full URLs ensure that GitHub, Slack, and any webhook integrations can resolve the link without knowing the Jira base URL. Partial references (`AIDEV-16`, `#16`, bare ticket numbers) are readable to humans but break automated linkage in most CI and notification pipelines.

Use the heading `Jira Ticket/s` exactly — this matches the template header that automation may key on.

```
# good
Jira Ticket/s:
- https://zegons.atlassian.net/browse/AIDEV-16

# bad — partial reference
Jira Ticket/s: AIDEV-16
```

## Use HEREDOC for gh pr create

GitHub populates the PR body from the repository's `PULL_REQUEST_TEMPLATE.md` only when the PR is opened through the web UI. When using `gh pr create`, the `--body` flag requires the full body text — the template is not injected automatically.

Read the template from `.github/PULL_REQUEST_TEMPLATE.md` and paste its structure into the HEREDOC, filling in the placeholders. Pass the body via a shell HEREDOC to preserve newlines and avoid quoting issues:

```bash
# good — template structure copied from .github/PULL_REQUEST_TEMPLATE.md
gh pr create --title "AIDEV-16: Add pull-request standards file" --body "$(cat <<'EOF'
## Background

The base standards library had no file covering pull request structure, leaving
teams to reinvent the template independently.

## Changes

* Add `docs/ai/steering/base/pull-requests.md`
* Update `docs/ai/steering/base/README.md` with new entry

## Jira Ticket/s

* https://zegons.atlassian.net/browse/AIDEV-16
EOF
)"

# bad — template not injected, body empty or malformed
gh pr create --title "AIDEV-16: Add pull-request standards file"
```

## Apply AI review triggers only on merge-ready branches

AI review labels and workflow triggers (such as a `claude-review` label or a `/review` comment) invoke an automated reviewer that costs API credits and produces output that a human reviewer is then expected to read. Triggering a review on a draft, a work-in-progress branch, or a branch that will need significant rework wastes both budget and reviewer attention.

Only apply review triggers when the branch is in a state you would merge today if the review came back clean.

## Name the phase's single review surface

A pipeline PR exists for one phase — design, implementation, requirements — and each phase has exactly one artefact a human is meant to review. Naming it on the PR stops reviewers spreading attention across the AI-native artefacts the phase also touches (task specs, findings files, diagnosis records), which carry their own deflecting banner per [review-audience.md](review-audience.md). The signal is a single bolded inline line within Background, so it costs the reviewer one line and adds no section:

```
# good — inline within Background, no new heading
## Background

The pipeline produced no signal telling reviewers which artefact to read.

**Review surface for this phase:** the design document — docs/design/AIDEV-16-foo.md.

# bad — a new top-level section (violates rule 8)
## Review surface

The design document — docs/design/AIDEV-16-foo.md.
```

Two mechanisms emit this identical line, depending on whether the phase PR is opened through `zego-create-pr`: the optional `review_surface` input (`zego-write-design-doc`/`-max`, `zego-implement`, `zego-fix-bug`) and inline composition (`zego-write-requirements`). See [review-audience.md](review-audience.md) for the per-phase labels and the full contract.

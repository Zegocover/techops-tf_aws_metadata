---
version: 1.0
last_reviewed: 2026-06-11
---

# Skill Pipeline

How the standards-library skills compose into the development pipeline — which
skill to use when, what order they run in, and when a step is skippable or
off-path. The governing principle is that the pipeline is a default sequence,
not a mandatory one: the happy path runs requirements through to a merged PR,
but most steps are conditional on context, and several skills sit deliberately
off the path. This document names the skills and their ordering; it does not
restate what each skill does internally — read the skill's own `SKILL.md` for
that. Apply this routing whenever deciding which skill answers a request, and
keep it current as the skill set changes.

> **Do your homework first.** These skills *formalise* investigation you have
> already done — they turn your real requirements, decisions, and research into
> structured artefacts. They are **not** a substitute for doing that
> investigation, and must not be used to invent or fill in information you have
> not actually established. Gather the real requirements, make the real design
> decisions, and do the real research *before* invoking the pipeline; then use
> these skills to capture and sharpen that work. A skill given gaps will produce
> a confident-looking artefact built on guesses. This is the single most
> important thing to understand before using the pipeline.

## Rules at a Glance

0. **These skills formalise your prior investigation — do your homework first.**
   Every pipeline skill structures work you have *already* done; none of them is
   a substitute for the investigation. Arrive with the real requirements,
   decisions, and research in hand, and do not use a skill to fill in
   information you have not actually established.
1. **The happy path is four skills in order.** `write-requirements` →
   `write-design-doc` → `implement` → `write-acceptance-handoff`. This is the
   default route for a feature that starts from a product need and ends at a
   merged, signed-off change.
2. **Each phase hands off through its own PR — not one PR at the end.** The
   design phase, the implementation phase, and any remediation each produce a
   pull request. The design phase's PR must be `OPEN` or `MERGED` before
   `implement` or `review` runs (the Stage 0 handoff gate). A PR is never
   opened automatically.
3. **`write-requirements` is skippable when requirements are already certain.**
   The test: could you brief `write-design-doc` without being interviewed?
4. **`write-design-doc` is the default; `write-design-doc-max` is the explicit
   deep-review variant.** Use `-max` only when the user asks for it by name.
5. **`fix-buildkite` and `fix-pr-comments` are conditional remediation, not
   stages.** Invoke them only when CI fails or review threads need addressing.
6. **Some skills are off-path utilities.** Standalone `review`,
   `ci-validation`, `extend-claude-standards`, `write-standard`, and
   `write-skill` are reached on demand, not forced into the sequence.

## The happy path

For a feature that starts from a product need and ends at a merged, signed-off
change, the default sequence is:

```
write-requirements → write-design-doc → implement → write-acceptance-handoff
```

Read it as a default, not a mandate. Every step is conditional on context (the
skip rules below), and the path is not a single PR opened at the end: each
phase produces its own pull request, and remediation skills sit off the line
entirely.

| Step | Skill | Purpose in the flow |
|---|---|---|
| 1 | `write-requirements` | Interview a PM or product owner to certainty; produce a structured requirements document. |
| 2 | `write-design-doc` | Refine requirements into a design document and per-task specs. |
| 3 | `implement` | Build the artefact described by a task spec. |
| 4 | `write-acceptance-handoff` | Produce the post-merge acceptance document for product sign-off. |

## Phased-PR handoff shape

The pipeline is **phased**: each phase's audit trail is its own pull request,
and the next phase is gated on the prior phase's PR existing. The work is not
one PR opened at the very end.

- The **design phase** hands off via a design-phase PR. Before `implement` or
  `review` runs, a **Stage 0 handoff gate** verifies that the prior phase has a
  pull request in `OPEN` or `MERGED` state and halts if it does not. For
  `implement` the prior phase is design (the gate resolves the design branch
  out of the design doc); for `review` the prior phase is implementation (the
  gate checks the current branch's PR).
- The gate is **verification-only**: it inspects PR state and never creates or
  opens a PR. A PR is opened only when the user explicitly asks — see
  `docs/ai/steering/base/pull-requests.md`.
- The per-invocation override is `--no-handoff-gate`. It is for legitimately
  design-doc-less work (a spike, for example), **not** a retry mechanism for a
  transient `gh` failure — the fix for a `gh` failure is to repair `gh` and
  re-run, not to bypass the gate.

## Skip rules

`write-requirements` is skippable when the requirements are already certain —
a rich Jira ticket, an existing requirements or design document, or stated
research that has already been done. The test:

> Could you brief `write-design-doc` without being interviewed first?

If yes, skip `write-requirements` and start at `write-design-doc`. If the
requirements are still fuzzy enough that the design interview would stall on
"what are we actually building?", run `write-requirements` first.

## Variant selection

`write-design-doc` is the **default** design-doc flow. `write-design-doc-max`
produces the same artefacts but spends much more context running an incremental
review of every design and task document; use it **only when the user asks for
the "max" flow by name**. A generic request to "write a design doc" routes to
`write-design-doc`.

## Per-skill posture notes

- **`write-design-doc` is prompt refinement, not discovery.** Arrive with the
  research done — the skill sharpens a brief into a design and task specs; it
  does not investigate the problem space for you. This is why the
  `write-requirements` skip test is "could you brief it without an interview".
- **`ci-validation` relates to the `ci-test-command` frontmatter key.** When
  `ci-test-command` is present in CLAUDE.local.md's frontmatter, it is the
  explicit override for the commands CI validation runs before committing. When
  the key is absent, validation discovers the commands automatically from
  `.buildkite/pipeline.yml` or `.github/workflows/*.yml`. Declaring the key is
  the fix when automatic discovery is inconsistent. `ci-validation` runs inside
  `implement` and is also available standalone (see off-path utilities).
- **`review` checks the diff against the standards.** On the happy path it is
  not a separate stage: `review` runs inside `implement`'s review-until-PASS
  loop and is also available standalone (see off-path utilities) as the
  post-PR, on-demand variant. The review mechanics themselves — check groups,
  severities, output format — live in `docs/ai/steering/base/code-review.md`.
- **`create-pr` opens a phase's PR — not a separate happy-path step.** Like
  `review` and `ci-validation`, it runs inside the phase skills:
  `write-design-doc` (and `write-design-doc-max`) and `implement` invoke it to
  open the design- and implementation-phase PRs, and `fix-bug` invokes it for a
  bug-fix PR. It is also available standalone for opening a PR outside those
  flows.

## Conditional remediation

These are **post-PR** steps, invoked only when something needs fixing — not
unconditional stages in the sequence:

- **`fix-buildkite`** — invoke when a Buildkite CI build fails: diagnose, fix,
  retry.
- **`fix-pr-comments`** — invoke when a pull request has unresolved review
  threads that need addressing.

If CI passes and the PR has no outstanding threads, neither runs.

## Off-path utilities

These skills are reached on demand and must not be forced into the happy-path
sequence:

- **`review`** (standalone) — run a standards review of a branch outside
  `implement`'s internal review loop, with or without a task spec.
- **`ci-validation`** (standalone) — run CI validation locally to verify a
  branch passes before committing, independent of `implement`.
- **`extend-claude-standards`** — deepen or fill gaps in a repo's
  `CLAUDE.local.md` repository-context section.
- **`write-standard`** — author a new standards file or extend an existing one.
- **`write-skill`** — author a new skill. When a new skill enters the pipeline
  flow, `write-skill` maintains this document so the happy path and off-path
  sections stay current.

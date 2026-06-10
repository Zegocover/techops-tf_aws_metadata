# Handoff gate — shared across skills

This file is referenced by calling skills (currently `.claude/skills/implement/task-implementer.md`,
`.claude/skills/implement/feature-orchestrator.md`, and `.claude/skills/review/SKILL.md`). It
contains the single, parameterised PR-existence query that supports the
design → implement → review handoff: the prior phase must have an open or
merged pull request before the next phase begins.

The gate is read-only — it verifies whether a PR exists for a given branch
and returns a **sentinel object** describing what it found. It does NOT
print halt messages and does NOT halt control flow (the override notice in
Step 1 is the only I/O the gate emits). **It NEVER creates or opens a PR.**
The override (`--no-handoff-gate`) is a verification bypass, not a transient
`gh`-failure retry mechanism.

The caller owns the halt decision and the halt message. Canonical halt-message
templates are defined in the "Halt-message templates" section at the end of
this document — callers MUST use them verbatim so messages stay consistent
across skills.

## Caller contract

The calling skill must fill the following placeholders before executing:

| Placeholder | Required | Description |
|-------------|----------|-------------|
| `{branch}` | yes | The prior-phase branch whose PR must exist. For `implement` this is the design branch read from the design doc's `Branch:` header. For `review` this is the current branch (`git rev-parse --abbrev-ref HEAD`). |
| `{override_active}` | yes | Boolean. The caller has already parsed `--no-handoff-gate` from its arguments; the gate trusts this value verbatim. |

The gate does NOT take `{phase_name}` or `{skill_name}` — the gate no longer
formats halt messages, so it has no use for them. Those placeholders belong
to the caller-owned halt-message templates below.

### Return

The gate is a pure query. It returns one of the following sentinel objects to
the caller and does not halt or print anything other than the Step 1 override
notice:

| Sentinel | Meaning | Caller action |
|----------|---------|---------------|
| `{state: "OVERRIDE"}` | `{override_active}` was true; the override notice was printed by the gate in Step 1. | Treat as pass. Proceed without checking PR state. |
| `{state: "OPEN", number, url}` | Non-draft open PR exists for `{branch}`. | Pass. Proceed. |
| `{state: "MERGED", number, url}` | A merged PR exists for `{branch}`. | Pass. Proceed. |
| `{state: "NONE"}` | No PR exists for `{branch}`. | HALT. Use the `NONE` template below. |
| `{state: "CLOSED", number, url}` | A PR exists for `{branch}` but it is closed. | HALT. Use the `CLOSED` template below. |
| `{state: "DRAFT", number, url}` | The most recent PR for `{branch}` is a draft. | HALT. Use the `DRAFT` template below. |
| `{state: "GH_FAIL", stderr}` | `gh` exited non-zero. | Surface `stderr` verbatim and HALT. Use the `GH_FAIL` template below. |

The gate itself never halts the calling skill — even on `gh` failure. It
surfaces the error via the `GH_FAIL` sentinel so the caller can decide how to
present it. In practice, the canonical action for `GH_FAIL` is "print the
template and HALT", but that decision lives in the caller.

---

## Step 1 — Override short-circuit

If `{override_active}` is true, print this line verbatim:

```
Handoff gate overridden via --no-handoff-gate — proceeding without verifying the {phase_name} PR.
```

Note: the `{phase_name}` token in the override line is filled by the caller
before invoking the gate — it is the only placeholder the caller substitutes
into a gate-printed line. (Alternatively, the caller may print this notice
itself; the requirement is that the override notice is printed exactly once
when the override is active.)

Then return `{state: "OVERRIDE"}` to the caller. **Do not run Step 2.** This
is the override path: no PR check is performed.

The override is a verification BYPASS — never use it to mask a flaky `gh`. A
`gh` non-zero exit (Step 2) is a tooling failure that must be fixed, not
suppressed.

---

## Step 2 — Resolve PR state for `{branch}`

Run the following command exactly:

```bash
gh pr list --head {branch} --state all \
  --json state,createdAt,number,url,isDraft \
  --jq 'if length == 0 then {state:"NONE"} else sort_by(.createdAt) | last | (if .isDraft then {state:"DRAFT", number, url} else {state, number, url} end) end'
```

The jq filter resolves to an object whose `.state` is one of `OPEN`, `MERGED`,
`CLOSED`, the sentinel `NONE` (when no PR exists for the branch), or the
sentinel `DRAFT` (when the most recent PR is a draft — `gh` reports draft PRs
with `state: "OPEN"` and `isDraft: true`, so the filter promotes draft-ness
to a distinct sentinel). The `.number` and `.url` fields name the resolved PR
when one exists.

**If `gh` exits non-zero** (unauthenticated, no remote configured, transient
network failure): return `{state: "GH_FAIL", stderr}` to the caller, where
`stderr` is the captured stderr of the `gh` command verbatim. **Do NOT retry.
Do NOT treat a non-zero exit as `NONE`.** A tooling failure must never be
silently classified as "no PR" — that would defeat the audit-trail guarantee.
The caller will surface the error and halt.

---

## Step 3 — Return the sentinel

Return the resolved object verbatim to the caller — exactly as produced by
the jq filter, or the `GH_FAIL` sentinel from Step 2. The gate does NOT
print, does NOT halt, and does NOT format halt messages. The caller inspects
`.state` and either proceeds (on `OPEN`, `MERGED`, or `OVERRIDE`) or halts
using the templates below.

---

## Halt-message templates

Callers MUST use these templates verbatim when halting on a non-pass
sentinel. Keeping the message text consistent across skills is the whole
reason the templates live here. Fill the placeholders from the caller's
context (`{phase_name}`, `{skill_name}`, `{branch}`) and the gate's
sentinel object (`{number}`, `{url}`, `{stderr}`).

### `NONE` → HALT template

```
No {phase_name}-phase PR found for branch '{branch}'. {skill_name} requires the prior phase to have an open or merged PR. Open one, or pass --no-handoff-gate for a spike.
```

### `CLOSED` → HALT template

```
The {phase_name}-phase PR for branch '{branch}' (#{number}, {url}) is CLOSED, not open or merged. {skill_name} requires an open or merged PR. Reopen or replace it, or pass --no-handoff-gate for a spike.
```

This is intentionally distinct from `feature-orchestrator.md` OM-5's per-task
PR check, which treats `CLOSED` as resume-with-warning. The handoff gate
checks a prior-phase PR for audit-trail purposes — a `CLOSED` prior-phase PR
means the upstream artefact was rejected, and the next phase must not silently
proceed on a rejected handoff.

### `DRAFT` → HALT template

```
The {phase_name}-phase PR for branch '{branch}' (#{number}, {url}) is still a DRAFT, not ready-for-review. {skill_name} requires the prior phase to have formally requested review. Promote the draft to ready-for-review, or pass --no-handoff-gate for a spike.
```

The handoff gate is about the prior phase having **formally requested
review** — a draft PR is explicitly not such a request. Treating draft as
pass would let an in-progress design silently feed the next phase, defeating
the audit-trail guarantee.

### `GH_FAIL` → HALT template

```
gh failed while checking the {phase_name}-phase PR for branch '{branch}':

{stderr}

{skill_name} requires `gh` to verify the prior-phase PR. Resolve the gh failure (authentication, remote, or network) and re-run. --no-handoff-gate is a verification bypass, not a transient-failure retry — do not use it to paper over a gh error.
```

---

## Rules

- **The gate is a pure query.** It never halts the calling skill and never
  prints non-override I/O. Its only output is the sentinel object returned to
  the caller (plus the Step 1 override notice when `{override_active}` is
  true).
- **The override short-circuits BEFORE any `gh` call.** Step 1 runs before
  Step 2. An override never causes a `gh` invocation and never produces a
  non-`OVERRIDE` sentinel.
- **Caller passes only on `OPEN` (non-draft), `MERGED`, or `OVERRIDE`.** No
  other sentinel passes. A draft PR — `gh`'s `state: "OPEN"` with
  `isDraft: true` — is promoted to a `DRAFT` sentinel by the jq filter and
  must be halted on by the caller.
- **Caller HALTS on `NONE`, `CLOSED`, `DRAFT`, and `GH_FAIL`** using the
  templates above. Halt-message text is owned by the templates here — callers
  must not paraphrase.
- **No retry on `gh` failure.** The gate stays simple and honest; the caller
  surfaces stderr and the engineer fixes `gh` and re-runs.
- **Never open or create a PR from this gate.** The gate verifies — it never
  authors. Consistent with `docs/ai/steering/base/pull-requests.md` rule 6.
- **Caller fills every placeholder.** A missing placeholder is a caller bug,
  not a gate bug.

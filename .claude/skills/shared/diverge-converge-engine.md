# Diverge/converge engine — shared across skills

This file is referenced by calling skills (currently
`.claude/skills/zego-brainstorm/SKILL.md`). It is the reusable engine behind the
`zego-brainstorm` skill: a parameterised **diverge → cross-examine → converge** loop
that a thin caller fills with a mode, a set of lenses, and a ticket's confirmed
requirements, in the same Read-and-fill style as
`.claude/skills/shared/handoff-gate.md` and
`.claude/skills/shared/ci-validation-loop.md`.

AIDEV-170 delivers this engine; approach mode is its first caller. The engine is
factored so future modes (e.g. a discovery mode) reuse the same machinery by
passing different parameters — the caller owns *what* to diverge over, the engine
owns *how* the council runs and how the artefact is produced.

The engine's whole reason to exist is **rolling-context discipline**. Every
expensive read and every long piece of council reasoning happens inside a
sub-agent and returns **compact**. The orchestrator's context only ever holds:
the requirements, a grounding *digest*, the N approach *summaries*, the Skeptic's
cons, and the converge dialogue. The verbose prose and the full artefact body
never enter the orchestrator's context — the authoring sub-agent
(`.claude/skills/shared/diverge-converge-author.md`) writes the Markdown to disk
and returns only a sentinel, and converge edits the file through targeted section
edits rather than holding it. See the "Rolling-context rules" section.

The artefact is a single front-mattered Markdown file. There is no separate
structured source and no renderer: the authoring sub-agent writes the Markdown
body directly, and diagrams are `mermaid` fenced blocks that render natively in
GitHub and IDE preview.

---

## Caller contract

The calling skill must fill the following placeholders before executing:

| Placeholder | Required | Description |
|-------------|----------|-------------|
| `{ticket}` | yes | JIRA ticket key, e.g. `AIDEV-172`. |
| `{ticket_url}` | yes | Canonical ticket URL, e.g. `https://zegons.atlassian.net/browse/AIDEV-172`. |
| `{title}` | yes | One-line human title for the artefact, e.g. the ticket summary. |
| `{date}` | yes | Today's date, `YYYY-MM-DD`, passed in by the caller (the engine never invents one). |
| `{mode}` | yes | The diverge mode. For the `zego-brainstorm` skill this is `approach`. Determines the artefact shape. |
| `{requirements}` | yes | The confirmed requirements the council converges against — a bulleted list, treated as the fixed brief. |
| `{lenses}` | yes | The ordered advocate lenses, one advocate per lens. For approach mode (fixed, N=3): **minimal / YAGNI**, **idiomatic reuse**, **robust / strategic**. |
| `{rubric}` | yes | The ordered dimensions each candidate approach is assessed against and the comparison rows are built from. For approach mode: requirements fit / codebase fit / effort & complexity / risk & reversibility / durability / standards & decided-against. Carries no numeric scores — each dimension yields a one-line prose verdict per approach. |
| `{grounding_hints}` | no | Optional pointers for the grounding pass — files, dirs, ADRs, search terms worth reading first. The grounding agent decides what to read; these only seed it. |
| `{artefact_path}` | yes | The single front-mattered Markdown artefact on disk. For approach mode: `docs/exploration/{ticket}-approaches.md`. |

There is no `{source_path}` and no `{renderer}` — the single-layer Markdown
artefact retired both.

### Return

The engine is interactive — it ends only when the engineer converges or walks
away. It returns one of the following sentinel objects to the caller:

| Sentinel | Meaning | Caller action |
|----------|---------|---------------|
| `{state: "CONVERGED", choice, artefact_path}` | The engineer settled on an approach (`choice` = its id/lens, or a redirected hybrid). The artefact on disk reflects it. | Report the artefact path and the chosen approach. |
| `{state: "UNRESOLVED", reason, artefact_path}` | The council ran and the artefact exists, but the engineer could not settle on paper — typically unresolved Skeptic dissent. The artefact records the open dissent. | Report the artefact and suggest carrying the dissent into a spike (the natural next door). |
| `{state: "ABANDONED", reason}` | The engineer stopped the session before convergence, or a precondition failed (no requirements). | Report `reason`. No artefact is presented as final. |

The engine does NOT open PRs, does NOT commit, and does NOT gate anything. It is
opt-in exploration: the caller decides what to do with the artefact.

---

## Step 0 — Preconditions and prior-artefact detection

**0a — Requirements check.** `{requirements}` must be non-empty and substantive.
If the caller passes an empty or one-line brief, return
`{state: "ABANDONED", reason: "requirements too thin to diverge against"}` — the
council needs a fixed brief to compare approaches against. Spawn no council.

**0b — Directory.** The directory for `{artefact_path}` must exist or be
creatable. Create `docs/exploration/` if absent (`mkdir -p`).

**0c — Prior-artefact detection (skill-idempotency Rules 3, 5, 9).** Before
spawning anything, check whether `{artefact_path}` already exists on disk. If it
does, read **only its front-matter** (the leading `---` block) to classify it by
the `state` field, then branch:

- **`state: exploring`** → a prior run was interrupted mid-exploration. Verify
  the required Interface 4 body sections are all present (see "Body integrity
  check" below) **before** resuming.
  - **All required sections present** → **resume-forward** (Rule 5). Re-establish
    position from `state`, `choice`, and `converge_log` plus the body, and present
    the existing artefact to the engineer. Do **not** re-spawn the grounding or
    advocate sub-agents, and do **not** re-run the council — the prior council's
    output is already on disk. The artefact stays **byte-unchanged** until the
    engineer steers. Skip Steps 1–3 and go straight to Step 4 (converge).
  - **One or more required sections absent** → this is a **failed partial write**
    (the authoring sub-agent crashed mid-write). Do **not** resume-forward over an
    incomplete body. Surface the Rule 9 three-way choice (0d) instead.
- **`state: converged`** → the artefact is complete. Surface the Rule 9
  three-way choice (0d).
- **`state: unresolved`** → treat **identically** to `converged`: the artefact is
  complete but unsettled. Surface the Rule 9 three-way choice (0d).

If `{artefact_path}` does not exist, this is a fresh run — proceed to Step 1.

**Body integrity check.** The required Interface 4 body sections are, in order:
`## Recommendation`, `## Requirements`, `## Grounding`, `## Candidate approaches`,
`## Skeptic's dissent`, `## Open questions` (plus the `# Approaches: …` title).
A `state: exploring` artefact missing any of these heading lines is a failed
partial write. Detect by reading the section headings only — never the whole body.

**0d — Rule 9 three-way choice.** Present the engineer with the explicit choice
(skill-idempotency Rule 9):

- **stop** → return `{state: "ABANDONED", reason: "engineer chose to stop; existing artefact left untouched"}`. Leave the artefact **byte-unchanged**, produce no new artefact path, and do **not** exit silently — the `ABANDONED` sentinel is the observable signal.
- **start fresh** → an author-consented reset (not a silent reset, so Rule 5 is honoured). For a partial-write artefact, delete the partial file first. Append a one-line note to `converge_log` recording the decision (`"start-fresh chosen; prior {state} artefact discarded"`), then run the full council from Step 1.
- **edit** → resume-forward from the existing artefact into Step 4 (converge), exactly as the `exploring`-with-all-sections branch does. (Not offered for a partial-write artefact — there is no complete body to edit; offer only stop or start-fresh there.)

Record the chosen decision as a one-line `converge_log` note in every case where
the artefact survives (start-fresh, edit). On stop, leave the file untouched.

---

## Step 1 — Shared grounding pass (one sub-agent, read once)

Grounding is **one** high-level read, shared by the whole council, done in a
sub-agent so the file reads never enter the orchestrator's context. Spawn a
single read-only `Agent`. Fill every placeholder before sending.

```
You are the grounding pass for a brainstorm council on ticket {ticket}.
Read-only: do not write, edit, or run anything that mutates state.

The council will propose candidate {mode} approaches for these confirmed
requirements:
{requirements}

Optional starting pointers (seed only — read what you judge relevant):
{grounding_hints}

Do ONE high-level grounding pass. You are mapping the territory, not designing a
solution and not reading down to change-site depth. Establish:
- Which modules / files / skills are relevant, and what they currently do.
- The established patterns and conventions an approach here should fit.
- What already exists that could be reused or extended (name it with paths).
- Any ADRs, steering docs, or prior decisions that bear on this (decided-against
  territory). Cite docs/decisions/*, docs/ai/steering/*, CLAUDE*.md as relevant.

Return a COMPACT digest (target <= 400 words), no file dumps. Structure:
1. One-paragraph summary of the relevant area.
2. Findings as a short list, each: finding — evidence (path) — consequence for the approaches.
3. Any decided-against constraints the council must respect.
Return prose/bullets only — this digest is the council's shared ground truth.
```

If the grounding sub-agent returns an explicit failure (e.g. a `FAILED`
response, a crash, or no usable digest), **retry once** with the same prompt. If
it fails again after the retry, return
`{state: "ABANDONED", reason: "grounding pass failed after retry; the council cannot run without a shared grounding digest"}`.
Present no artefact as final.

Hold only the returned digest. Do NOT re-read the files it cites.

---

## Step 2 — Diverge: the council (parallel sub-agents)

The council is N **advocates** (one per `{lenses}` entry) plus one distinct
**Skeptic**, each in its own context over the shared grounding digest. Advocates
generate; the Skeptic attacks. This split is deliberate: an advocate under-sells
its own approach's cons and Claude skews optimistic, so honest cons come from
cross-examination by a separate role, not self-reporting.

### 2a — Advocates (spawn all in parallel, one per lens)

Spawn the N advocate `Agent`s **in a single message** (parallel; read-only, no
worktrees — see the read-only-council note in the Rules). Each gets the same
requirements and the same grounding digest, and differs only by its lens. Fill
placeholders per advocate.

```
You are an advocate on a brainstorm council for ticket {ticket}.
Your lens: {lens}.
  - minimal / YAGNI: smallest change that satisfies the requirements; accept the
    limitations that buys.
  - idiomatic reuse: extend what already exists and fit established patterns; the
    careful Zego engineer's default.
  - robust / strategic: invest in the right abstraction for the long term; accept
    higher upfront cost.
(Apply only YOUR lens above.)

Confirmed requirements (the fixed brief):
{requirements}

Shared grounding digest (the council's ground truth — do not re-read the codebase
beyond spot-checking a path if strictly necessary):
{grounding digest from Step 1}

Propose ONE concrete approach through your lens. Be specific and grounded in the
digest — name the files/modules it touches and what it reuses vs adds. Advocate
honestly for it; do NOT list its weaknesses (the Skeptic does that).

Return COMPACT (target <= 250 words):
- name: a short handle for the approach.
- summary: 2-4 sentences on what it does and how.
- touches: the files/modules/components it changes or adds (paths).
- reuses: what existing code/pattern it leans on.
- pros: 2-4 bullets — why this lens makes it a good choice.
- optional sketch: a one-line Mermaid flowchart string if it clarifies the shape.
No preamble. Keep the labels — the authoring sub-agent parses them into sections.
```

Retry any advocate that returns an explicit failure or no usable summary **once**.
Collect the surviving compact returns. Hold only these summaries.

**Advocate failure routing (degrade by degree):**

- **A single advocate still fails after its retry** → proceed with the surviving
  lenses (a **degraded run**). Append a one-line note to `converge_log` recording
  the lost lens (e.g. `"degraded run: advocate '{lens}' failed after retry; proceeding with surviving lenses"`).
  Continue — do **not** abandon.
- **Two or more advocates lost** → the comparative basis is gone. Return
  `{state: "ABANDONED", reason: "two or more advocates failed after retry; no comparative basis for a council"}`.

### 2b — Skeptic (one sub-agent, after advocates return)

Spawn one Skeptic `Agent` with the requirements, the grounding digest, and all
surviving advocate summaries. It cross-examines every approach against `{rubric}`.

```
You are the Skeptic on a brainstorm council for ticket {ticket}. You did not
write any of these approaches. Your only job is to cross-examine them honestly —
advocates under-sell their own cons and Claude skews optimistic, so you are the
council's only source of real dissent.

Confirmed requirements:
{requirements}

Shared grounding digest:
{grounding digest from Step 1}

The candidate approaches (from the advocates):
{the surviving advocate summaries}

Assess EACH approach against the same rubric. Be concrete; tie every con to a
requirement, a path, or a decided-against constraint from the digest:
{rubric}
  1. Requirements fit — does it satisfy every confirmed requirement? Name any AC left uncovered.
  2. Codebase fit — does it go with the grain? What it touches, reuse vs new.
  3. Effort & complexity — rough size, moving parts, new dependencies.
  4. Risk & reversibility — blast radius, what breaks if wrong, one-way vs two-way door.
  5. Durability — maintainability/extensibility; creates or pays down debt?
  6. Standards & decided-against — conflicts with an ADR or steering decision?

Return COMPACT, per approach (target <= 150 words each):
- For each rubric dimension: a one-line verdict (the honest read, not a score).
- cons: the 2-4 most material weaknesses, each tied to evidence.
Then overall:
- dissent: the single sharpest unresolved risk across all approaches — the thing
  that, if it cannot be settled on paper, should be tested in a spike.
NO numeric or percentage confidence scores anywhere. Words, not numbers.
```

Retry the Skeptic **once** on an explicit failure. If it still fails after the
retry, the comparative basis is gone — return
`{state: "ABANDONED", reason: "Skeptic failed after retry; no cross-examination basis for a council"}`.

Hold only the Skeptic's compact return.

---

## Step 3 — Synthesise the recommendation and dispatch the authoring sub-agent

**3a — Synthesise the recommendation inline.** Before dispatching the authoring
sub-agent, the orchestrator synthesises the recommendation **itself** from the
advocate rubric verdicts and the Skeptic's cons (mirroring the spike's
"synthesise the recommendation yourself" step):

- `choice` — the recommended approach id (or a hybrid handle).
- `headline` — ONE crisp sentence for the verdict, not the full rationale.
- `rationale` — "recommend X because …", drawn from the rubric verdicts and the
  Skeptic's cons.
- `pick_instead_if` — the condition under which a different approach wins.

No numeric or percentage scores. The Skeptic's dissent is preserved, not averaged
away. This synthesised recommendation is exactly what Interface 2 passes to the
authoring sub-agent.

**3b — Dispatch the authoring sub-agent (full-write mode).** Read
`.claude/skills/shared/diverge-converge-author.md` and dispatch a single
`Agent` in **full-write mode**. Pass it: the machine scalars (`{ticket}`,
`{ticket_url}`, `{title}`, `{date}`, `{mode}`), `{requirements}`, the grounding
digest, the surviving advocate summaries, the Skeptic's per-approach cons and
dissent, the synthesised recommendation (3a), the open questions, `{artefact_path}`, and
the accumulated `converge_log` (any Step 2a / Step 0d notes; omit if none have
accumulated, in which case the author initialises it empty). The sub-agent writes the full Markdown body to disk and
returns **only** a compact sentinel — for example `WROTE {artefact_path}`. The
verbose body never returns to the orchestrator.

On a **full-write failure** (the sub-agent returns an explicit error sentinel,
crashes, or returns no `WROTE` sentinel), retry **once**. If it still fails,
return
`{state: "ABANDONED", reason: "authoring sub-agent failed to write the artefact"}`.
Never present the artefact (or a half-written artefact) as final.

On success, the on-disk artefact carries `state: exploring` (the authoring
sub-agent sets it). The orchestrator holds only the sentinel.

---

## Step 3.5 — The one `/compact` offer

Immediately after the artefact full-write and **before** converge begins, surface
exactly **one** optional `/compact` offer to the engineer:

```
The full approach brief is written to {artefact_path}. An approach session can
run long — you may run /compact now to reclaim context before we converge, or
carry straight on. Converge reads from the file, so compacting here is safe.
```

This is the only `/compact` checkpoint. Converge is resumable purely from the
on-disk artefact (front-matter `state`, `choice`, `converge_log`, plus the body),
so compacting here loses nothing. The engineer may compact or continue.

---

## Step 4 — Converge (interactive, main context, targeted edits)

Convergence is collaborative and stays in the main context — a sub-agent cannot
do the back-and-forth. It works through **targeted section edits**: the
orchestrator reads only the slice it is changing, never the whole file, and
appends one-line notes to `converge_log` in the front-matter.

Present compactly to the engineer (do NOT paste the artefact body):
- The candidate approaches by lens, each in 2-3 lines: what it does + its sharpest con.
- The rubric trade-offs at a glance (where the approaches genuinely differ).
- Your recommendation with rationale, and the "pick the other instead if…" condition.
- The Skeptic's preserved dissent.
- The artefact path (`{artefact_path}`) for the full view.

(On a resume-forward entry, re-establish this presentation from the on-disk
front-matter and body rather than from council output held in context.)

**The front-matter `state` is the durable checkpoint — change it ON DISK, not in
prose.** Every terminal transition below (`converged`, `unresolved`) MUST be
written into the artefact's front-matter `state:` field with an actual file edit
BEFORE the engine returns its sentinel. Narrating the transition in `converge_log`
or in your reply is NOT sufficient and is a defect: the on-disk `state:` line is
the observable contract the caller and tests read. After making the edit, read the
front-matter back to confirm the `state:` line now holds the new value. Never
return `CONVERGED`/`UNRESOLVED` while the on-disk `state:` still says `exploring`.

Then invite the engineer to steer. Handle their response:

- **Confirm** — they accept the recommendation (or pick another as-is). Edit the
  front-matter ON DISK: set `choice:` to the chosen id AND set `state:` to
  `converged` (an actual edit of both front-matter lines), then append a one-line
  note to `converge_log`. (If `## Recommendation` needs the choice reflected, read
  only that section's slice and overwrite it — never the whole file.) Read the
  front-matter back to confirm `state: converged` and the new `choice:` are on
  disk. Only then go to Step 5 with `CONVERGED`.
- **Scope** — they accept an approach but narrow/adjust it ("yes, but drop X").
  Read only the targeted approach section's slice, overwrite it with the
  adjustment (Rule 6 — overwrite, never append), append the adjustment to
  `converge_log`, and re-present the delta.
- **Redirect** — they want a hybrid or a genuinely new approach ("combine A's
  storage with B's detection"). Re-dispatch a **one-shot authoring sub-agent in
  redirect mode** (`.claude/skills/shared/diverge-converge-author.md`), passing it
  **only** the new approach and the target section id — never the council payload.
  It reads the targeted slice from disk and rewrites only that one approach
  section, returning `WROTE-SECTION {id}`. Append the redirect to `converge_log`,
  re-present. On a redirect section-write failure (error sentinel, crash, or no
  `WROTE-SECTION` sentinel), retry **once**; if it still fails, return
  `{state: "ABANDONED", reason: "authoring sub-agent failed on a redirect section write"}`
  and do not present a half-edited artefact as final.
- **Reject all / unresolved dissent** — none fit. If the blocker is an unresolved
  Skeptic risk (the engineer chooses the spike door), edit the front-matter ON
  DISK to set `state:` to `unresolved` (an actual edit of the `state:` line — not
  a `converge_log` note about it), ensure the dissent and open questions reflect it
  (targeted edits only), append to `converge_log`, and read the front-matter back
  to confirm `state: unresolved` is on disk. Only then return `UNRESOLVED`. If the
  engineer simply wants to stop, return `ABANDONED` (leave the file untouched).

Loop Scope/Redirect until the engineer confirms, leaves dissent unresolved, or
stops. Every turn edits only the slice it touches and appends to `converge_log` —
the full body is never held in context, and converge is resumable purely from the
on-disk artefact.

`converge_log` is an intentional **append-only accumulator** (skill-idempotency
Rule 3, not Rule 6): on a resume, detect the existing log and append to it —
never re-initialise it.

---

## Step 5 — Return the sentinel

Return the matching sentinel from the Return table to the caller. The artefact on
disk is the durable output; the sentinel tells the caller what happened so it can
report and (for `UNRESOLVED`) suggest the spike door.

---

## Reserved extension — mechanism C (not implemented)

A future mechanism C would run the council via a background `Workflow`
orchestrator rather than parallel foreground sub-agents, reached for only if N
grows large or repeated re-runs accumulate context. It is a **documented reserved
extension only** — do not implement it here. The current engine runs the council
as parallel foreground sub-agents (mechanism B), which is sufficient at N=3.

---

## Rolling-context rules

- **Every read happens in a sub-agent.** Grounding, advocacy, and cross-examination
  all run as `Agent`s that read on their own and return compact. The orchestrator
  never reads whole source files — at most it spot-checks a single path during
  converge if strictly necessary.
- **The artefact body is written by the authoring sub-agent, never built in
  context.** The single source of truth is the Markdown at `{artefact_path}`. The
  authoring sub-agent writes it; converge edits it through targeted section
  slices. The full body never enters the orchestrator's context. There is no
  renderer.
- **Read-only council, no worktree isolation.** The grounding, advocate, and
  Skeptic sub-agents are read-only — they read and reason but never mutate state —
  so they need no git worktree isolation (skill-idempotency Rule 7). Only the
  authoring sub-agent writes, and it writes the single artefact by overwrite.
- **Compact returns are mandatory.** Every council prompt caps its return length
  and forbids file dumps. If a sub-agent returns bloated output, summarise it down
  before storing — do not let raw reasoning accumulate in the orchestrator.
- **Diverge is parallel and out-of-context; converge is interactive and in-context.**
  This split is fixed across all modes. A background mechanism cannot do the
  converge back-and-forth, so converge always returns to the main context.
- **No scores.** Present trade-offs and a reasoned recommendation; never numeric or
  percentage confidence. Preserve Skeptic dissent rather than averaging it away.
- **Opt-in, never a gate.** The engine never auto-fires, never blocks a downstream
  skill, and never opens a PR or commits. It produces an artefact and returns.
- **Resumable purely from disk.** Converge state lives in the front-matter
  (`state`, `choice`, `converge_log`) and the body — never only in context. A
  resume re-establishes from the file (Step 0c).
- **The caller fills every placeholder.** A missing placeholder is a caller bug.
- **UK English** in all human-readable output and in the artefact.

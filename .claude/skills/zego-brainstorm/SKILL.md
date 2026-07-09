---
name: zego-brainstorm
description: You MUST use this when the user asks to brainstorm or explore candidate solution approaches for a ticket before designing it, to weigh options and trade-offs and get a reasoned recommendation, given confirmed requirements and a JIRA ticket. Opt-in only; never auto-fires; never a gate.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Read
  - Write
  - Edit
  - Bash
  - mcp__claude_ai_Atlassian__getJiraIssue
---

You are the orchestrator for the `zego-brainstorm` skill, **approach mode**. Given the
confirmed requirements for a ticket, you run a council that generates candidate
solution approaches, cross-examines them, and converges with the engineer on a
recommendation — emitting an artefact `zego-write-design-doc` can later consume.

This skill is a **thin caller** of the reusable diverge/converge engine at
`.claude/skills/shared/diverge-converge-engine.md`. The engine owns *how* the
council runs and how the artefact is produced; this skill owns *what* to brief it
with: the ticket, its requirements, the three advocate lenses, and the rubric.

It is **opt-in exploration**. It never auto-fires, it is never a gate, and it
never opens a PR or commits. It is an optional pre-design door —
"I know the goal, not the route" — that sits before `zego-write-design-doc`. Engineers
who already have their own pre-design approach go straight to `zego-write-design-doc`;
this skill is a leg-up for the route-finding step, not a mandated stage.

---

## Inputs

The single argument is a JIRA ticket URL or bare ticket key, optionally followed
by a path to a requirements file, e.g.
`/zego-brainstorm AIDEV-172` or
`/zego-brainstorm https://zegons.atlassian.net/browse/AIDEV-172 docs/requirements/AIDEV-172.md`.

Extract the ticket key with the pattern `[A-Z][A-Z0-9]*-[0-9]+`. If no key can be
extracted, stop with this usage message and do nothing else:

> `{argument}` does not contain a JIRA ticket key or URL. Usage:
> `/zego-brainstorm <ticket-url-or-key> [requirements-file]`.

---

## Stage 1 — Gather confirmed requirements

The engine needs a fixed brief to compare approaches against. Assemble it:

1. If a requirements file path was passed, read it — that is the brief.
2. Otherwise fetch the ticket via `getJiraIssue` (cloudId `zegons.atlassian.net`,
   `responseContentFormat: markdown`). Use its Problem / Goal / Success criteria
   as the requirements. If JIRA tooling is unavailable or the fetch fails, ask the
   engineer to paste the requirements, then continue.

Record, as a bulleted list:
- The ticket **summary** (for the artefact title) and **URL**.
- The **confirmed requirements** — the success criteria / acceptance criteria,
  treated as the fixed brief.

If the requirements are too thin to compare approaches against (no goal, no
success criteria), say so and ask the engineer to confirm or paste a fuller brief
before running the council — the council is only as good as its brief.

---

## Stage 2 — Run the diverge/converge engine

**Read `.claude/skills/shared/diverge-converge-engine.md` and execute it from
Step 0.** Fill its caller contract:

- `{ticket}` → the extracted ticket key.
- `{ticket_url}` → `https://zegons.atlassian.net/browse/{ticket}`.
- `{title}` → the ticket summary from Stage 1.
- `{date}` → today's date, `YYYY-MM-DD` (read it from the environment context; do
  not invent one).
- `{mode}` → `approach`.
- `{requirements}` → the confirmed requirements from Stage 1.
- `{lenses}` → the three fixed advocate lenses, in order:
  **minimal / YAGNI**, **idiomatic reuse**, **robust / strategic**.
- `{rubric}` → the six dimensions: requirements fit / codebase fit / effort &
  complexity / risk & reversibility / durability / standards & decided-against.
- `{grounding_hints}` → anything from the ticket worth reading first (named files,
  modules, the seam the ticket points at). Optional; the grounding agent decides
  what to read.
- `{artefact_path}` → `docs/exploration/{ticket}-approaches.md`.

The engine's Step 0 handles a pre-existing artefact itself: it resumes a
`state: exploring` artefact forward, and offers the skill-idempotency Rule 9
stop / start-fresh / edit choice for a completed (`state: converged` or
`state: unresolved`) artefact or a failed partial write. You do not need to probe
for the artefact before calling the engine — but when the engine reports that a
completed artefact already exists, relay its Rule 9 choice to the engineer.

The engine runs the grounding pass, the council, the artefact full-write, the one
`/compact` offer, and the interactive convergence, then returns a sentinel.

---

## Stage 3 — Report

Act on the engine's return sentinel:

- **`CONVERGED`** — tell the engineer, briefly:
  - The chosen approach (`choice`) in one line.
  - The artefact path (`artefact_path`) for the full brief.
  - That `zego-write-design-doc` can consume it as the confirmed approach (point
    `zego-write-design-doc` at the artefact manually).
- **`UNRESOLVED`** — report the artefact path and the preserved dissent, and note
  the natural next door: a **spike** to settle the open risk empirically, then
  back to `zego-write-design-doc`.
- **`ABANDONED`** — report the `reason`. No artefact is presented as final.

Do not commit and do not open a PR — this skill produces an exploration artefact
and stops. Committing the artefact, if wanted, is the engineer's call.

---

## Rules

- **Opt-in, never a gate.** This skill only runs when explicitly invoked. It never
  blocks `zego-write-design-doc` or any other skill, and the artefact is context for a
  downstream skill, never a contract it requires.
- **Thin caller.** All council mechanics live in the shared engine. This skill
  only assembles the brief, fills the caller contract, and reports the result — do
  not re-implement the council here.
- **Three fixed lenses.** Minimal / idiomatic reuse / robust, always, for
  comparability. Not ticket-derived, not saturation-gated.
- **No scores.** The output is trade-offs plus a reasoned recommendation, never
  numeric or percentage confidence. Skeptic dissent is preserved, not averaged.
- **Reads code, but never into the orchestrator.** All code reading happens in the
  engine's grounding and council sub-agents; the orchestrator holds only compact
  digests and summaries.
- **Confirmed requirements are the input.** This skill formalises route-finding on
  requirements you have already established; it does not invent requirements.
- **UK English** in all human-readable output.

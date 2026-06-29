---
name: write-skill
description: You MUST use this when the user asks to create a new skill, write a skill file, or produce a SKILL.md for a workflow.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - Edit
  - EnterWorktree
  - ExitWorktree
---

You are the orchestrator for `write-skill`. You guide the production of a
standardised, tested skill file through three stage groups: Interview & Design,
TDD Cycle, and Validation & Output.

Interview & Design stages are interactive — wait for engineer input at each
stage. TDD Cycle and Validation & Output stages are autonomous — no questions
to the engineer.

**Token cost warning:** The TDD Cycle (Stages 7–9) spawns two sub-agents — a
RED baseline agent and a REFACTOR pressure agent. Each runs a full scenario
battery. Expect approximately 50k–100k additional input tokens per sub-agent
invocation. Budget accordingly.

---

# Interview & Design

---

## Stage 1 — Input handling

Check the argument passed to `write-skill`:

- **If a name is given** (e.g. `write-skill audit-repo`): use it as the
  working skill name. Confirm with the engineer.
- **If a description or intent is given** (e.g. "a skill that enforces TDD"):
  extract a candidate name (kebab-case, gerund form per naming conventions).
  Propose it and wait for confirmation.
- **If no argument is given**: ask the engineer:

  > What skill do you want to create? Describe its purpose and I will propose
  > a name.

Wait for the engineer's response. Record the confirmed skill name.

Verify the skill does not already exist:

```bash
ls .claude/skills/{name}/SKILL.md 2>/dev/null && echo "EXISTS" || echo "NEW"
```

If it exists, ask the engineer whether to overwrite or choose a different name.

---

## Stage 2 — Purpose and triggering conditions

Ask the engineer to describe the skill's purpose and when it should be invoked:

> Describe the skill's purpose. Specifically:
>
> 1. What does this skill do?
> 2. When should an engineer (or Claude) reach for it? What user intent or
>    situation signals this skill applies?
> 3. What artefact or input must be present?
> 4. Will this skill need companion reference files (e.g. best-practices
>    guides, templates, checklists)? If so, list each file's name and
>    one-line purpose.

Wait for the engineer's response.

Record any companion files the engineer identifies (name and purpose for each).
If the engineer does not mention companion files, record that none are needed.

Draft a `description:` field following ADR 006 format:

```
You MUST use this when [specific triggering condition].
```

Present it to the engineer for confirmation. The description must contain
**triggering conditions only** — no workflow steps, stage names, sub-agent
names, tools, invocation syntax, or output format.

Record the confirmed description.

---

## Stage 3 — ADR 006 compliance gate

Before proceeding, validate the confirmed description against ADR 006. Read
`docs/decisions/006-skill-description-triggering-conditions.md` and check:

- [ ] Starts with "You MUST use this when"
- [ ] Contains only triggering conditions (user intent, required artefact)
- [ ] Does not contain: workflow steps, phase/stage names, sub-agent names,
      tool names, invocation syntax, output format, file paths produced

If the description fails any check, state which check failed and ask the
engineer to revise. Do not proceed until the description passes all checks.

> Description passes ADR 006 compliance. Proceeding.

---

## Stage 4 — Complexity and model selection

Present the model selection decision to the engineer:

> Model selection:
>
> - **claude-opus-4-8** — complex cognitive work: interviews, TDD cycles,
>   sub-agent orchestration, multi-step reasoning.
> - **claude-sonnet-4-6** — balanced: structured output, moderate reasoning,
>   good for most skills.
> - **claude-haiku-4-5-20251001** — cheap, fast: repetitive tasks, simple
>   transformations, high-volume work.
>
> Based on the skill's purpose, I recommend: **{recommendation}**
>
> Confirm or choose a different model.

Base the recommendation on the skill's complexity: if it runs sub-agents,
conducts interviews, or requires multi-step reasoning, recommend Opus. If it
produces structured output with moderate branching, recommend Sonnet. If it is
repetitive or simple, recommend Haiku.

Wait for the engineer's response. Record the confirmed model.

---

## Stage 5 — Skill type classification

Read `.claude/skills/write-skill/persuasion-principles.md`. Classify the skill as one
of:

- **Discipline-enforcing** — enforces a practice the agent might rationalise
  away (TDD, verification, safety checks). Use Authority + Commitment +
  Social Proof. Bright-line rules, no exceptions, explicit anti-rationalisation
  counters.
- **Guidance** — teaches a technique or approach without strict compliance
  requirements. Use moderate Authority + Unity. Direction over guardrails.
- **Reference** — provides information without behavioural requirements. Use
  clarity only. No persuasion principles.

Present the classification and rationale to the engineer:

> I classify this skill as **{type}** because {rationale}.
>
> This means the skill will use {persuasion approach}.
>
> Agree, or should I reclassify?

Wait for the engineer's response. Record the confirmed classification and
applicable persuasion principles.

---

# TDD Cycle

From this point forward, all stages are autonomous. Do not ask the engineer
questions.

---

## Stage 6 — Prepare draft skill

Before running the TDD cycle, produce a draft SKILL.md based on all confirmed
decisions from the Interview & Design stages.

Read `.claude/skills/write-skill/anthropic-best-practices.md` for structural guidance:
frontmatter format, progressive disclosure, degrees of freedom, content
guidelines.

Write the draft to `.claude/skills/{name}/SKILL.md`. The draft must include:

- Valid YAML frontmatter with `name`, `description`, `model`, `allowed-tools`.
- Numbered stages (`## Stage N — Name` format).
- A `## Rules` section with non-negotiable constraints.
- Companion reference files referenced via `Read` at point of need (not loaded
  upfront) if the skill requires them.

The draft is the GREEN target — it addresses the engineer's stated purpose. It
will be refined by the TDD cycle.

```bash
mkdir -p .claude/skills/{name}
```

Write the draft using the Write tool.

---

## Stage 7 — RED baseline test

**Goal:** Run pressure scenarios WITHOUT the draft skill to establish a
baseline of agent failures.

Read `.claude/skills/write-skill/testing-skills-with-subagents.md` for the full TDD
methodology.

### Worktree isolation

The RED sub-agent must NOT have access to the draft skill. Use `EnterWorktree`
to create a clean worktree:

```
EnterWorktree(name: "{name}-red-baseline")
```

Inside the worktree, verify the draft skill is not present:

```bash
ls .claude/skills/{name}/SKILL.md 2>/dev/null && echo "LEAKED" || echo "CLEAN"
```

If the file is present (worktree inherited it), delete it before spawning the
sub-agent:

```bash
rm .claude/skills/{name}/SKILL.md
```

If `EnterWorktree` is unavailable or fails: note this as a known limitation.
Proceed with the RED test in the main worktree after temporarily moving the
draft outside the skills tree so the sub-agent cannot discover it by listing
`.claude/skills/{name}/`:

```bash
mv .claude/skills/{name}/SKILL.md /tmp/{name}-skill-draft.md
```

Restore after the test (the orchestrator must guarantee this restore runs even
if the RED sub-agent errors mid-stage — run it before any early-exit
reporting):

```bash
mkdir -p .claude/skills/{name}
mv /tmp/{name}-skill-draft.md .claude/skills/{name}/SKILL.md
```

Add a note to the output: "RED baseline was approximate — the sub-agent may
have had access to the draft skill's environment."

### Spawn RED sub-agent

Design 3–5 pressure scenarios combining multiple pressures (time + sunk cost +
authority + exhaustion — see the testing reference for pressure types). Each
scenario must force an explicit A/B/C choice.

Spawn an Agent in the clean worktree:

```
You are being tested on how you handle a realistic engineering scenario.
This is a real scenario — choose and act. Do not ask hypothetical questions.

{Pressure scenario 1}

{Pressure scenario 2}

{Pressure scenario 3}

For each scenario, state your choice (A, B, or C) and your reasoning.
Be honest about your actual decision.
```

Wait for the sub-agent to return. Document:
- Which option the agent chose for each scenario.
- Exact rationalisations used (verbatim quotes).
- Patterns across scenarios (which excuses recur).

Exit the worktree:

```
ExitWorktree(action: "remove")
```

---

## Stage 8 — GREEN write

Read `.claude/skills/write-skill/persuasion-principles.md` to inform the persuasion
strategy for the skill type confirmed in Stage 5.

The draft skill from Stage 6 is the initial GREEN attempt. Review it against
the RED baseline failures:

- For each rationalisation documented in Stage 7, verify the draft skill
  contains a counter.
- For each failure pattern, verify the skill has a rule or constraint that
  prevents it.

If gaps exist, update the draft skill using Edit to address the specific
failures observed. Do not add content for hypothetical cases — address only
the actual failures from the RED baseline.

Write the updated draft to `.claude/skills/{name}/SKILL.md`.

---

## Stage 9 — REFACTOR pressure test

**Goal:** Run the same pressure scenarios WITH the draft skill loaded to find
loopholes.

Read `.claude/skills/write-skill/testing-skills-with-subagents.md` for the REFACTOR
methodology.

This sub-agent runs in the **main worktree** where the draft skill is present.

Spawn an Agent:

```
You have access to the skill defined in .claude/skills/{name}/SKILL.md.
Read it before proceeding.

IMPORTANT: This is a real scenario. You must choose and act.
Do not ask hypothetical questions — make the actual decision.

{Same pressure scenarios from Stage 7}

For each scenario, state your choice (A, B, or C) and your reasoning.
If you considered the skill's rules, explain how they affected your decision.
```

Wait for the sub-agent to return. Compare results to the RED baseline:

- **Agent now complies**: the skill addresses this scenario. No change needed.
- **Agent still violates**: the skill has a loophole. Capture the new
  rationalisation verbatim.
- **Agent finds a novel rationalisation**: a new loophole not seen in RED.

For each loophole found, update the draft skill:

1. Add an explicit negation in the Rules section.
2. Add an entry to a rationalisation table if the skill type is
   discipline-enforcing.
3. Add a red-flag entry if the pattern is a common bypass.

Write the updated skill to `.claude/skills/{name}/SKILL.md`.

If 2 or more loopholes were found, run one additional REFACTOR iteration
(maximum 2 REFACTOR iterations total to control token cost).

---

# Validation & Output

---

## Stage 10 — CSO final check

Read the completed skill file. Validate the `description:` field against
ADR 006 one final time:

- [ ] Starts with "You MUST use this when"
- [ ] Contains only triggering conditions
- [ ] Does not contain workflow steps, stage names, sub-agent names, tool
      names, invocation syntax, output format, or file paths

If the description drifted during the TDD cycle, restore it to the confirmed
version from Stage 2.

Validate frontmatter contains exactly: `name`, `description`, `model`,
`allowed-tools`. No other fields.

When companion files exist (written in Stage 12), Stage 12a re-runs these
same checks against each companion file:

- [ ] The file's content matches its declared one-line purpose from Stage 2.
- [ ] The file does not duplicate content already present in SKILL.md.
- [ ] UK English throughout.

---

## Stage 11 — Line-count check

```bash
wc -l .claude/skills/{name}/SKILL.md
```

- **Under 500 lines**: proceed.
- **500 lines or over**: flag in completion notes. Do not truncate — the
  500-line target is soft. Consider whether heavy content can be moved to
  companion reference files.

When companion files exist (written in Stage 12), Stage 12a re-runs this
same check against each companion file:

- **Under 500 lines per file**: proceed.
- **500 lines or over**: flag in completion notes. Companion files should be
  focused on a single responsibility — consider splitting.

---

## Stage 12 — Write final files

Write the completed skill file to `.claude/skills/{name}/SKILL.md`.

If the engineer identified companion reference files in Stage 2, draft and
write each one to `.claude/skills/{name}/`. For each companion file:

1. Re-read the file's name and one-line purpose recorded in Stage 2.
2. Draft the file's content to fulfil that stated purpose. Apply the same
   structural principles used for SKILL.md: progressive disclosure,
   one responsibility per file, UK English, and clear section headings.
3. Keep each companion file focused on its declared purpose — do not duplicate
   content already present in SKILL.md.
4. If a companion file's purpose is too vague to produce useful content (e.g.
   the purpose is a single ambiguous phrase), **halt and ask the engineer** for
   a clearer purpose statement. Do not write a skeleton with TODO comments —
   never commit known-incomplete artefacts. Resume Stage 12 once the engineer
   provides a sufficient purpose for every companion file.

Write each companion file using the Write tool.

Verify all files are in place:

```bash
ls -la .claude/skills/{name}/
```

---

## Stage 12a — Companion file validation

Skip this stage if no companion files were identified in Stage 2.

Run the Stage 10 and Stage 11 checks against each companion file:

- **Scope check:** Does the file's content match its declared one-line purpose
  from Stage 2? Does it avoid duplicating SKILL.md content?
- **UK English:** All human-readable text uses UK English spelling.
- **Line count:** Under 500 lines per file (soft target — flag if exceeded).

If any companion file fails validation, fix it before proceeding.

---

## Stage 12b — Engineer approval of companion files

Skip this stage if no companion files were identified in Stage 2.

Present each companion file's name, section headings, and line count to the
engineer for review:

> **Companion files for review:**
>
> {For each file:}
> - `.claude/skills/{name}/{filename}` — {line count} lines
>   Sections: {list of section headings}
>
> Review the companion files and confirm they are acceptable, or request
> changes.

Wait for the engineer's response. If the engineer requests changes, apply them
and re-run Stage 12a validation before proceeding.

---

## Stage 12c — Pipeline narrative maintenance

Autonomous — no engineer questions. Runs after the skill files are written.

The development pipeline narrative lives in
`docs/ai/steering/base/skill-pipeline.md` (the requirements-to-merged-PR
ordering, skip rules, and off-path utilities). When a new skill enters that
flow, the narrative must be updated so it does not drift.

**Authoring-repo only.** Reconcile the narrative ONLY when running in this
authoring standards-library repo, which owns the skill set and the doc. This
repo is identified by the physical `standards/` source directory backing the
`docs/ai/steering/base` symlink:

```bash
test -d standards/base && echo "AUTHORING" || echo "CONSUMER"
```

- **If CONSUMER** (no `standards/base/` source directory): skip this stage. In a
  consumer repo `/write-skill` adds the team's own extension skills, which are
  expected to live outside the fanned-out narrative. `skill-pipeline.md` is a
  fanned-out standards file: editing it would break the single-source-of-truth
  intent and the edit would be overwritten by the next fan-out bump. Record a
  note in the Stage 14 report — "Consumer repo; skill-pipeline.md not updated
  (owned by the authoring standards library)" — and do NOT fail the skill.
- **If AUTHORING**, continue with the reconciliation below.

First, check whether the pipeline doc is present:

```bash
ls docs/ai/steering/base/skill-pipeline.md 2>/dev/null && echo "PRESENT" || echo "ABSENT"
```

- **If ABSENT** (a repo without the standards bundle): skip this stage. Record
  a note in the Stage 14 report — "Pipeline narrative absent; skill-pipeline.md
  not updated" — and do NOT fail the skill.
- **If PRESENT**: decide whether the new skill participates in the development
  pipeline flow.
  - **Participation test:** does the skill sit on the happy path (a step a
    feature runs through from requirements to a merged PR), or is it conditional
    remediation invoked after a PR (CI failure, review threads)? If yes, it
    participates.
  - **If it participates**, edit `docs/ai/steering/base/skill-pipeline.md` to
    include the new skill in the appropriate place — the happy-path sequence,
    the conditional-remediation list, or a posture note — using the skill's
    confirmed name and a one-line purpose from the earlier stages.
  - **If it does not participate** (an off-path utility), either add it to the
    off-path utilities section or leave the doc untouched, per the same test —
    do NOT force an off-path skill into the happy-path sequence.

  Stage the edit via the physical source path, since git cannot stage through
  the symlink in this repo:

```bash
# In zego-ai-standards the steering file lives at standards/base/ — git cannot stage through the docs/ai/steering/base symlink.
# In a consumer repo (docs/ai/steering/base is a real directory) stage docs/ai/steering/base/skill-pipeline.md instead.
git add standards/base/skill-pipeline.md
```

---

## Stage 13 — Commit

Stage and commit all files:

```bash
# In zego-ai-standards the new skill lives at skills/{name}/ — git cannot stage through the .claude/skills symlink.
# In a consumer repo (.claude/skills is a real directory) stage .claude/skills/{name}/ instead.
git add skills/{name}/
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
Add {name} skill

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Stage 14 — Report

Report to the engineer:

> Skill written to `.claude/skills/{name}/SKILL.md`.
>
> **Frontmatter:**
> ```yaml
> name: {name}
> description: {description}
> model: {model}
> allowed-tools: {tools}
> ```
>
> **Skill type:** {classification}
>
> **TDD cycle results:**
> - RED baseline: {N} scenarios, {M} failures documented
> - GREEN: draft addressed {K} failure patterns
> - REFACTOR: {J} loopholes found and closed ({L} iterations)
> {If EnterWorktree was unavailable: "Note: RED baseline was approximate —
> the sub-agent may have had access to the draft skill's environment."}
>
> **Line count:** {count} lines {if over 500: "(soft target exceeded — review
> for content that can move to companion files)"}
>
> **Files written:**
> - `.claude/skills/{name}/SKILL.md`
> - {any companion files}
> {If Stage 12c updated the pipeline narrative:
> "- `docs/ai/steering/base/skill-pipeline.md` (pipeline narrative updated for {name})"}
> {If Stage 12c skipped: "Pipeline narrative absent; skill-pipeline.md not updated."}

---

## Rules

- **Interview & Design stages are interactive.** Wait for engineer input at
  every stage in the first group. Do not skip ahead.
- **TDD Cycle and Validation & Output stages are autonomous** — except
  Stage 12b (engineer approval of companion files). No other post-Stage-5
  stage asks the engineer questions.
- **ADR 006 compliance is a hard gate.** The description must pass the
  compliance check in Stage 3 before proceeding and must be re-validated in
  Stage 10. No workflow steps, no internal mechanism names, no output format
  in the description.
- **RED sub-agent isolation is mandatory.** Use `EnterWorktree` to create a
  clean worktree for the RED baseline. The sub-agent must not have access to
  the draft skill file. If `EnterWorktree` is unavailable, surface this as a
  known limitation.
- **REFACTOR sub-agent runs in the main worktree.** It must have access to
  the draft skill so it can test compliance under pressure.
- **Maximum 2 REFACTOR iterations.** The TDD cycle is expensive. Two
  iterations are sufficient to close major loopholes without unbounded token
  cost.
- **Read reference files at point of need, not upfront.** Progressive
  disclosure: `anthropic-best-practices.md` in Stage 6,
  `persuasion-principles.md` in Stages 5 and 8,
  `testing-skills-with-subagents.md` in Stages 7 and 9.
- **Frontmatter must contain exactly four fields:** `name`, `description`,
  `model`, `allowed-tools`. No other fields.
- **Skill type classification drives persuasion strategy.** Discipline-
  enforcing skills use Authority + Commitment + Social Proof. Guidance skills
  use moderate Authority + Unity. Reference skills use clarity only.
- **Stage structure uses `## Stage N — Name` format.** Consistent with
  existing skills in the library.
- **UK English throughout.** All human-readable text in the skill file must
  use UK English spelling.
- **Companion files: validate, approve, never commit incomplete.** Stage 12a
  validates each companion file (scope, UK English, line count). Stage 12b
  obtains engineer approval. If a purpose is too vague, halt and ask — never
  commit skeleton/TODO files.
- **Do not modify existing skills.** This skill produces new skills only.
- **Maintain the pipeline narrative.** In Stage 12c, when the new skill
  participates in the development pipeline flow, update
  `docs/ai/steering/base/skill-pipeline.md` to include it; if it is an off-path
  utility, leave the happy path untouched. If the pipeline doc is absent (a
  repo without the standards bundle), skip the step with a note in the report —
  never fail the skill over a missing pipeline doc.
- **Token cost transparency.** The TDD cycle costs ~50k–100k additional
  input tokens per sub-agent run. Note this in the skill output.

# Skill authoring best practices

Reference for writing effective Claude Code skills. Read this file when
creating or revising any skill under `.claude/skills/`.

---

## Token efficiency

The context window is shared across system prompts, conversation history, and
loaded skills. Every token in a SKILL.md competes with the active conversation.

- Only add context Claude does not already have.
- Challenge each explanation: if Claude knows this from training, remove it.
- Target SKILL.md under 500 lines (soft target — companion reference files
  absorb heavy content).

## Progressive disclosure

Keep SKILL.md focused on the workflow. Move detailed reference material into
companion files alongside SKILL.md.

### One-level-deep reference rule

All reference files must be linked directly from SKILL.md. Claude reads
complete files when a skill references them. Nested references (a reference
file pointing to another reference file) as load-bearing links cause partial
reads and missed content.

Non-load-bearing "see also" pointers between companion files are acceptable.
A "see also" pointer provides optional context or a worked example — the
referencing file remains fully self-contained without it. If a companion file
cannot stand alone without reading the target, the link is load-bearing and
must be promoted to SKILL.md instead.

### File organisation patterns

| Complexity | Structure |
|------------|-----------|
| Simple | Single SKILL.md |
| Growing | SKILL.md + separate reference files (e.g. `reference.md`, `examples.md`) |
| Domain-heavy | SKILL.md + domain-organised references (e.g. `reference/finance.md`) so Claude loads only what is relevant |

For files exceeding 100 lines, include a table of contents so Claude
understands the full scope even during partial reads.

## SKILL.md structure

### Frontmatter

YAML frontmatter requires:

```yaml
---
description: Triggering conditions only (see below)
model: claude-opus-4-8        # or claude-haiku-4-5-20251001 for cheap/repetitive work
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
argument_hint: "Optional — describe expected argument"
---
```

The `model:` field accepts the canonical model ID from
[Anthropic's model list](https://docs.anthropic.com/en/docs/about-claude/models)
(e.g. `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`).
Some models require a dated suffix — use the exact ID to avoid alias-resolution
failures.

See `.claude/skills/README.md` for the full frontmatter specification.

### Description requirements

The `description:` field states **triggering conditions only** — the
conditions under which the skill is the right tool. It must not describe what
the skill does internally, how it works, or how to invoke it.

Format: `You MUST use this when [specific triggering condition].`

What belongs in a description:
- The user intent or situation that signals this skill applies.
- The specific artefact or input that must be present.

What does not belong:
- Workflow steps, phases, or stage names.
- Names of sub-agents, tools, or internal mechanisms.
- Invocation syntax or example commands.
- Output format or file paths produced.

Rationale: when a description summarises workflow steps, an LLM reads it as an
abbreviated recipe and bypasses the full skill body. Triggering-conditions-only
descriptions force the LLM to read the full body for execution detail.

See `docs/decisions/006-skill-description-triggering-conditions.md` for the
full ADR.

### Naming conventions

Use gerund form for skill names: "Processing PDFs", "Writing design documents",
not "PDF Helper" or "Design doc tool". Gerund form communicates action and is
consistent across the skill library.

## Degrees of freedom

Match guidance strictness to task fragility:

| Task type | Guidance style | Example |
|-----------|---------------|---------|
| High freedom (code reviews, analysis) | Text-based direction | "Check for X, Y, Z" |
| Medium freedom (structured output) | Pseudocode with parameters | Template with placeholders |
| Low freedom (migrations, safety-critical) | Specific, unmodifiable steps | Exact commands to run |

Narrow bridge with cliffs needs guardrails. Open field needs direction.

## Workflows and validation

### Checklists

Structure multi-step operations with checklists the agent can track:

```
- [ ] Step 1: Analyse the input
- [ ] Step 2: Create mapping
- [ ] Step 3: Validate mapping
- [ ] Step 4: Produce output
- [ ] Step 5: Verify result
```

### Validation loops

Pattern: run validator, identify errors, revise, repeat. Validation loops
improve output quality significantly. See `.claude/skills/shared/ci-validation-loop.md`
for a worked example.

## Model-coverage testing

What works for Opus may need more detail for Haiku. Test skills across all
target models before deployment:

- **Haiku** — cheap, fast; needs more explicit instructions.
- **Sonnet** — balanced; good baseline for testing.
- **Opus** — strongest reasoning; test that skill does not over-constrain it.

Minimum: three test scenarios per target model. Use realistic tasks, not
academic recitations. For discipline-enforcing skills (those listed in
`.claude/skills/write-skill/persuasion-principles.md` as needing Authority + Commitment), three scenarios
is insufficient — see `.claude/skills/write-skill/testing-skills-with-subagents.md` for the full
TDD/bulletproofing loop with combined pressures and rationalisation tables.

## Content guidelines

- Avoid time-sensitive information. Use expandable sections for legacy patterns
  rather than date-gated instructions.
- Maintain consistent terminology. Choose one term and use it throughout
  (e.g. "artefact" not alternating with "output" and "deliverable").
- Provide output format templates where the skill produces structured output.
- Show input/output examples demonstrating desired style and detail level.
- Use conditional workflows for decision points: "Creating new content? Follow
  Creation workflow. Editing? Follow Editing workflow."

## Evaluation and iteration

Build evaluations before extensive documentation:

1. Run Claude without the skill — identify actual gaps.
2. Create test scenarios from real usage patterns.
3. Establish baselines for what Claude gets wrong.
4. Write minimal content addressing those gaps.
5. Test with a separate Claude instance and iterate.

Develop with one Claude instance (A) creating the skill while another (B)
tests it. Observe where B navigates unexpectedly or misses information. Refine
with A based on B's real behaviour, not assumptions.

See `.claude/skills/write-skill/testing-skills-with-subagents.md` for the full TDD
methodology applied to skill testing.

## Checklist

### Core quality

- [ ] Description is triggering conditions only (per ADR 006).
- [ ] SKILL.md under 500 lines.
- [ ] Heavy content in separate reference files.
- [ ] No time-sensitive information.
- [ ] Consistent terminology throughout.
- [ ] Concrete examples, not abstract.
- [ ] One-level-deep file references only (non-load-bearing "see also" pointers between companions are acceptable).
- [ ] Clear workflows with explicit steps.

### Testing

- [ ] Three evaluations minimum.
- [ ] Tested with Haiku, Sonnet, and Opus.
- [ ] Real usage scenarios, not recitations.
- [ ] Iterated based on observed agent behaviour.

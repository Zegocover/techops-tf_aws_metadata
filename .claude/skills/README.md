# Skills

Complex, named, developer-invoked workflows with YAML frontmatter specifying model, allowed tools, and argument hints.

Skills are fanned out to every consumer repo and installed into `.claude/skills/`. They are invoked with `/skill-name` in Claude Code.

## When to use a skill vs a command

Skills require YAML frontmatter, run sub-agents, need model selection, or accept structured arguments. If it fits in one paragraph with no branching — use a command. See `docs/framework/02-mechanism-hierarchy.md`.

## Frontmatter format

```yaml
---
description: One-line description shown in /help output
model: claude-opus-4-8        # Use Opus for expensive cognitive work, Haiku for cheap/repetitive
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
argument_hint: "Optional — describe expected argument if the skill accepts one"
---
```

## Skill inventory and ordering

This README does not list the installed skills — a hand-maintained inventory here has no forcing function keeping it in step with the skills on disk, and it drifts.

- For the **authoritative inventory** of skills, read the "Skills available in this repo" section of `CLAUDE.md`.
- For the **ordering, skip rules, and off-path utilities** — which skill to use when, and how the skills compose into the development pipeline — read `docs/ai/steering/base/skill-pipeline.md`.

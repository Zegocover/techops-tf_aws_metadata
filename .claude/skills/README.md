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

## Skills in this library

| Skill | Purpose | Model | Status |
|---|---|---|---|
| `init-claude.md` | Bootstrap a repo — absorbs existing AI configs, generates CLAUDE.md and local rules ([AIDEV-1](https://zegons.atlassian.net/browse/AIDEV-1)) | Opus | P0 |
| `review-code.md` | Parallel multi-agent code review against standards + steering doc | Opus | P1 |
| `create-pr/SKILL.md` | Open a PR after implement PASS — derives title from steering doc, builds Background + Changes + Jira Ticket/s from the diff ([AIDEV-25](https://zegons.atlassian.net/browse/AIDEV-25)) | Sonnet | P1 |
| `write-requirements.md` | PM-facing interview to certainty — produces structured Given/When/Then requirements document | Opus | P1 |
| `write-steering-doc.md` | Developer-facing interview to certainty — produces steering document with impact assessment | Opus | P1 |
| `fix-pr-comments.md` | Feed PR review comments back through the code → review loop | Sonnet | P1 |
| `fix-buildkite/SKILL.md` | Diagnose and remediate Buildkite CI failures via MCP — triage, retry flaky tests, fix code errors, commit and push | Opus | P1 |
| `write-skill/SKILL.md` | Staged orchestrator: interview, TDD cycle (RED/GREEN/REFACTOR with sub-agents), validation — produces tested skill files | Opus | P1 |
| `extend-claude-standards/SKILL.md` | Gap analysis and engineer interview for `## Repository context` in `CLAUDE.local.md` — classifies 10 topics, interviews for thin/absent, merges answers ([AIDEV-78](https://zegons.atlassian.net/browse/AIDEV-78)) | Opus | P1 |
| `write-standard/SKILL.md` | Interview-driven: creates a new standards file or extends an existing one. Analyses sources, detects conflicts, validates structure, commits | Opus | P1 |

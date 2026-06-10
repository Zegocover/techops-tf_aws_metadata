# Commands

Simple, single-concern prompts. Plain markdown, no YAML frontmatter.

Commands are fanned out to every consumer repo and installed into `.claude/commands/`. They are invoked with `/command-name` in Claude Code.

## When to use a command vs a skill

If the entire workflow fits in one paragraph and doesn't branch, orchestrate, or require model/tool control — it's a command. If it needs YAML frontmatter, runs sub-agents, or accepts structured arguments — it's a skill. See `docs/framework/02-mechanism-hierarchy.md`.

## Contributing

Add a new `.md` file to this directory. No frontmatter. The filename becomes the command name (e.g. `add-migration.md` → `/add-migration`).

## Commands in this library

No commands have been authored yet.

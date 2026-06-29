# Commands

Simple, single-concern prompts. Plain markdown, no YAML frontmatter.

Commands are fanned out to every consumer repo and installed into `.claude/commands/`. They are invoked with `/command-name` in Claude Code.

## When to use a command vs a skill

If the entire workflow fits in one paragraph and doesn't branch, orchestrate, or require model/tool control — it's a command. If it needs YAML frontmatter, runs sub-agents, or accepts structured arguments — it's a skill. See `docs/framework/02-mechanism-hierarchy.md`.

## Contributing

Add a new `.md` file to this directory. No frontmatter. The filename becomes the command name (e.g. `add-migration.md` → `/add-migration`).

## The `zego-` prefix convention

Every fanned-out command filename takes a `zego-` prefix, so `zego-onboard.md` is invoked as `/zego-onboard`. This is a hard convention — author new commands as `zego-<name>.md`.

The reason is namespace safety. Claude Code's command namespace is **flat and shared**: a command installed into `.claude/commands/` sits alongside Claude Code's built-in commands and any commands the team has authored locally, with no namespacing by source. An unprefixed `onboard.md` would collide with a team-authored `/onboard` and with any present or future built-in of the same name, and the resolution order between a library command and a built-in is **undocumented** — there is no guarantee which one runs. The `zego-` prefix reserves a private slice of the namespace for the library so library commands never clash with built-ins or local commands. It also groups them for autocomplete: typing `/zego-` lists the full library command set.

See `docs/decisions/015-zego-command-prefix.md` for the full decision record and rejected alternatives.

## Commands in this library

- `zego-onboard.md` (`/zego-onboard`) — orient a new engineer: reports the deployed standards version and `ci-test-command`, lists the installed skills, and walks the requirements-to-merged-PR pipeline.

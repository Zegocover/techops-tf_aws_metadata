---
name: implement
description: You MUST use this when the user asks to implement a task spec or produce the artefact it describes.
model: claude-opus-4-8
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - Edit
  - WebFetch
  - WebSearch
---

You are the orchestrator for the `implement` skill. Read a task spec,
produce the described artefact, then call `review` and loop until PASS. You
do not write artefacts or review findings yourself — you brief sub-agents and
orchestrate results.

---

## Parse `--no-handoff-gate` override (strict)

Before detecting input type, parse the override flag with strict semantics.
This step runs FIRST so the JIRA-key/path detection below sees only the
residual argument.

1. Split `ARGUMENTS` into whitespace-delimited tokens.
2. **Exact-match the override.** If the token `--no-handoff-gate` appears
   exactly (case-sensitive, no trailing characters, no fuzzy or
   typo-tolerant matching), remove it from the token list and set
   `override_active = true`. Otherwise `override_active = false`.
3. **Reject any other `--`-prefixed token.** Scan the remaining tokens. If
   ANY token starts with `--` and is not exactly `--no-handoff-gate`, stop
   immediately with this verbatim error (substituting the offending token):

   > Unrecognised flag: `{token}`. The only flag `implement` accepts is `--no-handoff-gate`. Did you mean `--no-handoff-gate`?

   This rejection is deliberately broad — it covers near-miss typos (e.g.
   `--no-handoff_gate`) AND any other unknown flag (e.g. `--resume`,
   `--force`). Do NOT silently consume unrecognised `--`-tokens into the
   JIRA-key/path value.
4. **Reject empty residual.** Concatenate the remaining tokens back into the
   cleaned argument string. If the cleaned argument is empty (no JIRA key
   and no task-spec path/fragment remains after stripping
   `--no-handoff-gate`), stop with this verbatim error:

   > `--no-handoff-gate` is a modifier on an invocation, not a standalone command. Pass a JIRA key or task-spec path/fragment alongside it (e.g. `implement AIDEV-103 --no-handoff-gate`).

The cleaned argument and `override_active` are passed to whichever companion
file is routed below.

---

## Detect input type

Check the cleaned argument:

- Matches `^[A-Z][A-Z0-9]*-[0-9]+$` (a JIRA ticket key, e.g. `AIDEV-70`) → read `.claude/skills/implement/feature-orchestrator.md` and execute it from OM-1. Pass `override_active` to the orchestrator.
- Otherwise → read `.claude/skills/implement/task-implementer.md` and execute it from Stage 0. Pass `override_active` to the task-implementer.

If the companion file cannot be read, stop with the verbatim error:

> Companion file `{path}` could not be read — `implement` skill is broken. Surface to engineer.

---
name: ci-validation
description: You MUST use this when the user asks to run CI validation locally or verify that code passes CI checks before committing.
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
---

You are executing the `ci-validation` skill. Discover the repo's CI
commands and execute them locally, gating on success before the caller
proceeds. You do not fix failures — you discover, execute, and report.

---

## Objective

Before committing, run CI-equivalent validation locally so that known failures
never reach the pipeline. This skill discovers the repo's CI commands and
executes them, gating on success before proceeding.

---

## Stage 1 — Discover CI commands

Follow this priority chain. Check each source in order. If a source file
exists but yields no extractable commands, fall through to the next source.
Stop at the first source that yields at least one command.

1. **CLAUDE.local.md frontmatter `ci-test-command`.**
   Read the consumer repo's `CLAUDE.local.md`. If its frontmatter
   contains a `ci-test-command` key whose value is non-empty, use it. The value
   may be a single command string or a newline-separated list of commands. Split
   on newlines and trim whitespace to produce the command list.

2. **`.buildkite/pipeline.yml`.**
   If no commands were found in step 1, check whether `.buildkite/pipeline.yml`
   exists. If it does, read it and extract every `command:` value that starts
   with `make` or that contains a test, lint, or format invocation (e.g.
   `pytest`, `npm test`, `ruff`, `sbt test`, `eslint`). For multi-line
   `command:` values (YAML `|` or `>` blocks), split on newlines and treat each
   non-empty line as a separate command, applying the same filter. If the
   pipeline exists but yields no extractable commands, fall through to step 3.

3. **`.github/workflows/*.yml`.**
   If no commands were found in steps 1–2, check for `.github/workflows/*.yml`.
   If any workflow files exist, read them and extract every `run:` value that
   contains a test, lint, or format invocation. If the workflows exist but
   yield no extractable commands, fall through to step 4.

4. **No CI configuration found.**
   If none of the above sources yielded commands, log:

   > No CI configuration found — skipping CI validation.

   Return verdict: **passed** (nothing to validate).

**For repos with complex pipelines** (multi-line command blocks, Docker
invocations, plugin-heavy steps), automatic extraction may produce
inconsistent results across runs. Declare `ci-test-command` explicitly in
CLAUDE.local.md frontmatter rather than relying on extraction. See
[ADR 003](docs/decisions/003-claudemd-frontmatter.md) for format details.

---

## Stage 2 — Prepare the command list

Once commands are discovered, prepare them for execution:

- **Check for a Makefile.** Run `test -f Makefile` to determine whether one
  exists.
- **`make` commands without a Makefile:** halt and report:

  > CI validation cannot proceed: `{command}` references a `make` target but
  > no Makefile exists in the working tree. Either add a Makefile or declare
  > the underlying commands via `ci-test-command` in CLAUDE.local.md frontmatter.

  Do not attempt to guess the underlying tool command. Do not skip the command.
  Return verdict: **failed**.

- **`make` commands whose target is not defined:** run `make -n {target}` (dry
  run) to check whether the target exists. This is the authoritative check — it
  handles pattern rules, included Makefiles, `.PHONY` declarations, conditional
  blocks, and dynamically generated targets. Do not grep the Makefile directly.
  If `make -n {target}` exits non-zero, halt and report:

  > CI validation cannot proceed: `{command}` references make target
  > `{target}` but it is not defined in the Makefile. Either add the target
  > or declare the underlying commands via `ci-test-command` in CLAUDE.local.md
  > frontmatter.

  Do not attempt to guess the underlying tool command. Do not skip the command.
  Return verdict: **failed**.

- **`make` commands where `make -n {target}` exits zero:** run as-is.

- **Non-`make` commands** (e.g. `npm test`, `pytest`, `sbt test`): run
  directly as-is regardless of whether a Makefile exists.

**Auto-format before lint.** The implement agent writes code but does not run
formatters. If the discovered command list contains a lint command but no
format command, find and prepend a format step so that lint does not fail on
style violations the formatter would fix automatically.

Search for a format command in this order:
1. **Makefile** (if present): scan for a target whose name exactly matches one
   of the allowlist entries — `format`, `fmt`, `format-all`, `fmt-all` — or
   that starts with `format-` or `fmt-` but is not a check target (reject
   names ending in `-check`, `-verify`, `-lint`, or `-deps`). Use the matched
   target as `make {target}`.
2. **Pipeline file**: look for a `command:` or `run:` value that invokes a
   known formatter tool (`ruff format`, `black`, `prettier --write`,
   `gofmt -w`, `gofumpt -w`, `sbt scalafmtAll`, `sbt scalafmt`) but was not
   included in the discovered list (e.g. it lives in a separate pipeline step
   that was filtered out). Do not match a value merely because it contains
   the substring `format` or `fmt` — the value must invoke a recognised
   formatter.
3. **Common tool commands**: if the lint command identifies the toolchain,
   infer the format command:
   - `ruff check` → `ruff format .`
   - `eslint` → `prettier --write .`
   - `flake8` → `black .`
   - `scalafmtCheck` / `scalafmtCheckAll` → `sbt scalafmtAll`
   - `gofmt -l` / `gofumpt` → `gofmt -w .` / `gofumpt -w .`

If a format command is found, insert it immediately before the first lint
command in the list. If the discovered list already contains a format command,
do not add another — but ensure it runs before lint. If no format command can
be determined, continue without one (do not halt).

**Otherwise preserve pipeline order.** Apart from the format-before-lint
insertion above, run all other commands in the order they appear in the CI
configuration.

---

## Stage 3 — Autonomous scope validation

This stage is fully autonomous — it contains NO interactive prompt. It
classifies and selects from the **Stage 2-prepared command list** (i.e. the
list after Stage 2's format-before-lint auto-prepend), biased toward running.
Stage 3 does NOT re-discover commands and does NOT re-prepend a format step —
it classifies and selects from the already-prepared list, and produces the
tier-selected command list that Stage 4 consumes.

### 3.1 — Determine the changed files

Prefer a threaded `{changed file(s)}` input passed in the spawn brief. When it
is empty or absent, fall back to deriving the changed files from git:

```bash
BASE=$(git merge-base HEAD origin/main 2>/dev/null) || BASE=""
if [ -n "$BASE" ]; then
  git diff "$BASE" --name-only
else
  echo "git-merge-base failed — running all tiers"  # triggers the broad/ambiguous fallback
fi
```

This compares ALL commits on the feature branch against the default branch —
NOT `HEAD~1`. If that command (or the inner `git merge-base`) exits non-zero
(detached HEAD, shallow clone, no commits, no `origin/main`), do NOT halt and
do NOT run nothing: treat the diff as broad/ambiguous, run ALL tiers, and
report the git-diff failure as the reason.

### 3.2 — Classify each command into a tier

Classify every command in the prepared list into exactly one of four tiers
using this tool-agnostic command/target-name keyword enumeration (it must be
matched against each command's tokens; it works across Python, Scala, JS, Go):

- **format/lint** ← `format`, `fmt`, `lint`, `ruff`, `scalafmt`, `prettier`,
  `eslint`, `black`, `flake8`, `gofmt`
- **unit** ← `test`, `pytest`, `sbt test`, `unit` (without an
  integration/smoke marker)
- **integration** ← `test-integration`, `integration-test`,
  `sbt "integration-test/test"`, `it-test`
- **smoke** ← `test-smoke`, `smoke`

**Tier-classification priority — most-specific-first.** Patterns are matched
in this order so that a more specific tier always claims the command before
the broad unit `test` pattern can:

1. format/lint patterns
2. smoke patterns
3. integration patterns
4. the unit `test` pattern LAST

Within a tier, a longer token match takes precedence. The first tier whose
pattern matches claims the command; later patterns are not tried. This is why
`test-integration` is classified as integration, NOT unit — the integration
pattern is matched before the bare `test` (unit) pattern.

**Unmatched commands.** A command that matches no tier is treated as must-run
(upward bias): assign it to the broadest tier already selected for this run.
It is never dropped.

### 3.3 — Format-signal vs lint-signal sub-partition

Within the format/lint tier, sub-partition each command for ordering:

- **format-signals** ← `format`, `fmt`, `scalafmt`, `prettier`, `black`,
  `gofmt` (canonical invocation writes files)
- **lint-signals** ← `lint`, `ruff`, `eslint`, `flake8` (canonical invocation
  reads and reports)

A token matched by bare name alone where the mode is ambiguous (e.g. a target
literally named `ruff`) defaults to lint-signal (conservative).

Format-signals are ordered BEFORE lint-signals within the selected set.

### 3.4 — "Non-code-only" definition

A diff is **non-code-only** when it contains no source-language files —
`.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.java`, `.kt`, `.scala`, `.go`, `.rb`,
`.rs` — i.e. only documentation, configuration, or data files.

Borderline cases are classified as code-affecting for tier purposes:

- `.proto` definitions and SQL migration files count as code, AND as
  service-boundary/converter touches → add integration.
- Dependency manifests (`requirements.txt`, `pyproject.toml`, `package.json`,
  `build.sbt`, lock files) and `Dockerfile`/startup config count as
  dependency/startup touches → add smoke.

### 3.5 — Select tiers by what the diff touches (err upward)

- **non-code only** → format/lint only (or skip entirely if no format/lint
  command exists — report each skipped tier with its reason).
- **any code change** → always format + lint + unit.
- **service boundary / I/O / API / DB / converter** (including `.proto`, SQL
  migrations) → add integration.
- **Dockerfile / dependency manifest / startup config** → add smoke.
- **broad / mixed / ambiguous** (and the git-diff-failure fallback from 3.1)
  → run all four tiers.

### 3.6 — Report

Report which tiers ran, which were skipped, and why. Every discovered command
must appear with a ran/skipped + reason — no silent skips. Within the
format/lint tier the selected output lists format-signal commands before
lint-signal commands.

Proceed to Stage 4 with the tier-selected command list.

---

## Stage 4 — Execute

This stage consumes the tier-selected command list produced by Stage 3. It is
fully autonomous — it contains NO interactive prompt.

Note what is about to run:

> Running CI validation: {comma-separated list of commands}.

Run each command in order using `run_in_background` so execution is
non-blocking.

### 4.1 — Autonomous 20-minute hard-ceiling timeout

Each command runs under a **hard ceiling of 20 minutes per command**. There is
NO interactive check-in. If a command is still running when the 20-minute
ceiling is exceeded:

1. Kill the command.
2. Record it as `failed` (never `skipped`, never silently continued).
3. Report the elapsed time and the partial stdout/stderr captured so far.

Never block on a human — the ceiling is a fixed autonomous bound.

**The killed command's partial output is auth-checked before its verdict is
emitted.** Pass the partial stdout/stderr through the same auth-signal check
defined in 4.2 (Interface A), exactly as for a normally-exited command:

- An auth signal from either family present in the partial output →
  `precondition: authentication` (so the loop short-circuits rather than
  feeding the fixer).
- No auth signal in the partial output → plain `verdict: failed`.

This keeps the bias-toward-precondition principle identical on the normal-exit
and timeout paths.

### 4.2 — Authentication / credentials precondition detection

An auth or credentials failure is an environment precondition, not a code
failure. The code fixer cannot fix it and must not be fed it. On any command
failure (non-zero exit) — and on the partial output of a timed-out, killed
command — check the full output for an auth signal BEFORE emitting the
verdict. The behaviour is **detect-and-report only**: do NOT export missing
variables, do NOT auto-run auth commands, and do NOT skip the command — all
three would make the local run diverge from CI.

Two signal families are checked independently of each other:

**Family (a) — environment-variable-absence / expired-session strings.**
Match these well-known patterns anywhere in the output:

- `CODEARTIFACT_AUTH_TOKEN not set`
- `Unable to set UV_INDEX_<INDEX>_PASSWORD`, where `<INDEX>` is any token
  (real uv output substitutes the index name, e.g.
  `Unable to set UV_INDEX_INTERNAL_PASSWORD`)
- the SSO-session-expiry set (open-ended; anchored by these canonical
  examples): `Error loading SSO Token`, `token is expired`,
  `SSO session has expired`,
  `The SSO session associated with this profile has expired`, and similar
  phrasings.

**Family (b) — HTTP registry auth statuses, tool-name-agnostic.**
Match these status strings anywhere in fetch/dependency-resolution output,
**regardless of the tool name**:

- `401 Unauthorized`
- `403 Forbidden`
- `HTTP Error 401`
- `received status code 401` / `received status code 403`

A 401/403 from an unfamiliar tool MUST still classify as auth — it must never
be swallowed as a generic failure merely because the tool was unrecognised.

**Classification rule (bias toward the precondition).** When either family
matches unambiguously, the classification is `precondition: authentication`
EVEN WHEN the command is otherwise ambiguous (e.g. an exit code that could
also indicate a compile error) — the remediation is non-destructive, so bias
toward the precondition. A failure with no auth signal is plain
`verdict: failed`.

**Remediation, resolved per family.** Emit exactly ONE remediation line:

- Family (a): name the documented path for the matched signal —
  CodeArtifact / SSO expiry → `aws sso login`; a `UV_INDEX_*_PASSWORD`
  absence → the documented UV index-credential refresh for that index.
- Family (b): `refresh your registry credentials via the documented path
  (see the repo's auth/registry documentation)`.
- **Dual match** (the same output matches BOTH families): family (a)'s
  remediation path takes precedence; emit exactly ONE remediation line
  carrying family (a)'s path. Never emit two lines.

### 4.3 — Emit the verdict

- **On success:** record the command as passed and continue to the next.
- **On failure (non-zero exit, or a 20-minute-ceiling kill) WITH an auth
  signal:** do not run remaining commands. Return:

  1. `verdict: failed`
  2. A distinct classification LINE: `precondition: authentication`
  3. The failing command name and exit code (or elapsed time for a killed
     command)
  4. The full (or partial, for a killed command) command output verbatim,
     ending with exactly one appended line of the exact form:
     `precondition: authentication — remediation: {documented path}`

- **On failure (non-zero exit, or a 20-minute-ceiling kill) WITHOUT an auth
  signal:** do not run remaining commands. Return:

  1. `verdict: failed`
  2. The failing command name and exit code (or elapsed time for a killed
     command)
  3. The full (or partial) command output verbatim

  No `precondition: authentication` line — this is a generic code/test
  failure. The fix loop will handle retries; this skill only discovers,
  executes, and reports.

After all commands complete successfully, report the outcome of every command:

> CI validation passed:
> - `{command 1}` — passed
> - `{command 2}` — passed
> - `{command 3}` — passed
> - ...

Return verdict: **passed**. The caller must surface this report so that every
command's outcome is visible, not silently dropped.

---

## Rules

- **CI validation must not be skipped when CI configuration exists.**
  The skill gates the commit — if discovered commands fail, return the failure
  to the implement skill. Do not retry or fix within this skill — the
  implement skill's fix loop handles that.
- **CI command discovery follows a strict priority chain.** Check
  `ci-test-command` in CLAUDE.local.md frontmatter first, then
  `.buildkite/pipeline.yml`, then `.github/workflows/*.yml`. Stop at the first
  source that yields commands. Do not merge commands from multiple sources.
- **Do not hardcode `make` target names.** Discover targets from the CI
  configuration at runtime. The skill must work across repos with different
  target names and build systems.
- **Halt when `make` is referenced but no Makefile exists.** Do not guess the
  underlying tool command and do not silently skip the command. A missing
  Makefile when the pipeline references `make` targets is a misconfiguration
  that must be surfaced, not papered over.
- **Auto-format before lint.** The implement agent does not run formatters,
  so CI validation must prepend a format step when lint is discovered but
  format is not. Search the Makefile, pipeline, and common tool conventions.
- **Scope validation and execution are fully autonomous.** Neither Stage 3
  nor Stage 4 may prompt the user. There is no Accept/Select/Skip menu and no
  keep-waiting / skip / fail check-in anywhere in the skill. Scope selection
  errs upward (ambiguous/broad/mixed diffs and git-diff failures run
  everything; no silent skips).
- **Per-command timeout is an autonomous 20-minute hard ceiling.** Every CI
  command runs in the background under a 20-minute hard ceiling. If the
  command is still running when the ceiling is exceeded, kill it, record it as
  `failed`, and report the elapsed time and partial output — do NOT prompt the
  user, do NOT silently continue, and do NOT mark it skipped. The partial
  output of a killed command is auth-checked (Stage 4.2) before the verdict is
  emitted.
- **Auth preconditions are detect-and-report only.** When a command's output
  carries an auth signal (Stage 4.2, either family), classify it
  `precondition: authentication` and report the remediation path. Never export
  missing variables, never auto-run an auth command, and never skip the
  command — all three would make the local run diverge from CI.

---

## Red flags — stop and reconsider

These are the tool-agnostic rationalisations that quietly defeat local CI
validation. If you catch yourself reasoning along any of these lines, stop and
do the disciplined thing instead. (This table is deliberately self-contained
and tool-agnostic; it does not reference or reconcile any steering-doc table.)

| Rationalisation | Why it is wrong | Do this instead |
|-----------------|-----------------|-----------------|
| "I'll just run the bare tool (`pytest`, `ruff`, `sbt test`) directly instead of the discovered CI command." | The bare tool may use different flags, config, or scope than CI, so a local pass does not predict a CI pass. | Run the discovered CI command exactly as Stage 1–2 prepared it. |
| "The bare tool passed, so I can trust that over the CI command." | A bare-tool pass is not equivalent to a CI-command pass — CI may add coverage gates, stricter config, or extra targets. | Trust only the discovered CI command's result; never substitute a bare-tool run for it. |
| "This change is small, so I can skip local validation." | "Small" changes break CI as often as large ones; size is not a proxy for safety. | Run the tier-selected validation regardless of diff size. |
| "These tests are slow, so I'll skip them." | Slow tests (integration/smoke) are exactly the ones that catch boundary regressions; skipping them defeats the gate. | Run the selected tiers; the 20-minute hard ceiling bounds runtime without skipping. |
| "Only this one command is obviously related to my change, so I'll run just that." | Changes have non-obvious blast radius; running only the obviously-related command misses regressions the scope rules would have caught. | Let Stage 3's upward-biased tier selection decide; run every selected command. |
| "I'll just export the missing credential / run the auth command by hand to get past this auth error." | Exporting a credential or running auth by hand makes the local run diverge from CI and masks an environment precondition the developer must fix. | Classify it `precondition: authentication`, report the remediation path, and stop — never export or auto-authenticate. |

Ticket-level orchestration of the implement skill. Reached via the SKILL.md dispatcher when the input matches a JIRA ticket key.

Inputs from the dispatcher:
- `TICKET` — the JIRA ticket key (already validated by the dispatcher).
- `override_active` — boolean. The dispatcher has already parsed `--no-handoff-gate`; this orchestrator trusts the value verbatim and never re-parses arguments. It propagates the value into each OM-5 sub-agent prompt (see OM-5).

## Orchestration mode

Entered when the `Detect input type` section routes to orchestration mode. Runs all task specs for the ticket in dependency order using the single-task implement flow (Stages 0–7) per task via sub-agent. Does not reimplement any stage.

### OM-1 — Discover task specs

```bash
ls docs/tasks/ | rg "^{TICKET}-TASK-[0-9]+-.*\.md$" | sort
```

If no files match, stop:

> No task specs found for ticket {TICKET} in docs/tasks/. Cannot proceed.

Store the sorted list as the task set.

### OM-2 — Validate dependency graph

For each task spec in the task set, read its `Depends on:` body header (absent → treat as `nothing`).

**Reference check.** For each non-`nothing` value:

- If the value ends in `.md`: confirm `docs/tasks/{filename}` exists. If not, stop:
  > Broken Depends on: reference in {spec filename} — docs/tasks/{filename} not found.

  If the referenced file does not match `^{TICKET}-TASK-[0-9]+-.*\.md$`, stop:
  > Cross-ticket dependency in {spec filename} — {filename} belongs to a different ticket. Cross-ticket dependencies are not supported.

- If the value does not end in `.md` (literal branch name): validate it exists on the remote:
  ```bash
  git ls-remote --exit-code origin refs/heads/{branch-name}
  ```
  If the command exits non-zero, stop:
  > Broken Depends on: reference in {spec filename} — branch {branch-name} not found on remote.

**Cycle check.** For each task, follow the `Depends on:` chain. If any chain revisits a task already in the chain, stop:

> Dependency cycle detected: {task-A.md} → {task-B.md} → … → {task-A.md}. Resolve the cycle before proceeding.

All reference and cycle checks must complete before any task starts.

### OM-3 — Pre-flight checks

Run before any task starts. Any failure stops the run entirely — no partial-run state results from pre-flight failures.

**Clean working tree:**

```bash
git status --porcelain
```

If non-empty, stop and display the file list:

> The working tree has uncommitted changes (listed above). Commit or stash them before running `implement {TICKET}`.

**Push access:**

```bash
gh auth status
```

If this fails, stop and surface the error verbatim.

```bash
git ls-remote origin
```

If this fails, stop and surface the error verbatim.

**Design-phase PR handoff gate (fail-fast).** Runs EXACTLY ONCE for the whole
ticket, before OM-4. ORTHOGONAL to the per-task PR check in OM-5: OM-5
handles per-task skip/resume on the task's own implementation branch and
treats `CLOSED` as resume-with-warning; this gate checks the **design
branch** and passes only on `OPEN` or `MERGED`. The insertion point is
pinned to this sequential structure (see ADR 011 and ADR 009 — a future
parallel scheduler may restructure this file, but the current sequential
form is authoritative).

Resolve the design branch from the design doc for `{TICKET}`:

```bash
rg -l "^(JIRA|Ticket): {TICKET}$" docs/design/
```

Both `^JIRA:` and `^Ticket:` are matched on purpose — the `docs/design/`
inventory currently holds a genuine mix of both, and narrowing the lookup to
a single key would silently miss design docs keyed with the other. Do NOT
strip the `Ticket:` branch (ADR 011).

**If `rg` returns no results** (and `override_active` is false): stop with
this verbatim error before any sub-agent is spawned:

> No design doc found for ticket `{TICKET}` (searched `docs/design/` for both `^JIRA:` and `^Ticket:` headers). `implement` requires a design doc to verify the design-phase PR handoff. If this ticket legitimately has no design doc (e.g. a spike), re-run with `--no-handoff-gate`.

**If `rg` returns one or more design docs:** for each match, attempt to read
its `Branch:` header (matching the regex `^Branch:[[:space:]]+([^[:space:]].*)$`).
Collect the set of resolved design branches.

**If no design doc has a resolvable `Branch:` header** (every match is a
legacy doc) and `override_active` is false: stop with this verbatim error:

> Found {N} design doc(s) for ticket `{TICKET}` but none carry a resolvable `Branch:` header (legacy docs). Cannot resolve the design-phase branch to verify its PR. Normalise the design doc by adding a `Branch:` header, or re-run with `--no-handoff-gate`.

**Run the handoff gate against the resolved design branches.** The gate is
a pure query (see `.claude/skills/shared/handoff-gate.md`): it returns a sentinel
object describing the PR state and never halts itself. OM-3 inspects the
sentinel and either proceeds or halts the orchestrator using the canonical
halt-message templates from `.claude/skills/shared/handoff-gate.md`. The gate passes
if ANY resolved design branch returns a pass sentinel (`OVERRIDE`, `OPEN`,
or `MERGED`).

If `override_active` is true: read `.claude/skills/shared/handoff-gate.md` and execute
Step 1 (the override short-circuit) once with placeholders:

| Placeholder | Value |
|-------------|-------|
| `{branch}` | the first resolved design branch (only used in the override notice — the gate makes no `gh` call) |
| `{phase_name}` | `design` (substituted into the override notice line printed by Step 1) |
| `{override_active}` | `true` |

The gate prints the override notice and returns `{state: "OVERRIDE"}`. Treat
this as a pass and proceed to OM-4.

If `override_active` is false: for each resolved design branch in turn, read
`.claude/skills/shared/handoff-gate.md` and execute it with placeholders:

| Placeholder | Value |
|-------------|-------|
| `{branch}` | the resolved design branch |
| `{override_active}` | `false` |

Inspect the returned sentinel's `.state`:

- `OPEN` or `MERGED` → the gate passes for this branch. Exit the loop and
  proceed to OM-4.
- `NONE`, `CLOSED`, `DRAFT`, or `GH_FAIL` → record the sentinel and move on
  to the next candidate branch. The gate did not halt; OM-3 owns the halt
  decision.

If every resolved design branch returned a non-pass sentinel, halt the
orchestrator here — no sub-agent is spawned. Emit exactly ONE halt message
using the canonical halt-message template from `.claude/skills/shared/handoff-gate.md`
corresponding to the **last** (final) candidate branch's sentinel state.
Fill `{phase_name}` = `design`, `{skill_name}` = `implement`, `{branch}` =
the last candidate branch, and (for `CLOSED` / `DRAFT`) `{number}` and
`{url}` from the sentinel, or (for `GH_FAIL`) `{stderr}` from the sentinel.
Because the gate is a pure query, non-final candidate branches produce no
noisy false halts — only the final halt message is printed.

### OM-4 — Build execution order

Assign each task a depth: `Depends on: nothing` (or absent) → depth 0; `Depends on: {branch-name}` (literal branch name, no `.md` suffix) → depth 0 (external dependency, not a member of the task set); `Depends on: {filename}` (ends in `.md`) → dependency's depth + 1. Sort by depth ascending, then TASK-NN ascending within the same depth. Each task starts only after all tasks it depends on complete.

### OM-5 — Execute tasks in order

For each task in execution order:

**Idempotency check.** Read the task spec's `branch` frontmatter. Check whether the branch exists locally:

```bash
git rev-parse --verify {branch} 2>/dev/null && echo "exists" || echo "absent"
```

If the branch exists, check PR state (use the most recent PR by creation date if multiple exist):

```bash
gh pr list --head {branch} --state all --json state,createdAt --jq 'if length == 0 then empty else sort_by(.createdAt) | last | .state end'
```

Decide:
- Branch absent → **start fresh** — invoke single-task implement
- Branch exists, PR state `OPEN` or `MERGED` → **skip** — report to user and move to next task:
  > Task {filename}: skipped — already complete (PR {state}).
- Branch exists, PR state `CLOSED` → **resume with warning** — report to user before invoking single-task implement:
  > Task {filename}: branch has a previously CLOSED PR — re-running the writer may reproduce a previously rejected artefact. Proceeding.
  Then invoke single-task implement.
- Branch exists, no PR (empty output) → **resume** — invoke single-task implement

**Invoke single-task implement.** Spawn a sub-agent. Propagate
`--no-handoff-gate` into the sub-agent's argument string when
`override_active` is true. Without this propagation, each sub-agent's
Stage 0 would re-halt on the same check this orchestrator already cleared
(ADR 011, Risk 4). The token is appended to the sub-agent's argument
exactly as the dispatcher's strict parser expects — whitespace-delimited,
exact-match.

When `override_active` is true, set:

```
ARGUMENTS_FOR_SUBAGENT = "docs/tasks/{filename} --no-handoff-gate"
```

When `override_active` is false, set:

```
ARGUMENTS_FOR_SUBAGENT = "docs/tasks/{filename}"
```

Then send this brief to the sub-agent (substitute the literal value of
`ARGUMENTS_FOR_SUBAGENT` before sending):

```
You are running the `implement` skill for a single task.
Read `.claude/skills/implement/SKILL.md` and execute it starting from Stage 0.
The argument the dispatcher must parse is exactly: {ARGUMENTS_FOR_SUBAGENT}
Do not ask questions — all context is below.

Ticket: {TICKET}
Mode: non-interactive sub-agent — do not prompt; on auth precondition return FAIL carrying precondition: authentication

Execute Stages 0 through 7 in full. Return when Stage 7 completes or the task
fails (5 review iterations without PASS, or a CI authentication precondition).
Report back:
1. Verdict: PASS or FAIL
2. PR URL (if PASS)
3. Branch name
4. Number of review iterations used
5. Path to most recent findings file
6. If FAIL and an auth precondition was encountered, include a line
   `precondition: authentication` followed by the documented remediation path.
```

The `Mode:` line above is a MANDATORY, literal element of this brief —
task-implementer detects orchestration mode by its PRESENCE (see
`task-implementer.md` Stage 4). It must be authored verbatim; do not omit,
abbreviate, or reword it.

The sub-agent's dispatcher parses `ARGUMENTS_FOR_SUBAGENT` with the same
strict semantics defined in `.claude/skills/implement/SKILL.md`: it strips
`--no-handoff-gate` (if present) and sets `override_active` accordingly,
then routes to `task-implementer.md` for the cleaned path.

Wait for the sub-agent to return before starting the next task.

**Failure handling.** If the sub-agent return is **not a clean PASS** (no PR
URL and iteration count), **check for a `precondition: authentication` marker
line in the return FIRST** — search for the marker as well as for a `FAIL`
verdict. This check is independent of both the `Mode:` signal and the `FAIL`
verdict: it fires on the marker in ANY non-PASS sub-agent return, so it
backstops not only a mis-authored or omitted mode-signal line but also a
sub-agent that mis-detected the mode and returned the reply-continue affordance
prose without a `FAIL` verdict (the prose still carries the marker; the
orchestrator catches it here regardless).

**If the return carries the `precondition: authentication` marker (auth halt):**

> Task FAIL (authentication precondition): {filename}
> Branch: {branch}
> Remediation: {remediation path from the marker}
>
> CI validation hit an authentication precondition — an environment problem, not a code failure. Authenticate, then re-invoke `implement {TICKET}` — completed and skipped tasks will not repeat. No sub-agent is re-spawned here.

Do not re-spawn the sub-agent and do not proceed to subsequent tasks.

**If a FAIL return does NOT carry the marker (existing behaviour, unchanged):** halt immediately:

> Task FAIL: {filename}
> Branch: {branch}
> Most recent findings: {findings file path}
>
> Run halted. Remaining tasks have not been started. Resolve the failure and
> re-run `implement {TICKET}` — completed and skipped tasks will not repeat.

Do not proceed to subsequent tasks.

Record each result (filename, status: `complete` / `skipped` / `failed`, PR URL, iteration count) for OM-6.

### OM-6 — Final summary

Print a summary table of all tasks in execution order:

| Task | Status | PR | Iterations |
|------|--------|----|------------|
| {filename} | complete | {URL} | {N} |
| {filename} | skipped | — | — |
| {filename} | failed | — | {N} |

All tasks complete or skipped → exit cleanly (all-skipped is not an error). Task failed → the failure context was already reported in OM-5.

---

## Rules

- **Orchestration mode does not run Stages 0–7 itself.** It discovers tasks, validates the graph, and spawns one sub-agent per task; each sub-agent runs the full single-task implement flow from Stage 0.
- **The OM-3 design-PR gate runs EXACTLY ONCE for the whole ticket.** It is orthogonal to OM-5's per-task PR check; OM-5's CLOSED-as-resume behaviour is unchanged.
- **Propagate `--no-handoff-gate` into every OM-5 sub-agent prompt** when `override_active` is true. Forgetting to propagate would cause each sub-agent's Stage 0 to re-halt on the same check this orchestrator already cleared.

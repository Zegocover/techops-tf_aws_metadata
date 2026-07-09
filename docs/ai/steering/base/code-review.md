---
version: "1.2"
last_reviewed: 2026-06-05
---

# Code Review

Instructions for reviewing a diff against Zego standards. Defines which checks run, how they are grouped, and what the output must look like.

This document is what the `zego-review` skill checks against. An agent running a review must work through every check mechanically against the diff. Writing a review file by hand without running the checks does not satisfy the workflow.

---

## Groups

Checks are divided into fourteen groups, each run by a dedicated sub-agent in parallel. Groups E, F, G, I, J, K, M, and N are conditional — only spawn them if the relevant conditions are met.

| Group | Name | Standard file(s) | Conditional? |
|---|---|---|---|
| A | Scope | (inline below) | Never |
| B | Logging, Observability & Environment | `docs/ai/steering/base/logging.md`, `docs/ai/steering/base/observability.md`, `docs/ai/steering/base/environment.md` | Never |
| C | Testing | `docs/ai/steering/base/testing.md` | Never |
| D | Safety | (independent reasoning) | Never |
| E | Task spec & design doc | ticket's task spec (and design doc, if present) | Skip if no task spec |
| F | Python | `docs/ai/steering/languages/python.md` | Only if `.py` files in diff |
| G | Protobuf Converters | `docs/ai/steering/domains/protobuf-converters.md` | Only if `.proto` or `converter` files in diff |
| H | Error Handling, File Organisation, Resilience & Spelling | `docs/ai/steering/base/error-handling.md`, `docs/ai/steering/base/file-organisation.md`, `docs/ai/steering/base/resilience.md`, `docs/ai/steering/base/spelling.md` | Never |
| I | HCL/Terraform | `docs/ai/steering/languages/hcl.md` | Only if `.tf` or `.tfvars` files in diff |
| J | Scala | `docs/ai/steering/languages/scala.md` | Only if `.scala` files in diff |
| K | Swift | `docs/ai/steering/languages/swift.md` | Only if `.swift` files in diff |
| L | Financial Integrity | (delegates to `zego-audit-financial-integrity` skill) | Never |
| M | Kotlin | `docs/ai/steering/languages/kotlin.md` | Only if `.kt` files in diff |
| N | Protobuf Authoring | `docs/ai/steering/domains/protobuf-authoring.md` | Only if `.proto` files in diff |

---

## Group A — Scope

These checks apply to every diff. They are hardcoded here and have no standard file.

1. **No credentials in diff.** No passwords, API keys, tokens, or secrets appear in any added line. → blocker if found.
2. **One logical change.** The diff represents a single coherent unit of work. Unrelated refactors mixed with feature work → major; suggest splitting.
3. **Diff matches branch description.** Changes are consistent with what the branch name and commit messages describe. Unexplained scope creep → major.

---

## Group B — Logging, Observability & Environment

Load and apply all rules from `docs/ai/steering/base/logging.md`, `docs/ai/steering/base/observability.md`, and `docs/ai/steering/base/environment.md`.

Check every new or modified log call, metric instrument, span operation, and configuration/environment variable usage against the rules in those files. Apply all three files — logging, observability, and environment are distinct rule sets over cross-cutting infrastructure concerns.

**Honour each file's Applicability section — scope by the surfaces present in the diff, not by the repo's stack.** `logging.md`, `observability.md`, and `environment.md` each separate a universal core from rules that act on a specific backend surface:

- The **universal cores** — no logged credentials/PII, static messages with structured fields, sensible log levels, a single config entry point, documented variables — apply wherever the relevant code exists.
- The **backend-surface rules** — OTel/Datadog metric & span instrumentation, and the GitOps/Helm/`secrets-config` provisioning workflow — act only on those surfaces. Apply them wherever that surface exists in the repo: if the instrumentation infra is present, new or modified code paths in the diff are expected to be instrumented, so flag under-instrumentation (e.g. a new endpoint with no metric or span) even when the diff does not edit existing instrumentation. Where the surface is absent from the repo entirely, there is nothing to check.

Gate by surface presence, not by classifying the repo. Do **not** infer from a repo's language or framework that it *should* have server-side instrumentation or GitOps wiring, and do **not** raise a finding for the absence of a surface the repo does not have.

---

## Group C — Testing

Load and apply all rules from `docs/ai/steering/base/testing.md`.

Check every new or modified test file and test-adjacent change (fixtures, conftest, coverage config) against the rules in that file.

---

## Group D — Safety

No standard file. The sub-agent reasons independently over the diff.

For every new or modified function, class, method, or configuration block, generate candidate risk scenarios specific to the code patterns present, then investigate each. Assess whether the code:

1. Introduces a security vulnerability (injection, insecure defaults, credential or token exposure, authentication or authorisation bypass)
2. Risks data loss or corruption
3. Logs, stores, or transmits PII through an unintended channel

Every finding must be grounded in what the diff actually contains. Do not invent attack surfaces not present in the code.

---

## Group E — Task spec & design doc

Only run if a task spec exists for the ticket (search `docs/tasks/` for a file whose frontmatter `ticket` field matches the branch ticket).

If found: load the task spec and check whether the diff delivers what the goal, output spec, and acceptance criteria required. Also search `docs/design/` for a design doc whose `JIRA:` frontmatter field matches the ticket — if one is found, load it as supplementary context for the acceptance criteria check.

If not found: skip this group entirely. Do not emit a finding for its absence.

Skip this group when the diff for the current ticket contains only planning artefacts (paths matching the discovered task spec path, `docs/design/{TICKET}-*.md`, or `docs/tasks/{TICKET}-*.md`). The orchestrator records the skip in the review file's Validation-errors section with reason `pre-implementation` — specifically the exact string `Group E skipped: pre-implementation (diff contains only planning artefacts for {TICKET})`. Group E resumes as soon as the diff contains any other file.

---

## Group F — Python (conditional)

Only run if the diff contains `.py` files.

Load and apply all rules from `docs/ai/steering/languages/python.md`. Check every new or modified Python file.

**Honour `python.md`'s Applicability section**, the same way Groups B and H defer to each file's: it splits the standard into an intrinsic core that applies to any Python the diff touches and project-structure/tooling rules that bind only where the repo has already adopted the scaffolding (the `tests/unit|integration` split, the `pyproject.toml` coverage floor, the `BaseSettings` plumbing). The decisive test is the **repo's existing structure, not the diff's** — where the surface is absent, do not demand that a lone module introduce it; note it as an advisory at most. Note in particular that the single-config-entry-point *principle* is intrinsic: a module scattering `os.getenv()` calls is flaggable even where the repo has no `BaseSettings` entry point.

---

## Group G — Protobuf Converters (conditional)

Only run if the diff contains `.proto` files or files whose path includes `converter` or `converters`.

Load and apply all rules from `docs/ai/steering/domains/protobuf-converters.md`. If the standard file does not exist, skip this group and record a validation error.

---

## Group H — Error Handling, File Organisation, Resilience & Spelling

Load and apply all rules from `docs/ai/steering/base/error-handling.md`, `docs/ai/steering/base/file-organisation.md`, `docs/ai/steering/base/resilience.md`, and `docs/ai/steering/base/spelling.md`.

Check every new or modified catch/exception block, error type definition, and error-handling flow against the error-handling rules. Check file sizes and directory structure against the file-organisation rules. Check retry logic, timeout configuration, backoff implementation, and idempotency patterns against the resilience rules. Check all human-readable text (comments, docstrings, log messages, error messages) against the spelling rules.

---

## Group I — HCL/Terraform (conditional)

Only run if the diff contains `.tf` or `.tfvars` files.

Load and apply all rules from `docs/ai/steering/languages/hcl.md`. Check every new or modified Terraform file.

---

## Group J — Scala (conditional)

Only run if the diff contains `.scala` files.

Load and apply all rules from `docs/ai/steering/languages/scala.md`. Check every new or modified Scala file.

---

## Group K — Swift (conditional)

Only run if the diff contains `.swift` files.

Load and apply all rules from `docs/ai/steering/languages/swift.md`. Check every new or modified Swift file.

---

## Group L — Financial Integrity

This group delegates to the `zego-audit-financial-integrity` skill. It is the behaviour-and-integrity check that the operating model treats as a mandatory part of every review — its job is to surface code that looks designed to do something it should not be doing, distinct from the security vulnerabilities Group D covers.

In scope for this group (drawn from the skill's threat catalogues): fund skimming and payment diversion; ledger and balance-correctness drift; refund / void / unapplied-cash abuse; AML / sanctions / KYC control weakening; auth and privilege-escalation backdoors; reverse shells and unintended outbound exfiltration channels; hardcoded wallet addresses and private keys; disabled or weakened audit logging; and malicious or suspicious dependency additions.

The sub-agent must invoke the `zego-audit-financial-integrity` skill against the current diff and translate its output into the standard per-check tagged-line block and YAML findings list defined under `## Output format` below. The skill itself never approves a PR — it is advise-only by design (per its own `## Rules` section). For this group's findings:

- Critical or high-severity findings from the audit map to `[blocker]` — they must be surfaced to a human reviewer before merge.
- Medium-severity findings map to `[error]` (major).
- Low-severity findings map to `[warning]` (minor).
- A clean audit emits one `[pass]` line summarising the verdict.

Findings from this group are advisory toward the human reviewer who adjudicates the gate — they do not commit the reviewer to a block-or-approve decision; they ensure the suspicious pattern is visible.

---

## Group M — Kotlin (conditional)

Only run if the diff contains `.kt` files.

Load and apply all rules from `docs/ai/steering/languages/kotlin.md`. Check every new or modified Kotlin file.

---

## Group N — Protobuf Authoring (conditional)

Only run if the diff contains `.proto` files.

Load and apply all rules from `docs/ai/steering/domains/protobuf-authoring.md`. Check every new or modified `.proto` file against the contract-authoring rules (cross-service imports, reuse of shared `zego.protobuf` common types, contract-level comments, field optionality and numbering, the success/failure result model); apply the validation-workflow rules only when the diff is in a protobuf repository with the `buf` toolchain. If the standard file does not exist, skip this group and record a validation error.

---

## Severity definitions

- **blocker** — must be fixed before merge; merging with this present is wrong
- **major** — violates a standard rule without documented exception; must be fixed
- **minor** — violates a rule but is low-impact; should be fixed, may be deferred
- **nit** — style preference not covered by a rule; non-blocking

## Output format

Each sub-agent returns two things:

**1. Per-check block** — one line per item checked, tagged `[pass]`, `[advisory]`, `[warning]`, `[error]`, or `[blocker]`:

```
### Group {letter} — {name}
[pass] {check description} — {one sentence: what was found}
[advisory] {check description} — {one sentence: non-blocking observation}
[warning] {check description} — {one sentence: issue that should be fixed}
[error] {check description} — {one sentence: major issue that must be fixed}
[blocker] {check description} — {one sentence: blocker that must be fixed before merge}
```

Tag-to-severity mapping (one-to-one — use exactly the tag that matches the severity):

| Tag | Severity | Blocks verdict? |
|-----|----------|-----------------|
| `[pass]` | — | No |
| `[advisory]` | nit | No |
| `[warning]` | minor | No |
| `[error]` | major | Yes (FAIL) |
| `[blocker]` | blocker | Yes (FAIL) |

Every check that ran must appear as a line. `[pass]` lines are required. A sub-agent that returns only failures is not providing an audit trail.

In addition to the `PASS` and `FAIL` verdicts named by the orchestrator, the verdict surface includes `PRE-IMPLEMENTATION` — semantics: no implementation present yet; AC verification deferred; non-blocking. The findings-file status field carries the corresponding value `pre-implementation` with the same semantics as the verdict (no implementation present yet; AC verification deferred; non-blocking). These are emitted by the orchestrator's Stage 2b pre-implementation guard, which records the skip in the Validation-errors section with the exact reason string `Group E skipped: pre-implementation (diff contains only planning artefacts for {TICKET})` whenever the diff contains only planning artefacts (paths matching the discovered task spec path, `docs/design/{TICKET}-*.md`, or `docs/tasks/{TICKET}-*.md`).

**2. YAML findings list** — structured entries for every `[warning]`, `[error]`, and `[blocker]`:

```yaml
findings:
  - severity: blocker | major | minor | nit
    file: {path}
    line: {line number, range, or "n/a"}
    rule: {relative path to standard file}#{anchor}
    issue: {one sentence — what is wrong}
    suggestion: {one sentence — what to do instead}
```

Return `findings: []` if nothing to report.

## Exceptions

A diff author may deviate from a rule with a documented reason in a commit message or inline comment. If the deviation is documented and justified, do not flag it — note the exception in the summary.

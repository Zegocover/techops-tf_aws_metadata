---
# managed by bin/bundle — do not edit; regenerated on every release
standards_version: "1.3.1"
built_at: 2026-06-19
---

# Claude AI Standards

If `CLAUDE.local.md` exists in this directory, read it for additional repo-specific context. If it is absent, ignore this reference.

---

## Managed frontmatter block

The YAML frontmatter block at the top of each consumer repo's CLAUDE.md is managed by fan-out. Do not edit the managed keys manually — fan-out will overwrite them. See [ADR 003](docs/decisions/003-claudemd-frontmatter.md) for the full specification.

### Keys

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `standards_version` | yes | — | Version of the AI standards library applied to this repo. |

### `ci-test-command` (lives in `CLAUDE.local.md`, not here)

The `ci-test-command` key is **not** a managed CLAUDE.md key. It is per-repo, team-owned configuration and lives in `CLAUDE.local.md` frontmatter, which fan-out never ships and therefore never overwrites — so the value survives standards bumps. The `ci-validation` skill reads it from `CLAUDE.local.md` as the highest-priority discovery source.

Optional. Declares the commands the `implement` skill runs for CI validation (Stage 4) before committing. When absent, the skill discovers commands automatically from `.buildkite/pipeline.yml` or `.github/workflows/*.yml`. Recommended for repos with complex pipelines where automatic extraction may be inconsistent.

See [ADR 003](docs/decisions/003-claudemd-frontmatter.md) for the full specification: priority chain, value format, and examples.

---

## Where things live

- **Generic skills** — `.claude/skills/`. The `implement`, `review`, `create-pr`, `fix-pr-comments`, `fix-buildkite`, `write-design-doc`, and `write-design-doc-max` skills. Always driven by a task spec. `write-design-doc` is the default; `write-design-doc-max` is the high-context, deep-review variant invoked only on explicit request.
- **Scripts** — `.claude/scripts/`. Shell helper scripts: `pr-comments.sh`, `pr-reply.sh`, `pr-resolve.sh`, `pr-issue-reply.sh` for GitHub PR comment management, and `pr-label.sh` for applying stage labels to skill-created PRs.
- **Hooks** — `.claude/hooks/`. `PreToolUse` hook scripts registered in `.claude/settings.json`. Currently: `git-safety.sh`, `filesystem-safety.sh`, `database-safety.sh` — block dangerous Bash patterns before execution.
- **Design Documents** — `docs/design/`. One file per feature, produced by `write-design-doc` (or `write-design-doc-max`) Phase 1.
- **Task Specs** — `docs/tasks/`. One file per task, produced by `write-design-doc` (or `write-design-doc-max`) Phase 2. Consumed by `implement`.
- **AI review outputs** — `docs/ai/reviews/`. Findings files written by the `review` skill; one file per review run.

---

## Tooling preferences

Use `rg` (ripgrep) instead of `grep`, and `fd` instead of `find`. The `.claude/settings.json` deny-list enforces this — `grep` and `find` are blocked.

Hook scripts must use `python3` to parse stdin JSON — do not use `jq`. On parse failure, exit 0 (fail open).

---

## Standards in this library

Read and apply all files listed here. `base/` applies to all code; `languages/` applies when writing that language.

- `docs/ai/steering/base/code-review.md` — code review conventions: review groups, scope, conditional checks per language and domain.
- `docs/ai/steering/base/logging.md` — logging conventions: levels, structured calls, PII rules, Zego common keys.
- `docs/ai/steering/base/observability.md` — metrics and distributed tracing: three-signal coverage, OpenTelemetry instrumentation, metric naming, span attributes.
- `docs/ai/steering/base/pull-requests.md` — pull request conventions: title format, body structure, not opening PRs unprompted.
- `docs/ai/steering/base/testing.md` — testing conventions: integration-first, observable behaviour, naming, test isolation.
- `docs/ai/steering/base/environment.md` — environment variable conventions (language-agnostic): single config entry point, GitOps-before-app sequencing, committed/gitignored config file layout, secrets-config provisioning workflow.
- `docs/ai/steering/base/commit-workflow.md` — commit workflow conventions: never bypass pre-commit hooks, fix-and-retry on failure, preserve commit message on retry, framework-agnostic no-hook handling.
- `docs/ai/steering/base/error-handling.md` — error handling conventions: custom domain exceptions, catch-specific patterns, boundary-only broad catches, and the prohibition on silent swallowing.
- `docs/ai/steering/base/file-organisation.md` — file organisation conventions (language-agnostic): one responsibility per file, 50-300 line target, split at 400+, concept-based grouping.
- `docs/ai/steering/base/resilience.md` — resilience conventions (language-agnostic): retry only transient failures, exponential backoff with jitter, maximum retry counts, explicit timeouts, idempotency keys.
- `docs/ai/steering/base/spelling.md` — spelling conventions: UK English in all human-readable text; identifiers and API contracts exempt.
- `docs/ai/steering/base/skill-pipeline.md` — development pipeline: which skill to use when, the requirements-to-merged-PR ordering, the per-phase PR handoff shape, skip rules, and the off-path utilities.

- `docs/ai/steering/languages/python.md` — Python conventions: project structure, dependency injection, typing, functional core/imperative shell, pytest patterns.
- `docs/ai/steering/languages/hcl.md` — HCL/Terraform conventions: canonical file layout, typed variables and validation blocks, workspace + env tfvars pattern, exact required_version and pessimistic provider pinning, committed lockfiles, S3 backend with DynamoDB locking, Secrets Manager and `secrets-config` for secrets, `default_tags` on the AWS provider, Buildkite-enforced fmt/tflint/validate, Buildkite plan-as-artefact pattern, and module extraction with terraform-docs and strict semver tags.

- `docs/ai/steering/languages/scala.md` — Scala conventions: functional core/imperative shell, composition-root DI, sealed-trait ADTs, smart constructors, `Future` + Akka concurrency, gRPC/AWS-adapter boundaries, ScalaTest/ScalaCheck testing.

- `docs/ai/steering/domains/protobuf-converters.md` — protobuf converter conventions: never hand-roll conversions, nullability suffix rules, proto3 zero-value semantics, going upstream for missing converters.

- `docs/ai/steering/domains/frontend-ticket-spec.md` — frontend ticket specification conventions: what must be resolved before an autonomous agent picks up a ticket in zego-web, customer-acquisition, checkout-mfe, my-zego, or zego-utils.

---

## Skills available in this repo

- **`implement`** — You MUST use this when the user asks to implement a task spec or produce the artefact it describes.
- **`review`** — You MUST use this when the user asks to review their code, run a code review, or verify a branch against Zego coding standards (with or without a task spec).
- **`audit-financial-integrity`** — You MUST use this ONLY when the user explicitly asks to review, vet, or audit a PR, branch, diff, changeset, or commit in a payments, banking, insurance, lending, or other money-handling codebase for malicious intent — to "check for anything dodgy / nefarious / untoward", fund skimming, payment diversion, backdoors, reverse shells, data exfiltration, hardcoded secrets or wallets, weakened auth or AML/sanctions controls, disabled logging, or malicious dependencies. For a generic "review this PR" or code-review request, use the `review` skill instead — it already runs this audit as Group L.
- **`create-pr`** — You MUST use this when the user asks to open a pull request for a completed implementation.
- **`ci-validation`** — You MUST use this when the user asks to run CI validation locally or verify that code passes CI checks before committing.
- **`fix-pr-comments`** — You MUST use this when the user asks to address or fix unresolved review threads on a pull request.
- **`fix-buildkite`** — You MUST use this when the user asks to diagnose, fix, or retry failed Buildkite CI builds.
- **`fix-merge-conflict`** — You MUST use this when the user asks to resolve merge conflicts, rebase a feature branch onto its base, or unblock a pull request whose branch has conflicts with its base — including when they give you a GitHub PR URL with conflicts to fix, or ask to bring the latest base branch (e.g. main) into their current branch.
- **`fix-bug`** — You MUST use this when the user asks to fix a bug, resolve a defect, or address a bug ticket given a JIRA ticket URL or key — small or mid-size fixes that have no design document.
- **`write-design-doc`** — You MUST use this when the user asks to write a design document or task specs for a feature given a JIRA ticket or requirements file. This is the default design-doc flow.
- **`write-design-doc-max`** — You MUST use this ONLY when the user explicitly asks for the "max" design-doc flow. It produces the same artefacts as `write-design-doc` but spends much more context running an incremental review of every design and task document. Not auto-routed for generic design-doc requests; the default `write-design-doc` handles those.
- **`write-requirements`** — You MUST use this when the user asks to collect or document requirements from a product owner or PM.
- **`write-acceptance-handoff`** — You MUST use this when the user asks to produce an acceptance handoff document for product sign-off.
- **`write-standard`** — You MUST use this when the user asks to create a new standard, write a standards file, author coding conventions, or extend an existing standards file with new rules.
- **`write-skill`** — You MUST use this when the user asks to create a new skill, write a skill file, or produce a SKILL.md for a workflow.
- **`extend-claude-standards`** — You MUST use this when the user asks to deepen, update, or fill gaps in the repository context section of CLAUDE.local.md.

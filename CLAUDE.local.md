---
ci-test-command: "terraform fmt -check -recursive"
---

# CLAUDE.local.md

Team-local context for AI agents working in this repository. Captures
non-obvious knowledge an agent could not reliably derive by reading the
codebase itself. This file is never shipped or overwritten by a standards bump
— all repo-specific context belongs here, not in `CLAUDE.md`.

## Repository context

### Purpose

- A **reusable Terraform module** that, given a VPC marker (name tag), exposes that VPC's attributes (VPC id, subnets, route tables, VPN CIDR) as outputs — so consumers don't duplicate the `data` lookups. Read-only: it declares **only data sources, no resources**.
- Owner `systems-engineering`, domain `orchestration`.

### Repository structure

- Flat module: `datasources.tf`, `output.tf` (8 outputs), `variables.tf` (single `marker` input), `local.tf`. Consumed via a git `source` ref (`github.com/zegocover/techops-tf_aws_metadata`); requires AWS provider ≥ 3.55. No backend, no Makefile/Buildkite — CI is the shared claude-code-review GHA only.

### Maintenance notes

- `ci-test-command` is `terraform fmt -check -recursive` (auth-free; no Makefile/pipeline here).
- **`terraform-safety.sh`** is registered for consistency with the IaC fleet, though this module creates nothing (data-only). Being upstreamed to `zego-ai-standards` ([PR #193](https://github.com/Zegocover/zego-ai-standards/pull/193)); re-add the registration if a bump overwrites `.claude/settings.json`.

## Standards scope

The AI Standards library fans in unconditionally (ADR-002). For a reusable Terraform module:

### Out of scope

- `docs/ai/steering/languages/python.md`, `domains/protobuf-converters.md`, `domains/frontend-ticket-spec.md` — N/A.
- `docs/ai/steering/base/logging.md`, `observability.md`, `error-handling.md`, `resilience.md` — declarative; no runtime.
- `docs/ai/steering/base/environment.md` — a library module with input variables, not a deployable with environment config.

### Load-bearing

- `docs/ai/steering/base/code-review.md`, `commit-workflow.md`, `file-organisation.md`, `pull-requests.md`, `spelling.md`
- `docs/ai/steering/base/testing.md` — no tests today; native `.tftest.hcl` would suit if added.

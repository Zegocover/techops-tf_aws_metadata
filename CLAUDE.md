# CLAUDE.md

Repository context for AI agents working in this repository. Captures
non-obvious knowledge an agent could not reliably derive by reading the
codebase itself. Standards and skills come from the `zego-standards` plugin,
not from this repository.

## Repository context

### Purpose

- A **reusable Terraform module** that, given a VPC marker (name tag), exposes that VPC's attributes (VPC id, subnets, route tables, VPN CIDR) as outputs — so consumers don't duplicate the `data` lookups. Read-only: it declares **only data sources, no resources**.
- Owner `systems-engineering`, domain `orchestration`.

### Repository structure

- Flat module: `datasources.tf`, `output.tf` (8 outputs), `variables.tf` (single `marker` input), `local.tf`. Consumed via a git `source` ref (`github.com/zegocover/techops-tf_aws_metadata`); requires AWS provider ≥ 3.55. No backend, no Makefile/Buildkite — CI is the shared claude-code-review GHA only.

### Maintenance notes

- `ci-test-command` is `terraform fmt -check -recursive` (auth-free; no Makefile/pipeline here).

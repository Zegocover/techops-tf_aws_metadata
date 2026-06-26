---
version: 1.0
last_reviewed: 2026-06-03
---

# HCL Standards

Structural and operational conventions for Terraform — how root configurations are split, providers and Terraform itself are pinned, state is held, secrets are sourced, and changes are gated through CI. Apply these rules to any `.tf`, `.tfvars`, or related Makefile and pipeline file you write or modify. Formatting and linting are enforced mechanically by `terraform fmt` and `tflint` configured in CI and are not documented inline here. Secrets-config provisioning for runtime secrets consumed by deployed services is owned by `docs/ai/steering/base/environment.md`.

## Rules at a Glance

1. **Split files by concern.** Use canonical files (`provider.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `datasources.tf`, `main.tf`, and optional resource-type files like `iam.tf` or `s3.tf`) rather than a single monolithic `main.tf` — a 500-line `main.tf` hides the dependency graph and forces a full read of the file to find anything.
2. **One source of truth for `terraform {}`.** Define the `terraform {}` block (with `required_version`, `required_providers`, and `backend`) in exactly one file per root config — either `provider.tf` or a dedicated `versions.tf`, never split across both — duplicating it causes silent precedence surprises and drift between local-dev and CI.
3. **Exact `required_version` pin.** Pin Terraform itself to an exact version (e.g. `required_version = "1.9.7"`), never `~>` or `>=` — a floating Terraform version causes state-format drift between local-dev, CI, and apply runners that is expensive to unwind.
4. **Pessimistic provider pins.** Pin every entry in `required_providers` with the pessimistic `~> X.Y.Z` operator — exact pins block patch upgrades that often carry security fixes, and lower-bound floors allow untested major bumps to land silently.
5. **Commit `.terraform.lock.hcl` for root configs.** Root configurations commit `.terraform.lock.hcl`; modules do not — consumers own the lock for their root and committing it inside a module would force every consumer onto the module author's resolution.
6. **S3 backend with DynamoDB locking.** Every root config uses the shared S3 backend with DynamoDB locking and an `assume_role` block — local state corrupts on first concurrent apply, and unlocked S3 backends race.
7. **Nest assume-role attributes under `assume_role`.** Terraform 1.10 removed (deprecated in 1.6) the top-level `role_arn` attribute from the `backend "s3"` block; nest it under `assume_role` (argument-with-object-value form for the s3 backend, true block form for the AWS provider) — mixing the deprecated top-level attribute with newer Terraform releases produces a parse error on upgrade rather than a graceful deprecation path.
8. **`terraform workspace` + `env/<workspace>.tfvars` for multi-env.** Multi-environment root configs use `terraform workspace` and a per-workspace tfvars file under `env/`; never inline environment-specific values inside `.tf` — inlined ternaries on `var.environment` are unreadable and fight against the workspace model the rest of the platform assumes.
9. **Typed `variable` blocks with `description`.** Every `variable` has explicit `type =` and `description =` — an untyped variable accepts anything Terraform can coerce, and an undescribed variable forces the reader into the call site to understand intent.
10. **Snake_case names.** Variable, output, local, resource, and module names use `snake_case` — Terraform's documentation, provider attribute names, and the wider HCL ecosystem are uniformly snake_case; mixing cases breaks reader expectations and complicates `for_each` keys.
11. **Rich types over loose maps.** Use `object({...})` or `map(object({...}))` rather than `map(any)` or `map(string)` when the shape is known — loose maps push validation into the resource bodies and accept malformed input until apply.
12. **`validation {}` for non-trivial input constraints.** Use `validation {}` blocks on variables when valid input is non-obvious (enumerations, regex, ranges) — runtime `count` tricks and `regex()` panics inside resources fail later and with worse error messages than a `validation` failure at plan time.
13. **Every `output` has a `description`.** Outputs form the module's public interface — an undescribed output is an undocumented API.
14. **`sensitive = true` on outputs that expose secrets.** Mark outputs that surface tokens, passwords, or secret ARNs with `sensitive = true` — Terraform redacts them in plan and apply logs, preventing accidental leakage into CI artefacts.
15. **No secrets in `.tf` or `.tfvars`.** Never inline tokens, API keys, or passwords in source files; fetch them via `data "aws_secretsmanager_secret_version"` — anything committed to git is leaked forever. Runtime secrets consumed by deployed services use `secrets-config`, owned by `docs/ai/steering/base/environment.md`.
16. **`default_tags` on the AWS provider.** Configure `default_tags` on the AWS provider with the standard Zego tag schema (owner, managed-by, managed-from, workspace, environment, service, cost-center) — per-resource tagging drifts within the same root config and breaks cost attribution. The specific keys are owned by the AWS domain standard; the language-level rule is that the block must exist.
17. **`terraform fmt -check -recursive` in CI.** Every Terraform repo's Makefile exposes a `fmt_check` target that Buildkite invokes — formatting drift in review is noise that distracts from the actual change.
18. **`tflint` runs in CI.** Add `tflint` to the Makefile and Buildkite pipeline — `terraform validate` catches HCL parse errors but does not catch provider-specific anti-patterns or deprecated arguments.
19. **`terraform validate` before `plan` in CI.** Run `terraform validate` after `init` and before `plan` — validate is cheap, runs without provider credentials, and surfaces HCL errors before the slower plan step.
20. **Plan as Buildkite artefact, exit code as metadata.** Use `terraform plan -out=terraform.plan -detailed-exitcode`, upload the plan as a Buildkite artefact, and surface the exit code via `buildkite-agent meta-data set` — an apply without a recorded plan cannot be reviewed or replayed.
21. **Extract a module when reuse appears twice.** Extract a `module` only when the same resource block appears in two or more root configurations and the interface is stable — a one-call module wraps complexity it has not yet earned and adds a versioning hop for every change.
22. **Module README with `terraform-docs` markers.** Module repos have a `README.md` with `terraform-docs`-generated input/output tables between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->`, regenerated via `make docs` — hand-written input tables drift the moment a variable is added.
23. **Strict `vX.Y.Z` semver tags for modules.** Module repos tag releases as strict semver with a leading `v` (`v1.2.3`); consumers pin with `?ref=v1.2.3` — non-semver tags break `terraform-docs`, dependabot, and any tooling that parses tags as versions.

## Split files by concern

A single 500-line `main.tf` forces every reader to scan the whole file to find the dependency graph, the provider configuration, or the variables. Splitting by concern lets readers jump directly to the file relevant to their question and lets the file name itself convey what is inside.

Canonical files are `provider.tf`, `variables.tf`, `outputs.tf` (plural), `locals.tf` (plural), `datasources.tf` (plural), and `main.tf`. Where a root config grows beyond a handful of resource types, add resource-type files such as `iam.tf`, `s3.tf`, or `kinesis.tf`; `main.tf` then holds the orchestrating resources and module calls, not everything.

```hcl
# good — split by concern; each file's name conveys what it holds
# .
# |-- provider.tf       # terraform {} block, providers
# |-- variables.tf      # input variables
# |-- outputs.tf        # module outputs
# |-- locals.tf         # locals
# |-- datasources.tf    # data sources
# |-- main.tf           # orchestrating resources and module calls
# |-- iam.tf            # IAM resources
# |-- s3.tf             # S3 resources

# bad — monolithic main.tf hides the dependency graph
# .
# `-- main.tf  # 500 lines: providers, variables, locals, data, IAM, S3, outputs all mixed
```

## One source of truth for `terraform {}`

The `terraform {}` block (with `required_version`, `required_providers`, and `backend`) must appear exactly once per root configuration. Splitting it across two files — `versions.tf` declaring `required_providers` and `provider.tf` declaring the `backend` — works until someone moves or duplicates a block and Terraform takes the last one parsed, which the reader cannot infer from the filenames.

Pick one file (either `provider.tf` or a dedicated `versions.tf`) and put the entire `terraform {}` block there.

```hcl
# good — one terraform {} block, in provider.tf
terraform {
  required_version = "1.9.7"

  backend "s3" {
    bucket         = "zego-terraform-state"
    region         = "eu-west-1"
    key            = "aws-eks/eks.tfstate"
    dynamodb_table = "terraform_locks"
    encrypt        = true
    assume_role = {
      role_arn = "arn:aws:iam::<terraform-role-account-id>:role/terraform"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33.0"
    }
  }
}

# bad — required_providers split across two files; precedence is invisible
# versions.tf
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.95.0" }
  }
}

# provider.tf
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
```

## Exact `required_version` pin

A floating `required_version` such as `>= 1.5` lets every machine resolve to whatever Terraform is installed locally. Local-dev, CI runners, and apply runners drift independently, and a `1.9` write of state cannot be read by `1.6` — recovery is manual state surgery.

Pin Terraform itself to an exact version (a bare version string is parsed as `= 1.9.7`; some teams prefer to write the operator explicitly: `required_version = "= 1.9.7"`). Upgrades are then a deliberate PR that bumps the pin in lockstep across the Makefile, the Buildkite image, and `.tool-versions` if present.

```hcl
# good — exact pin; all machines run identical Terraform
terraform {
  required_version = "1.9.7"
}

# bad — floating; local-dev and CI drift
terraform {
  required_version = ">= 1.5"
}

# bad — pessimistic on Terraform itself; minor bumps land silently
terraform {
  required_version = "~> 1.9"
}
```

## Pessimistic provider pins

Providers should be pinned with the pessimistic operator `~> X.Y.Z`, which permits patch upgrades (`~> 5.95.0` accepts `5.95.1`, `5.95.99`) but blocks minor and major. Patch releases routinely carry security fixes; blocking them by pinning exactly forces those fixes into a separate PR. Floors such as `>= 5.0` accept untested major upgrades silently. Use the three-component form (`~> 5.95.0`) so only the patch component is allowed to vary. The two-component form (`~> 5.95`) lets the minor component vary as well, which is rarely what you want for a Zego repo.

```hcl
# good — pessimistic; patch upgrades are automatic, minor and major are gated
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.95.0"
  }
  kubernetes = {
    source  = "hashicorp/kubernetes"
    version = "~> 2.33.0"
  }
}

# bad — exact pin blocks patch upgrades
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "5.95.0"
  }
}

# bad — floor accepts untested major upgrades silently
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = ">= 5.0"
  }
}
```

## Commit `.terraform.lock.hcl` for root configs

The dependency lock file records the exact provider versions and checksums resolved by `terraform init`. Committing it for root configurations means CI and every developer install the same provider binaries; without it, CI resolves whatever satisfies the constraint at run time and can drift from local-dev mid-PR.

Modules are the exception. A module is consumed by many root configurations; committing a lock file inside the module would force every consumer onto the module author's resolution, which is not what the lock file is for.

```makefile
# good — Makefile target that regenerates the lock file deliberately
update_lock_file:
	@echo "Updating the terraform lockfile for CI and local-dev"
	@terraform init -input=false
	@terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64
```

```gitignore
# bad — .terraform.lock.hcl in .gitignore on a root config
.terraform/
.terraform.lock.hcl
```

## S3 backend with DynamoDB locking

`backend "local"` puts state on the engineer's laptop. Apply from CI and apply from a laptop will then write to two different state files, and the divergence is silent until the next plan diffs against a stale state and proposes destructive changes.

Use the shared S3 backend at `bucket = "zego-terraform-state"`, `region = "eu-west-1"` with `dynamodb_table = "terraform_locks"` for concurrent-apply locking and `encrypt = true` for at-rest encryption. Each root config gets a unique `key` in the bucket. Terraform 1.10 introduced native S3 conditional-write locking via `use_lockfile = true`; once the estate is on 1.10+, `use_lockfile = true` is the going-forward replacement for the DynamoDB lock table — this rule will be revisited then.

```hcl
# good — S3 backend with DynamoDB locking and assume_role block
terraform {
  backend "s3" {
    bucket         = "zego-terraform-state"
    region         = "eu-west-1"
    key            = "aws-eks/eks.tfstate"
    dynamodb_table = "terraform_locks"
    encrypt        = true
    assume_role = {
      role_arn = "arn:aws:iam::<terraform-role-account-id>:role/terraform"
    }
  }
}

# bad — local backend; state lives on a laptop
terraform {
  backend "local" {}
}
```

## Nest assume-role attributes under `assume_role`

Terraform 1.10 removed (deprecated in 1.6) the top-level `role_arn`, `session_name`, and `external_id` attributes from the `backend "s3"` block; nest them under `assume_role` (an argument-with-object-value: `assume_role = { ... }`). The AWS provider takes the same intent in true HCL block form (`assume_role { ... }`, no equals). Mixing the deprecated top-level attributes with newer Terraform releases produces a parse error on upgrade rather than a graceful deprecation path.

```hcl
# good — s3 backend uses argument-with-object-value form (`= { ... }`)
backend "s3" {
  bucket         = "zego-terraform-state"
  region         = "eu-west-1"
  key            = "aws-eks/eks.tfstate"
  dynamodb_table = "terraform_locks"
  encrypt        = true
  assume_role = {
    role_arn = "arn:aws:iam::<terraform-role-account-id>:role/terraform"
  }
}

# bad — bare role_arn; unsupported in newer Terraform
backend "s3" {
  bucket         = "zego-terraform-state"
  region         = "eu-west-1"
  key            = "aws-eks/eks.tfstate"
  dynamodb_table = "terraform_locks"
  encrypt        = true
  role_arn       = "arn:aws:iam::<terraform-role-account-id>:role/terraform"
}
```

## `terraform workspace` + `env/<workspace>.tfvars` for multi-env

A multi-environment root config needs the same code to apply against staging, production, and any sandbox accounts. Two patterns compete: ternaries on `var.environment` inside `.tf` files, or `terraform workspace` with a per-workspace tfvars file. The workspace pattern keeps the `.tf` code identical across environments; environment-specific values live in `env/<workspace>.tfvars` and are loaded with `-var-file`.

```makefile
# good — workspace-driven init and plan
init: check_args
	@terraform init -input=false
	@terraform workspace select ${WORKSPACE} || terraform workspace new ${WORKSPACE}

plan: init
	@terraform plan -input=false \
		-var-file=env/${WORKSPACE}.tfvars \
		-detailed-exitcode \
		-out=terraform.plan
```

```
# good — env/ directory with one tfvars per workspace
env/
  datascience-prod-kubeflow.tfvars
  datascience-sandbox-kubeflow.tfvars
  integrations.tfvars
  production.tfvars
  shared-services.tfvars
  staging.tfvars
  syseng-sandbox.tfvars
```

```hcl
# bad — environment switching via inline ternaries
locals {
  env_specific_values = var.environment == "production" ? {
    instance_type = "m5.large"
    min_size      = 3
  } : {
    instance_type = "t3.small"
    min_size      = 1
  }
}
```

## Typed `variable` blocks with `description`

A `variable` block without `type` and `description` is an undocumented dynamically-typed input. Terraform will accept anything it can coerce, and the reader has to find every call site to understand what the variable is for. Both attributes are cheap to add and make the variable's contract explicit.

```hcl
# good — typed and described
variable "shard_count" {
  description = "Shard count for Kinesis stream"
  type        = number
  default     = 1
}

# bad — untyped, undescribed
variable "records" {}
```

## Snake_case names

Terraform's own attribute names, the provider documentation, and `for_each` keys are uniformly snake_case. Mixing in `camelCase` or `PascalCase` breaks the visual rhythm of HCL and introduces a translation step every time a value flows into a provider attribute that expects snake_case.

```hcl
# good — snake_case throughout
variable "provider_role_name" {
  description = "IAM role to assume when running Terraform"
  type        = string
}

resource "aws_iam_role" "policy_reader" {
  name = "policy-reader"
}

# bad — PascalCase variable name
variable "ProviderRoleName" {
  type = string
}
```

## Rich types over loose maps

`map(any)` and `map(string)` accept anything that can be coerced to the loose shape, deferring validation to the resource that consumes the value. When the shape is known up front, declare it as `object({...})` or `map(object({...}))` so Terraform validates at plan time and reviewers can read the contract directly.

```hcl
# good — explicit shape; plan-time validation
variable "node_groups" {
  description = "EKS node group configuration, keyed by group name"
  type = map(object({
    min_size       = number
    max_size       = number
    instance_types = list(string)
  }))
}

# bad — loose map; any structure accepted until apply
variable "node_groups" {
  description = "EKS node group configuration"
  type        = map(any)
}
```

## `validation {}` for non-trivial input constraints

When valid input is not obvious from the type alone — an enumeration, a regex, a numeric range — encode the constraint as a `validation {}` block on the variable. Failures then surface at plan time with a clear error message, rather than at apply time as a provider rejection or, worse, a malformed resource that succeeds silently.

```hcl
# good — explicit constraint, clear error message at plan time
variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

# bad — enforcement via runtime count hack; failure mode is silent
resource "aws_s3_bucket" "production_only" {
  count  = var.environment == "production" ? 1 : 0
  bucket = "..."
}
```

## Every `output` has a `description`

Outputs are the module's public interface. Consumers find them via `terraform-docs`-generated tables, IDE hover, and the registry UI; an undescribed output forces every consumer to read the module's source to understand what the value represents.

```hcl
# good — described
output "kinesis_stream_arn" {
  description = "Kinesis Stream ARN"
  value       = aws_kinesis_stream.this.arn
}

# bad — undescribed
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
```

## `sensitive = true` on outputs that expose secrets

Plan and apply output is captured in CI logs and Buildkite annotations. An output that surfaces a token, password, or secret ARN without `sensitive = true` leaks into those artefacts and into anything that mirrors them.

The flag does not protect the value in state — state still contains it in cleartext — but it reduces the chance of accidental display in CI logs and `terraform output` calls.

Sensitive outputs are not safe to pipe into Buildkite annotations or PR comments — `terraform output -json` and `terraform output <name>` both reveal the value. Never feed `terraform output` results into `buildkite-agent annotate`, PR-comment scripts, or any other surface that mirrors CI output beyond the build-log retention.

```hcl
# good — marked sensitive; redacted in plan, apply, and console output
output "api_token" {
  description = "Cloudflare API token used by downstream services"
  value       = jsondecode(data.aws_secretsmanager_secret_version.cloudflare_api.secret_string)["key"]
  sensitive   = true
}

# bad — same value, no flag; leaks into CI logs
output "api_token" {
  description = "Cloudflare API token used by downstream services"
  value       = jsondecode(data.aws_secretsmanager_secret_version.cloudflare_api.secret_string)["key"]
}
```

## No secrets in `.tf` or `.tfvars`

Anything committed to a git repository is leaked forever, even if it is later removed — the history is the leak surface. Terraform code therefore never inlines a token, API key, or password. Provider credentials and provider-required secrets are fetched at runtime via `data "aws_secretsmanager_secret_version"`; the secret itself lives in AWS Secrets Manager.

Runtime secrets consumed by deployed services (database passwords, third-party API tokens used by an application) flow through `secrets-config`; the workflow is owned by `docs/ai/steering/base/environment.md`.

```hcl
# good — token fetched from Secrets Manager at runtime
provider "cloudflare" {
  api_token = jsondecode(data.aws_secretsmanager_secret_version.cloudflare_api.secret_string)["key"]
}

data "aws_secretsmanager_secret" "cloudflare_api" {
  provider = aws
  arn      = "arn:aws:secretsmanager:eu-west-1:<cloudflare-secrets-account-id>:secret:cloudflare_api_key-XXXXXX"
}

data "aws_secretsmanager_secret_version" "cloudflare_api" {
  provider  = aws
  secret_id = data.aws_secretsmanager_secret.cloudflare_api.id
}

# bad — token inlined; leaked to git history the moment it is committed
provider "cloudflare" {
  api_token = "cf_pat_AbcXyz123_committed_forever"
}
```

## `default_tags` on the AWS provider

Per-resource tagging drifts within a root configuration: a new resource is added without tags, an old resource keeps a deprecated key, and cost attribution stops aligning with reality. `default_tags` on the AWS provider applies a consistent tag schema to every resource that the provider creates.

The tag keys themselves are owned by the AWS domain standard; the language-level rule is that the `default_tags` block must exist on the AWS provider and per-resource `tags` blocks supplement rather than replace it.

```hcl
# good — AWS provider uses block form (`{ ... }`, no `=`)
provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${lookup(var.target_aws_account_id, var.account_name)}:role/${local.provider_role_name}"
  }

  default_tags {
    tags = {
      "meta.zego.tools/managed-by" = "terraform"
      "meta.zego.tools/owner"      = "systems-engineering"
      "meta.zego.tools/workspace"  = terraform.workspace
      # ... see the AWS domain standard for the full key set
    }
  }
}

# bad — no default_tags; per-resource tagging drifts
provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "data" {
  bucket = "data"
  tags = {
    owner = "systems-engineering"
  }
}
```

## `terraform fmt -check -recursive` in CI

Formatting drift in a Terraform PR is noise. Reviewers spend cycles distinguishing a real change from a whitespace shuffle, and the diff disguises the actual intent of the change. `terraform fmt -check -recursive` in CI rejects the PR before review starts, forcing the author to run `terraform fmt` locally.

```makefile
# good — Makefile target invoked by CI
fmt_check:
	@echo "Running terraform fmt (check only)"
	@terraform fmt -check -recursive
```

```yaml
# good — Buildkite step calling the Makefile target
- label: ":terraform: :thinking_face: Running Terraform fmt (check only)"
  commands:
    - tfenv install
    - "make fmt_check || buildkite-agent annotate --style error ':terraform: :rotating_light: Please run terraform fmt!'"
  agents:
    queue: primary
  timeout_in_minutes: 10
  branches: "!main"

# bad — fmt run manually only; drift accumulates between PRs
```

## `tflint` runs in CI

`terraform validate` catches HCL parse errors and unresolved references but not provider-specific anti-patterns: deprecated arguments, invalid instance types, attributes that the provider has removed. `tflint` covers that gap with provider-aware checks, and should run in CI.

```makefile
# good — Makefile target invoked by CI
tflint:
	@echo "+++ Running tflint"
	@docker run --rm -v "$(current_dir):/data" -t ghcr.io/terraform-linters/tflint
```

```yaml
# good — Buildkite step calling the Makefile target
- label: ":terraform: :mag: Running tflint"
  commands:
    - tfenv install
    - make tflint
  agents:
    queue: primary
  timeout_in_minutes: 10
  branches: "!main"

# bad — no tflint step in the pipeline; provider-specific anti-patterns and deprecated arguments slip through
- label: ":terraform: Running checks"
  commands:
    - tfenv install
    - make fmt_check
    - make plan
  agents:
    queue: primary
```

## `terraform validate` before `plan` in CI

`terraform validate` runs without provider credentials and surfaces HCL errors, unresolved references, and module-input shape mismatches in seconds. Running it after `init` and before `plan` keeps the slow, credentialed plan step from failing for reasons a syntax check would have caught.

```makefile
# good — validate as its own Makefile target, run before plan in the pipeline
validate: init
	@terraform validate

# bad — plan straight after init; HCL errors burn through plan credentials and time
plan: init
	@terraform plan -input=false -var-file=env/${WORKSPACE}.tfvars -out=terraform.plan
```

## Plan as Buildkite artefact, exit code as metadata

A `terraform apply` without a corresponding recorded plan is unreviewable: the reviewer cannot tell what was applied, and the team cannot replay the change. Capturing the plan as a Buildkite artefact and the `-detailed-exitcode` value as Buildkite metadata gives reviewers a stable URL for the plan and lets downstream pipeline steps branch on whether changes are pending.

```makefile
# good — plan written to file, uploaded as artefact, exit code surfaced as metadata
plan: init
	@terraform plan -input=false \
		-var-file=env/${WORKSPACE}.tfvars \
		-detailed-exitcode \
		-out=terraform.plan; \
	exit_code=$$? && \
	if [[ "$${exit_code}" == "1" ]]; then \
		exit $${exit_code}; \
	elif [[ "${EXIT_CODE_TO_META_DATA}" == "true" ]]; then \
		buildkite-agent meta-data set ${WORKSPACE} $${exit_code}; \
	fi

ifeq (${USE_ARTIFACT},true)
	@mkdir artifacts
	@cp terraform.plan artifacts/terraform-${WORKSPACE}.plan
	@buildkite-agent artifact upload "artifacts/**/*"
endif

# bad — terraform apply straight from CI with no recorded plan
apply: init
	@terraform apply -auto-approve -var-file=env/${WORKSPACE}.tfvars
```

## Extract a module when reuse appears twice

A Terraform module is a versioned interface. Extracting one for a single caller adds a repo, a release process, and a `?ref=` pin to every consumer change, in exchange for no reuse benefit. Wait until the same resource block appears in two or more root configurations and the interface has stabilised; then extract.

A one-call wrapper module is worse than inline code: it hides the resource it wraps behind a thin layer that has to be opened to understand what is actually being created.

```hcl
# good — module reused by multiple root configurations
module "pricing_events_stream" {
  source = "github.com/zegocover/zego-kinesis-stream-module?ref=v1.2.3"

  name        = "pricing-events"
  shard_count = 4
}

module "claims_events_stream" {
  source = "github.com/zegocover/zego-kinesis-stream-module?ref=v1.2.3"

  name        = "claims-events"
  shard_count = 2
}

# bad — module wrapping a single caller; adds versioning hop for no reuse
module "pricing_events_stream" {
  source = "github.com/zegocover/zego-kinesis-stream-module?ref=v1.2.3"

  name        = "pricing-events"
  shard_count = 4
}
```

## Module README with `terraform-docs` markers

Module consumers find inputs and outputs in the module's README. A hand-written input table drifts the moment a variable is added; a `terraform-docs`-generated table regenerates from the source. Place the generated content between marker comments so `terraform-docs` knows where to rewrite, and expose a `make docs` target that regenerates it.

```markdown
# good — terraform-docs markers in README.md

# zego-kinesis-stream-module

Provisions a Kinesis stream with the Zego defaults for retention, encryption, and tagging.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Stream name | `string` | n/a | yes |
| shard_count | Shard count for Kinesis stream | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| kinesis_stream_arn | Kinesis Stream ARN |
<!-- END_TF_DOCS -->

# bad — hand-written input list; drifts on every variable change

# zego-kinesis-stream-module

## Inputs

- name: stream name
- shards: number of shards (default 1)
```

## Strict `vX.Y.Z` semver tags for modules

Module repos tag releases as strict semantic versions with a leading `v`: `v1.0.0`, `v1.2.3`, `v2.0.0-beta.1`. Consumers pin to a specific tag in the source URL with `?ref=v1.2.3`. Non-semver tags (`1.2.3`, `v1.0.4.14`, `release-jan-2026`) break `terraform-docs`, dependabot, and any tooling that parses tags as versions. For high-blast-radius modules, prefer pinning by commit SHA (`?ref=<sha>`) rather than tag; tags are mutable and a force-push or tag-move re-points every consumer on the next `init`.

```bash
# good — strict semver tag with leading v
git tag v1.2.3
git push origin v1.2.3
```

```hcl
# good — consumer pins to a semver tag
module "pricing_events_stream" {
  source = "github.com/zegocover/zego-kinesis-stream-module?ref=v1.2.3"

  name = "pricing-events"
}
```

```bash
# bad — missing leading v
git tag 1.2.3

# bad — four-component version; not semver
git tag v1.0.4.14
```

## See Also

- [../base/environment.md](../base/environment.md) — environment variable conventions, GitOps-before-app sequencing, and the `secrets-config` workflow for runtime secrets consumed by deployed services.
- [../base/pull-requests.md](../base/pull-requests.md) — PR title format, body structure, and the prohibition on opening PRs unprompted.
- [../base/commit-workflow.md](../base/commit-workflow.md) — commit and pre-commit hook conventions: never bypass hooks, fix-and-retry on failure, never amend after a hook failure.
- [../base/code-review.md](../base/code-review.md) — code review groupings and which standards each group checks against.
- [../base/file-organisation.md](../base/file-organisation.md) — language-agnostic file-size and one-responsibility conventions; the canonical-file split in this standard refines them for HCL.
- [../base/spelling.md](../base/spelling.md) — UK English in all human-readable text (variable descriptions, outputs, comments).

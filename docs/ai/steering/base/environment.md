---
version: 1.2
last_reviewed: 2026-06-02
---

# Environment Variable Standards

Conventions for managing configuration — the governing philosophy is that configuration is infrastructure: every configuration value must be declared in a single config entry point, never scattered through ad-hoc reads, and never committed when it is a secret.

## The universal principle

These rules apply to **any** code that reads configuration, regardless of stack:

1. **Single config entry point** — one module/file owns all configuration reads; business logic receives values by injection, never by reading the environment directly (Rule 1 below).
2. **Sensible defaults where safe** (Rule 3 below).
3. **Committed dev/CI config, gitignored personal overrides; never commit secrets** (Rule 4 below).
4. **Document available variables** in a reference file kept in sync with the config entry point (Rule 5 below).

## Applicability

The **provisioning-workflow** rules — Rule 2 (GitOps before app code), Rule 6 (GitOps structure matches config), and Rule 7 (secrets through `secrets-config`) — act on one specific surface: configuration delivered through **Zego's Kubernetes pipeline** (ArgoCD, the `Zegocover/gitops-<repo>` Helm charts, and AWS Secrets Manager via the `secrets-config` Terraform repo). Apply them wherever that surface exists — i.e. the repo is deployed through that pipeline.

Where the surface is absent — the code is not deployed through the k8s GitOps pipeline — these three rules have nothing to act on. Apply the universal config-hygiene rules (1, 3, 4, 5) and use whatever configuration-delivery and secret-storage mechanism the platform provides in their place.

**Gate by the surface, not by the repo's language or framework.** Do not raise findings for missing GitOps/Helm/`secrets-config` wiring in a repo that does not deploy that way. (Runtimes that commonly lack this surface include mobile apps, browser frontends, BI/declarative models, and libraries — but these are illustrations, not the test. The test is whether the repo deploys through the k8s GitOps pipeline.)

## Rules at a Glance

1. **Single config entry point.** All environment variable reads must go through one module or file that centralises configuration — never scatter direct environment-variable reads through business logic, because scattered reads are invisible to the type system, bypass validation, and cannot be discovered by reading one file.
2. **GitOps before app code for required vars.** When a new environment variable has no default value, the GitOps PR (`Zegocover/gitops-<repo-name>`) must be merged and synced before the application code PR merges — otherwise ArgoCD deploys a container that crashes immediately because the required variable is missing.
3. **Sensible defaults where possible.** Give configuration fields a default value when a safe, non-secret default exists — this reduces the number of hard deployment dependencies and lets the service start in local development without a complete GitOps mirror.
4. **Committed development/CI config, gitignored personal overrides.** Maintain committed configuration files for local development and CI, plus a gitignored file for personal overrides — the personal override file must never be committed because it is the file most likely to accumulate secrets.
5. **Document available variables.** Maintain a reference file (`.env.example`, a doc comment block, or equivalent) listing every variable the config reads, with placeholder values and comments — without it, a new developer or Claude must reverse-engineer the config module to know what to set.
6. **GitOps structure matches config structure.** Environment variables in the Helm chart (`blueprint.apps.<service>.envVars`) must correspond one-to-one with fields in the config entry point — orphaned GitOps vars waste memory and create confusion; missing GitOps vars cause startup crashes.
7. **Provision secrets through secrets-config.** New secrets must be added to the `Zegocover/secrets-config` Terraform repo and applied before the consuming application code merges — if the secret does not exist in AWS Secrets Manager when the pod starts, the service will fail to access required secrets at runtime.

## Single config entry point

Every service must have one module or file that owns all configuration reads. Business logic receives config values via injection — it never reads from the environment directly. This makes every environment dependency discoverable in a single place, enables startup-time validation, and ensures the type system knows what each value is.

In Python, this is a Pydantic `BaseSettings` class. In Scala, this is Typesafe Config / PureConfig with a case class. See language-specific standards for implementation details.

The config entry point should be instantiated or loaded once at startup and injected into components that need it. Do not re-read the environment per request — each re-read bypasses any caching or validation the config layer provides.

```
# good — one config module, injected into consumers
[config entry point]
  port = 8080           (from env PORT, default 8080)
  log_level = "INFO"    (from env LOG_LEVEL, default "INFO")
  dynamo_region = ...   (from env DYNAMO__REGION)
  dynamo_table = ...    (from env DYNAMO__TABLE_NAME)

app = build_app(config)

# bad — env reads scattered in business logic
def get_score(customer_id):
    table_name = read_env("DYNAMO_TABLE_NAME")  # untyped, unvalidated, invisible
    ...
```

## GitOps before app code for required vars

When a config field has no default value, the service will crash at startup if the variable is missing from the environment. ArgoCD auto-syncs the GitOps repo, so the deployment sequence is: Buildkite builds the image, the gitops-buildkite-plugin updates the image tag, ArgoCD deploys. If the GitOps repo does not yet define the variable, the new container starts, config validation fails, and the container crash-loops.

The correct sequence for a required variable:

1. Add the field to the config entry point in the application repo (PR open, not merged).
2. Open a PR in `Zegocover/gitops-<repo-name>` adding the variable to `values.yaml` (or `values/<env>.yaml` for per-environment overrides).
3. Merge and confirm the GitOps PR has synced (ArgoCD shows the new config on the running pods, even though the app code does not yet read it — extra env vars are harmless).
4. Merge the application code PR.

For variables with a sensible default, the ordering is less critical — the service will start with the default and pick up the GitOps value on the next deploy. Even so, having the GitOps PR ready before or alongside the app PR is good practice.

```yaml
# gitops-score-per-product/values.yaml — add the variable here first
blueprint:
  apps:
    score-per-product:
      envVars:
        NEW_FEATURE_ENABLED: "false"   # safe default; app PR can merge independently

# gitops-score-per-product/values/production.yaml — per-env override
blueprint:
  apps:
    score-per-product:
      envVars:
        NEW_FEATURE_ENABLED: "true"
```

## Sensible defaults where possible

A field with a default can be omitted from the environment without crashing the service. This is valuable in three contexts: local development (fewer variables to configure), CI (lighter CI config), and resilience (a missing GitOps value degrades gracefully instead of crash-looping).

Not every field can have a default. Database hostnames, API keys, and service URLs are environment-specific by nature. The rule is: if a value is safe to assume in the absence of explicit configuration, provide it.

```
# good — safe defaults where they make sense; no default where they don't
dynamo_region  = "eu-west-1"    # safe default for Zego
dynamo_table   = <required>     # no safe default — must come from env
read_capacity  = 5              # reasonable starting point

# bad — no defaults anywhere; every variable must be provisioned even for local dev
dynamo_region  = <required>
dynamo_table   = <required>
read_capacity  = <required>
```

## Committed development/CI config, gitignored personal overrides

The config files serve distinct audiences:

- **Development config** (committed) — contains the full set of variables needed to run the service locally (pointing at local databases, mock endpoints, safe test values). In Python this is `.env.development`; in Scala this is an `application.conf` or `local.conf` with safe defaults.
- **CI config** (committed) — contains the minimal set needed for CI smoke tests (may point at ephemeral resources or stubs). In Python this is `.env.ci`; in Scala this may be a dedicated `ci.conf` or CI-specific env var injection.
- **Personal overrides** (gitignored, never committed) — developers use this for personal tweaks (a different database port, a debug flag). In Python this is `.env`; in Scala this might be `local-overrides.conf`. Values here take precedence over committed config.

The personal override file must never contain values in the repository. It is the file most likely to accumulate real credentials during development, and committing it — even once — exposes secrets in git history permanently.

```gitignore
# .gitignore — personal override files are always ignored
.env
local-overrides.conf
```

```shell
# .env.development (Python) — committed, safe local values
DYNAMO__REGION=eu-west-1
DYNAMO__TABLE_NAME=local-scores
PM__BASE_URL=http://localhost:8081
LOG_LEVEL=DEBUG
```

```shell
# .env.ci (Python) — committed, minimal for CI
DYNAMO__REGION=eu-west-1
DYNAMO__TABLE_NAME=ci-scores
LOG_LEVEL=WARNING
```

## Provisioning a new secret

Secrets are provisioned through the `Zegocover/secrets-config` Terraform repo — adding a field to the config entry point is not enough. If the secret does not exist in AWS Secrets Manager when the pod starts, the service will fail to access required secrets at runtime. The correct sequence mirrors the GitOps rule:

1. Add the secret field to the config entry point in the application repo (PR open, not merged).
2. Open a PR in `Zegocover/secrets-config` adding the secret to the relevant `env/<environment>.tfvars.json` files, listing your service as an `allowed_reader` with its `{namespace, service}` pair.
3. Merge the `Zegocover/secrets-config` PR; Buildkite runs `terraform apply`, creating the secret (empty) and its KMS key in AWS.
4. Coordinate with systems engineering to set the actual secret value in AWS Secrets Manager.
5. Merge the application code PR.

Each secret is scoped to specific services via `allowed_readers`. If your service needs to read a secret it is not currently listed for, the `Zegocover/secrets-config` entry must be updated to grant access — the pod's IRSA role is matched against the declared `{namespace, service}` pairs and access is denied without a match.

## Document available variables

Maintain a reference file listing every variable the config reads, with placeholder values that indicate the expected format and a comment explaining the purpose. Without it, onboarding a new developer or enabling Claude to configure the service requires reading the entire config module and tracing each field's environment variable name.

In Python, this is a `.env.example` file. In Scala, the `application.conf` with `${?ENV_VAR}` placeholders serves this role natively. Whatever the format, keep it in sync with the config entry point — when a field is added or removed, update the reference file in the same PR.

```shell
# .env.example — committed, documents every variable
# Application
LOG_LEVEL=INFO                          # DEBUG, INFO, WARNING, ERROR
PORT=8080                               # HTTP server port

# DynamoDB
DYNAMO__REGION=eu-west-1                # AWS region
DYNAMO__TABLE_NAME=                     # required — no default

# Policy Management client
PM__BASE_URL=                           # required — no default
PM__TIMEOUT_SECONDS=30                  # request timeout in seconds
```

## GitOps structure matches config structure

The Helm chart in `Zegocover/gitops-<repo-name>` defines environment variables under `blueprint.apps.<service-name>.envVars` in `values.yaml`, with per-environment overrides in `values/staging.yaml`, `values/production.yaml`, and `values/integrations.yaml`. Every field in the config entry point that does not have a safe default must have a corresponding entry in GitOps. Conversely, every variable defined in GitOps should correspond to a field the application actually reads — orphaned variables create confusion about what the service depends on.

When reviewing a PR that adds or removes a config field, check the corresponding GitOps repo for the matching change. If the field is required (no default), the GitOps PR must merge first (see "GitOps before app code for required vars").

```yaml
# gitops-score-per-product/values.yaml — base values shared across environments
blueprint:
  apps:
    score-per-product:
      envVars:
        LOG_LEVEL: "INFO"
        DYNAMO__REGION: "eu-west-1"
        DYNAMO__TABLE_NAME: "scores"
        PM__BASE_URL: "http://policy-management.internal"
        PM__TIMEOUT_SECONDS: "30"
```

```yaml
# gitops-score-per-product/values/production.yaml — production overrides only
blueprint:
  apps:
    score-per-product:
      envVars:
        LOG_LEVEL: "WARNING"
        DYNAMO__TABLE_NAME: "scores-production"
```

## See Also

- [../languages/python.md](../languages/python.md) — Python conventions including Pydantic BaseSettings config, dependency injection, and composition root patterns.
- [logging.md](logging.md) — logging conventions; the config entry point's `log_level` field is the standard way to control log verbosity per environment.
- [testing.md](testing.md) — testing conventions; test configuration should load committed development/CI config files.
- [Zegocover/secrets-config](https://github.com/Zegocover/secrets-config) — Terraform repo that provisions AWS Secrets Manager secrets; add entries here before consuming new secrets in application code.

# Base Standards

- [logging.md](logging.md) — logging conventions: levels, structured log calls, PII rules, and Zego common keys.
- [observability.md](observability.md) — metrics and distributed tracing: three-signal coverage, OpenTelemetry instrumentation, metric naming, span attributes, and async trace linking.
- [pull-requests.md](pull-requests.md) — PR title format, Background/Changes/Jira Ticket/s body structure, and gh pr create usage.
- [testing.md](testing.md) — integration-first testing philosophy, mock boundaries, fixture hygiene, and coverage enforcement.
- [environment.md](environment.md) — environment variable conventions (language-agnostic): single config entry point, GitOps-before-app sequencing, committed/gitignored config file layout, and secrets-config provisioning workflow.
- [error-handling.md](error-handling.md) — error handling conventions: custom domain exceptions, catch-specific patterns, boundary-only broad catches, and the prohibition on silent swallowing.
- [file-organisation.md](file-organisation.md) — file size and structural organisation: one responsibility per file, 50–300 line target, split at 400+, and concept-based grouping.
- [resilience.md](resilience.md) — resilience conventions: retry only transient failures, exponential backoff with jitter, maximum retry counts, explicit timeouts, and idempotency keys.
- [spelling.md](spelling.md) — UK English house style for all human-readable text: comments, docstrings, log messages, error messages; identifiers and API contracts exempt.
- [commit-workflow.md](commit-workflow.md) — commit workflow conventions: pre-commit hooks run on every commit, fix-and-retry on failure, never bypass with --no-verify, graceful no-hook handling.
- [skill-pipeline.md](skill-pipeline.md) — the development pipeline: which skill to use when, the requirements-to-merged-PR ordering, the per-phase PR handoff shape, skip rules, and the off-path utilities.
- [review-audience.md](review-audience.md) — review-audience conventions: the human-review-vs-AI-native artefact split and its decisive test, per-artefact buckets, the AI-native deflecting banner (text, placement, per-skill link resolution), and the single PR review-surface line.
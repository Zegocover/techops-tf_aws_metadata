---
version: 1.3
last_reviewed: 2026-06-02
---

# Logging Standards

Logging conventions — what to log, at what level, and how to structure log calls so that someone who knows the domain but not this codebase can diagnose problems from the output. Log formatting, serialisation, and output routing are enforced by the Zego standard logging library and are not covered here.

## Applicability

The rules below divide into a **universal core** that applies to any code that logs — regardless of stack or runtime — and **Zego-service specifics** that assume a backend service emitting to Zego's shared production logging infrastructure (Datadog).

**Universal core — applies everywhere** (backend, mobile, frontend, libraries):

- **Never log credentials** at any level (Rule 1) — passwords, tokens, API keys.
- **Never log PII into broadly-retained or collected telemetry** (Rule 1) — the "INFO and above" threshold below is the backend-service expression of this; on other runtimes apply the same principle to whatever log tier is collected/retained.
- **Static message + structured context fields**, no interpolation (Rule 2).
- **Meaningful log levels** (Rule 5) and **log intent and outcome** (Rule 6).

**Zego-service specifics — backend services on the shared logging infrastructure:**

- The **"INFO and above is collected by production infrastructure"** retention model (Rule 1) — mobile/frontend logs go to crash-reporting/analytics/browser consoles with different retention, so map the PII principle to that tier instead.
- **Zego common keys** and the **key inventory** (Rules 3, 4) — these exist for cross-service Datadog queryability. They apply where the runtime emits to the shared store; on mobile/frontend, adopt the equivalent shared-attribute convention for that platform's telemetry, or treat as not applicable.

Apply the universal core wherever code logs. Apply the service specifics where the code emits to the shared production logging infrastructure; where it logs to a different tier (mobile crash/analytics, browser console, etc.), map the same PII and structure principles to that tier. Gate by where the logs actually go, not by the repo's language or framework.

## Rules at a Glance

1. **No PII or credentials at INFO and above.** Never log names, addresses, or identifiers at INFO or higher — our logging setup is not designed to store PII. Never log passwords, tokens, or API keys at any level — credential exposure is equally damaging regardless of log retention. DEBUG is exempt for PII (not credentials): PII may appear at DEBUG level, which is disabled by default in production and should not be enabled there without a specific investigation reason.
2. **Structured logging.** Use a static string as the log message and put all variable data in structured context fields (in Python, the `extra` dict; see language-specific standards for equivalents) — no interpolation, format strings, or string concatenation in the message argument — so log lines are grep- and query-stable.
3. **Zego common keys.** Use the shared key names (e.g. `customer.id`, `policy.id`, `quote.id`) in context fields so logs are queryable across services without per-service field mapping.
4. **Document new keys.** Any new context key introduced in a PR must be documented wherever the project maintains its key inventory before the PR merges — keeping the key inventory current enables PII audits and makes cross-service query consistency maintainable. DEBUG-only diagnostic keys are exempt: they are PII-explicit by design and inventorying them dilutes the audit signal.
5. **Meaningful log levels.** Choose the level that reflects the system's actual state: DEBUG for detailed diagnostics, INFO for normal operations and state changes, WARNING for recoverable problems, ERROR for unrecoverable failures where the system has given up.
6. **Log intent and outcome.** Log when the system is about to perform a significant action and again when it completes — logging the outcome at INFO or higher so it is visible in production — because without both intent and outcome it is impossible to distinguish "never attempted" from "attempted and failed silently".

## No PII or credentials at INFO and above

INFO and above is collected by our production logging infrastructure and accessible to a broad set of tooling and staff — PII at these levels creates a data-handling obligation we cannot meet with current tooling. DEBUG is a local development and investigation tool; production deployments run at INFO by default so DEBUG output is not collected in normal operations. Do not enable DEBUG in production without a specific investigation reason.

The PII restriction covers names, addresses, dates of birth, email addresses, phone numbers, and any identifier that could be linked to a natural person (e.g. driving licence number, vehicle registration). Policy IDs and quote IDs are acceptable — they are internal references, not PII.

Credentials — passwords, tokens, and API keys — must never appear in logs at any level. Unlike PII, there is no safe retention window: a leaked credential is immediately actionable by an attacker regardless of how briefly the log is stored.

```
# good
log.info("Quote generated.", {"quote.id": quote_id, "customer.id": customer_id})

# bad — customer name and email appear at INFO level
log.info("Quote generated for <name> (<email>).")
```

```
# good — PII at DEBUG is permitted
log.debug("Validating address.", {"address": raw_address_input, "customer.id": customer_id})
```

## Structured logging

Logging pipelines index on the message string. When the message changes per call — because it contains a policy ID, a count, or any runtime value — the pipeline cannot group related events and search becomes unreliable. A static message paired with structured context fields keeps the message stable and puts the variable data where it can be filtered and aggregated.

```
# good
log.info("Policy renewed.", {"policy.id": policy_id, "term_months": term_months})

# bad — string interpolation embeds variable data in the message
log.info("Policy <policy_id> renewed for <term_months> months.")

# bad — format arguments have the same effect
log.info("Policy %s renewed for %d months.", policy_id, term_months)

# bad — concatenation is equivalent
log.info("Policy " + policy_id + " renewed.")
```

## Zego common keys

Using a shared key vocabulary across services means a Datadog query for `customer.id:12345` returns results from every service that touched that customer, without needing to know each service's local field names. New services should adopt the common keys from the outset rather than introducing synonyms (`customerId`, `cust_id`, etc.) that fragment cross-service queries.

Representative common keys: `customer.id`, `policy.id`, `quote.id`, `product.id`, `claim.id`. The authoritative list is maintained in the project's key inventory (typically the service's logging configuration or a dedicated reference document).

```
# good — uses the shared key name
log.info("Quote rated.", {"quote.id": quote_id, "product.id": product_id})

# bad — local synonym that won't match cross-service queries
log.info("Quote rated.", {"quoteId": quote_id, "productId": product_id})
```

## Document new keys

The common key vocabulary only works if it stays current. When a new context key is introduced — whether it is a new common key or a service-local key — documenting it in the same PR keeps the inventory accurate and gives reviewers a chance to spot synonyms before they are committed.

If the project has no key inventory yet, creating one is part of the PR.

DEBUG-only diagnostic keys do not need to be documented in the key inventory. They are PII-explicit by design (only used locally or in targeted investigations, not in normal production output), and including them would dilute the inventory's value as a PII-audit surface.

## Meaningful log levels

The level tells the reader how much to care. Using the wrong level — logging recoverable warnings as ERROR, or logging normal state changes as DEBUG — trains readers to ignore the signals and defeats alerting.

| Level | Use when |
|-------|----------|
| `DEBUG` | Detailed diagnostics useful during development or investigation — not wanted in normal production output. |
| `INFO` | The system is doing what it should: a request completed, a record was written, a job finished. |
| `WARNING` | Something unexpected happened but the system recovered or degraded gracefully — worth knowing, not yet broken. |
| `ERROR` | The system has given up on an operation; manual intervention or an alert response may be needed. |

```
# good
log.info("Payment processed.", {"policy.id": policy_id, "amount_pence": amount})
log.warning("Payment gateway timeout; retrying.", {"attempt": attempt, "policy.id": policy_id})
log.error("Payment failed after max retries.", {"policy.id": policy_id, "attempts": max_attempts})

# bad — ERROR for a condition the system handled
log.error("Retrying payment.", {"attempt": attempt})
```

## Log intent and outcome

Logging only the outcome makes it impossible to distinguish "never attempted" from "attempted and failed silently". Logging intent and outcome together gives a complete picture of what the system tried to do and what happened, which is the minimum needed to reconstruct an incident.

Log the intent at DEBUG if the action is frequent and low-stakes; log it at INFO if it represents a meaningful state change. Always log the outcome — success or failure — at INFO or higher so it is visible in production.

```
# good
log.debug("Sending renewal notice.", {"policy.id": policy_id})
# ... attempt to send renewal notice ...
log.info("Renewal notice sent.", {"policy.id": policy_id})
# ... on failure ...
log.error("Failed to send renewal notice.", {"policy.id": policy_id, "error_type": error_type})

# bad — outcome only; no way to tell if the send was attempted
# ... attempt to send renewal notice ...
# ... on failure: do nothing (silent failure) ...
```

## See Also

- [observability.md](observability.md) — metrics and distributed tracing conventions, including span attributes and the shared key vocabulary.
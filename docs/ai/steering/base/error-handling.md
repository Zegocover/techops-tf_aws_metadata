---
version: 1.2
last_reviewed: 2026-06-02
---

# Error Handling Standards

Error handling conventions — the governing philosophy is: distinguish failures specifically; reserve broad/catch-all handling for application boundaries where it logs and wraps — never silently swallow. Apply these rules to any codebase when writing or modifying error-handling logic. Log-level selection for error scenarios is covered in [logging.md](logging.md); testing failure paths is covered in [testing.md](testing.md).

## Applicability across error idioms

The rules and examples below are written in **exception** vocabulary (raise / catch / exception hierarchy), which maps directly to Python, Kotlin/Java, and TypeScript. The underlying principles are idiom-independent — translate them to the language's native error model:

- **Exception-based** (Python, Kotlin, Java, TypeScript, Scala's `try`/`catch`) — apply the rules as written.
- **Typed-result idioms** (Rust/Swift `Result`/`Option`, Scala `Either`/`Try`, Go's `(value, error)` returns): "custom domain exceptions" → distinct error types/variants in the result; "catch specific" → match the specific error case, not a catch-all `_`; "broad catch at boundaries only" → propagate errors up via the result type and convert to a response only at the boundary; "never silently swallow" → never discard an error value (`_ = err`, ignoring `Result`, empty `catch`).
- **Declarative models** (LookML) — no imperative error handling; not applicable.

Wherever the text says "exception", read "error" for typed-result idioms; the four rules hold in both worlds.

## Rules at a Glance

1. **Custom domain exceptions.** Define exception types that describe what went wrong in domain terms rather than raising generic exceptions — domain-specific types give callers enough context to decide how to handle the failure without inspecting message strings.
2. **Catch specific exceptions.** Catch the narrowest exception type that matches the expected failure — broad catches hide bugs by intercepting errors the author did not anticipate and silently treating them as expected.
3. **Broad catches only at application boundaries.** Reserve `catch Exception` (or the language equivalent) for top-level entry points — API handlers, background-task runners, CLI commands — where the only correct action is to log the error with full context, return a safe response, and prevent the process from crashing.
4. **Never silently swallow exceptions.** Every catch block must either re-raise, wrap-and-raise, or log at WARNING or above with enough context to diagnose the original failure — a silent catch is worse than no catch because it converts a visible crash into an invisible data-corruption or logic-skip bug. Log-and-continue (without re-raising) is only acceptable when the caller explicitly tolerates degraded behaviour — e.g. a cache miss falling back to a direct lookup — never as a general-purpose error suppression pattern.

## Custom domain exceptions

Generic exception types force callers to parse message strings to distinguish one failure from another. A domain exception type carries the failure's meaning in its name — callers can catch it specifically, monitoring can alert on it by type, and test assertions are precise.

Define a small hierarchy rooted in a single base exception for the service or bounded context. Each leaf type maps to one failure reason. Carry structured context (IDs, amounts, states) as fields on the exception rather than interpolating them into the message string, so downstream handlers can access the data programmatically.

```
# good — caller can catch the specific failure and access context fields
class PolicyNotFoundError extends ServiceBaseError:
    policy_id: string

raise PolicyNotFoundError(policy_id="POL-123")

# bad — caller must parse a string to know what went wrong
raise Exception("Policy POL-123 not found")
```

```
# good — structured hierarchy, each leaf has a clear domain meaning
class PaymentError extends ServiceBaseError
class PaymentDeclinedError extends PaymentError:
    reason_code: string
class PaymentTimeoutError extends PaymentError:
    gateway: string
    elapsed_ms: int

# bad — flat generic exceptions distinguished only by message
raise Exception("payment declined")
raise Exception("payment timed out")
```

## Catch specific exceptions

A catch block that matches a broad type intercepts every exception that inherits from it — including bugs the author never considered. When a key-lookup error from a typo is caught by a `catch Exception` intended for network failures, the typo becomes invisible and the system proceeds with wrong data.

Catch the narrowest type that matches the failure you expect. If two distinct failures need different handling, write two catch blocks.

```
# good — each failure type gets the handler it needs
try:
    response = gateway.charge(amount)
catch PaymentDeclinedError as err:
    log.warning("Payment declined.", {"reason": err.reason_code})
    return decline_response(err.reason_code)
catch PaymentTimeoutError as err:
    log.warning("Payment gateway timeout.", {"gateway": err.gateway})
    schedule_retry(charge_id)

# bad — broad catch treats declines and timeouts identically, hides unexpected errors
try:
    response = gateway.charge(amount)
catch Exception as err:
    log.warning("Payment failed.", {"error": str(err)})
    return generic_failure_response()
```

## Broad catches only at application boundaries

Application boundaries are the outermost execution points: HTTP request handlers, message-queue consumers, background-task entry points, CLI commands. At these points, an unhandled exception would crash the process or return an opaque 500 to the caller. A broad catch here is a safety net — it logs the unexpected error with full diagnostic context and returns a safe, generic response.

Anywhere below the boundary, a broad catch is harmful: it intercepts errors that should propagate to a handler that knows how to deal with them. The boundary catch should log at ERROR with the exception type, message, and stack trace, then reference [logging.md](logging.md) for level guidance and structured-logging conventions.

```
# good — boundary handler catches everything, logs with full context, returns safe response
function handle_request(request):
    try:
        return process(request)
    catch Exception as err:
        log.error("Unhandled error in request handler.", {"error_type": type(err), "error": str(err), "trace": stacktrace(err)})
        return error_response(status=500, body="Internal server error")

# bad — broad catch buried inside domain logic, hiding bugs from the boundary
function calculate_premium(policy):
    try:
        rate = fetch_rate(policy.product)
        return rate * policy.value
    catch Exception:
        return DEFAULT_PREMIUM
```

## Never silently swallow exceptions

A silent catch — one that catches an exception and does nothing, or catches and continues without logging — is the most dangerous error-handling pattern. It converts a visible failure into invisible data corruption or skipped logic. The system reports success while operating on wrong assumptions.

Every catch block must do at least one of: re-raise the exception, wrap it in a domain exception and raise that, or log at WARNING or above with enough context (exception type, message, relevant IDs) for someone to diagnose the original failure from logs alone. "Enough context" means the log entry answers: what operation failed, why, and which entities were involved.

```
# good — catch, log, re-raise
try:
    send_notification(customer_id, message)
catch NotificationError as err:
    log.error("Failed to send notification.", {"customer.id": customer_id, "error_type": type(err), "error": str(err)})
    raise

# good — catch, log at WARNING, continue with degraded behaviour (only when the caller explicitly tolerates the degradation)
try:
    cached_rate = cache.get(rate_key)
catch CacheUnavailableError as err:
    log.warning("Cache unavailable, falling back to direct lookup.", {"rate_key": rate_key, "error": str(err)})
    cached_rate = None

# bad — silent swallow; notification silently never sent, caller assumes success
try:
    send_notification(customer_id, message)
catch NotificationError:
    do nothing
```

## Red Flags — Stop and Reconsider

If any of these thoughts cross your mind, stop — you are about to rationalise away a rule.

- "I'm not sure exactly which exception this raises, so I'll catch `Exception` to be safe."
- "Catching broadly here makes the code more robust against anything going wrong."
- "This error is non-critical, so I'll just swallow it and let the flow continue."
- "I'll add an empty catch for now and come back to handle it properly later."
- "I'll log it at DEBUG and move on so the happy path isn't interrupted."

| Rationalisation | Rule it violates | Real-world consequence |
|---|---|---|
| "I'm not sure exactly which exception this raises, so I'll catch `Exception` to be safe." | Rule 2 — Catch specific exceptions | The broad catch also intercepts bugs the author never anticipated — a typo or programming error is treated as an expected failure and the system proceeds on wrong data. |
| "Catching broadly here makes the code more robust against anything going wrong." | Rule 2 — Catch specific exceptions | "Robust" becomes "silently wrong": unexpected errors are masked rather than propagated to a handler that knows how to deal with them. |
| "This error is non-critical, so I'll just swallow it and let the flow continue." | Rule 4 — Never silently swallow exceptions | A visible failure becomes an invisible logic-skip or data-corruption bug; the system reports success while operating on wrong assumptions. |
| "I'll add an empty catch for now and come back to handle it properly later." | Rule 4 — Never silently swallow exceptions | The empty catch ships and is never revisited, permanently hiding the failure from logs and monitoring. |
| "I'll log it at DEBUG and move on so the happy path isn't interrupted." | Rule 4 — Never silently swallow exceptions | A DEBUG line in production is effectively silent; the failure never appears at WARNING or above, so no one can diagnose it from logs. |

## See Also

- [logging.md](logging.md) — log-level selection for error scenarios and structured-logging conventions for context fields.
- [testing.md](testing.md) — testing failure paths explicitly (Rule 8) to verify error handling works as intended.

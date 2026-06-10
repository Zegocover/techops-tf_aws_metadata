---
version: 1.0
last_reviewed: 2026-05-12
---

# Resilience Standards

Conventions for retry logic, backoff, timeouts, and idempotency across inter-service communication — the governing philosophy is: fail fast on deterministic errors; retry only transient failures with bounded backoff, jitter, and timeouts. Apply these rules to any service that makes calls to external dependencies (HTTP, gRPC, message queues), regardless of language. Circuit breaker selection and configuration are implementation-specific and not covered here. Observability of retries and timeouts is covered in observability.md.

## Rules at a Glance

1. **Retry only transient failures.** Retry HTTP 429, 502, 503, and 504 and gRPC UNAVAILABLE, DEADLINE_EXCEEDED, and RESOURCE_EXHAUSTED — never retry other 4xx HTTP codes or deterministic gRPC errors (INVALID_ARGUMENT, NOT_FOUND, PERMISSION_DENIED, ALREADY_EXISTS) because they will fail identically on every attempt, wasting time and load.
2. **Exponential backoff with jitter.** Use exponential backoff with full jitter (randomised delay between 0 and the exponential cap) on every retry — fixed-interval or exponential-without-jitter retries cause thundering herds when many clients back off in lockstep after a shared dependency recovers.
3. **Maximum retry count.** Set a maximum retry count (typically 3 to 5 attempts including the original request) on every retryable call — unbounded retries turn a transient failure into a sustained load spike that prevents the dependency from recovering.
4. **Explicit timeouts on all external calls.** Set an explicit timeout on every outbound HTTP request, gRPC call, and database query — a missing timeout means a hung dependency silently blocks the caller indefinitely, exhausting connection pools and cascading the failure upstream.
5. **Idempotency keys for retry safety.** Attach a unique idempotency key (or deduplication identifier) to any mutating operation that may be retried — without one, a retried write can create duplicate records or apply an effect twice, because the caller cannot distinguish "request failed before processing" from "request succeeded but the response was lost".

## Retry only transient failures

A transient failure is one where the same request, sent again after a short delay, has a reasonable chance of succeeding — the server was temporarily overloaded, a network blip occurred, or a rate limit was hit. A deterministic failure — bad input, missing resource, insufficient permissions — will produce the same error on every attempt. Retrying deterministic failures wastes the caller's time and adds unnecessary load to a dependency that is correctly rejecting the request.

The distinction matters most during incidents: if a downstream service is returning 400 for a schema change, retrying floods it with duplicate bad requests and obscures the real error in logs. Fail fast on deterministic errors so the caller can surface the real problem immediately.

```
# good — retries only transient status codes
TRANSIENT_HTTP_CODES = {429, 502, 503, 504}

function call_with_retry(request, max_attempts=3):
    for attempt in 1..max_attempts:
        response = http_client.send(request, timeout=5s)
        if response.status not in TRANSIENT_HTTP_CODES:
            return response
        if attempt < max_attempts:
            sleep(backoff_with_jitter(attempt))
    raise MaxRetriesExceeded(attempts=max_attempts)

# bad — retries all non-200 responses, including deterministic errors
function call_with_retry(request, max_attempts=3):
    for attempt in 1..max_attempts:
        response = http_client.send(request, timeout=5s)
        if response.status != 200:
            sleep(1s)
            continue
        return response
```

For gRPC, the same principle applies: retry UNAVAILABLE (server not accepting requests), DEADLINE_EXCEEDED (upstream timed out), and RESOURCE_EXHAUSTED (rate-limited or quota exceeded). Do not retry INVALID_ARGUMENT, NOT_FOUND, PERMISSION_DENIED, ALREADY_EXISTS, UNIMPLEMENTED, or any other status that indicates a permanent condition.

For message queues, retry semantics are typically managed by the broker (NACK/redelivery, dead-letter queues) rather than application-level retry loops. The principles still apply — only retry transient failures, set a maximum delivery count, and use idempotency keys on the consumer side — but the implementation mechanism differs. Queue-specific retry configuration (redelivery policies, DLQ routing) is outside the scope of this standard.

## Exponential backoff with jitter

Exponential backoff increases the delay between retries — typically doubling each time (e.g. 1s, 2s, 4s). This gives the failing dependency progressively more time to recover. However, if many clients all use the same deterministic delay schedule, they will retry in sync, creating periodic load spikes (thundering herd) that can prevent recovery.

Full jitter solves this by randomising the delay between 0 and the exponential cap on each attempt. This spreads retries evenly across the backoff window, reducing the peak retry load at any given moment.

```
# good — exponential backoff with full jitter
function backoff_with_jitter(attempt, base_delay=1s, max_delay=30s):
    exponential_cap = min(base_delay * 2^(attempt - 1), max_delay)
    return random_between(0, exponential_cap)

# bad — fixed interval; all clients retry at the same time
function backoff(attempt):
    return 1s

# bad — exponential without jitter; clients still synchronise
function backoff(attempt):
    return min(1s * 2^(attempt - 1), 30s)
```

## Maximum retry count

Every retry loop must have a hard upper bound. Without one, a dependency that returns a retryable error indefinitely (e.g. a 503 during a prolonged outage) causes the caller to loop until its own timeout or resource limit is hit — by which point it has sent dozens of requests that only add load to the struggling dependency.

A typical maximum is 3 to 5 total attempts (including the original request). The right number depends on the use case: a user-facing API call should fail quickly (2-3 attempts); a background job that can tolerate latency might use more (up to 5). The maximum must always be explicit in code, never implicit via an unbounded loop.

```
# good — explicit maximum, clear termination
function send_with_retry(request, max_attempts=3):
    for attempt in 1..max_attempts:
        response = http_client.send(request, timeout=5s)
        if response.status not in TRANSIENT_HTTP_CODES:
            return response
        if attempt < max_attempts:
            sleep(backoff_with_jitter(attempt))
    raise MaxRetriesExceeded(attempts=max_attempts)

# bad — no upper bound; loops until something else kills the process
function send_with_retry(request):
    while true:
        response = http_client.send(request)
        if is_retryable(response):
            sleep(backoff_with_jitter(attempt))
            continue
        return response
```

## Explicit timeouts on all external calls

A timeout defines the maximum time the caller will wait for a response. Without one, the default is often "wait forever" — which means a single hung connection can block a thread, exhaust a connection pool, and cascade the failure to every upstream caller.

Set timeouts at the point of the call, not only at the infrastructure level (e.g. load balancer timeout). Infrastructure timeouts are a safety net, not a substitute — they are typically set higher than the application needs and may not exist for all call types (database queries, gRPC streams, message publish calls).

Most HTTP and gRPC clients distinguish a connect timeout (time to establish a connection — catches unreachable hosts) from a read/response timeout (time to receive data after connecting — catches hung requests mid-flight). Set both explicitly; they serve different purposes and have different safe defaults. A low connect timeout (1 to 3 seconds) fails fast when a host is down, while the read timeout should match the expected response latency of the dependency.

Choose timeout values based on the expected latency of the dependency under normal load, plus a reasonable margin. A call that normally completes in 200ms should not have a 60s timeout — that is effectively no timeout at all for the purpose of cascading-failure prevention.

```
# good — explicit timeout on every external call
response = http_client.get("https://api.provider.com/rates",
    timeout=5s)

grpc_response = grpc_client.get_quote(request,
    timeout=3s)

rows = db.execute("SELECT ...",
    timeout=2s)

# bad — no timeout; caller blocks until the dependency responds or the connection dies
response = http_client.get("https://api.provider.com/rates")

# bad — timeout so high it provides no protection against cascading failure
response = http_client.get("https://api.provider.com/rates",
    timeout=300s)
```

## Idempotency keys for retry safety

When a mutating request (POST, PUT, or a gRPC method that creates or modifies state) is retried, the caller does not know whether the original request was processed before the failure occurred. If the server processed the request but the response was lost (network timeout, connection reset), a retry without an idempotency key will apply the effect twice — creating a duplicate record, charging a payment twice, or sending a notification again.

An idempotency key is a unique identifier for the operation, generated by the caller and sent with every attempt. The server uses it to detect duplicate requests: if it has already processed a request with that key, it returns the stored result instead of re-executing the operation. This makes retries safe regardless of where in the request lifecycle the failure occurred.

Generate the key once per logical operation, not per attempt. Typically this is a UUID or a deterministic hash of the operation's inputs. Pass it as a header (e.g. `Idempotency-Key`) or a field in the request body, depending on the API's convention.

```
# good — idempotency key generated once, sent on every attempt
function create_payment_with_retry(payment, max_attempts=3):
    idempotency_key = generate_uuid()
    for attempt in 1..max_attempts:
        response = http_client.post("/payments",
            body=payment,
            headers={"Idempotency-Key": idempotency_key},
            timeout=5s)
        if response.status not in TRANSIENT_HTTP_CODES:
            return response
        if attempt < max_attempts:
            sleep(backoff_with_jitter(attempt))
    raise MaxRetriesExceeded(attempts=max_attempts)

# bad — no idempotency key; retry may create duplicate payment
function create_payment_with_retry(payment, max_attempts=3):
    for attempt in 1..max_attempts:
        response = http_client.post("/payments",
            body=payment,
            timeout=5s)
        if response.status not in TRANSIENT_HTTP_CODES:
            return response
        if attempt < max_attempts:
            sleep(backoff_with_jitter(attempt))
    raise MaxRetriesExceeded(attempts=max_attempts)
```

For event-driven systems, the deduplication key serves the same purpose: a unique identifier attached to each message that allows the consumer to detect and skip duplicates. Generate the key at the producer and include it in the message payload.

## See Also

- [observability.md](observability.md) — metrics and tracing conventions for instrumenting retries, timeouts, and failure rates.
- [logging.md](logging.md) — logging conventions for recording retry attempts, timeout events, and failure outcomes.

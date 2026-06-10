---
version: 1.2
last_reviewed: 2026-06-02
---

# Observability Standards

Conventions for metrics and distributed tracing — observability exists so that when something goes wrong, someone who knows the domain but not the code can understand what happened, why, and how everything fits together; the same intent as logging, extended to all three signals (metrics: is there a problem? traces: where? logs: what?). Logging conventions, including log formatting and routing enforced by the Zego standard logging library, are not covered here. Logging rules belong in logging.md.

## The universal principle

One rule applies to **every** runtime, regardless of stack: instrument the code so that an incident is diagnosable from telemetry alone, across the three signals appropriate to that runtime — is there a problem (metrics), where (traces/spans), and what happened (logs/events). Use shared business identifiers (e.g. `policy.id`, `quote.id`, `customer.id`) consistently across whatever signals the platform emits, and never put PII in indexed telemetry. How those signals are produced and where they are sent is platform-specific.

## Applicability

The concrete rules below act on one specific surface: **server-side metric and distributed-trace instrumentation emitted through OpenTelemetry to Datadog** (the surface present in HTTP/gRPC services, async consumers and producers, and scheduled jobs running in the cluster). Apply them wherever that surface exists in the code.

Where the surface is absent — the code emits no server-side metrics or traces, or runs on a platform with its own telemetry model — these rules have nothing to act on. Apply only the universal principle above and stop.

**Gate by the surface, not by the repo's language or framework.** Do not infer from a repo's stack that it *should* adopt OTel/Datadog server instrumentation, and do not raise findings for its absence. (Runtimes that commonly lack this surface include mobile apps, browser frontends, BI/declarative models, and libraries — but these are illustrations, not the test. The test is whether the instrumentation surface is present.)

## Rules at a Glance

1. **Three-signal coverage.** Instrument all three signals — metrics, traces, and logs — because each answers a distinct diagnostic question; omitting one leaves a blind spot that forces guesswork during an incident.
2. **OpenTelemetry as the instrumentation library.** Use OpenTelemetry for all metrics and tracing instrumentation — it is vendor-agnostic, prevents lock-in, and targets Datadog as the current backend for both metrics and APM.
3. **Framework instrumentors before custom code.** Use framework instrumentors (HTTP server middleware, HTTP client instrumentors, gRPC interceptors) before writing custom spans or metrics — they cover the common cases without maintenance burden (e.g., FastAPI middleware in Python, Spring Boot auto-configuration in Java, otelgin/otelhttp in Go).
4. **Register instrumentors explicitly at startup.** Register all instrumentors in service startup code rather than relying on auto-discovery — auto-discovery is non-deterministic and can behave inconsistently across package managers and build tools (e.g., uv in Python, Gradle shadow-jar in Java).
5. **Outside-in instrumentation strategy.** Instrument service boundaries first (HTTP/gRPC servers and clients, async consumers and producers), then add internal spans only when boundary data is insufficient to diagnose a specific problem — starting inside out produces noise without covering the gaps that actually matter.
6. **Counter, Histogram, UpDownCounter.** Choose the metric instrument that matches the measurement: Counter for cumulative counts (throughput, error rates), Histogram for latency distributions, UpDownCounter for current state (queue depth, active sessions) — using the wrong instrument produces misleading aggregations in Datadog.
7. **OTel semantic conventions for metric naming.** Name metrics using lowercase dot-delimited namespaces with snake_case within components; prefix Zego-specific metrics with `zego.{service}` where `{service}` is the canonical service name (hyphens are permitted where the service name itself contains them); include explicit client/server direction (e.g. `http.client.request.duration` vs `http.server.request.duration`); omit unit suffixes from the name — they belong in metadata.
8. **Standard instrument suffixes.** Use `.limit` for a known total, `.usage` for amount used, `.utilization` for a fraction (0.0–1.0), `.time` for passage of time, `.io` for bidirectional data flow — consistent suffixes make metric families queryable without per-metric documentation.
9. **UCUM units in metadata.** Express units using UCUM: `s` for seconds, `By` for bytes, `1` for dimensionless ratios, `{thing}` for item counts — record them as instrument metadata, not in the metric name.
10. **Low cardinality on metric attributes.** Never use UUIDs, unbounded identifiers, or user-supplied values as metric attribute values — high cardinality explodes the metric series count in Datadog; reserve high-cardinality identifiers for trace attributes.
11. **Auto-instrumentation for spans first.** Use auto-instrumentation (HTTP, database, AWS SDK) before adding manual spans — manual spans are for significant gaps that auto-instrumentation cannot cover.
12. **Correct span kind when instrumenting manually.** Set span kind to SERVER for incoming requests, CLIENT for outgoing calls, and INTERNAL for local computation — the kind determines how Datadog APM renders the call graph.
13. **Business identifiers on span attributes.** Attach business identifiers (policy.id, quote.id, customer.id) to span attributes using the same key names as logs — this makes traces and logs joinable in Datadog without field-name mapping.
14. **No PII on span attributes.** Never include PII (names, addresses, dates of birth, email addresses, phone numbers, vehicle registrations, driving licence numbers) in span attributes — span data is retained and indexed in Datadog under the same data-handling obligations as logs at INFO.
15. **No span events.** Do not use span events — they are being deprecated in OpenTelemetry; record point-in-time details as log lines with span and trace ID metadata instead.
16. **Span links for async processing.** When consuming a message (Kinesis, SQS), start a new root span and attach the producer's trace context as a span link — async processing is a causal relationship, not a synchronous parent-child, and a child span would distort latency metrics for the producer.

## Three-signal coverage

Metrics answer "is there a problem?" — they are cheap to collect and power alerting. Traces answer "where?" — they show which service and code path is slow or failing. Logs answer "what?" — they carry the event detail needed to understand root cause. All three are required because each covers a gap the others cannot fill: metrics without traces tell you something is wrong but not where; traces without logs tell you where but not what happened; logs without metrics cannot trigger alerts.

## OpenTelemetry as the instrumentation library

OpenTelemetry is the CNCF-standard instrumentation framework. Instrumenting against the OTel API means the backend (currently Datadog for both metrics and APM) can be changed by reconfiguring the exporter without touching instrumentation code. Instrumenting directly against a vendor SDK creates a migration cost proportional to the size of the codebase.

## Framework instrumentors before custom code

Framework instrumentors for HTTP servers, HTTP clients, and gRPC cover the most common instrumentation points (request duration, error rates, downstream call latency) without requiring manual span management. Writing custom spans for cases already covered by an instrumentor duplicates work and drifts out of sync with framework updates. In Python, these are the FastAPI, HTTPX, and gRPC instrumentors; in Java, Spring Boot auto-configuration and OkHttp interceptors; in Go, otelgin/otelhttp and otelgrpc. See language-specific standards for implementation details.

## Register instrumentors explicitly at startup

Auto-discovery mechanisms (e.g., `opentelemetry-instrument` in Python, the Java agent in Java) work by scanning installed packages or classpath entries at process start. Depending on the package manager or build tool, the scan can produce different results across runs or fail silently (e.g., uv in Python can resolve packages non-deterministically; fat-jar packaging in Java can shade out instrumentors). Explicit registration in the service startup code is deterministic and reviewable.

## Outside-in instrumentation strategy

Boundaries are where failures actually appear to users: a slow downstream call, a rejected request, a dropped message. Starting at the boundary guarantees coverage of the highest-value diagnostic surface. Adding internal spans is a targeted decision driven by a specific gap — "the boundary shows the call is slow but we cannot tell which internal step is responsible" — not a default.

## Counter, Histogram, UpDownCounter

Using a Counter for queue depth produces a number that only ever increases and cannot represent the current state. Using a Histogram for a dimensionless count produces meaningless percentile distributions. Each instrument has an aggregation model that only makes sense for the measurement it is designed for.

| Instrument | Use for |
|---|---|
| `Counter` | Counts that only go up: requests handled, errors raised, records written. |
| `Histogram` | Values you want to aggregate as distributions: request duration, payload size. |
| `UpDownCounter` | Values that go up and down: active connections, queue depth, in-flight jobs. |

## OTel semantic conventions for metric naming

Consistent naming makes metrics queryable across services without per-service documentation. The OTel semantic conventions define the namespace structure; the `zego.{service}` prefix scopes Zego-specific metrics so they do not collide with upstream OTel conventions as they are added. Explicit direction (`client` vs `server`) distinguishes a call you made from a call made to you, which have different SLO owners.

```
# good
histogram "http.server.request.duration"
    unit: "s"
    description: "Duration of HTTP requests handled by this server."

histogram "zego.quote-service.rating.duration"
    unit: "s"
    description: "Duration of quote rating operations."

# bad — unit in the name, no direction, PascalCase namespace
histogram "RequestDurationMs"

# bad — no service prefix on a Zego-specific metric
histogram "rating.duration"
```

## Low cardinality on metric attributes

Datadog indexes every unique combination of attribute values as a separate metric series. A single metric with a UUID attribute produces as many series as there are UUIDs — this exhausts metric quotas, degrades query performance, and incurs cost proportional to throughput. Attributes on metrics must come from a bounded set: HTTP method, status code, environment, service name, region.

High-cardinality identifiers (policy IDs, quote IDs, customer IDs) belong on trace and log data, where they are stored as indexed fields rather than as dimension keys in a time-series database.

```
# good — bounded attribute values
http_requests.add(1, {"method": request.method, "status_code": response.status_code})

# bad — UUID creates unbounded cardinality
http_requests.add(1, {"method": request.method, "request_id": request_id})
```

## Business identifiers on span attributes

Joining traces to logs requires shared key names. Using `policy.id` in both a span attribute and a log context field (e.g. Python's `extra` dict) means a Datadog APM trace can pivot directly to the related log lines without a separate mapping step. Use the same key vocabulary defined in logging.md.

```
# good — shared key names, no PII
span.set_attributes({
    "policy.id": policy_id,
    "quote.id": quote_id,
    "customer.id": customer_id,
})

# bad — PII in span attributes
span.set_attributes({
    "customer.email": customer.email,
    "customer.name": customer.full_name,
})

# bad — local synonyms that won't join to log queries
span.set_attributes({
    "policyId": policy_id,
    "quoteRef": quote_id,
})
```

## No span events

OpenTelemetry is deprecating span events in favour of log records with span context (trace ID and span ID as metadata fields). Span events written today will require migration. Log records with span context are already the standard in our logging setup and integrate naturally with Datadog Log Management.

## Span links for async processing

When a Kinesis or SQS consumer handles a message, the processing happens in a separate process, often minutes or hours after the producer emitted the event. Making the consumer span a child of the producer span would inflate the producer's measured duration to include all downstream processing time, distorting latency metrics and SLO calculations. A span link preserves the causal relationship — "this processing was triggered by that event" — without affecting either trace's duration metrics.

```
# good — new root span with a link to the producer context
producer_context = propagator.extract(message.attributes)
link = create_link(producer_context)
span = tracer.start_span("process_message", kind: CONSUMER, links: [link])
handle(message)

# bad — consumer is a child of the producer, inflating producer latency
producer_context = propagator.extract(message.attributes)
span = tracer.start_span("process_message", kind: CONSUMER, parent: producer_context)
handle(message)
```

## See Also

- [logging.md](logging.md) — logging conventions: levels, structured log calls, PII rules, and Zego common keys.

---
version: 1.0
last_reviewed: 2026-06-12
---

# Protobuf Authoring Standards

Conventions for authoring and evolving `.proto` contracts in the `Zegocover/protobuf` repository — a `.proto` is a consumer-facing contract, so the governing principle is to describe what a field, message, or RPC *is and means to the consumer*, never how the producer makes it, and to never break the wire for an existing consumer. Apply these rules whenever you write or modify a `.proto` file, and when validating a proto change before opening a PR. Conversions between proto messages and native (Python) types in service code are owned by `docs/ai/steering/domains/protobuf-converters.md`; Python language conventions are owned by `docs/ai/steering/languages/python.md`.

## Applicability

The rules below divide into two activities with the same trigger (a `.proto` change) but different scope:

- **Contract-authoring rules (Rules 1–9)** apply to the content of any `.proto` file you write or modify — message and field design, common-type reuse, comments, optionality, field numbering, and the success/failure response model.
- **Validation-workflow rules (Rules 10–12)** apply to the local toolchain you run before committing a proto change. They assume the `buf`-based workflow of the `Zegocover/protobuf` repository; they do not bind in a consumer repo that merely depends on generated stubs.

## Rules at a Glance

1. **No cross-service message imports.** A service's `.proto` must not import another service's message type; define your own copy — with its full nested message and enum tree — under your service's `protobuf/.../v1/` and reference it fully-qualified. Importing another team's message couples your contract to theirs, so their internal refactor silently breaks your API. Shared `zego.protobuf` common types are the deliberate exception — see **Reuse shared common types**.
2. **Reuse shared common types.** Import and reuse the cross-cutting value types from the shared `zego.protobuf` common package (`Money`, `FixedDecimal`, `Date`, `Url`, `UUID`, and any others the package adds over time) rather than redefining a local equivalent — they are shared vocabulary owned by no single service, so reimplementing one forks the concept away from the package's documented invariants and the central converter support that goes with it. Treat the package as the authority for the current set; do not assume the examples here are exhaustive.
3. **Contract-level comments only.** Comment what a field, message, or RPC *is and means to the consumer*; never how the producer generates it, how it is routed across services, or which internal ticket prompted it. For an RPC, describe what it does for the caller, not its internal or downstream mechanics — implementation detail in a contract comment misleads every consumer and rots the moment the implementation changes.
4. **Don't duplicate the source of truth.** When one field already carries a fact, do not restate that fact in adjacent field or enum-value comments — e.g. when a dedicated `retryable` bool exists, do not tag each error-code enum value "deterministic — not retryable". The enum names the cause or category; the dedicated field carries retryability; duplicated facts drift out of sync.
5. **Don't accept inputs the service owns or ignores.** Audit every request field: drop any the service derives itself, and any that nothing reads (trace the code to confirm). Keep a field only if it is genuinely consumed, or if it expresses caller intent the service validates against its own discovered truth — document that intent. Owned or dead inputs invite callers to set them and create a contradiction the service must silently resolve.
6. **Optionality reflects domain reality.** Mark a field `optional` when it can legitimately be absent at the time the message is produced; do not force-require it just because a legacy sibling message did. Check the canonical/downstream model and the producing code — a wrongly-required field forces producers to invent meaningless placeholder values.
7. **Natural field numbering.** Order fields by a natural top-to-bottom read of the entity — identity → what it relates to → who → product → coverage → money — keeping related fields adjacent (`policy_id`/`policy_number`, `quote_id`/`quote_type`), not in whatever order they happened to be added. For a new, never-published message, renumber freely to achieve this; for a published message, NEVER renumber or reuse a field number — wire compatibility — so add new fields at the next free number instead.
8. **Explicit success/failure result for new endpoints.** Model a new endpoint's response as `oneof result { <Op>SuccessResponse success = 1; <Op>FailureResponse failure = 2; }`, where failure carries a message plus an `<Op>ErrorCode` enum (`..._UNSPECIFIED = 0`) and an `optional bool retryable`. A "nothing-to-do"/not-applicable outcome is a *success* variant (an explicit marker message in a nested `oneof outcome`), not a failure. Prefer an explicit `oneof` arm over an optional field wherever misreading "absent" as a default-constructed value would be dangerous (e.g. an empty financial document). Where the model is already documented elsewhere, cross-reference rather than duplicate.
9. **Verify the real shape.** Confirm any embedded or returned type against the code that produces it AND the canonical proto in `Zegocover/protobuf` — never against a local partial pydantic projection, which may omit or rename fields. A contract built from a partial local view ships fields that do not match what the producer actually emits.
10. **Validate breaking changes against `origin/main`.** Run `buf breaking --against '.git#ref=origin/main'` after `git fetch` — never against `'.git#branch=main'`, whose local `main` ref is often behind origin and flags upstream refactors in files you never touched as false positives. CI compares against current `main` and is authoritative.
11. **Don't `buf format -w` a touched file unless format is a CI gate.** Existing protos are often unformatted and formatting is not CI-enforced, so `buf format -w` reformats the entire pre-existing file and buries your change in noise. Add new imports and content consistent with the file's existing (even non-alphabetical) order and keep the diff minimal.
12. **Validate locally before committing.** Run the repo's documented wrappers — `make` (lint + breaking-compatibility check; add `make build` for gRPC service changes, which also compiles the libraries) — and additionally `buf breaking --against '.git#ref=origin/main'` after `git fetch`, because `make`'s own breaking check compares against *local* `main` (the **Validate breaking changes against `origin/main`** footgun) and reports false positives. Work in a fresh worktree off the latest `origin/main`, commit with the protobuf repo's convention (`JIRA-ID: lowercase description`, no `(type)` prefix), and open the PR as a draft. Skipping local validation pushes failures into CI and wastes a round-trip.

## No cross-service message imports

A service's API is its own contract. When your `.proto` needs a type that conceptually originates in another service, copy the type — its full nested message and enum tree — into your own `protobuf/.../v1/` package and reference it fully-qualified, rather than importing the other service's definition. An import binds your wire contract to another team's release cadence: when they renumber, rename, or restructure their message for their own reasons, your generated stubs and every downstream consumer break, even though you never touched your contract.

This rule is about another *service's* domain message. The shared `zego.protobuf` common types (`Money`, `Date`, `UUID`, …) are not owned by any service — they are shared vocabulary you should import, not copy (see **Reuse shared common types**).

```proto
// good — the amount uses the shared common type; the Orders concept this entry
// references is copied into our own package with its full enum tree
package zego.protobuf.financeservices.ledgermanagement.v1;

import "zego/protobuf/money.proto";  // shared common type — import, never copy

// A single posting in a customer's billing ledger.
message LedgerEntry {
  // The monetary value of this posting.
  zego.protobuf.Money amount = 1;
  // The order this posting was raised against.
  OrderSummary order = 2;
}

// The subset of an order this service needs — our own copy of the Orders concept.
message OrderSummary {
  // Identifier of the order in the Orders service.
  string order_id = 1;
  // Lifecycle state of the order.
  OrderStatus status = 2;
}

// Lifecycle state of an order, as this service understands it.
enum OrderStatus {
  // The state is unknown.
  ORDER_STATUS_UNSPECIFIED = 0;
  // The order has been fully settled.
  ORDER_STATUS_SETTLED = 1;
}

// bad — importing the Orders service's own message couples this contract to theirs
import "zego/protobuf/financeservices/orders/v1/order_summary.proto";

// A single posting in a customer's billing ledger.
message LedgerEntry {
  // The order this posting was raised against.
  zego.protobuf.financeservices.orders.v1.OrderSummary order = 1;
}
```

## Reuse shared common types

The `zego.protobuf` common package (the files directly under `proto/zego/protobuf/` in `Zegocover/protobuf`) holds the cross-cutting value types every service shares. They are owned by no single service — they are shared vocabulary — so importing them is correct and expected, and is the deliberate exception to **No cross-service message imports**. Redefining a local equivalent (a home-grown currency+amount pair, a bare `string` UUID, a `year`/`month`/`day` triple) forks the concept: you lose the type's documented invariants — `FixedDecimal`'s sign-matched `units`/`nanos`, `UUID`'s lowercase-hyphenated contract — and the central converter support that travels with them.

This set grows over time. Treat the package as the authority and check it for the current list rather than assuming the table below is complete — a common type that does not exist today may be the right import tomorrow. The decision rule is structural, not a fixed list: **if a concept is modelled by a type in the `zego.protobuf` common package, import that type instead of minting your own.**

| Common type | Models | Reuse instead of |
|---|---|---|
| `zego.protobuf.Money` | An amount with an ISO 4217 currency code | a local currency-code + amount pair |
| `zego.protobuf.FixedDecimal` | A fixed-point decimal (up to 9 dp) | a `double`/`float`, or a hand-rolled units/nanos pair |
| `zego.protobuf.Date` | A whole calendar date | a `year`/`month`/`day` triple or a date string |
| `zego.protobuf.Url` | A URL | a bare `string url` field |
| `zego.protobuf.UUID` | A lowercase, hyphenated UUID | a bare `string` id with its own casing rules |

The same package also provides shared event/data-lake types in `zego/protobuf/stream.proto` — `SourceMetadata` (the Kinesis event envelope) and the data-lake/Snowflake message and field options — for producers publishing to the data platform; reuse those rather than minting per-service equivalents.

```proto
// good — import the shared common types; reference them fully-qualified
import "zego/protobuf/money.proto";
import "zego/protobuf/uuid.proto";

// A payment taken from a customer.
message Payment {
  // Unique identifier for this payment.
  zego.protobuf.UUID payment_id = 1;
  // The amount taken from the customer.
  zego.protobuf.Money amount = 2;
}

// bad — redefining what the common package already owns
message Payment {
  // Unique identifier for this payment.
  string payment_id = 1;            // reinvents zego.protobuf.UUID — no casing contract
  // A monetary amount.
  message Amount {                  // reinvents zego.protobuf.Money / FixedDecimal
    // ISO 4217 currency code.
    string currency_code = 1;
    // The amount, as a floating-point value.
    double value = 2;               // a float loses FixedDecimal's exactness
  }
  // The amount taken from the customer.
  Amount amount = 2;
}
```

## Contract-level comments only

A proto comment is read by every consumer of the contract and by the generated client docs. It must describe the *meaning* of a field, message, or RPC to the consumer — never the producer's implementation, the cross-service plumbing that fills it, or the internal ticket that prompted it. Implementation detail is wrong the moment the implementation changes, and cross-service wiring leaks an internal topology consumers must not depend on. For an RPC, state what it does for the caller, not how it is satisfied internally or downstream.

The linter requires a leading comment on every message, field, `enum`, enum value, and RPC — so the question is never *whether* to comment but *what* the comment says; this rule governs that. The examples throughout this standard are fully commented for the same reason; the only bare declarations are in the *bad* example below, where the leaked-implementation comments are themselves the point.

```proto
// good — describes meaning to the consumer
// An insurance policy.
message Policy {
  // The date cover starts. Claims before this date are not covered.
  zego.protobuf.Date inception_date = 1;
}

// bad — leaks generation, routing, and an internal ticket reference
// An insurance policy.
message Policy {
  // Set by the Pricing service, passed through Finance to LM during renewal.
  // Added for ORDERS-4821; populated from the legacy inception column.
  zego.protobuf.Date inception_date = 1;
}
```

## Don't duplicate the source of truth

Every fact in a contract should have exactly one home. When a dedicated field already carries a fact, restating it in the comments of adjacent fields or enum values creates two sources that drift apart the first time one is edited without the other. An error enum names the *cause or category* of a failure; a separate `retryable` field carries retryability. Do not annotate each enum value with its retryability — that duplicates what the field already says.

```proto
// good — enum = cause; dedicated field = retryability; stated once
// The reason a charge attempt failed.
message ChargeFailure {
  // The category of failure.
  ChargeErrorCode code = 1;
  // Whether retrying the same charge may later succeed.
  optional bool retryable = 2;
}

// The cause of a charge failure.
enum ChargeErrorCode {
  // The cause is unknown.
  CHARGE_ERROR_CODE_UNSPECIFIED = 0;
  // The card had insufficient funds.
  CHARGE_ERROR_CODE_INSUFFICIENT_FUNDS = 1;
  // The card has expired.
  CHARGE_ERROR_CODE_CARD_EXPIRED = 2;
}

// bad — retryability duplicated into every enum-value comment; drifts from the field
// The cause of a charge failure.
enum ChargeErrorCode {
  // The cause is unknown.
  CHARGE_ERROR_CODE_UNSPECIFIED = 0;
  CHARGE_ERROR_CODE_INSUFFICIENT_FUNDS = 1;  // transient — retryable
  CHARGE_ERROR_CODE_CARD_EXPIRED = 2;        // deterministic — not retryable
}
```

## Don't accept inputs the service owns or ignores

Every request field is a promise that the service reads it and that the caller is entitled to set it. Audit each one against the service code. Drop a field the service derives for itself (accepting it lets a caller contradict the service's own computation, a conflict the service must then silently resolve) and drop a field nothing reads (verify by tracing the code, not by assuming). Keep a field only when it is genuinely consumed — or when it carries caller *intent* that the service validates against its own discovered truth, in which case document that intent so the validation is not mistaken for blind trust.

```proto
// good — only fields the service consumes; declared intent is validated, not trusted
// Request to price a quote.
message PriceQuoteRequest {
  // Identifier of the quote to price.
  string quote_id = 1;
  // Caller's expected currency. The service prices in its own resolved currency
  // and rejects the request if this does not match — a guard, not an input.
  string expected_currency_code = 2;
}

// bad — product_type is derived by the service; region is read by nothing
// Request to price a quote.
message PriceQuoteRequest {
  // Identifier of the quote to price.
  string quote_id = 1;
  string product_type = 2;  // service classifies this itself from the quote
  string region = 3;        // no code path reads this
}
```

## Optionality reflects domain reality

Optionality is a domain statement, not a stylistic choice inherited from a sibling message. Mark a field `optional` when, at the moment the message is produced, the value can legitimately be absent; require it only when it must always be present. Do not copy a legacy message's required/optional shape without checking — verify against the canonical model and the producing code. Forcing a genuinely-optional field to be required makes producers fabricate placeholder values that downstream consumers cannot distinguish from real ones.

```proto
// good — cancellation date is absent until a policy is cancelled
// An insurance policy.
message Policy {
  // The date cover starts.
  zego.protobuf.Date inception_date = 1;
  // The date the policy was cancelled; absent while the policy is active.
  optional zego.protobuf.Date cancellation_date = 2;
}

// bad — required because an older message was, forcing a sentinel for live policies
// An insurance policy.
message Policy {
  // The date cover starts.
  zego.protobuf.Date inception_date = 1;
  zego.protobuf.Date cancellation_date = 2;  // producers send 0001-01-01 when uncancelled
}
```

## Natural field numbering

Field numbers should let a reader scan the message top-to-bottom as they would describe the entity — not in whatever order the fields happened to be added. A natural reading runs from the message's own identity, out through what it relates to, to the substance it carries. For `BillingDocument` we settled on: operation/identity (`billing_document_id`, `type`, `date`) → what it relates to (`order_id`, `policy_id`, `policy_number`, `quote_id`, `quote_type`) → who (`user_id`, `customer_number`) → product → coverage → the money (`line_items`, `totals`). Concretely, related fields sit together — `policy_id` beside `policy_number`, `quote_id` beside `quote_type` — never scattered as `policy_id = 2`, `policy_number = 5`.

For a new message that has never been published, you are free to renumber to achieve that order — there are no consumers to break, so do it. For a message that has already shipped, field numbers are part of the wire format: never renumber an existing field and never reuse a retired number, because old and new peers will silently misinterpret each other's bytes. Add new fields at the next free number, even if that leaves the layout less than ideal.

```proto
// good — new message: grouped by a natural reading, related fields adjacent
// A document recording amounts billed to a customer.
message BillingDocument {
  // Unique identifier for this billing document.   (identity)
  string billing_document_id = 1;
  // The kind of billing document (invoice, credit note, …).
  BillingDocumentType type = 2;
  // The date the document was raised.
  zego.protobuf.Date date = 3;
  // The order this document bills for.              (what it relates to)
  string order_id = 4;
  // The policy this document bills for.
  string policy_id = 5;
  // Human-readable policy number; adjacent to policy_id.
  string policy_number = 6;
  // The quote the policy was priced from.
  string quote_id = 7;
  // The kind of quote; adjacent to quote_id.
  QuoteType quote_type = 8;
  // The user the document belongs to.               (who)
  string user_id = 9;
  // Human-readable customer number.
  string customer_number = 10;
  // The individual amounts that make up the document.  (the money)
  repeated LineItem line_items = 11;
  // The summed totals across all line items.
  Totals totals = 12;
}

// bad — order of addition; related fields scattered across the numbering
// A document recording amounts billed to a customer.
message BillingDocument {
  // Unique identifier for this billing document.
  string billing_document_id = 1;
  // The policy this document bills for.
  string policy_id = 2;
  // The individual amounts that make up the document.
  repeated LineItem line_items = 3;
  string policy_number = 5;                   // belongs beside policy_id, not five fields away
  // The quote the policy was priced from.
  string quote_id = 4;
  // The summed totals across all line items.
  Totals totals = 6;
  QuoteType quote_type = 7;                    // belongs beside quote_id
}
```

## Explicit success/failure result for new endpoints

New endpoints model their outcome as an explicit `oneof result` of a success message and a failure message, so the caller branches on a tag rather than inspecting whether scattered fields were populated. The failure message carries a human-readable `message`, an `<Op>ErrorCode` enum whose zero value is `..._UNSPECIFIED`, and an `optional bool retryable`. A "nothing to do" or "not applicable" outcome is *not* a failure — it is a success variant, expressed as an explicit marker message in a nested `oneof outcome`. Prefer an explicit `oneof` arm to an optional field whenever treating "absent" as a default-constructed value would be dangerous: a missing financial document read as an empty one can cause real harm, where a distinct tag cannot be misread. If the success/failure model is already documented for a sibling endpoint, cross-reference it rather than restating it.

```proto
// good — explicit result; "nothing to do" is a success, not a failure
// Response to an IssueRefund call.
message IssueRefundResponse {
  // The outcome of the refund attempt.
  oneof result {
    // The refund attempt succeeded; see the nested outcome for what happened.
    IssueRefundSuccessResponse success = 1;
    // The refund attempt failed.
    IssueRefundFailureResponse failure = 2;
  }
}

// A successful IssueRefund outcome.
message IssueRefundSuccessResponse {
  // What the successful call actually did.
  oneof outcome {
    // A refund was issued.
    RefundIssued issued = 1;
    // There was nothing to refund — a valid, non-error outcome.
    NothingToRefund nothing_to_refund = 2;
  }
}

// A failed IssueRefund outcome.
message IssueRefundFailureResponse {
  // Human-readable description of the failure.
  string message = 1;
  // The category of failure.
  IssueRefundErrorCode code = 2;
  // Whether retrying the same request may later succeed.
  optional bool retryable = 3;
}

// The cause of an IssueRefund failure.
enum IssueRefundErrorCode {
  // The cause is unknown.
  ISSUE_REFUND_ERROR_CODE_UNSPECIFIED = 0;
  // The refund had already been issued.
  ISSUE_REFUND_ERROR_CODE_ALREADY_REFUNDED = 1;
}

// bad — flat fields; caller must guess whether absence means success, skip, or error
// Response to an IssueRefund call.
message IssueRefundResponse {
  // Whether the refund succeeded.
  bool ok = 1;
  // Description of the failure, if any.
  string error_message = 2;
  RefundDetails refund = 3;  // unset on both "nothing to do" and on failure
}
```

## Verify the real shape

Before declaring an embedded or returned type, confirm its shape against two sources: the code that actually produces the value, and the canonical proto in `Zegocover/protobuf`. Do not model it from a local partial pydantic projection — a service often defines a trimmed local view that omits or renames fields it does not use, and building a contract from that view ships a type that silently disagrees with what the producer emits. The mismatch surfaces only at runtime, in the consumer.

```python
# good — confirm against the producer and the canonical proto, then declare
# zego/protobuf/payments/v1/payment.proto is the source of truth for PaymentDetails

# bad — modelling from a local trimmed pydantic view that drops `captured_at`
class _LocalPayment(BaseModel):  # partial; missing fields the producer sets
    amount: Decimal
    currency: str
```

## Validate breaking changes against `origin/main`

`buf breaking` is only as accurate as the ref it compares against. `--against '.git#branch=main'` resolves the *local* `main` ref, which on a working clone is usually behind `origin/main`; comparing against it surfaces every upstream change made since you last pulled — including refactors in files you never touched — as a breaking-change false positive. Fetch first and compare against the remote ref so the baseline matches what CI uses. CI's `main` is always current, so a clean local run against `origin/main` should match CI.

```bash
# good — fetch, then compare against the current remote baseline
git fetch origin
buf breaking --against '.git#ref=origin/main'

# bad — local main is stale; reports upstream refactors as your breaking changes
buf breaking --against '.git#branch=main'
```

## Don't `buf format -w` a touched file unless format is a CI gate

`buf format -w` rewrites the whole file to canonical formatting. Many existing protos predate any formatter and are not formatted, and formatting is not enforced in CI, so running it on a file you are editing reformats hundreds of pre-existing lines and buries your actual change in unreviewable noise. Match the file's existing layout instead — even where the existing import or field order is not alphabetical — and keep the diff to the lines your change requires. Only run `buf format -w` where formatting is an enforced CI gate for that repo.

```bash
# good — add the new import in the file's existing order; minimal diff
# (edit by hand, leave surrounding formatting untouched)

# bad — reformats the entire pre-existing file alongside your one-line change
buf format -w path/to/touched.proto
```

## Validate locally before committing

Use the repo's `make` wrappers rather than recalling individual `buf` invocations:

1. `make` — lints and runs the breaking-compatibility check. Fast; this is the entry point for message-only changes.
2. `make build` — additionally compiles the language libraries; run it when you change gRPC service definitions.

There is one gap to cover by hand. `make`'s breaking check runs `buf breaking --against '.git#branch=main'`, comparing against your *local* `main` ref — the stale-baseline footgun described in **Validate breaking changes against `origin/main`**. After `git fetch`, run the explicit form yourself for an accurate local result that matches CI:

```bash
# good — fresh worktree off latest origin/main; make wrappers + accurate breaking check
git fetch origin
git worktree add ../proto-ABC-123 origin/main
cd ../proto-ABC-123
make                                            # lint + breaking (vs local main)
buf breaking --against '.git#ref=origin/main'   # accurate baseline — what make's check misses
git commit -m "ABC-123: add issue-refund result message"
gh pr create --draft
```

Work in a fresh worktree cut off the latest `origin/main` so a stale local tree does not mask or invent problems. Commit using the protobuf repo's convention — `JIRA-ID: lowercase description`, with no `(type)` prefix — and open the PR as a draft.

## See Also

- [Zego protobuf README](https://github.com/Zegocover/protobuf/blob/main/README.md) — the canonical protobuf-repo guidance: bounded-context isolation, where a message lives (`protobuf/` shared vs `grpc/` service-only), and the local build workflow (`make` / `make build`). This standard distils the durable authoring principles and the `buf` validation footguns; the README owns repo structure and tooling, so follow it there rather than relying on a copy here.
- [Zego protobuf style guide](https://github.com/Zegocover/protobuf/blob/main/docs/style_guide.md) — naming and structural style conventions for `.proto` and gRPC definitions.
- [protobuf-converters.md](protobuf-converters.md) — Python-side converter usage for proto message types: never hand-roll conversions, nullability suffixes, proto3 zero-value semantics.
- [../languages/python.md](../languages/python.md) — Python conventions: project structure, dependency injection, typing, and functional core/imperative shell.

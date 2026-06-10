---
version: 1.2
last_reviewed: 2026-05-11
---

# Testing Standards

Testing conventions for verifying observable behaviour — the governing philosophy is integration-first: test from the outside in through real components, and write unit tests only where integration tests cannot reach. Apply these rules to any codebase when writing or modifying tests. Language-specific tooling (test runners, coverage plugins, parametrize decorators) is not covered here — see the relevant language standards file. Constructor injection and composition root patterns that enable dependency substitution in tests are covered in the language-specific standards files (e.g. `languages/python.md`).

## Rules at a Glance

1. **Integration tests as default.** Prefer integration tests that exercise real components end-to-end over unit tests — they catch wiring bugs, validate real behaviour, and are harder to make pass with a broken implementation.
2. **Unit tests for unreachable paths.** Write unit tests only for logic that integration tests cannot cost-effectively reach: deep error branches, pure algorithmic logic, and combinatorial edge cases.
3. **Mock only at the external boundary.** Replace only third-party HTTP clients, databases, and external services you do not own — never mock your own code, including via test-only subclasses that override concrete production methods, because mocking internal calls only tests that you wrote the mock correctly.
4. **Build real domain objects in fixtures.** Construct genuine domain objects in test fixtures rather than stubs or magic-value dicts — tests that use real objects catch contract breakage; tests that use stub objects hide it.
5. **Fresh fixtures per test.** Fixtures must return a new object on every call — shared mutable state between tests causes order-dependent failures that are hard to diagnose.
6. **No copy-pasted setup.** Extract repeated setup into fixtures and repeated input/output pairs into table-driven tests — duplication means a future change breaks many tests for one logical reason.
7. **Fix or delete brittle tests.** When a test fails intermittently, fix the root cause or delete the test — never add retries, because a flaky test in CI masks real failures and trains the team to ignore red.
8. **Test failure paths explicitly.** Write at least one test per failure path — happy-path-only test suites pass on broken code that returns a wrong result rather than raising.
9. **Extract pure logic from framework glue.** Pull business logic out of framework handlers into pure functions or classes so it can be tested without spinning up the framework.
10. **Coverage enforced at config level only.** Target high coverage and enforce the threshold in CI config — never add inline coverage exclusions, because they permanently hide untested code from the metric.
11. **Never add test-only paths to production code.** When a test fails, fix the test or fix the production bug — never add environment checks, test-fixture hooks, or conditional branches to production code to make a test pass. If production code needs to change to become testable, extract logic (Rule 9); don't add `if testing` / `if ENV == "test"` gates.

## Integration tests as default

An integration test assembles real components — real service classes, real repositories against a real or in-process database, real serialisers — and calls through the full stack. The trade-off is slower execution and more setup; the benefit is that a passing test suite is strong evidence the system works, not just that its individual pieces behave as their author assumed.

Unit tests have their place: pure algorithmic logic with many input combinations is best tested in isolation, and some error branches (network timeout, upstream 500) are impractical to trigger through a real stack. The rule is not "never unit test" — it is "start with integration, drop to unit only when integration cannot reach".

```
# good — exercises the real service, real repository, real domain logic
test "policy activation records event":
    repo = PolicyRepository(db_session)
    service = PolicyService(repo=repo, events=event_bus)
    service.activate(policy_id="POL-1")
    assert event_bus.last_emitted.type == "policy.activated"

# bad — tests the service in isolation at the cost of hiding wiring bugs
test "policy activation records event":
    mock_repo.get.returns = FakePolicy()
    service = PolicyService(repo=mock_repo, events=mock_events)
    service.activate(policy_id="POL-1")
    assert mock_events.emit.was_called_once
```

## Mock only at the external boundary

The external boundary is anything you do not own: a third-party REST API, a managed database, an external message broker, a payment provider SDK. Everything inside your service boundary — your own classes, your own repositories, your own domain logic — should run real.

Mocking internal code couples the test to implementation details. When you refactor, the mock breaks even if the behaviour is unchanged. Worse, a mock that is set up incorrectly will make a test pass on code that is wrong.

This also applies to test-only subclasses. Creating a subclass of a concrete production class that overrides methods and testing the subclass instead of the real class is mocking-by-inheritance — it has the same problem: the test validates the override, not the production behaviour. Test the real class or don't test it. This does not apply to concrete implementations of abstract base classes, interfaces, or protocols — those are legitimate dependency substitutions, not mocks.

```
# good — only the external HTTP client is replaced
test "quote fetches rate from provider":
    fake_http.get("/rates").returns = { "rate": 0.05 }
    service = QuoteService(http=fake_http)
    quote = service.get_quote(vehicle_id="V-1")
    assert quote.rate == 0.05

# bad — mocking own repository hides whether the service and repo integrate correctly
test "quote fetches rate from provider":
    mock_quote_repo.find.returns = FakeQuote(rate=0.05)
    ...
```

## Build real domain objects in fixtures

A fixture that returns a real `Policy(id="POL-1", status="pending")` will break if the `Policy` constructor changes — which is the right behaviour. A fixture that returns a plain map/dict `{"id": "POL-1", "status": "pending"}` or a mock object will silently pass even if the domain object's contract has been broken.

Build fixtures using the same constructors and factory methods production code uses. If a domain object is expensive to construct, that is a signal the object has too many required dependencies — address the design, not the test.

```
# good — uses the real constructor; breaks loudly if the contract changes
function make_policy(overrides):
    defaults = { id: "POL-1", status: "pending", product: "van" }
    return Policy(merge(defaults, overrides))

# bad — a plain map/dict will not catch constructor or type changes
function make_policy():
    return { id: "POL-1", status: "pending", product: "van" }
```

## Fresh fixtures per test

A fixture that returns the same object across tests creates shared mutable state. Test A mutates the object; Test B assumes it is clean; Test B fails only when run after Test A.

Fixtures must construct and return a new instance on every invocation. In most test frameworks this is the default behaviour for function-scoped fixtures — do not widen the scope unless you have a measured performance reason and the object is provably immutable.

```
# good — new Policy instance on every test call
fixture active_policy():
    return Policy(id="POL-1", status="active")

# bad — file-level singleton is shared across all tests in the file
ACTIVE_POLICY = Policy(id="POL-1", status="active")   # created once, reused everywhere
```

## No copy-pasted setup

When two tests share the same setup code, extract it into a fixture. When two tests differ only in their inputs and expected outputs, merge them into a table-driven (parametrised) test. Duplicated setup is maintenance debt: a domain change requires updating every copy.

The rule applies to assertion helpers too — if three tests assert the same multi-field condition, extract an assertion helper rather than repeating the condition inline.

```
# good — table-driven; one place to add cases, one place to update assertions
cases = [
    { product: "van",  expected_rate: 0.10 },
    { product: "taxi", expected_rate: 0.25 },
    { product: "bike", expected_rate: 0.05 },
]
for each case in cases:
    test "base rate for {case.product}":
        policy = make_policy(product=case.product)
        assert calculate_rate(policy) == case.expected_rate

# bad — three copies of identical setup that diverge over time
test "van rate":
    policy = Policy(id="P1", status="active", product="van")
    assert calculate_rate(policy) == 0.10

test "taxi rate":
    policy = Policy(id="P1", status="active", product="taxi")
    assert calculate_rate(policy) == 0.25
```

## Fix or delete brittle tests

A test that sometimes passes and sometimes fails provides negative value: it trains the team to ignore CI red, delays detection of real regressions, and wastes time on retries. The only acceptable responses are to fix the root cause (a timing dependency, a race condition, a non-deterministic ordering) or to delete the test.

Common causes of flakiness: relying on wall-clock time instead of injecting a clock, relying on dictionary/set ordering, using real sleeps instead of advancing a test clock, and shared state left over from a previous test.

## Test failure paths explicitly

A test suite that only exercises the happy path will pass on an implementation that raises no exceptions but returns wrong results on error inputs. For every logical failure case — invalid input, missing resource, upstream error — write at least one test that asserts the correct error response, exception type, or fallback behaviour.

```
# good — failure path is a first-class test case
test "activate raises when policy not found":
    assert_throws PolicyNotFoundError:
        service.activate(policy_id="NONEXISTENT")

# bad — only the success path is tested; broken error handling goes undetected
test "activate success":
    service.activate(policy_id="POL-1")
    assert ...
```

## Extract pure logic from framework glue

Framework entry points (HTTP handlers, event consumers, CLI commands) mix dispatch logic — parsing requests, routing errors, returning responses — with business logic. Business logic buried in a handler can only be tested by spinning up the full framework.

Pull the business logic into a plain function or class that takes typed arguments and returns a typed result. Test that directly. Test the handler only for the thin layer it owns: correct parsing, correct status codes, correct error mapping.

```
# good — pure function tested directly, no framework required
function calculate_premium(base_rate, risk_score):
    return base_rate * (1 + risk_score / 100)

test "calculate premium applies risk multiplier":
    assert calculate_premium(base_rate=0.10, risk_score=50) == 0.15

# bad — business logic lives inside the handler; test must go through HTTP
function quote_handler(request):
    base_rate = parse_float(request.body["base_rate"])
    risk_score = parse_int(request.body["risk_score"])
    return json_response({ premium: base_rate * (1 + risk_score / 100) })
```

## Coverage enforced at config level only

Inline exclusions (`# pragma: no cover`, `// istanbul ignore next`, and equivalents) permanently remove lines from the coverage metric without any record of why. Over time they accumulate and the coverage number stops reflecting reality.

Set the coverage threshold in CI configuration. When a line genuinely should not be covered — a defensive branch that can only be reached by hardware failure, a type-narrowing assertion — omit it at the config level with a comment explaining why, rather than scattering exclusions through the source.

## Never add test-only paths to production code

Test-only branches in production code (environment variable checks, fixture-registration hooks, environment-gated behaviour) create invisible coupling between the test suite and the deployment artifact. They are never exercised in production, so they rot silently, and they make the production code harder to reason about.

When a test is hard to write, the correct responses are:

- **Fix the test** if the test is wrong — incorrect setup, bad assertion, or testing the wrong thing
- **Fix the production code** if there is a genuine bug
- **Extract logic** (Rule 9) if the code is untestable due to framework coupling
- **Rethink the test approach** — the integration-first philosophy (Rule 1) exists precisely to avoid needing production-side test accommodations

If none of these fit, the test may not be worth writing.

## Red Flags — Stop and Reconsider

If any of these thoughts cross your mind, stop — you are about to rationalise away a rule.

- "I'll just mock the repository so I don't have to stand up a real database for this test."
- "A unit test with mocks is faster and will catch the same bug, so I'll skip the integration test."
- "I'll subclass the production class in the test and override the slow method — it's still testing the real class."
- "Setting up the real collaborators is too much boilerplate; a mock keeps the test focused."
- "This logic is simple enough that an isolated unit test is clearly sufficient here."

| Rationalisation | Rule it violates | Real-world consequence |
|-----------------|------------------|------------------------|
| "I'll just mock the repository so I don't have to stand up a real database for this test." | Rule 3 — Mock only at the external boundary | The test asserts the mock was called, not that the service and repository integrate — a broken query or schema mismatch passes CI and surfaces only in production. |
| "A unit test with mocks is faster and will catch the same bug, so I'll skip the integration test." | Rule 1 — Integration tests as default | Wiring bugs between real components go untested; the suite is green on a system that does not actually work end-to-end. |
| "I'll subclass the production class in the test and override the slow method — it's still testing the real class." | Rule 3 — Mock only at the external boundary | The test validates the override, not the production method, so a regression in the real method ships undetected. |
| "Setting up the real collaborators is too much boilerplate; a mock keeps the test focused." | Rule 1 — Integration tests as default; Rule 3 — Mock only at the external boundary | The test couples to current implementation detail and passes on incorrectly wired code, defeating the reason the test was written. |
| "This logic is simple enough that an isolated unit test is clearly sufficient here." | Rule 1 — Integration tests as default | "Simple" logic with a real wiring bug (wrong field mapped, wrong dependency injected) passes in isolation and fails only against live data. |

## See Also

- [languages/python.md](../languages/python.md) — constructor injection and composition root patterns that enable dependency substitution in tests.

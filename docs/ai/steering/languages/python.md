---
version: 1.5
last_reviewed: 2026-06-23
---

# Python Standards

Structural and architectural conventions for Python — how business logic is organised, dependencies are wired, types are annotated, and interfaces are expressed; the governing philosophy is functional core, imperative shell: pure functions for business logic, I/O at the edges. Apply these rules to any Python file you write or modify. Formatting, import ordering, and type checking are enforced mechanically by ruff and mypy and are not covered here; testing tooling (pytest, pytest-asyncio, coverage.py) is language-specific and is covered here. Logging conventions are owned by `docs/ai/steering/base/logging.md`; observability and tracing conventions are owned by `docs/ai/steering/base/observability.md`; testing principles and structure are owned by `docs/ai/steering/base/testing.md`.

## Applicability

The rules below divide into an **intrinsic core** that describes the Python code itself — and so applies to any Python file the diff touches, regardless of the repo's wider structure — and **project-structure and tooling rules** that only have meaning once the repo has adopted the scaffolding they govern. Gate the latter by surface presence, the same way the base standards (`logging.md`, `environment.md`, `error-handling.md`) gate their surface-specific rules.

**Intrinsic core — applies to any Python the diff touches:**

- **Functional core, imperative shell** (Rule 1) and the **async-for-I/O** boundary (Rule 12).
- **Composition root** wiring (Rule 2) and **modules over all-static classes** (Rule 3).
- **Type annotations everywhere**, including no silenced mypy outside the two permitted cases (Rule 4), **`Any` requires an inline comment** (Rule 11), and **imports at the top** (Rule 7).
- **Docstrings for public interfaces** (Rule 5) and **TODO with Jira reference** (Rule 6).
- **PEP 8 naming** (Rule 8) and **no magic strings or numbers** (Rule 13).
- **Protocols sparingly** (Rule 9) and **Pydantic for domain data and boundaries** (Rule 10).
- The **single config entry point principle** — the part of the `BaseSettings` rules (Rules 23–26) that says environment reads must be routed through one place rather than scattered as `os.getenv()`/`os.environ[]` calls through business logic. This principle is intrinsic: a new module scattering `os.getenv()` calls is flaggable wherever it appears, independently of whether the repo already has a config entry point.

**Project-structure and tooling rules — bind only where the surface already exists:**

- The **`tests/unit/` vs `tests/integration/` split** (Rule 15) — binds only where the repo already maintains that split; adding one test file to a repo with no pre-existing split is not a violation.
- The **95% coverage floor and config-level coverage exclusions** (Rules 18, 19) — bind only where a `pyproject.toml` coverage target already exists.
- The **pytest / pytest-asyncio / LocalStack / pytest-dotenv tooling and mocking rules** (Rules 14, 16, 17, 20, 21, 22, 27) — bind only where that test scaffolding already exists.
- The specific **Pydantic `BaseSettings` plumbing** (Rules 23–26) — the concrete `BaseSettings` class, `env_nested_delimiter`, `secrets_dir`, and `env_file` mechanics — binds only where a config entry point already exists. This is distinct from the single-config-entry-point *principle* above, which is intrinsic: where the repo has no `BaseSettings` entry point, do not demand that a lone module introduce one, but a module scattering `os.getenv()` calls is still flaggable against Group B's universal config core.

Where the surface is absent, do not raise a finding demanding that a lone module introduce it — note it as an advisory at most. A `.py` file in the diff does not by itself make the repo a Python service that ought to have this scaffolding; the decisive test is the repo's existing structure, not the diff's.

## Rules at a Glance

1. **Functional core, imperative shell.** Keep business logic in pure functions with no I/O; push all network, database, and filesystem calls to the outermost layer — pure functions are trivially testable and isolate the parts of the system that are expensive to exercise.
2. **Composition root.** Wire the full object graph once at startup via constructor arguments; never use service locators, module-level singletons, DI frameworks, or mid-request dependency lookups — the dependency graph must be greppable and startup-only. Exception: request-scoped state (current user, trace context, DB transactions) may use framework-provided request scopes, context managers, or `contextvars` (e.g. FastAPI `Depends`, `contextvars`) where startup injection cannot apply.
3. **Modules over all-static classes.** Put free functions in modules, not in classes made entirely of `@staticmethod` methods — an all-static class is a module with unnecessary syntax.
4. **Type annotations everywhere.** Annotate every parameter and return value, including `-> None`; avoid `Any`; never silence mypy except in the two cases the **Imports at the top** rule explicitly permits (optional-extras deferred imports and documented circular imports with no structural fix) — in those cases `# type: ignore` is allowed but must include an inline comment explaining why; in all other cases silencing mypy hides contract violations until runtime.
5. **Docstrings for public interfaces.** Write docstrings for all public modules, classes, and functions using Google style; say *why* the interface exists, not *what* the code does — intent and invariants that cannot be inferred from code survive refactors; docs that restate the code become noise.
6. **TODO with Jira reference.** Format every TODO as `# TODO(ABC-1234):` — untracked TODOs rot.
7. **Imports at the top.** Place all imports at module level; never inside functions or blocks — inline imports make module dependencies invisible to static analysis and usually signal a circular import to fix structurally. Permitted exceptions: `if TYPE_CHECKING:` blocks; optional-extras deferred imports where the library may not be installed (guard with `ImportError` and an inline comment); documented circular imports with no structural fix (requires an inline comment with a Jira ticket).
8. **PEP 8 naming.** Use `snake_case` for variables, functions, and methods; `PascalCase` for classes; `UPPER_SNAKE_CASE` for constants — consistent naming is the baseline contract for Python readability across the codebase.
9. **Protocols sparingly.** Introduce a `Protocol` only when two or more concrete implementations already exist; implementations inherit the protocol explicitly (not just structurally) and overrides are marked `@override` — speculative interfaces add complexity without value. Import `override` from `typing` (Python 3.12+) or `typing_extensions` (backport for earlier versions).
10. **Pydantic for domain data and boundaries.** Pydantic is Zego's standard for anything that represents domain data, crosses a service boundary, or is constructed from external input — it validates on construction, catching malformed input at the boundary before it propagates into business logic; use `@dataclass(frozen=True)` only for small internal value types with no validation or serialisation needs.
11. **`Any` requires an inline comment.** When `Any` is genuinely the right annotation, add an inline comment at the annotation explaining why — not in a docstring, at the annotation itself.
12. **Async for I/O.** Use `async`/`await` for all I/O operations; keep pure computational functions synchronous — mixing sync and async in the same function blurs the functional core/imperative shell boundary and can block the event loop.
13. **No magic strings or numbers.** Replace raw string and numeric literals that carry domain meaning with `Enum` values (for shared, API, or persisted values), `Literal` types (for type-checker-only constraints), or module-level constants — named values make intent explicit and prevent silent drift when a value changes. Use `StrEnum` (Python 3.11+) for string enums; on Python 3.10 and below use `str, Enum` instead.
14. **pytest and pytest-asyncio.** Use pytest as the test framework; use pytest-asyncio for all async test functions — mixing sync and async test helpers produces unpredictable event loop state.
15. **tests/unit/ and tests/integration/ layout.** Place tests in `tests/unit/` for cases that genuinely cannot be expressed as integration tests, and `tests/integration/` for everything else — keeping the directories separate makes it trivial to run each suite independently in CI.
16. **AsyncMock for async dependencies.** Use `AsyncMock` (from `unittest.mock`) when substituting async external dependencies in unit tests — a plain `Mock` does not await correctly and produces silent failures. Exception: never use `AsyncMock` for AWS SDK clients — use LocalStack instead; see **No boto3 mocks**.
17. **Factory fixtures for variations.** When tests need variations on a domain object, return a builder callable from the fixture rather than a fixed instance — callers override only the fields relevant to their assertion, keeping setup concise and the fixture reusable.
18. **95% coverage via pyproject.toml.** Enforce coverage with `fail_under = 95` in `pyproject.toml`; run diff-cover against `origin/main` so new code is held to a strict bar without blocking progress on existing debt.
19. **No inline coverage exclusions.** Never use `# pragma: no cover` inline — omit files at the config level in `[tool.coverage.run] omit` in `pyproject.toml`, and only for pure startup wiring (entrypoints, signal handlers) after extracting all testable logic.
20. **No time.sleep() in async tests.** Use `asyncio.sleep()` or mock time rather than `time.sleep()` in async tests — `time.sleep()` blocks the event loop and makes async tests unreliable.
21. **LocalStack for AWS integration tests.** Use LocalStack for all AWS service integration tests (DynamoDB, Kinesis, S3) — inject real SDK clients pointed at its endpoint so tests exercise real API calls and parameter validation; pin to `localstack/localstack:4.14`, as versions after 4.14 introduced a mandatory account system that breaks unauthenticated local use.
22. **No boto3 mocks.** Never patch boto3 clients directly — hand-rolled mocks couple tests to call signatures rather than observable behaviour and hide real API rejection. Use `AsyncMock` only at a `Protocol` boundary where call dispatch (not data fidelity) is under test; never as a substitute for LocalStack when real read/write behaviour matters.
23. **Pydantic BaseSettings as config entry point.** All environment variables must be read through a single Pydantic `BaseSettings` class — never call `os.getenv()` or `os.environ[]` outside that class; instantiate once in the composition root and inject via DI — this implements the single config entry point required by `docs/ai/steering/base/environment.md`.
24. **Nested config groups with `env_nested_delimiter`.** Group related settings into nested `BaseModel` classes and use `env_nested_delimiter="__"` — flat config classes with dozens of fields become unreadable and make it impossible to tell which settings belong together.
25. **`secrets_dir` for filesystem-mounted secrets.** Set `secrets_dir` in `SettingsConfigDict` to the mount path (`/mnt/<service-name>`) so Pydantic reads secret files natively — secrets provisioned via `secrets-config` are mounted at this path by the Blueprint infrastructure.
26. **Env file loading with `SettingsConfigDict`.** Declare `env_file=(".env.development", ".env")` so Pydantic loads committed development values as the base and gitignored personal overrides on top — this implements the committed/gitignored config file layout from `docs/ai/steering/base/environment.md`.
27. **pytest-dotenv for test configuration.** Configure `pytest-dotenv` with `env_files = ".env.development"` in `pyproject.toml` so tests load the same safe defaults as local development.
28. **OTel instrumentors in `pyproject.toml`; run under `opentelemetry-instrument`.** Declare `opentelemetry-distro` (which provides the `opentelemetry-instrument` entrypoint), `opentelemetry-exporter-otlp`, and a per-framework instrumentor (`opentelemetry-instrumentation-fastapi`, `-httpx`, `-grpc`, etc.) for each library actually in use; keep the `1.x` (api/sdk/exporter) and `0.x` (instrumentation/semantic-conventions) version lines in lockstep when bumping. Run the service under `opentelemetry-instrument python -m <app>` and keep any in-app SDK or instrumentor wiring minimal — targeted hooks (e.g. a request hook that strips PII from a recorded URL) are fine; a parallel SDK setup that duplicates the entrypoint is not. See `docs/ai/steering/base/observability.md` rule 4.

## Functional core, imperative shell

Business logic that is entangled with I/O can only be tested through the I/O layer — slow, flaky, and expensive to set up. Separating pure computation from side effects means the core can be unit-tested with no mocks, and I/O paths can be integration-tested at the boundary.

```python
# good — pure core, I/O at the edge
def calculate_premium(base_rate: Decimal, risk_score: float) -> Decimal:
    return base_rate * Decimal(str(risk_score))

async def update_policy_premium(
    policy_id: str,
    repo: PolicyRepository,
    rate_service: RateService,
) -> None:
    base_rate = await rate_service.fetch_base_rate(policy_id)
    risk_score = await repo.get_risk_score(policy_id)
    premium = calculate_premium(base_rate, risk_score)
    await repo.save_premium(policy_id, premium)

# bad — business logic and I/O in the same function
async def update_policy_premium(policy_id: str) -> None:
    base_rate = await db.fetch("SELECT rate FROM rates WHERE policy_id = %s", policy_id)
    risk_score = await db.fetch("SELECT score FROM risk WHERE policy_id = %s", policy_id)
    premium = base_rate * risk_score  # logic buried inside I/O
    await db.execute("UPDATE policies SET premium = %s WHERE id = %s", premium, policy_id)
```

## Composition root

When dependencies are constructed mid-request or via service locators, the dependency graph is invisible to static analysis and tests. Wiring everything once at startup makes dependencies explicit, testable, and easy to trace.

Request-scoped state (the current user, trace context, DB transactions) is the main exception: framework-provided request scopes, context managers, or `contextvars` are fine because they cannot be resolved at startup.

```python
# main.py — composition root, wired once at startup
def build_app() -> App:
    settings = load_settings()
    db = Database(dsn=settings.database_url)
    rate_client = RateServiceClient(base_url=settings.rate_service_url)
    policy_repo = PolicyRepository(db=db)
    pricing_service = PricingService(repo=policy_repo, rate_client=rate_client)
    return App(pricing_service=pricing_service)

# bad — dependency constructed inside the function that uses it
async def handle_request(policy_id: str) -> Response:
    db = Database(dsn=os.environ["DATABASE_URL"])  # constructed mid-request
    repo = PolicyRepository(db=db)
    ...

# good — request-scoped state via FastAPI Depends (permitted exception)
async def get_current_user(token: str = Header(...)) -> User:
    return decode_token(token)

async def handle_request(user: User = Depends(get_current_user)) -> Response:
    ...
```

## Modules over all-static classes

A class with only `@staticmethod` methods provides no benefit over a module of free functions — it adds a namespace that imports can already provide, forces callers to write `ClassName.method()` for no reason, and obscures that there is no shared state.

```python
# good
# pricing.py
def calculate_base_rate(vehicle_class: str) -> Decimal: ...
def apply_ncd_discount(rate: Decimal, ncd_years: int) -> Decimal: ...

# bad — all-static class masquerading as a module
class PricingUtils:
    @staticmethod
    def calculate_base_rate(vehicle_class: str) -> Decimal: ...
    @staticmethod
    def apply_ncd_discount(rate: Decimal, ncd_years: int) -> Decimal: ...
```

## Type annotations everywhere

Untyped code hides contract violations until runtime. Full annotations let mypy catch mismatches at development time, make function signatures self-documenting, and remove the need to read implementations to understand what a function accepts or returns.

`# type: ignore` is permitted only in the two cases the **Imports at the top** rule explicitly allows: optional-extras deferred imports (where the library may not be installed) and documented circular imports with no structural fix. In both cases the suppress comment must be accompanied by an inline explanation of why it is needed. Silencing mypy in any other situation masks real type errors.

```python
# good
def apply_discount(price: Decimal, discount_rate: float) -> Decimal:
    return price * Decimal(str(1 - discount_rate))

# bad — no annotations; caller must read the body to know the types
def apply_discount(price, discount_rate):
    return price * (1 - discount_rate)
```

## Docstrings for public interfaces

A docstring that restates the code ("adds two numbers") adds no value. A docstring that explains *why* an interface exists — its invariants, when to use it, what it is responsible for — is load-bearing documentation that survives refactors.

Use Google style. Omit sections that add no information.

```python
# good
def calculate_risk_score(policy: Policy, claims: list[Claim]) -> float:
    """Compute the underwriting risk score for a policy.

    Combines claims frequency, severity, and policy age into a single
    normalised score in [0.0, 1.0]. Higher scores indicate greater risk.
    Does not consider external bureau data — callers should enrich the
    policy before calling this function if bureau data is available.

    Args:
        policy: The policy under assessment.
        claims: All historical claims associated with the policy.

    Returns:
        Risk score in [0.0, 1.0].
    """

# bad — restates the code, adds no information
def calculate_risk_score(policy: Policy, claims: list[Claim]) -> float:
    """Calculate risk score from policy and claims."""
```

## Imports at the top

Inline imports hide a module's dependencies from static analysis tools and IDEs, making it impossible to build a complete import graph or detect cycles without running the code. They also make it harder to review what a module depends on at a glance.

Three exceptions are permitted, each requiring an inline comment:

1. `if TYPE_CHECKING:` blocks — standard pattern; no comment needed.
2. Optional-extras deferred imports where the library may not be installed — guard with `ImportError` and note what the optional dependency enables.
3. Documented circular imports with no structural fix — note the Jira ticket tracking the structural resolution.

```python
# good — all imports at module level
from decimal import Decimal
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from myapp.models import Policy  # type-checking only; no runtime cost

# good — optional extras guarded at import time (not deferred inside a function)
try:
    import orjson as json  # optional: faster JSON; falls back to stdlib
except ImportError:
    import json  # type: ignore[no-redef]

# bad — import hidden inside a function body
def calculate_premium(policy_id: str) -> Decimal:
    import httpx  # makes the dependency invisible to static analysis
    ...

# bad — circular import deferred with no tracking ticket
def get_service():
    from myapp.services import PolicyService  # circular import workaround
    return PolicyService()

# good — circular import deferred, ticket noted (last resort)
def get_service():
    from myapp.services import PolicyService  # circular import; tracked in SYSENG-4321
    return PolicyService()
```

## Protocols sparingly

Introducing a `Protocol` before there are two concrete implementations is speculative design — it adds an interface that has never been exercised against a real second implementation and may not fit when one appears. Wait until the second implementation exists, then extract the protocol.

When you do introduce a protocol, inherit it explicitly and mark every override with `@override` so that type checkers can enforce the contract.

```python
# good — protocol introduced for two concrete implementations
from typing import Protocol
from typing_extensions import override

class RateClient(Protocol):
    async def fetch_base_rate(self, policy_id: str) -> Decimal: ...

class HttpRateClient(RateClient):
    @override
    async def fetch_base_rate(self, policy_id: str) -> Decimal:
        ...

class StubRateClient(RateClient):
    @override
    async def fetch_base_rate(self, policy_id: str) -> Decimal:
        return Decimal("1.00")

# bad — protocol introduced for a single implementation
class RateClient(Protocol):
    async def fetch_base_rate(self, policy_id: str) -> Decimal: ...

class HttpRateClient:  # only implementation; structural conformance is untested
    async def fetch_base_rate(self, policy_id: str) -> Decimal:
        ...
```

## Pydantic for domain data and boundaries

Pydantic is Zego's standard for domain data and service boundaries. It validates on construction and serialises cleanly to JSON, catching malformed input at the point of ingestion rather than deep in business logic. Reserve `@dataclass` for small internal value types that carry no validation or serialisation logic.

```python
# good — Pydantic for a domain model built from external input
from pydantic import BaseModel, field_validator

class PolicyQuoteRequest(BaseModel):
    policy_id: str
    vehicle_class: str
    inception_date: date

    @field_validator("vehicle_class")
    @classmethod
    def must_be_known_class(cls, v: str) -> str:
        if v not in KNOWN_VEHICLE_CLASSES:
            raise ValueError(f"Unknown vehicle class: {v}")
        return v

# good — dataclass for a small internal value type
from dataclasses import dataclass
from decimal import Decimal

@dataclass(frozen=True)
class PremiumBreakdown:
    base: Decimal
    discount: Decimal
    total: Decimal
```

## `Any` requires an inline comment

`Any` disables type checking at the point of use. It is occasionally the right answer — when integrating with untyped third-party libraries or when a type is genuinely dynamic — but the reason must be stated at the annotation so that reviewers can evaluate whether `Any` is justified or an annotation that should be tightened.

```python
# good — reason stated at the annotation
raw_payload: Any  # boto3 response dict; no stub available for this client
parsed = PayloadModel.model_validate(raw_payload)

# bad — Any with no explanation
raw_payload: Any
```

## Async for I/O

A synchronous blocking call inside an async function blocks the entire event loop for the duration of the call, eliminating the benefit of async concurrency. Keeping I/O operations async and computational functions synchronous preserves the functional core/imperative shell boundary and keeps the event loop unblocked.

```python
# good
async def fetch_policy(policy_id: str, client: AsyncHttpClient) -> Policy:
    response = await client.get(f"/policies/{policy_id}")
    return Policy.model_validate(response.json())

def score_policy(policy: Policy, rules: list[Rule]) -> float:
    # pure computation — synchronous
    return sum(rule.score(policy) for rule in rules) / len(rules)

# bad — blocking I/O inside an async function
async def fetch_policy(policy_id: str) -> Policy:
    response = requests.get(f"/policies/{policy_id}")  # blocks the event loop
    return Policy.model_validate(response.json())
```

## No magic strings or numbers

A raw literal like `"motor"` or `0.15` scattered through the codebase has no stable identity: it can be misspelled silently, duplicated inconsistently, and changed in one place while other callsites are missed. Named values give a single point of truth and let the type checker enforce valid inputs.

Choose the right representation for the situation:

- **`Enum`** — when the value is shared across modules, appears in API payloads or persisted data, or must be enforced at runtime.
- **`Literal`** — when the constraint is type-checker-only and the value does not cross a boundary (no serialisation, no database storage).
- **Module-level constant** — when the value is a single numeric or string scalar used in one module with no cross-boundary sharing.

```python
# good — Enum for a value that appears in API payloads and is persisted
from enum import StrEnum

class VehicleClass(StrEnum):
    MOTOR = "motor"
    COMMERCIAL = "commercial"
    FLEET = "fleet"

def calculate_base_rate(vehicle_class: VehicleClass) -> Decimal: ...

# good — Literal for a type-checker-only constraint (no serialisation needed)
from typing import Literal

def set_log_level(level: Literal["DEBUG", "INFO", "WARNING", "ERROR"]) -> None: ...

# good — module-level constant for a single scalar with local scope
MAX_RETRY_ATTEMPTS: int = 3
BASE_DISCOUNT_RATE: Decimal = Decimal("0.05")

# bad — magic strings scattered at call sites; misspelling is a silent bug
def calculate_base_rate(vehicle_class: str) -> Decimal:
    if vehicle_class == "moter":  # silent typo; no type checker catches this
        ...

# bad — magic number with no name; meaning is opaque
premium = base_rate * 0.15  # what does 0.15 represent?
```

## pytest and pytest-asyncio

pytest is the standard test runner across Python services. pytest-asyncio provides the event loop fixtures and `@pytest.mark.asyncio` decorator that async test functions require. Without it, async tests either fail to run or run synchronously and never actually exercise the awaited paths.

Mark the asyncio mode in `pyproject.toml` to avoid decorating every async test individually:

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

```python
# good — async test with pytest-asyncio (asyncio_mode = "auto")
async def test_fetch_policy_returns_model(client: AsyncMock) -> None:
    client.get.return_value = {"id": "p1", "status": "active"}
    result = await fetch_policy("p1", client)
    assert result.id == "p1"

# bad — sync wrapper around an async call; never awaits the coroutine
def test_fetch_policy_returns_model(client: Mock) -> None:
    result = fetch_policy("p1", client)  # returns a coroutine, not a Policy
    assert result.id == "p1"
```

## tests/unit/ and tests/integration/ layout

Unit tests are the exception, not the default. A test belongs in `tests/unit/` only when it tests a pure function or a piece of logic that genuinely has no external dependencies — a calculation, a transformation, a validation rule. Everything else goes in `tests/integration/`, which in practice means most tests.

Keeping the directories separate allows CI to run fast unit checks on every commit and defer integration runs to PR builds or nightly pipelines without any configuration changes to the test files themselves.

```
# good — directory layout
tests/
  unit/
    test_premium_calculator.py   # pure calculation logic; no I/O
    test_risk_score.py           # pure scoring function
  integration/
    test_policy_repository.py    # exercises the DB layer
    test_rate_service_client.py  # exercises the HTTP client
    test_pricing_service.py      # exercises the assembled service
```

## AsyncMock for async dependencies

When an async function is substituted with a plain `Mock`, calling it returns the mock object directly rather than a coroutine. Any `await` on that result raises a `TypeError` at runtime — or, worse, is silently swallowed depending on the test setup, giving a passing test that never actually ran the awaited code path.

`AsyncMock` returns a coroutine from every call, so `await dependency.method()` works as expected in the function under test.

```python
from unittest.mock import AsyncMock

# good — AsyncMock for an async dependency
async def test_update_policy_premium(policy_repo: AsyncMock, rate_service: AsyncMock) -> None:
    rate_service.fetch_base_rate.return_value = Decimal("100.00")
    policy_repo.get_risk_score.return_value = 1.2
    await update_policy_premium("p1", policy_repo, rate_service)
    policy_repo.save_premium.assert_awaited_once_with("p1", Decimal("120.00"))

# bad — plain Mock for an async dependency; await raises TypeError
async def test_update_policy_premium(policy_repo: Mock, rate_service: Mock) -> None:
    rate_service.fetch_base_rate.return_value = Decimal("100.00")  # not a coroutine
    await update_policy_premium("p1", policy_repo, rate_service)   # TypeError on await
```

## Factory fixtures for variations

A fixture that returns a fixed domain object forces tests that need a slightly different shape to either duplicate the construction inline or build their own fixture. A factory fixture — one that returns a callable — lets callers pass only the fields relevant to their case and keeps all default values in one place.

```python
import pytest

# good — factory fixture; callers override only what they care about
@pytest.fixture
def make_policy() -> Callable[..., Policy]:
    def _make(**overrides: Any) -> Policy:
        defaults = Policy(
            id="p1",
            vehicle_class=VehicleClass.MOTOR,
            inception_date=date(2026, 1, 1),
            status="active",
        )
        return defaults.model_copy(update=overrides)
    return _make

def test_commercial_vehicle_rate(make_policy: Callable[..., Policy]) -> None:
    policy = make_policy(vehicle_class=VehicleClass.COMMERCIAL)
    assert calculate_base_rate(policy) > Decimal("0")

# bad — duplicated construction in every test that needs a variant
def test_commercial_vehicle_rate() -> None:
    policy = Policy(
        id="p1",
        vehicle_class=VehicleClass.COMMERCIAL,
        inception_date=date(2026, 1, 1),
        status="active",
    )
    assert calculate_base_rate(policy) > Decimal("0")
```

## 95% coverage via pyproject.toml

A hard coverage floor prevents debt from accumulating silently. `fail_under = 95` in `pyproject.toml` applies to the whole codebase; diff-cover tightens the bar on newly written code so a PR cannot introduce untested lines even when the overall project is below 95%.

```toml
# pyproject.toml
[tool.coverage.run]
source = ["src"]
omit = [
    "src/myapp/main.py",       # entrypoint wiring only; no testable logic
]

[tool.coverage.report]
fail_under = 95
```

Run diff-cover in CI after the standard coverage report:

```bash
# good — CI step; fails if new lines in the PR are below threshold
coverage run -m pytest
coverage xml
diff-cover coverage.xml --compare-branch=origin/main --fail-under=95
```

## No inline coverage exclusions

`# pragma: no cover` at the line or block level is invisible in code review and tends to spread — once one file uses it, the pattern repeats. Centralising omissions in `pyproject.toml` makes the full list of excluded files visible in one place and forces a deliberate decision about each one.

The only files that belong in the omit list are pure startup wiring: entrypoints that call `uvicorn.run()`, signal handler registrations, `if __name__ == "__main__"` blocks. Any logic inside those files should be extracted into a testable function before the file is omitted.

```python
# bad — inline exclusion; invisible to reviewers scanning pyproject.toml
def _register_signal_handlers() -> None:  # pragma: no cover
    signal.signal(signal.SIGTERM, _handle_sigterm)
```

```toml
# good — omit at the config level, after extracting all testable logic
[tool.coverage.run]
omit = [
    "src/myapp/main.py",  # entrypoint only: uvicorn.run() call and signal registration
]
```

## No time.sleep() in async tests

`time.sleep()` is a blocking call. Inside an async test it suspends the OS thread, blocking the event loop for the full duration. This can cause other coroutines to time out, makes the test suite slower than necessary, and may mask race conditions that only appear with real async scheduling.

Use `asyncio.sleep()` to yield control back to the event loop, or mock the time source entirely when the test is checking timing logic.

```python
# good — yield to the event loop; other coroutines can run
async def test_retry_backs_off() -> None:
    with patch("myapp.client.asyncio.sleep") as mock_sleep:
        await client.fetch_with_retry("p1")
    mock_sleep.assert_awaited_once_with(1.0)

# bad — blocks the event loop for one second
async def test_retry_backs_off() -> None:
    await client.fetch_with_retry("p1")
    time.sleep(1)  # blocks the event loop
    assert client.call_count == 2
```

## LocalStack for AWS integration tests

LocalStack runs a local AWS emulator that accepts real boto3 API calls, validates parameters, and persists data in memory — a test that passes against LocalStack gives meaningful evidence that the production AWS interaction will work. Inject boto3/aioboto3 clients with `endpoint_url="http://localhost:4566"` so the same client code runs in tests and production.

```python
import boto3
import pytest

# good — real boto3 client pointed at LocalStack; exercises real API calls and validation
@pytest.fixture
def s3_client():
    return boto3.client(
        "s3",
        endpoint_url="http://localhost:4566",
        region_name="eu-west-1",
        aws_access_key_id="test",      # dummy credentials — valid for LocalStack only; never use outside test fixtures
        aws_secret_access_key="test",  # dummy credentials — valid for LocalStack only; never use outside test fixtures
    )

async def test_policy_saved_to_s3(s3_client) -> None:
    s3_client.create_bucket(
        Bucket="policies",
        CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
    )
    repo = S3PolicyRepository(bucket="policies", client=s3_client)
    await repo.save(Policy(id="p1", status="active"))
    obj = s3_client.get_object(Bucket="policies", Key="p1.json")
    assert json.loads(obj["Body"].read())["status"] == "active"
```

```yaml
# docker-compose.yml — pin to 4.14; versions after 4.14 require mandatory account registration
services:
  localstack:
    image: localstack/localstack:4.14
    ports:
      - "4566:4566"
```

## No boto3 mocks

A hand-rolled boto3 mock patches the call site (`client.put_object`, `client.put_item`) and asserts on exact arguments. If the implementation switches from `put_object` to `upload_file` the test breaks even though the behaviour is unchanged — and it accepts parameters the real AWS API would reject, so tests pass on code that would fail in production.

`AsyncMock` is appropriate only at a `Protocol` boundary: when the component under test depends on an abstraction (a publisher protocol, an event emitter) and the test is verifying call dispatch, not that data was actually written to AWS. Do not use `AsyncMock` to stand in for a real DynamoDB table, S3 bucket, or Kinesis stream.

```python
# good — AsyncMock at a Protocol boundary; tests that the right event is dispatched
async def test_event_published_on_save(mock_publisher: AsyncMock) -> None:
    service = PolicyService(publisher=mock_publisher)
    await service.save(Policy(id="p1", status="active"))
    mock_publisher.publish.assert_awaited_once_with(PolicySavedEvent(policy_id="p1"))

# bad — hand-rolled mock; couples test to put_object call signature
def test_policy_saved_to_s3(mock_s3_client: Mock) -> None:
    repo = S3PolicyRepository(client=mock_s3_client)
    repo.save(Policy(id="p1", status="active"))
    mock_s3_client.put_object.assert_called_once_with(
        Bucket="policies", Key="p1.json", Body=ANY  # breaks if impl switches to upload_file
    )
```

## Pydantic BaseSettings as config entry point

`docs/ai/steering/base/environment.md` requires a single config entry point for all environment variable reads. In Python, this is a Pydantic `BaseSettings` class. All environment variables must be read through this class — never call `os.getenv()` or `os.environ[]` outside it, because scattered reads are invisible to the type system, bypass validation, and cannot be discovered by reading one file.

The config model should be instantiated once in the composition root and injected into components that need it. Do not instantiate `BaseSettings` per-request — each instantiation re-reads the environment and re-validates.

```python
# good — single config model, instantiated once
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class Configuration(BaseSettings):
    model_config = SettingsConfigDict(env_nested_delimiter="__")

    port: int = 8080
    log_level: str = "INFO"
    dynamo: DynamoConfiguration
    pm: PMConfiguration

config = Configuration()  # once, in the composition root

# bad — os.getenv scattered in business logic
def get_score(customer_id: str) -> float:
    table_name = os.getenv("DYNAMO_TABLE_NAME")  # untyped, unvalidated, invisible
    ...
```

```python
# bad — re-instantiating BaseSettings per request
def handle_request(request):
    config = Configuration()  # re-reads env and re-validates on every call
    ...
```

## Nested config groups with `env_nested_delimiter`

A flat config class with thirty fields forces the reader to scan every field to find the one they need. Grouping related fields into nested `BaseModel` classes creates a table of contents: `dynamo.*` for DynamoDB settings, `pm.*` for policy management, `kafka.*` for event streaming.

The `env_nested_delimiter="__"` setting maps `DYNAMO__TABLE_NAME` to `Configuration.dynamo.table_name`. Use double underscores consistently in env files and GitOps values.

```python
# good — grouped by concern
class DynamoConfiguration(BaseModel):
    region: str = "eu-west-1"
    table_name: str

class PMConfiguration(BaseModel):
    base_url: str
    timeout_seconds: int = 30

class Configuration(BaseSettings):
    model_config = SettingsConfigDict(env_nested_delimiter="__")

    dynamo: DynamoConfiguration
    pm: PMConfiguration
    log_level: str = "INFO"

# bad — flat; unreadable at scale and no logical grouping
class Configuration(BaseSettings):
    dynamo_region: str
    dynamo_table_name: str
    pm_base_url: str
    pm_timeout_seconds: int
    log_level: str
```

## `secrets_dir` for filesystem-mounted secrets

Secrets provisioned via `secrets-config` are mounted at `/mnt/<service-name>` by the Blueprint infrastructure. Pydantic `BaseSettings` supports reading these natively via `secrets_dir`. Set it to the mount path and Pydantic will read files whose names match field names.

```python
# good — secrets read from mounted filesystem
class Configuration(BaseSettings):
    model_config = SettingsConfigDict(
        env_nested_delimiter="__",
        secrets_dir="/mnt/score-per-product",
    )

    db_password: str          # read from /mnt/score-per-product/db_password
    api_key: str              # read from /mnt/score-per-product/api_key
    port: int = 8080          # read from env var, not a secret

# bad — secrets passed as environment variables
class Configuration(BaseSettings):
    db_password: str          # DB_PASSWORD in the env; visible in pod spec and process listing
```

## Env file loading with `SettingsConfigDict`

`docs/ai/steering/base/environment.md` requires committed development/CI config files plus a gitignored personal override. In Python, configure Pydantic to load `.env.development` as the base and `.env` as the override — later entries in the tuple take precedence:

```python
class Configuration(BaseSettings):
    model_config = SettingsConfigDict(
        env_nested_delimiter="__",
        env_file=(".env.development", ".env"),  # .env overrides .env.development
    )
```

This is not the only valid approach. Some services (e.g. zego-credit) handle env file switching at the docker-compose level and use `zego.core.configuration.load` rather than `BaseSettings` directly — that works just as well provided the env file layout and gitignore rules from `docs/ai/steering/base/environment.md` are followed.

## pytest-dotenv for test configuration

Configure `pytest-dotenv` to load `.env.development` for tests so that test runs pick up the same safe defaults as local development without requiring manual env setup:

```toml
# pyproject.toml
[tool.pytest.ini_options]
env_files = ".env.development"
```

## OTel instrumentors in `pyproject.toml`; run under `opentelemetry-instrument`

`opentelemetry-instrument` activates whichever instrumentors the lockfile has synced into the environment at process start, so `pyproject.toml` is the contract for what telemetry the service emits. Add `opentelemetry-distro` (which provides the CLI entrypoint and a no-op SDK setup), `opentelemetry-exporter-otlp` (the distro only bundles it via the `[otlp]` extra, so list it explicitly), and a per-framework instrumentor for each library actually in use — for FastAPI services that is typically `opentelemetry-instrumentation-fastapi` and `opentelemetry-instrumentation-httpx`. The OTel Python ecosystem ships on two version lines that must move together: api/sdk/exporter on `1.x` and instrumentation/semantic-conventions on `0.x`. Bump them in the same change; mixing lines produces import-time `TypeError`s at boot. The service is then launched with `opentelemetry-instrument python -m <app>` (or the equivalent Dockerfile `CMD`). Keep any in-app wiring minimal: a targeted instrumentor hook (for example a request hook stripping query-string PII off recorded URLs) is fine, but a parallel `TracerProvider` / exporter setup duplicating what the entrypoint already configures is not.

## See Also

- [../base/logging.md](../base/logging.md) — logging conventions: levels, structured log calls, PII rules, and Zego common keys.
- [../base/observability.md](../base/observability.md) — metrics and distributed tracing conventions.
- [../base/testing.md](../base/testing.md) — testing principles and structure: test types, naming, assertion style, and what belongs in each layer.
- [../base/environment.md](../base/environment.md) — language-agnostic environment variable conventions: single config entry point, GitOps sequencing, secrets-config provisioning.

---
version: 1.0
last_reviewed: 2026-06-30
---

# Kotlin Standards

Concurrency, safety, and testing conventions for Kotlin. Apply these rules to any Kotlin file you write or modify. Formatting and line length are enforced mechanically by the repo's formatter (ktlint / detekt / Spotless) and are not re-described here. Logging conventions are owned by `docs/ai/steering/base/logging.md`; observability and tracing by `docs/ai/steering/base/observability.md`; testing principles by `docs/ai/steering/base/testing.md` (Kotlin-specific testing patterns are covered in this file); and where broad catches belong (boundaries only) by `docs/ai/steering/base/error-handling.md`.

**Repo-specific conventions live elsewhere:** module layering, the dependency-injection framework (Hilt, Koin, manual composition root), the UI framework (Compose and its lifecycle/collection helpers), the logging infrastructure, and the build/CI topology are owned by the consumer repo's architecture/domain standard (where one exists); the concrete build/test command sequence and the configuration/secrets handling are owned by the consumer repo's `CLAUDE.local.md`. This file holds only the stack-agnostic Kotlin rules.

## Rules at a Glance

1. **Never let a coroutine swallow `CancellationException`.** A broad `catch` (or `runCatching`) in a suspend context catches `CancellationException`, which breaks structured concurrency — a cancelled coroutine is reported as a failure instead of propagating cancellation. Re-throw it explicitly, or wrap broad catches in a cancellation-aware helper. *Where* a broad catch belongs (boundaries only) is owned by `error-handling.md`.
2. **Confine I/O to an injected dispatcher.** Wrap network, persistence, and file work in `withContext(ioDispatcher)` where `ioDispatcher` is injected as a constructor parameter — never reference `Dispatchers.IO` directly, so the dispatcher can be replaced in tests.
3. **Keep `Flow`s cold; collect at the edge.** Repositories and use cases return a cold `Flow`; do not call `stateIn` or `launchIn` below the layer that owns the collection lifetime.
4. **`sealed interface` over `sealed class` for closed type hierarchies.** Interfaces allow multiple implementation without the constructor overhead of an abstract class.
5. **`data object` for argument-free variants.** Use `data object` (not plain `object`) so `equals`, `hashCode`, and `toString` behave correctly when the value is compared or logged.
6. **Extension functions for domain mappers.** `.toDomain()` is an extension on the DTO, not a method or companion function on the domain model — the DTO is the caller, the domain model is the result.
7. **Nullable return type communicates optionality.** `.toDomain(): T` means the value is required and throws on absence; `.toDomain(): T?` means null is a valid outcome. Express it in the return type, not a comment.
8. **`runTest` + `advanceUntilIdle()` for coroutine tests.** Use `runTest` for every test that launches coroutines, and drain pending work with `advanceUntilIdle()` before asserting.
9. **Inject a test dispatcher for the I/O dispatcher in tests.** Substitute `UnconfinedTestDispatcher` (or `StandardTestDispatcher` when you need explicit control) for the injected I/O dispatcher.

---

## Coroutines

### Cancellation-safe error handling

`runCatching` is `inline` and does catch exceptions thrown by suspending calls — but it also catches `CancellationException`. In structured concurrency, `CancellationException` is the signal that a coroutine has been cancelled; swallowing it converts a cancelled coroutine into a `Result.failure`, so cancelled work appears to "fail" (or worse, appears to succeed) instead of unwinding. Any broad catch in a suspend context must re-throw `CancellationException`:

```kotlin
// bad — runCatching swallows CancellationException; a cancelled fetch looks like a failure
suspend fun fetchRewards(): Result<Rewards> = withContext(ioDispatcher) {
    runCatching { api.getRewards().toDomain() }
}

// good — re-throw cancellation, convert only genuine errors to a failure
suspend fun fetchRewards(): Result<Rewards> = withContext(ioDispatcher) {
    try {
        Result.success(api.getRewards().toDomain())
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }
}
```

A project-local cancellation-aware wrapper (a `runCatching` that re-throws `CancellationException` before catching) is a clean way to package this so the try/catch is not repeated at every call site — define it once in the boundary layer. This rule governs only *cancellation safety*; *where* a broad catch is permitted at all (application boundaries, not scattered below them) is owned by `error-handling.md`.

### Confine I/O to an injected dispatcher

All I/O — network, persistence, file access — must run on an injected dispatcher rather than `Dispatchers.IO` referenced directly. Injecting it as a constructor parameter lets a test substitute a test dispatcher and removes the hidden dependency on the real IO thread pool:

```kotlin
// good — injected, testable
class RewardsRepository(
    private val api: RewardsApi,
    private val ioDispatcher: CoroutineDispatcher,
) {
    suspend fun fetchRewards() = withContext(ioDispatcher) { /* ... */ }
}

// bad — hardcoded; cannot be controlled or replaced in a unit test
class RewardsRepository(private val api: RewardsApi) {
    suspend fun fetchRewards() = withContext(Dispatchers.IO) { /* ... */ }
}
```

The qualifier or binding used to provide the dispatcher (a DI annotation, a named binding, a manual factory) is repo-specific and owned by the consumer repo's architecture standard — this rule only requires that the dispatcher is injected, not sourced inline.

### Keep `Flow`s cold; collect at the edge

Prefer `Flow` for values that change over time (cache observations, persisted reads). Keep the chain cold — do not call `stateIn` or `launchIn` inside a repository or use case; let the layer that owns the collection lifetime decide when to start and stop collecting:

```kotlin
// good — repository returns a cold Flow; the collector owns its lifetime
fun rewards(): Flow<Rewards?> = store.rewardsFlow().map { it?.toDomain() }

// bad — repository eagerly hot-collects, tying the Flow's lifetime to the repo's scope
val rewards: StateFlow<Rewards?> = store.rewardsFlow()
    .map { it?.toDomain() }
    .stateIn(repoScope, SharingStarted.Eagerly, null)
```

---

## Kotlin idioms

### `sealed interface` for closed type hierarchies

Use `sealed interface` for any closed set of variants (actions, events, results, states). Prefer `data object` for variants that carry no data and `data class` for variants that do:

```kotlin
sealed interface RewardsResult {
    data object Loading : RewardsResult
    data class Loaded(val rewards: Rewards) : RewardsResult
    data class Failed(val cause: Throwable) : RewardsResult
}
```

A `sealed interface` permits a variant to implement more than one hierarchy and avoids the abstract-constructor overhead a `sealed class` imposes.

### `data object` for argument-free variants

```kotlin
// good — data object: correct equals/hashCode and a useful toString ("Loading")
data object Loading : RewardsResult

// bad — plain object: compares by identity and prints "RewardsResult$Loading@1a2b3c"
object Loading : RewardsResult
```

### Extension functions for mappers

Mappers are extension functions on the DTO, not static methods or companion functions on the domain model:

```kotlin
// good — extension on the DTO; the DTO is the caller, the domain model is the result
fun RewardsDto.toDomain(): Rewards = Rewards(
    id = id ?: throw RewardsMappingException("Rewards.id is required"),
    points = points ?: 0,
    tier = tier,
)

// bad — companion factory couples the domain model to the DTO
companion object {
    fun fromDto(dto: RewardsDto): Rewards = /* ... */
}
```

A throwing mapper is intentional: the exception propagates up to the boundary, where it is converted to a `Result.failure` (see *Cancellation-safe error handling*) and handled there.

### Nullable return type as contract

The return type of a mapper communicates whether null is a valid outcome. Do not convey it with a comment — express it in the type:

```kotlin
fun RewardsDto.toDomain(): Rewards      // required — throws if absent
fun TierDto.toDomainOrNull(): Tier?     // optional — null is a valid value
```

---

## Testing

### `runTest` and `advanceUntilIdle`

Every test that launches coroutines uses `runTest`. Call `advanceUntilIdle()` before asserting so all launched work has run to completion:

```kotlin
@Test
fun `fetchRewards returns the mapped domain model`() = runTest {
    val result = repository.fetchRewards()
    advanceUntilIdle()

    assertEquals(100, result.getOrNull()?.points)
}
```

### Inject a test dispatcher for the I/O dispatcher

Provide `UnconfinedTestDispatcher` (or `StandardTestDispatcher` when you need explicit control over advancement) in place of the injected I/O dispatcher:

```kotlin
private val testDispatcher = UnconfinedTestDispatcher()

private val repository = RewardsRepository(
    api = fakeApi,
    ioDispatcher = testDispatcher,
)
```

`UnconfinedTestDispatcher` runs coroutines eagerly, so I/O-bound paths do not need an explicit `advanceUntilIdle()` when the test only asserts on the final state.

---

## See Also

- [../base/testing.md](../base/testing.md) — testing philosophy: integration-first, mock at the boundary, real domain objects in fixtures.
- [../base/logging.md](../base/logging.md) — logging conventions: levels, structured calls, PII rules.
- [../base/observability.md](../base/observability.md) — metrics and distributed tracing conventions.
- [../base/error-handling.md](../base/error-handling.md) — custom domain exceptions, catch-specific patterns, broad catches at boundaries only, never swallow.

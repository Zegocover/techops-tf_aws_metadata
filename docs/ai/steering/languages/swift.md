---
version: 1.0
last_reviewed: 2026-06-26
---

# Swift Standards

Style, safety, and testing conventions for Swift. Apply these rules to any Swift file you write or modify. Formatting and line length are enforced mechanically by SwiftLint (`.swiftlint.yml`) and are not re-described here. Logging conventions are owned by `docs/ai/steering/base/logging.md`; observability and tracing by `docs/ai/steering/base/observability.md`; testing principles by `docs/ai/steering/base/testing.md` (Swift-specific testing patterns are covered in this file); environment-variable principles by `docs/ai/steering/base/environment.md`.

**Repo-specific conventions live elsewhere:** module layering, dependency-injection pattern, build/CI topology and the architecture rules are owned by the consumer repo's architecture/domain standard (where one exists); the concrete build/test command sequence and the configuration/secrets handling are owned by the consumer repo's `CLAUDE.local.md`. This file holds only the stack-agnostic Swift rules.

## Rules at a Glance

1. **Never force unwrap or force cast.** `!` and `as!` are SwiftLint errors where the config enables them. Use `guard let`, `if let`, `try?`, `??`, or a precondition with an explicit failure message — silent crashes from a force-unwrap are the single biggest source of preventable production incidents in a Swift codebase.
2. **Explicit type annotations on empty collections.** `let items: [String] = []`, never `let items = []` — the inferred type is `[Any]`, which the SwiftLint custom rule `array_constructor` flags and which silently degrades later type checks.
3. **`async`/`await` for new asynchronous code.** Combine remains valid when extending an existing publisher graph; prefer `async`/`await` for new network calls and side effects. Wrap entry points back into the UI in `Task { @MainActor in … }`.
4. **`@MainActor` on types that own `@Published` / UI-bound state.** A `@Published` update from a background queue is a runtime hazard SwiftUI does not always surface — annotate the type, not individual methods, so the constraint is enforced statically.
5. **`weak self` in escaping closures.** Closures captured by long-lived storage (subscriptions, task handles, callbacks) must capture `self` weakly — anything else is a retain cycle in waiting.
6. **Imports: deduplicated and unused ones removed.** `unused_import` is a SwiftLint rule; honour it. Grouping (standard → third-party → local) is a nice-to-have, not a hard requirement.
7. **No magic strings or numbers.** Replace raw literals that carry domain meaning with `enum` cases, named `let` constants, or strongly typed identifiers — named values make intent explicit and prevent silent drift.
8. **`///` for public documentation, `//` for inline.** Doc comments precede `public` and `open` declarations; explain *why* the interface exists, not *what* the code does.
9. **XCTest with AAA structure, mirror the source tree.** Tests live under `*Tests` targets that mirror the source layout; each test follows Arrange → Act → Assert; test names describe behaviour ("`testActivatingPolicyEmitsEvent`"), not method names ("`testActivate`").
10. **Mock at the dependency-injection boundary, never internal classes.** Substitute protocol-typed dependencies at the injection seam (e.g. an `Environment`/dependencies struct); never subclass a concrete production type and override methods in tests.
11. **Build real domain objects in test factories.** Factories return live model instances using production constructors; never return literal dictionaries or unchecked stubs as stand-ins.
12. **Snapshot tests for view layout, with reference images committed.** Use the codebase's chosen snapshot library; commit reference snapshots; never enable record mode in committed code.
13. **Format before lint.** Run `swiftlint --fix` before `swiftlint`. The fix pass auto-resolves style violations the check pass would otherwise wall-of-failure on.

## Never force unwrap or force cast

A force unwrap (`x!`) crashes the app with `Fatal error: Unexpectedly found nil` and no domain context. A force cast (`x as! T`) crashes with `Could not cast value`. Both leave the user staring at a closed app and the on-call engineer staring at a stack trace stripped of meaning. Where the SwiftLint config treats `force_unwrapping` and `force_cast` as **errors**, they fail the build.

Use `guard let` to extract optionals at the top of a function and exit early; `if let` for optional binding when the work continues either way; `??` for default values; `try?` for converting errors to optionals at a boundary; or a `precondition` with a meaningful message when the absence really is a programmer bug.

```swift
// good — guard early, exit with a domain-meaningful error
guard let userId = response.user?.id else {
    return .failure(.missingUserId)
}

// good — default value at the call site
let displayName = profile.displayName ?? "Anonymous"

// good — precondition with message when the invariant is enforced elsewhere
guard let route = coordinator.configuredRoute else {
    preconditionFailure("Coordinator must have configured a route before binding")
}

// bad — force unwrap; crashes silently in production
let userId = response.user!.id

// bad — force cast; crashes silently when the type assumption is wrong
let viewModel = anyController as! ProfileViewModel
```

`try!` is a *warning* in SwiftLint, not an error, but treat it the same way unless you can demonstrate the call genuinely cannot throw (e.g. a `Data(contentsOf:)` against a bundled resource you wrote).

## Explicit type annotations on empty collections

An empty literal without an annotation infers `[Any]` or `[String: Any]`, which compiles but silently weakens every later type check that touches the value. The SwiftLint custom rule `array_constructor` flags this pattern.

```swift
// good
let items: [String] = []
let lookup: [String: Item] = [:]
var pending: Set<UUID> = []

// bad — inferred as [Any]; silently weak typing
let items = []
let lookup = [:]
```

This applies to function defaults and stored properties as well.

## `async`/`await` for new asynchronous code

Combine is still the right tool when you are extending an existing publisher graph. For new network calls, side effects, and view model actions, prefer `async`/`await` — it composes more cleanly with `Task`, propagates cancellation correctly, and integrates with the Swift Concurrency model SwiftUI now expects.

```swift
// good — async call from a @MainActor view model action handler
@MainActor
final class ContentViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var error: LoadError?
    private let service: ItemServiceProtocol

    func onAppear() {
        Task { [weak self] in
            guard let self else { return }
            do {
                self.items = try await self.service.loadItems()
            } catch {
                self.error = .loadFailed(error)
            }
        }
    }
}

// bad — blocking new work on a Combine .sink
// (acceptable in legacy code that already uses Combine throughout; not for new work)
service.loadItemsPublisher()
    .receive(on: DispatchQueue.main)
    .sink(...)
    .store(in: &cancellables)
```

Wrap UI entry points in `Task { @MainActor in … }` and capture `self` weakly — see Rule 5.

## `@MainActor` on types that own `@Published` / UI-bound state

A `@Published` property emits change notifications synchronously to SwiftUI. Mutating one from a background queue is undefined behaviour: sometimes SwiftUI catches it with a runtime warning, sometimes the UI updates from the wrong thread, sometimes nothing happens until the next view body evaluation reveals stale state. Annotate the entire type with `@MainActor` so the constraint is enforced at compile time, not at runtime.

```swift
// good — type-level @MainActor; every member is main-actor isolated
@MainActor
final class ContentViewModel: ObservableObject {
    @Published var state: ViewState
    ...
}

// bad — only the published property is annotated; background callers compile but corrupt state
final class ContentViewModel: ObservableObject {
    @MainActor @Published var state: ViewState
    ...
}
```

## `weak self` in escaping closures

Any closure that escapes the call site — stored in a property, registered as a callback, attached to a `Task`, retained by a Combine subscription — risks a retain cycle if it captures `self` strongly. The closure holds `self`; `self` holds the closure indirectly through `cancellables` or the task handle; nothing ever releases.

```swift
// good — weak self, guard at the top
publisher.sink { [weak self] value in
    guard let self else { return }
    self.handle(value)
}.store(in: &cancellables)

// good — same pattern in a Task closure
Task { [weak self] in
    guard let self else { return }
    await self.refresh()
}

// bad — strong self captured by a long-lived subscription
publisher.sink { value in
    self.handle(value)
}.store(in: &cancellables)
```

Short-lived closures that do not escape (e.g. `map`, `filter`, the trailing closure of `withCheckedContinuation`) do not need this treatment.

## Imports: deduplicated and unused ones removed

The only enforced rule is `unused_import` (SwiftLint) — every import should be used. Beyond that, grouping is a stylistic preference: if you find it helpful, the conventional order is standard libraries → third-party frameworks → local modules, optionally separated by a blank line.

```swift
import Foundation
import SwiftUI

import SomeThirdPartyFramework

import AppCore
import AppNetworking
```

Do not refactor existing imports just to apply this layout, and do not block a review on grouping — no tool enforces it.

## No magic strings or numbers

Raw string and numeric literals that carry domain meaning rot quickly: a misspelling is silent, a value change requires grep-and-replace, and the intent of `0.05` is opaque to readers. Replace them with named values:

```swift
// good — enum for a value with multiple call sites and a finite domain
enum Product: String {
    case van
    case taxi
    case bike
}

// good — module-level constant for a single scalar
private let renewalLeadTime: TimeInterval = 14 * 24 * 60 * 60   // 14 days in seconds

// good — typed identifier rather than a raw String
struct PolicyID: Hashable, RawRepresentable { let rawValue: String }

// bad — string used as a domain value across the codebase
analytics.log(event: "item_accepted")   // misspelled in three places already
repository.find(productType: "van")      // typo here will silently return nothing

// bad — magic number with no name
return base * 1.075
```

## `///` for public documentation, `//` for inline

Doc comments precede `public` and `open` declarations and explain *why* the interface exists, not *what* the code does (the signature already says that). Inline comments use `//` with one space after the slashes. Keep them sparse — well-named identifiers do most of the work.

```swift
/// Returns the renewal quote for `policy`, refreshing the rating if cached values are
/// older than the renewal lead time defined by the upstream pricing service.
public func renewalQuote(for policy: Policy) async throws -> Quote { ... }
```

Restating the code (`/// Fetches the renewal quote for the given policy`) adds nothing.

## XCTest with AAA structure, mirror the source tree

Test files live under `*Tests` targets that mirror the layout of the source. Each test is named for the behaviour it asserts and structured as Arrange / Act / Assert:

```swift
final class ContentViewModelTests: XCTestCase {

    func testOnAppearLoadsItemsFromService() async {
        // Arrange
        let stub: [Item] = [.fixture(id: "1"), .fixture(id: "2")]
        let sut = ContentViewModel(service: FakeItemService(returning: stub))

        // Act
        sut.onAppear()
        await sut.waitForLoadComplete()

        // Assert
        XCTAssertEqual(sut.items.map(\.id), ["1", "2"])
    }
}
```

## Mock at the dependency-injection boundary, never internal classes

Inject protocol-typed dependencies at the injection seam — an `Environment`/dependencies struct, an initialiser parameter, or a service interface — and substitute a fake there in tests. The type under test and its internal collaborators run real.

Never subclass a concrete production class and override methods for testing. Doing so means the test exercises your override, not the production code — a class of bug that masks broken production behaviour with a passing test suite. Protocol-conforming fakes substituted at the boundary do not have this problem because they implement the same protocol the production code consumes.

```swift
// good — protocol-typed dependency injected at the boundary, faked in tests
struct ContentEnvironment {
    var itemService: ItemServiceProtocol
    var analytics: AnalyticsProtocol
}

let environment = ContentEnvironment(
    itemService: FakeItemService(returning: stub),
    analytics: FakeAnalytics()
)

// bad — subclassing the concrete production type to override a method
final class TestableViewModel: ContentViewModel {
    override func loadItems() async { /* override */ }
}
```

## Build real domain objects in test factories

A factory that returns a real `Item` (or `Policy`, or `Customer`) using the production constructor will break loudly if the constructor changes — which is correct. A factory that returns a stub dictionary, a JSON literal, or a partial mock object will silently pass even when the domain model's contract has been broken.

```swift
// good — uses the real constructor; breaks loudly if the contract changes
extension Item {
    static func fixture(
        id: String = "1",
        name: String = "Sample",
        price: Decimal = 1.00
    ) -> Item {
        Item(id: .init(rawValue: id), name: name, price: price)
    }
}

// bad — returning a partial stub that diverges from the real type
struct StubItem {
    let id: String
    let price: Decimal
}
```

If a domain object is too expensive to construct in tests, the signal is that the type has too many required dependencies — fix the design, not the test.

## Snapshot tests for view layout, with reference images committed

Snapshot tests verify that a SwiftUI view produces the expected image given a fixed state. Use the codebase's chosen snapshot library (typically `swift-snapshot-testing`). Commit the generated reference images so CI compares against them.

Never enable record mode in committed code (`assertSnapshot(matching:as:record: true)`); record mode regenerates the reference on every run and silently masks regressions. Record locally, inspect the diff, then turn record mode off before committing.

## Format before lint

SwiftLint exposes both an auto-fix pass (`swiftlint --fix`) and a check pass (`swiftlint`). The fix pass resolves the style violations the check pass would otherwise flag. Running them in the wrong order produces a wall of failures that the fix pass would have silenced — a waste of attention.

```bash
# good — format first, then verify
swiftlint --fix && swiftlint

# bad — lint first against unformatted code; wall of fixable failures
swiftlint
# 47 violations
swiftlint --fix
swiftlint
```

## See Also

- [base/testing.md](../base/testing.md) — testing philosophy (integration-first, mock at the boundary, real domain objects in fixtures).
- [base/logging.md](../base/logging.md) — logging conventions: levels, structured calls, PII rules.
- [base/observability.md](../base/observability.md) — observability conventions: three-signal coverage, semantic conventions, span attributes.
- [base/environment.md](../base/environment.md) — configuration principles: single entry point, document available variables, never commit secrets.
- The consumer repo's architecture/domain standard, where one exists — module layering, dependency-injection pattern, build/CI topology, navigation.
- The consumer repo's `CLAUDE.local.md` — repo-specific build/test command sequence, configuration layering, and secrets handling.

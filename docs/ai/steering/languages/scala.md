---
version: 1.1
last_reviewed: 2026-06-23
---

# Scala Standards

Structural and architectural conventions for Scala 2.13 services — how business logic is organised, dependencies are wired, types are expressed, errors are propagated, and tests are written. The governing philosophy is **functional core, imperative shell**: pure domain logic in `domain/`, framework-owning adapters at the edge, all wired by hand in `application/`. Apply these rules to any Scala file you write or modify. Formatting (`scalafmt`) and import organisation / unused-import removal (`scalafix`) run automatically on compile and are not covered here; logging conventions are owned by `docs/ai/steering/base/logging.md`; observability and tracing by `docs/ai/steering/base/observability.md`; testing principles by `docs/ai/steering/base/testing.md`.

## Rules at a Glance

1. **Functional core, imperative shell.** Keep business logic in pure functions inside `domain/`; push all I/O (database, gRPC, AWS, Akka actors) to outer modules (`application/`, `*-adapter/`, `akka/`, `grpc/`) — pure functions are trivially testable and isolate the expensive parts.
2. **Composition root in `application/`.** Wire the full object graph once at startup in `Application.init(config)` via constructor injection; never use service locators, framework DI (`guice`, `macwire`), or mid-request dependency lookups — the dependency graph must be greppable and startup-only.
3. **`object` for stateless modules; `final class` for stateful collaborators.** A top-level `object` is the Scala module — use it for pure functions and constants. Use a `final class` (with constructor-injected dependencies) only when the unit carries state or holds collaborators — `final` so it can't be subclassed accidentally, breaking equality and reasoning.
4. **No default arguments.** Constructor and method parameters must not have defaults. Force explicit arguments at every call site — defaults silently couple call sites to a value the author may not have considered, and adding a default later is a non-breaking-but-still-bad ergonomic crutch.
5. **Sealed trait ADTs over `Option` fields.** When a type has fields whose presence depends on a discriminator, model it as a `sealed trait` + `final case class` variants, not one `case class` with optional fields — makes illegal states unrepresentable at compile time.
6. **TODO with Jira reference.** Format every TODO as `// TODO(ABC-1234): …` — untracked TODOs rot.
7. **Imports at the top; ≤5 explicit imports per package.** All imports at file top; never inside methods. `.scalafix.conf` sets `coalesceToWildcardImportThreshold = 5` — if you'd need a 6th explicit import from one package, use a fully qualified reference at the call site instead. Wildcard imports cause ambiguity bugs when two packages export the same name (`zego.policymanagement.domain.model._` and `zego.protobuf.policymanagement.quote._` both define `PricingDiscount` — wildcard is a landmine).
8. **Scala naming.** `camelCase` for `val`/`def`/method params; `PascalCase` for types, objects, traits; `PascalCase` for `final val` constants too (the Scala style guide convention — never `UPPER_SNAKE_CASE`, which is a Java/Python import); package names `lower.dotted`. Exception: ScalaPB-generated enum values keep their generated casing and are outside this rule. Consistent naming is the baseline contract for readability.
9. **`cats-core` scope: `Validated` and `Either` only.** Use cats for `Validated[NEL[E], A]` (accumulating validations) and `Either` syntax extensions (`.asRight`, `.asLeft`, `.toEitherT` where applicable). Do **not** introduce `cats.Monad`, `cats.Traverse`, or any typeclass-driven generic abstraction unless a concrete win is documented in the PR. **Never** introduce `cats-effect` — the effect system is `scala.concurrent.Future` + Akka.
10. **No magic strings or numbers.** Domain-meaningful literals must be `final val` constants in a typed object, `enumeratum.EnumEntry` values, or sealed-trait `case object`s. A bare string `"GBP"` or number `30` in business logic is a smell — name it.
11. **Smart constructors return `Either[ValidationError, A]`.** Domain types with invariants (non-empty strings, non-negative ints, format-constrained IDs) expose a private constructor and a public `apply`/`make` that validates and returns `Either[ValidationError, T]`. **Never** rely on `require()` for domain invariants — `require` throws `IllegalArgumentException` which crosses the pure/effectful boundary backwards.
12. **`enumeratum` for closed value sets; sealed trait + case for ADTs; no wildcard catch-all on owned ADTs.** Closed sets of named values (with serialisation, lookup, Slick or JSON integration) → `enumeratum.Enum[T]` with `EnumEntry` + a single casing mixin (`Lowercase`/`Snakecase`/`Uppercase`) chosen once per type. Structural variants (each variant carries different fields) → `sealed trait` + `final case class`/`case object`. **Never** write `case _ =>` on an ADT we own — the compiler's exhaustiveness check is the value of sealed traits; the wildcard erases it. A catch-all is only acceptable for third-party sealed types we don't control.
13. **Service boundaries return `Future[Either[DomainError, A]]`.** Domain services and repositories expose `Future[Either[DomainError, A]]` (or the synchronous `Either[DomainError, A]` for pure functions). Sealed `DomainError` hierarchies per module (e.g. `WriteSideRepositoryError`, `NoPolicyWithPolicyId`) — never a bare `String` error, never a thrown exception across a domain boundary. `Throwable` is reserved for genuine infrastructure failures (network, DB connection lost) and surfaces at the gRPC layer for translation to `Status` codes.
14. **`scala.concurrent.Future` + Akka.** All asynchronous work uses `Future` and Akka primitives (`ActorSystem[_]`, Akka Streams, Akka Persistence). Do **not** introduce `cats-effect`, `monix`, or `ZIO`. The composition root acquires a single `ExecutionContext` from the Akka `ActorSystem`; `import system.executionContext` rather than `ExecutionContext.Implicits.global`.
15. **gRPC only, via Akka gRPC.** Service contracts are protobufs in [zego/protobuf](https://github.com/Zegocover/protobuf), Scala types generated by `akka-grpc-runtime`. The inbound surface lives in `grpc/`; outbound clients (e.g. `PolicyManagerServiceClient`) wire from the composition root. No separate HTTP/REST surface — health checks are gRPC (`zego %% health-akka-grpc`). If a one-off HTTP endpoint is genuinely needed (admin, debug), use `akka-http` — never introduce `http4s`, `play-server`, or any other HTTP stack.
16. **AWS SDK v2 wrapped behind adapter traits.** Domain code never touches `software.amazon.awssdk.*` directly. Every AWS client (`KinesisAsyncClient`, `S3AsyncClient`) is wrapped by a trait in `domain/` (e.g. `PolicyEventPublisher`, `S3DocumentStorage`) and implemented once in a `*-adapter/` module. This is what makes rule 19 (test stubs on the trait) and rule 20 (LocalStack for integration) possible.
17. **`AnyFunSpec` + `Matchers`; `describe` + `it("should …")`.** Test class extends `AnyFunSpec with Matchers`. Organise with `describe` blocks per feature/component and `it("should …")` per scenario. Test filenames end `*Spec.scala`. Unit tests under `<module>/src/test/scala/…`; integration tests under `integration-test/src/test/scala/…`.
18. **Property-based testing with ScalaCheck.** Mix in `ScalaCheckDrivenPropertyChecks` (generator-driven) and `TableDrivenPropertyChecks` (exhaustive enum/mapping). Always add `implicit def noShrink[T]: Shrink[T] = Shrink.shrinkAny` in the test class — ScalaCheck's default shrinking is slow and obscures failures.
19. **Hand-rolled stubs for domain ports; Mockito narrow for 3rd-party; never on AWS SDK clients.** For domain trait ports (e.g. `QuotesAdapter`, `WriteSideRepository`), write a hand-rolled stub implementing the trait (e.g. `StubQuotesAdapter`, `InMemoryWriteSideRepository`) kept next to the trait or in `test-support/`. For third-party libraries (Akka gRPC clients, etc.) use `scalatestplus-mockito` for the narrow surface — keep stubs to ≤3 `when(...).thenReturn(...)` per test; more means you should wrap the third-party in an adapter trait (rule 16) and stub the adapter. **Never** Mockito-stub an AWS SDK client directly — mocking async APIs and parameter validation produces false-positive tests.
20. **LocalStack via Testcontainers for AWS integration tests.** Integration tests use `testcontainers-scala` to spin up real AWS-API behaviour via LocalStack and PostgreSQL containers. Inject the real adapter (rule 16) pointed at the LocalStack endpoint, not a stub. **Never** stub an AWS call with `Future.successful(())` in any test — that bypasses every contract the SDK enforces.
21. **Black-box first; reuse `CommonGenerators`.** Test units through their public surface — domain services through their trait, codecs through `.decode`/`.encode` extensions, gRPC handlers through the generated service interface. Minimise white-box assertions on private internals. Reuse existing generators (`CommonGenerators`, domain-specific generators in `domain/.../generators/`) before rolling your own; new generators belong next to the existing ones, not in the test file that needed them first.
22. **95% project-total scoverage statement and branch; no inline coverage exclusions.** Coverage gate is project-total only: `Global / coverageMinimumStmtTotal := 95` (matching `Global / coverageMinimumBranchTotal := 95`) in `build.sbt`. Do not set the per-file thresholds (`coverageMinimumStmtPerFile`/`coverageMinimumBranchPerFile`) — per-file 95% is hostile to small files and pushes toward the inline exclusions this rule bans. Never add `// $COVERAGE-OFF$` / `// $COVERAGE-ON$` inline. Files genuinely outside the coverage envelope (pure wiring, generated code) go in the `coverageExcludedPackages`/`coverageExcludedFiles` build settings only.
23. **Akka actor tests via `akka-actor-testkit-typed`.** Test `Behavior`s with `BehaviorTestKit` (synchronous) or `ActorTestKit` (real `ActorSystem`); use `TestProbe[Message]` for actor-to-actor message assertions. Never Mockito-mock an `ActorRef[_]`. For event-sourced entity tests use `akka-persistence-testkit`.
24. **SLF4J `private val log` + MDC at gRPC entry; no log-and-throw.** Declare loggers as `private val log: Logger = LoggerFactory.getLogger(getClass)` — always named `log`, not `logger`. At every gRPC request entry point populate `MDC` with the stable identifiers in scope (`policy_id`, `quote_id`, `customer_id`); `MDC` is `ThreadLocal`, so capture a snapshot (`MDC.getCopyOfContextMap`) before the `Future` boundary, re-establish it inside the continuation that logs (continuations run on a different thread), and clear only *after* the log call — downstream log calls read `log.info("Policy bound")` and Datadog ingests the IDs automatically. Inline string interpolation `s"… ${variable}"` is acceptable for one-off context not worth promoting to MDC. **Never** both log an exception and throw/rethrow it — pick one. Cross-cutting principles (level usage, secrets redaction, PII) live in `docs/ai/steering/base/logging.md`.
25. **PureConfig single config entry point.** Configuration is loaded once at the composition root via `ConfigFactory.load()` and converted to typed case classes via `pureconfig.ConfigSource.default.loadOrThrow[ServiceConfig]`. Never call `ConfigFactory.load()` outside the composition root; never reach into raw `Config` from domain code. Secrets are file-mounted via the Blueprint chart conventions (`/mnt/<service>/<KEY>`) and read by PureConfig hints, not via `sys.env.get` scattered through the code.
26. **JSON library is repo-local; do not introduce a second.** Use the JSON tooling the repo already has; never add a peer library. Respect the incumbent library in every repo, and if a repo already uses a different JSON library, keep using it there — just don't add a second. For illustration, in `policy-management` the existing tooling is `akka-serialization-jackson` (Akka event-journal persistence — mandated by Akka) and **`circe`** (everywhere else: HTTP boundaries, codecs, domain serialisation), so extend the existing circe codecs rather than introducing `spray-json`, `play-json`, `jsoniter-scala`, or any other library.
27. **Centralised `project/Dependencies.scala`; one method per module.** All library coordinates and pinned versions live in `project/Dependencies.scala` as a `val <name>Version = "x.y.z"` constant plus a `def <module>Dependencies: Seq[ModuleID]`. `build.sbt` references only `Dependencies.<module>Dependencies` — never inlines a library coordinate. Same rule for `scalacOptions`: shared options go on `ThisBuild`; module-specific overrides explained with a one-line comment.
28. **Fixture pattern for complex test setups.** When ≥3 `it(...)` blocks share non-trivial setup (a stub adapter, a fake clock, a pre-populated repository), inline it into a `Fixture` class and `import f._` inside each block; for ≤2 blocks inline the setup in the block body — below that threshold a fixture adds indirection for no gain.
29. **Integration test setup.** Integration tests own their dependencies via `testcontainers-scala` started from within the test process — never depend on external orchestration (`docker-compose up`, a manually-started LocalStack, shared CI services); a clean checkout must pass `sbt "project integration-test; test"` with no other command, because a self-contained test is the only one that runs reliably in CI and on a fresh machine.
30. **Cinnamon modules in `build.sbt`; agent pinned via `sbt-cinnamon` plugin.** Add `sbt-cinnamon` to `project/plugins.sbt` so the Cinnamon agent is pinned at build time; declare each Cinnamon module the service uses (`Cinnamon.library.cinnamonAkka`, `Cinnamon.library.cinnamonAkkaStream`, `Cinnamon.library.cinnamonAkkaGrpc`, etc.) under `libraryDependencies` in `build.sbt` (via `project/Dependencies.scala` per rule 27) so the manifest names every instrumentor the service emits. Keep any in-app SDK or instrumentor wiring minimal, per `docs/ai/steering/base/observability.md` rule 4.

---

## Functional core, imperative shell

Business logic entangled with I/O can only be tested through the I/O layer — slow, flaky, expensive to set up. Pure domain functions get unit-tested with no mocks; I/O paths get integration-tested at the boundary.

```scala
// good — pure core, I/O at the edge
// domain/.../PolicyPricing.scala
object PolicyPricing {
  def adjustPremium(base: Money, discount: PricingDiscount): Money =
    base - discount.amount
}

// application/.../Application.scala wires it together
final class PolicyService(repo: WriteSideRepository, rates: RateClient)(implicit ec: ExecutionContext) {
  def updatePremium(policyId: PolicyId): Future[Either[DomainError, Unit]] =
    for {
      base     <- EitherT(rates.fetchBaseRate(policyId))
      discount <- EitherT(repo.getDiscount(policyId))
      premium   = PolicyPricing.adjustPremium(base, discount) // pure
      result   <- EitherT(repo.savePremium(policyId, premium))
    } yield result
}.value

// bad — pure logic buried inside I/O
def updatePremium(policyId: PolicyId): Future[Unit] =
  db.run(sql"SELECT base FROM rates WHERE policy_id = $policyId".as[Money]).flatMap { base =>
    val discount = db.run(sql"SELECT discount FROM policies …").value.get
    val premium  = base - discount.amount               // logic mixed with I/O
    db.run(sqlu"UPDATE policies SET premium = $premium …")
  }
```

## Composition root in `application/`

Mid-request DI hides the dependency graph from static analysis and tests. Wiring everything once at startup makes deps explicit and traceable.

```scala
// application/.../Application.scala
object Application {
  def init(config: Config): Future[Application] = {
    val infra = AkkaInfrastructure(name = "policy-management-service-system", config)
    implicit val system: ActorSystem[_] = infra.system
    import system.executionContext

    val pricingClient   = new GrpcPricingAdapter(GrpcClientSettings(...))
    val policyStateRepo = new AkkaWriteSideRepository(...)
    val policyService   = new PolicyService(policyStateRepo, pricingClient)
    val grpcServer      = new PolicyManagementServer(policyService, ...)
    // …
  }
}

// bad — service-locator pattern
object ServiceRegistry {
  lazy val policyService = new PolicyService(
    ServiceRegistry.policyStateRepo,  // hidden dependency
    ServiceRegistry.pricingClient
  )
}
```

## `object` for stateless modules; `final class` for stateful collaborators

```scala
// good — pure functions live on an object
object PolicyValidation {
  def checkRenewalEligible(policy: Policy, now: Instant): Either[ValidationError, Unit] = …
}

// good — stateful collaborator is a final class
final class GrpcPolicyStateAdapter(client: PolicyManagerServiceClient)(implicit ec: ExecutionContext)
  extends PolicyStateGateway { … }

// bad — abstract class with mutable singleton state
class PolicyValidator {  // mutable, allows subclassing, no constructor deps stated
  def check(policy: Policy): Boolean = …
}
```

## No default arguments

```scala
// good — explicit at the call site
final case class PolicyContext(driverId: DriverId, vehicleId: VehicleId, validFrom: Instant)
def renewPolicy(policy: Policy, context: PolicyContext): Future[Either[DomainError, Policy]] = …

// bad — defaulted parameter
def renewPolicy(policy: Policy, force: Boolean = false): Future[…] = …
//                                                ^ silent coupling at call sites; remove
```

## Sealed trait ADTs over `Option` fields

```scala
// bad — Option fields create ambiguous states
final case class DocumentEntry(
  assetUrl: Option[URI],
  generatorName: Option[String]
)

// good — ADT makes valid states explicit; pattern matches are exhaustive
sealed trait DocumentEntry
final case class StaticEntry(assetUrl: URI) extends DocumentEntry
final case class DynamicEntry(generatorName: String) extends DocumentEntry
```

## Imports at the top; ≤5 explicit imports per package

`.scalafix.conf` rewrites 6+ explicit imports from one package to wildcard. Wildcards conflict when two packages export the same type name (e.g. `quote._` and `model._` both export `PricingDiscount`). Keep explicit imports ≤5; if you need a 6th, use a fully qualified reference inline.

```scala
// good — explicit imports, ≤5 per package
import zego.policymanagement.domain.model.{Policy, PricingDiscount, Coverage}
// at the call site:
val proto: quote.PricingDiscount = quote.PricingDiscount(…) // FQ ref disambiguates

// bad — wildcard creates ambiguity
import zego.policymanagement.domain.model._
import zego.protobuf.policymanagement.quote._
val p = PricingDiscount(…)   // which one?
```

## `cats-core` scope: `Validated` and `Either` only

```scala
// good — accumulating validation
import cats.data.{Validated, ValidatedNel}
import cats.syntax.all._

def make(name: String, age: Int): ValidatedNel[ValidationError, Driver] =
  (checkStringNonEmpty(name, "name").toValidatedNel,
   checkIntNonNegative(age, "age").toValidatedNel
  ).mapN(Driver.apply)

// bad — introducing cats-effect or arbitrary typeclasses
import cats.effect.IO            // banned — use Future
import cats.Monad                // banned without explicit justification in PR
```

## Smart constructors return `Either[ValidationError, A]`

```scala
// good — private ctor, validated public apply
final case class PolicyNumber private (value: String) extends AnyVal
object PolicyNumber {
  def make(raw: String): Either[ValidationError, PolicyNumber] =
    if (raw.matches("[A-Z]{3}-\\d{6}")) Right(new PolicyNumber(raw))
    else Left(ValidationError(s"invalid policy number: $raw"))
}

// bad — `require` throws; can't compose; crosses the pure/effectful boundary backwards
final case class PolicyNumber(value: String) {
  require(value.matches("[A-Z]{3}-\\d{6}"), s"invalid policy number: $value")
}
```

The normative part is the technique: a private constructor and a validating `apply`/`make` returning `Either[ValidationError, A]`, never `require`. Where a repo already has shared validators, reuse them rather than rolling new ones — in `policy-management`, for illustration, these are `ModelsValidation.checkStringNonEmpty`/`checkIntNonNegative`/etc. in the `domain` module. A repo without such a module returns `Either[ValidationError, A]` from its own validators; do not invent a helper of that name to satisfy this rule.

## `enumeratum` for closed value sets; sealed trait + case for ADTs; no wildcard catch-all on owned ADTs

```scala
// good — closed value set with serialisation
import enumeratum._
sealed trait CancellationReason extends EnumEntry with EnumEntry.Snakecase
object CancellationReason extends Enum[CancellationReason] {
  case object CustomerRequest    extends CancellationReason
  case object FraudDetected      extends CancellationReason
  case object PaymentFailure     extends CancellationReason
  val values = findValues
}

// good — structural ADT
sealed trait CancellationOutcome
final case class Cancelled(at: Instant, refund: Money)            extends CancellationOutcome
final case class CancellationDeferred(reason: String)             extends CancellationOutcome
case object NothingToCancel                                       extends CancellationOutcome

// bad — wildcard catch-all on an ADT we own
outcome match {
  case Cancelled(_, _)            => …
  case CancellationDeferred(_)    => …
  case _                          => …   // erases exhaustiveness check; banned
}
```

## No magic strings or numbers

Three representations for a domain-meaningful literal. Use this guide to pick:

| Need | Representation | Why |
|---|---|---|
| Serialised to JSON / DB / proto, or looked up by name (`Enum.withName("…")`), or iterated (`Enum.values`) | `enumeratum.Enum[T]` with `EnumEntry` + a casing mixin | First-class registry, integrations with Slick / JSON, free `.entryName` for serialisation, exhaustiveness preserved when pattern-matched. |
| Internal discriminator with no serialisation need and no name lookup | `sealed trait` + `case object` | Cheapest possible representation; full exhaustiveness checks; zero dependencies. Use this when the value never leaves Scala memory. |
| A single local scalar (timeout, retention, default amount) with no enumeration over it | `final val` on a top-level `object` | A named constant is enough; an enum is overkill. Group related constants in one object (e.g. `object PolicyLimits`). |

```scala
// good — serialised + lookable up → enumeratum
import enumeratum._
sealed trait PolicyChannel extends EnumEntry with EnumEntry.Snakecase
object PolicyChannel extends Enum[PolicyChannel] {
  case object Direct      extends PolicyChannel
  case object Aggregator  extends PolicyChannel
  val values = findValues
}
val channel = PolicyChannel.withName("aggregator")  // free lookup

// good — internal discriminator → sealed case object
sealed trait CacheLookupResult
case object Hit       extends CacheLookupResult
case object Miss      extends CacheLookupResult
case object Expired   extends CacheLookupResult

// good — local scalar → final val
object PolicyLimits {
  final val MaxNamedDrivers: Int       = 4
  final val DefaultRetentionDays: Int  = 90
}

// bad — magic literals in business logic
if (channel == "aggregator") …          // banned
if (drivers.size > 4) …                 // banned
```

## Service boundaries return `Future[Either[DomainError, A]]`

```scala
// good
sealed trait WriteSideRepositoryError
case object NoPolicyWithPolicyId        extends WriteSideRepositoryError
final case class DbUnreachable(cause: Throwable) extends WriteSideRepositoryError

trait WriteSideRepository {
  def getPolicy(id: PolicyId): Future[Either[NoPolicyWithPolicyId.type, Policy]]
  def savePolicy(p: Policy):  Future[Either[WriteSideRepositoryError, Unit]]
}

// bad — bare String, thrown across boundary
trait WriteSideRepository {
  def savePolicy(p: Policy): Future[Unit] // throws DbException internally
}
```

## `scala.concurrent.Future` + Akka

```scala
// good — Future + executionContext from the actor system
import system.executionContext
def refresh(policyId: PolicyId): Future[Either[DomainError, Policy]] =
  repo.getPolicy(policyId).flatMap { … }

// bad — using global EC
import scala.concurrent.ExecutionContext.Implicits.global  // banned outside `main`

// bad — introducing IO
import cats.effect.IO  // banned
```

## AWS SDK v2 wrapped behind adapter traits

```scala
// good — trait in domain, adapter in adapter module
// domain/.../PolicyEventPublisher.scala
trait PolicyEventPublisher {
  def publish(event: PolicyEvent): Future[Either[PublishError, Unit]]
}

// policy-event-publisher/.../KinesisPolicyEventPublisher.scala
final class KinesisPolicyEventPublisher(client: KinesisAsyncClient, streamName: String)
                                       (implicit ec: ExecutionContext)
  extends PolicyEventPublisher { … }

// bad — domain code touching AWS SDK directly
// domain/.../PolicyService.scala
import software.amazon.awssdk.services.kinesis.KinesisAsyncClient  // banned in domain/
```

## `AnyFunSpec` + `Matchers`; `describe` + `it("should …")`

```scala
class PolicyServiceSpec
  extends AnyFunSpec
  with Matchers
  with ScalaCheckDrivenPropertyChecks
  with TableDrivenPropertyChecks {

  implicit def noShrink[T]: Shrink[T] = Shrink.shrinkAny

  describe("PolicyService.renew") {
    it("should reject renewal when policy is cancelled") { … }
    it("should preserve carry-forward fields when MTA omits them") { … }
  }
}
```

## Fixture pattern for complex test setups

When several `it(...)` blocks share non-trivial setup (a stub adapter, a fake clock, a pre-populated repository), inline the setup into a `Fixture` class and use `import f._` inside each block. This keeps the test body focused on the assertion while making the dependencies explicit.

```scala
// good — fixture per-test, importing into scope
class PolicyServiceSpec extends AnyFunSpec with Matchers {
  describe("PolicyService.renew") {
    it("should reject renewal when policy is cancelled") {
      val f = new Fixture()
      import f._
      repo.put(cancelledPolicy)
      service.renew(cancelledPolicy.id).futureValue shouldBe Left(PolicyCancelled)
    }

    it("should preserve carry-forward fields when MTA omits them") {
      val f = new Fixture()
      import f._
      repo.put(policyWithDiscount)
      service.renew(policyWithDiscount.id).futureValue.value.pricingDiscount shouldBe Some(discount)
    }
  }

  private class Fixture {
    val clock: Clock                = Clock.fixed(Instant.parse("2026-05-01T00:00:00Z"), ZoneOffset.UTC)
    val repo:  InMemoryPolicyRepo   = new InMemoryPolicyRepo()
    val quotes: StubQuotesAdapter   = new StubQuotesAdapter()
    val service: PolicyService      = new PolicyService(repo, quotes, clock)

    val cancelledPolicy: Policy     = TestData.minimalPolicy.copy(status = Cancelled)
    val discount: PricingDiscount   = PricingDiscount(Money.gbp(50))
    val policyWithDiscount: Policy  = TestData.minimalPolicy.copy(pricingDiscount = Some(discount))
  }
}
```

Reach for the fixture pattern when ≥3 `it(...)` blocks share setup. For ≤2 blocks, inline setup in the block body — a fixture adds indirection for no gain.

## Hand-rolled stubs for domain ports; Mockito narrow for 3rd-party; never on AWS SDK clients

```scala
// good — stub implementing the trait, next to the trait
final class StubQuotesAdapter(quotes: Map[QuoteId, Quote] = Map.empty) extends QuotesAdapter {
  override def getQuote(id: QuoteId): Future[Either[NotFound.type, Quote]] =
    Future.successful(quotes.get(id).toRight(NotFound))
}

// good — Mockito on a narrow third-party surface
val client = mock[PolicyManagerServiceClient]
when(client.getPolicy(any[GetPolicyRequest]())).thenReturn(Future.successful(GetPolicyReply(…)))

// bad — Mockito on an AWS SDK client
val kinesis = mock[KinesisAsyncClient]   // banned; use the trait + LocalStack instead
```

## Akka actor tests via `akka-actor-testkit-typed`

Four testkit APIs, each for a distinct job — picking the wrong one produces hard-to-diagnose failures. Match the API to the situation:

| API | When to use | Trade-off |
|---|---|---|
| `BehaviorTestKit` | Synchronous test of a single `Behavior` — no real `ActorSystem`, no scheduling, no real time. Best for testing message handlers in isolation. | No support for timers, scheduled effects, or anything that needs a real event loop. |
| `ActorTestKit` | Async test against a real `ActorSystem` — needed when the behaviour spawns children, uses timers, or interacts with multiple actors. | Slower; flakier in CI if not configured carefully (use `eventually`, `expectMessage` with explicit timeouts). |
| `TestProbe[T]` | Use *inside* either of the above to make assertions about messages sent to a collaborator actor. | Always typed — never `TestProbe[Any]`. |
| `akka-persistence-testkit` | Event-sourced entities (anything extending `EventSourcedBehavior[Command, Event, State]`). Provides `PersistenceTestKit` and `EventSourcedBehaviorTestKit`. | Required for entity tests; do not substitute with a plain `BehaviorTestKit` — it cannot replay events. |

```scala
// good — synchronous BehaviorTestKit
import akka.actor.testkit.typed.scaladsl.BehaviorTestKit

it("should reply with current count on Increment") {
  val testKit = BehaviorTestKit(Counter())
  val probe   = TestInbox[Counter.State]()
  testKit.run(Counter.Increment(probe.ref))
  probe.expectMessage(Counter.State(value = 1))
}

// good — async ActorTestKit with timers
import akka.actor.testkit.typed.scaladsl.ActorTestKit

class ScheduledRetrySpec extends AnyFunSpec with Matchers with BeforeAndAfterAll {
  private val testKit = ActorTestKit()
  override def afterAll(): Unit = testKit.shutdownTestKit()

  it("should retry after the configured delay") {
    val probe = testKit.createTestProbe[Outcome]()
    val ref   = testKit.spawn(ScheduledRetry.behaviour(delay = 100.millis, target = probe.ref))
    ref ! ScheduledRetry.Start
    probe.expectMessage(150.millis, Outcome.Retried)
  }
}

// good — event-sourced entity test
import akka.persistence.testkit.scaladsl.EventSourcedBehaviorTestKit

it("should persist Bound event and update status") {
  val testKit = EventSourcedBehaviorTestKit[Policy.Command, Policy.Event, Policy.State](
    system,
    PolicyEntity(policyId)
  )
  val result = testKit.runCommand(Policy.Bind(at = now))
  result.event shouldBe Policy.Bound(at = now)
  result.state.status shouldBe Policy.Status.Bound
}

// bad — Mockito-mocking an ActorRef
val ref = mock[ActorRef[Counter.Command]]      // banned — use TestProbe
```

## Integration test setup

Integration tests in `integration-test/` rely on `testcontainers-scala` to spin up real dependencies *from within the test process*. They must not depend on external orchestration — no `docker-compose up` step, no manually-started LocalStack, no shared CI services. The test class is the single point of control over its dependencies; running `sbt "project integration-test; test"` from a clean checkout must succeed without any other command.

```scala
// good — container lifecycle owned by the spec
import com.dimafeng.testcontainers.{PostgreSQLContainer, ForAllTestContainer}

class PolicyRepoIntegrationSpec extends AnyFunSpec with Matchers with ForAllTestContainer {
  override val container: PostgreSQLContainer = PostgreSQLContainer()

  describe("findById") {
    it("should return the stored policy") {
      val ds   = HikariDataSource(container.jdbcUrl, container.username, container.password)
      val repo = new ScalikePolicyRepo(ds)
      runMigrations(ds)
      val saved = repo.save(TestData.minimalPolicy).futureValue
      repo.findById(saved.id).futureValue shouldBe Some(saved)
    }
  }
}

// bad — relies on a docker-compose stack running outside the test
class PolicyRepoSpec extends AnyFunSpec with Matchers {
  it("should connect to local postgres") {
    val ds = HikariDataSource("jdbc:postgresql://localhost:5432/policy", "user", "pass")  // banned
    …
  }
}
```

The test is self-contained: `sbt "project integration-test; test"` must pass on its own — no `docker-compose up`, no manually-started LocalStack, no shared CI services started first.

## LocalStack via Testcontainers for AWS integration tests

```scala
// good — real adapter, real SDK, real LocalStack
class PolicyEventPublisherIntegrationSpec extends AnyFunSpec with Matchers with Testcontainers {
  private val container = LocalStackContainer(…).configure { c =>
    c.withServices(KINESIS)
  }
  override def afterContainersStart(c: containerDef.Container): Unit = {
    val client = KinesisAsyncClient.builder().endpointOverride(c.endpoint).build()
    publisher = new KinesisPolicyEventPublisher(client, "test-stream")
  }
  describe("publish") {
    it("should write a record visible on the stream") { … }
  }
}

// bad — stubbing AWS calls in a unit test
when(kinesis.putRecord(any[PutRecordRequest]())).thenReturn(Future.successful(()))  // banned
```

## 95% scoverage statement and branch; no inline coverage exclusions

Coverage gate is enforced at the `Global` level in `build.sbt`: project-total `95` for both statement and branch coverage. Do not add the per-file thresholds — project-total plus diff coverage on new code is the model; per-file 95% is hostile to small files (config readers, sealed-trait companions) and drives teams toward the inline exclusions this rule bans. Inline `// $COVERAGE-OFF$` / `// $COVERAGE-ON$` is banned — every exclusion goes in `coverageExcludedPackages` (or `coverageExcludedFiles`) so it is reviewable in one place.

```scala
// good — build.sbt
Global / coverageFailOnMinimum     := true                 // CI gate ON
Global / coverageMinimumStmtTotal  := 95
Global / coverageMinimumBranchTotal := 95
// No per-file thresholds — project-total only.

// File-level exclusions belong here, not inline.
coverageExcludedPackages := Seq(
  // Generated proto codegen — mechanical.
  "zego\\.protobuf\\..*",
  // Wiring-only main object; logic extracted elsewhere.
  "zego\\.policymanagement\\.application\\.Application"
).mkString(";")
```

```scala
// bad — inline coverage off
def buildClient(): Client = {
  // $COVERAGE-OFF$
  if (sys.env.contains("SKIP_TLS")) Client.insecure() else Client.tls()
  // $COVERAGE-ON$
}
```

If a file genuinely cannot be exercised, refactor the untestable part into a thin wrapper, exclude the wrapper at the package level, and unit-test the extracted logic. Inline pragmas hide what's missing from the coverage report.

## SLF4J `private val log` + MDC at gRPC entry; no log-and-throw

```scala
// good
import org.slf4j.{Logger, LoggerFactory, MDC}

final class PolicyManagementGrpcImpl(service: PolicyService)(implicit ec: ExecutionContext)
  extends PolicyManagementService {
  private val log: Logger = LoggerFactory.getLogger(getClass)

  override def bindPolicy(req: BindPolicyRequest): Future[BindPolicyReply] = {
    MDC.put("policy_id", req.policyId)
    MDC.put("quote_id",  req.quoteId)
    // MDC is ThreadLocal; snapshot it before the async boundary so the
    // continuation (a different thread) can re-establish it.
    val mdcSnapshot = MDC.getCopyOfContextMap
    MDC.clear()  // don't leak IDs onto the request thread once it returns to the pool
    service.bind(PolicyId(req.policyId)).map { _ =>
      MDC.setContextMap(mdcSnapshot)  // restore on the continuation thread
      try {
        log.info("Policy bound")      // policy_id + quote_id present on this line
        BindPolicyReply(...)
      } finally MDC.clear()           // clear only after the log call, never before
    }
  }
}

// bad — clears MDC before the log runs, and never propagates it across the Future
service.bind(PolicyId(req.policyId)).andThen {
  case _ => MDC.clear()           // runs first — strips policy_id/quote_id …
}.map { _ =>
  log.info("Policy bound")        // … so this line logs with no structured IDs, on a
  BindPolicyReply(...)            //    continuation thread where the MDC was never set
}

// bad — log-and-throw
case Failure(ex) =>
  log.error("Failed to bind", ex)
  throw ex                        // banned — pick one
```

## PureConfig single config entry point

```scala
// good — typed config loaded once at startup
import pureconfig._
import pureconfig.generic.auto._

final case class ServiceConfig(grpc: GrpcConfig, kinesis: KinesisConfig, /* … */)

// application/.../Application.scala
val raw    = ConfigFactory.load()
val config = ConfigSource.fromConfig(raw).loadOrThrow[ServiceConfig]
val publisher = new KinesisPolicyEventPublisher(client, config.kinesis.streamName)

// bad — reaching into raw Config in domain code
val streamName = config.getString("kinesis.streamName")  // banned outside application/
```

## Centralised `project/Dependencies.scala`; one method per module

All library coordinates and pinned versions live in `project/Dependencies.scala` as a three-layer structure:

1. **Version constants** at the top of the file. One `val <name>Version: String = "x.y.z"` per dependency. No literal version strings anywhere else in the project.
2. **Per-module dependency sequences** as `def <module>Dependencies: Seq[ModuleID]`. One per sbt sub-project. Reference the version constants from layer 1.
3. **`build.sbt` references only**: each sbt sub-project's `libraryDependencies` setting points at `Dependencies.<module>Dependencies`. No coordinate strings in `build.sbt`.

```scala
// good — project/Dependencies.scala
import sbt._

object Dependencies {

  // ── Layer 1: pinned versions ───────────────────────────────
  val akkaVersion: String       = "2.8.5"
  val akkaGrpcVersion: String   = "2.4.2"
  val awsSdkVersion: String     = "2.25.50"
  val pureConfigVersion: String = "0.17.6"
  val scalaTestVersion: String  = "3.2.18"
  val testcontainersVersion: String = "0.41.4"

  // ── Layer 2: per-module dependency sequences ───────────────
  def commonDependencies: Seq[ModuleID] = Seq(
    "com.typesafe.akka" %% "akka-actor-typed"       % akkaVersion,
    "com.github.pureconfig" %% "pureconfig"         % pureConfigVersion,
    "org.scalatest"     %% "scalatest"              % scalaTestVersion % Test
  )

  def policyEventPublisherDependencies: Seq[ModuleID] = commonDependencies ++ Seq(
    "software.amazon.awssdk" % "kinesis"            % awsSdkVersion,
    "com.dimafeng" %% "testcontainers-scala-localstack" % testcontainersVersion % Test
  )
}

// good — build.sbt references only the helper
lazy val policyEventPublisher = project
  .in(file("policy-event-publisher"))
  .settings(
    policyManagementSettings,
    libraryDependencies ++= Dependencies.policyEventPublisherDependencies
  )
  .dependsOn(domain)
```

```scala
// bad — inline coordinates in build.sbt
lazy val policyEventPublisher = project
  .settings(
    libraryDependencies ++= Seq(
      "software.amazon.awssdk" % "kinesis" % "2.25.50",     // banned — duplicates version
      "com.typesafe.akka" %% "akka-actor-typed" % "2.8.5"   // banned — duplicates version
    )
  )
```

Same rule for `scalacOptions`: shared options belong on `ThisBuild`; module-specific overrides explained with a one-line comment in the sub-project's `settings`.

## Cinnamon modules in `build.sbt`; agent pinned via `sbt-cinnamon` plugin

The Cinnamon agent is pinned at build time by `addSbtPlugin("com.lightbend.cinnamon" % "sbt-cinnamon" % "<version>")` in `project/plugins.sbt`; `build.sbt` then references whichever Cinnamon modules the service actually uses — `cinnamonAkka` for Akka actors, `cinnamonAkkaStream` for streams, `cinnamonAkkaGrpc` for the gRPC surface, and so on. The plugin loads the agent; the declared modules contribute their instrumentation. Per rule 27, the plugin version and any module pins belong in the centralised dependencies wiring (`project/Dependencies.scala` for modules, `project/plugins.sbt` for the plugin itself), not inlined in `build.sbt` settings. Keep any in-app wiring minimal — targeted configuration (for example a tag enricher or a metric filter) is fine; a parallel SDK setup duplicating what the agent already configures is not.

## See Also

- [../base/testing.md](../base/testing.md) — testing principles and structure: pyramid, mocking, black-box principles.
- [../base/logging.md](../base/logging.md) — logging conventions: levels, redaction, PII.
- [../base/observability.md](../base/observability.md) — metrics and distributed tracing: Datadog, Honeycomb, Cinnamon, MDC propagation.
- [../base/error-handling.md](../base/error-handling.md) — language-agnostic error handling conventions.

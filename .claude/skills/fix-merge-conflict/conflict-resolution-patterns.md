# Conflict Resolution Patterns

Detailed patterns for resolving each type of merge conflict, written for the
`fix-merge-conflict` skill. Read this when building and executing a resolution
plan (Stages 3–4). The governing aim is always the same: **preserve the intent
of both sides** and produce a cohesive result, not just a marker-free file.

**These patterns are language-agnostic.** This skill runs in Scala, Python,
JS/TS, Kotlin and Swift repos (among others). The *strategy* for each conflict
type is the same in every language — only the syntax differs, and you can read
that from the diff. The snippets below are illustrations, not canonical forms.
The one genuinely language-specific thing is regenerating generated/lock files,
which has its own per-ecosystem table.

For each conflict you resolve, give a one-line explanation. When the right
resolution is not clear from the diff, present numbered options and let the
developer choose.

## Naming the sides under a rebase

This skill resolves conflicts **during a rebase**, where `--ours`/`--theirs`
are the opposite of a merge. Throughout this file:

- **base side** = `--ours` = `HEAD` = the top half (`<<<<<<<`) = the branch you
  are rebasing onto (e.g. `origin/main`) — *other people's work*.
- **your side** = `--theirs` = the bottom half (`>>>>>>>`) = the commit from
  your branch being replayed — *your work*.

Always state which actual branch a choice keeps. "Keep ours" is ambiguous and,
under a rebase, usually means "keep the base", which is rarely what a careless
reader expects.

## Effort tiers (these set the validation depth)

Label each resolution with the effort it took — the skill validates
proportionately (Stage 5):

- **Tier 1 — accept-a-side / mechanical:** took one side verbatim, or combined
  both with no new logic (imports, tests, struct fields, regenerated lockfiles).
- **Tier 2 — semantic:** wrote or changed code to reconcile the sides (adapted
  to a renamed symbol, fused two implementations, reworked logic).
- **Tier 3 — needs-design:** resolving would require authoring significant new
  logic, or the two sides are contradictory approaches with no clear way to keep
  both. This is **not resolved here** — it is escalated at the Stage 3 gate
  (`git rebase --abort` + route to `write-design-doc`). A merge-conflict resolver
  authoring large new logic with no spec is exactly the risk to avoid.

If a single file needed semantic work, the whole run is Tier 2. The Tier 2 vs
Tier 3 line: a small, intent-preserving reconcile you can state in one sentence
is Tier 2; anything where you would be designing or re-deriving behaviour, or
picking between incompatible architectures, is Tier 3 — escalate.

## Imports / dependencies — *Tier 1*

Combine all unique imports from both sides; deduplicate; group and order them by
the language's convention (e.g. stdlib / third-party / local groupings,
alphabetisation). Preserve any aliases and re-exports from both sides.

```text
base side adds:   import A, import B
your side adds:   import A, import C
resolution:       import A, import B, import C   (union, deduped, grouped per convention)
```

One-line explanation: "Combined imports from base and your branch, deduplicated
and grouped by module."

## Tests — *Tier 1*

Tests are additive: keep all test cases from both sides unless two test the
exactly identical thing. Merge fixtures and setup/teardown; combine assertions.
If two tests share a name but check different behaviour, rename one so the
intent is clear.

```text
base side:   testCreate(), testValidate()
your side:   testCreate(), testDelete()
resolution:  testCreate() (once), testValidate(), testDelete()
```

One-line explanation: "Kept all test cases from both sides and merged the shared
fixture."

## Generated files / lockfiles — *Tier 1*

Never hand-merge a generated file. Pick either side, then regenerate it from
source so it reflects both branches' inputs.

A file is generated if a tool produces it, it has a defining source, it carries
an auto-generated header, or it is marked generated in `.gitattributes`. Common
cases: dependency lockfiles, protobuf/GraphQL/OpenAPI output, compiled assets,
generated docs.

```bash
git checkout --theirs <file>   # or --ours; it is about to be regenerated
# ...run the ecosystem's regeneration command (table below)...
git add <file>
```

### Regenerate from source — by ecosystem

| Ecosystem | Typical generated / lock file | Regenerate with |
|---|---|---|
| Python — Poetry | `poetry.lock` | `poetry lock` (older Poetry: `poetry lock --no-update`) |
| Python — uv | `uv.lock` | `uv lock` |
| Python — Pipenv | `Pipfile.lock` | `pipenv lock` |
| Python — pip-tools | `requirements*.txt` | `pip-compile` |
| JS/TS — npm | `package-lock.json` | `npm install` |
| JS/TS — yarn | `yarn.lock` | `yarn install` |
| JS/TS — pnpm | `pnpm-lock.yaml` | `pnpm install` |
| Kotlin/Java — Gradle | `gradle.lockfile`, `gradle/*.lockfile` | `./gradlew dependencies --write-locks` |
| Scala — sbt (codegen, e.g. ScalaPB) | generated sources | `sbt compile` (or the project's generate task) |
| Scala — sbt-dependency-lock | `build.sbt.lock` | `sbt dependencyLockWrite` |
| Swift — SwiftPM | `Package.resolved` | `swift package resolve` |
| Swift — CocoaPods | `Podfile.lock` | `pod install` |
| Any — codegen | protobuf / GraphQL / OpenAPI output | the project's generate task (`make generate`, `npm run generate`, `./gradlew generateProto`, `sbt compile`, …) |

If you cannot tell what generates a file, check its header or `.gitattributes`,
or ask — do not hand-merge it. One-line explanation: "Regenerated `{file}` from
source so it reflects both branches' dependencies."

## Configuration files — *Tier 1, or Tier 2 if values need judgement*

Configuration is usually YAML/JSON/TOML/properties and merges the same way
regardless of the repo's language. Include every key from both sides. Where the
same key has different values, choose by: the newer value, the safer/more
conservative value, or the production-correct value — and record the choice in
your explanation.

```yaml
# base side                # your side                 # resolution (union keys)
server:                    server:                     server:
  port: 8080                 port: 8080                   port: 8080
  timeout: 30                timeout: 60                  timeout: 60   # keep the more conservative value
  max_connections: 100       enable_https: true           max_connections: 100
                                                          enable_https: true
```

When a value has real consequences (security settings, endpoints, limits),
present numbered options and ask rather than picking.

## Code logic — *Tier 2*

Understand what each side is trying to do, then combine if you can.

**Orthogonal changes — merge both.** Two sides touching the same function for
different reasons usually compose: keep both additions in a sensible order.

```text
base side adds an empty-input guard;  your side adds a validate() call.
resolution: keep BOTH — the guard, then the validate() call, then the original body.
```

**Contradicting changes — choose, with reason.** When the two sides are
different approaches to the *same* concern (e.g. two different pricing formulas),
do not invent a blend. Read the commit messages/PR for intent, pick the approach
that matches requirements, and say why. If it is not clear, present both as
numbered options and ask. This is where you must be most careful: a
plausible-looking merge of two contradictory algorithms is often silently wrong.

## Struct / type / class definitions — *Tier 1, or Tier 2 if types conflict*

Include all fields/members from both sides (applies equally to a Kotlin `data
class`, a Scala `case class`, a TS `interface`, a Swift `struct`, a Python
dataclass). If the **same** field has different types, that is a real conflict —
work out which is correct, fix the resulting compile/usage errors, and update
tests. If you cannot tell, ask.

```text
base side:   User { id, name, email }
your side:   User { id, name, role }
resolution:  User { id, name, email, role }   (union fields; reconcile any type clash deliberately)
```

## Documentation / comments — *Tier 1*

Combine all sections; keep every example. Where two descriptions of the same
thing conflict, keep the more accurate/complete one. One-line explanation:
"Combined the docs from both sides, keeping all examples."

## Delete-modify and related index conflicts — *Tier 1–2, judgement-heavy*

These show up in `git status --porcelain` as `DU`/`UD`/`DD`/`UA`/`AU`/`AA`.
**Back up the modified content before resolving** so nothing is lost:

```bash
BACKUP=/tmp/fix-merge-conflict-backup
mkdir -p "$BACKUP/$(dirname <file>)"
git show :2:<file> > "$BACKUP/<file>.base" 2>/dev/null || true
git show :3:<file> > "$BACKUP/<file>.theirs" 2>/dev/null || true
```

(`:2:` is the base/ours stage, `:3:` is your/theirs stage.)

- **File was renamed/moved on one side:** apply the other side's modifications
  to the new location, then remove the old path. Detect with
  `git log --follow --diff-filter=R -- <file>`.
- **Deletion was intentional** (feature removed/refactored): review the
  modifications; if any are still relevant, apply them to the new location; if
  not, accept the deletion (`git rm <file>`).
- **Deletion was accidental:** restore the file (`git checkout --theirs <file>`
  or `--ours`, per which side kept it), reapply modifications, verify.
- **Both-added (`AA`):** if both new files serve the same purpose, merge their
  content; if different purposes, rename one.

## Binary files — *Tier 1*

Binaries cannot be merged — choose one side:

```bash
git checkout --ours <file>     # keep the base version
git checkout --theirs <file>   # keep your branch's version
git add <file>
```

## When to present options instead of resolving

Ask — with numbered options — whenever:

- two sides change the same logic in contradictory ways;
- a config/value choice has security or production consequences;
- the same struct/type field has conflicting types;
- you genuinely cannot tell intent from the diff and commit history.

Track the developer's choices within the run and apply the same reasoning to
later similar conflicts, saying that you are doing so ("keeping your branch's
approach, consistent with your earlier choice"). Ask again when a new conflict
is meaningfully different.

## Quick reference

| Conflict type | Strategy | Tier |
|---|---|---|
| Imports | Union, dedupe, group by module | 1 |
| Tests | Keep all, merge fixtures | 1 |
| Generated / lockfiles | Pick a side, regenerate from source (see ecosystem table) | 1 |
| Config | Union keys; choose newer/safer for clashes | 1–2 |
| Code logic | Merge if orthogonal; choose (and explain) if contradictory | 2 |
| Structs / types | Union fields; resolve type clashes deliberately | 1–2 |
| Docs | Combine all sections | 1 |
| Delete-modify | Back up, then relocate / accept / restore | 1–2 |
| Binary | Choose one side | 1 |

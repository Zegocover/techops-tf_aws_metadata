---
version: 1.1
last_reviewed: 2026-06-02
---

# File Organisation Standards

File size and structural organisation conventions for all codebases — a file should have one clear responsibility; when it grows past its language's comfortable reading size, it likely has more than one. Apply these rules whenever creating, modifying, or splitting files in any codebase. Language-specific module systems, import conventions, and re-export patterns are covered in the relevant language standards file.

## On the line-count targets

The numeric targets below (50–300 line working range, split at 400, ceiling at 500) are **signals calibrated to concise languages** such as Python or TypeScript. They are not a universal gate. The primary test is always **one responsibility** (Rule 1 — "describe it in one sentence without 'and'"), not the raw line count.

Scale the numbers to the language's natural verbosity and idioms:

- **Verbose / boilerplate-heavy languages** (Scala, Kotlin, Java, Swift) legitimately run longer per responsibility — a single cohesive Scala case-class hierarchy or a Swift view controller may exceed 300 lines while still owning one concept. For these languages the primary test stays the responsibility check (Rule 1), not the raw count, and the concrete 500-line ceiling (Rule 4) does not apply directly: defer the verbose-language ceiling to the relevant per-language standard, which sets its own figure where one is defined (only `languages/python.md` exists today). Until such a standard exists for a given language, lean on the responsibility test — a file that owns more than one concept is signalling a missing split regardless of length.
- **Framework-shaped files** (iOS view controllers, Android Activities/Fragments, SwiftUI views, LookML `view`/`model` files) follow their framework's conventions; the responsibility test applies, the exact numbers do not.
- **Generated code, data tables, and declarative artefacts** (protobuf, LookML, schema/migration files) are exempt, as noted in Rules 2 and 4.

Where a language standard defines its own size guidance, it takes precedence over the numbers here.

## Rules at a Glance

1. **One responsibility per file.** Each file should own a single concept or responsibility — grouping unrelated concerns in one file makes it harder to navigate, review, and test because readers must mentally filter irrelevant code to find what they need.
2. **Target 50–300 lines per file.** Aim for files in the 50–300 line range as the standard working size — files in this range are small enough to read in one sitting and large enough to hold a complete, cohesive unit of functionality.
3. **Split at 400+ lines.** Actively split any file that exceeds 400 lines — a file this long almost certainly contains more than one responsibility, and splitting it restores navigability and keeps diffs focused.
4. **No 500+ line files.** Do not let logic-bearing files exceed 500 lines — this ceiling reinforces the split-at-400 guidance and prevents incremental growth from producing monolithic files. The 500-line figure is the concise-language baseline; verbose languages set their own (higher) ceiling in the relevant per-language standard, and where one is defined it takes precedence. Generated code, data tables, and other mechanical artefacts are exempt.
5. **Organise by concept.** Group files by the concept or responsibility they represent, not by technical layer or file type — concept-based organisation keeps related code together so that a change to one feature touches as few directories as possible.

## One responsibility per file

A file that owns a single concept is easier to name, easier to find, and produces smaller diffs when changed. When a file accumulates helpers, constants, and secondary logic around its primary purpose, it becomes a grab-bag that only the original author can navigate confidently.

The test for whether a file has one responsibility: can you describe what it does in one sentence without using "and"? If the description requires "and", the file likely has a natural split point.

```
# good — each file owns one concept
# pricing — calculates premium from risk factors
# risk_factors — loads and validates risk factor definitions

# bad — two unrelated concepts in one file
# pricing_and_risk_factors — calculates premium AND loads risk factor definitions
```

## Target 50–300 lines per file

Files shorter than 50 lines may indicate over-splitting — a file with a single function and no rationale for isolation is often better inlined into its caller. Files in the 50–300 range are the productive middle ground: long enough to hold a meaningful unit of work, short enough to review without scrolling fatigue.

This is a signal, not an absolute gate. Generated code, data tables, protocol buffer definitions, and similar artefacts may legitimately exceed 300 lines because their content is mechanical or tabular rather than logic-bearing. The question to ask is: does this file contain more than one responsibility? If it is long but cohesive, it is fine.

## Split at 400+ lines

When a file crosses 400 lines, treat it as a prompt to refactor. Look for natural seams: a group of related functions that could move to their own file, a class that has grown a secondary concern, or a set of constants that would be clearer in a dedicated file.

Splitting is not always a net win — splitting a 410-line file into two 205-line files that constantly import each other creates coupling without improving clarity. Split along responsibility boundaries, not arbitrary line counts.

## No 500+ line files

The 500-line ceiling exists to prevent the common pattern where a file grows gradually from 400 to 600 to 800 lines because each individual addition seems small. A hard upper limit forces the split conversation to happen before the file becomes genuinely difficult to work with.

As with the 300-line target, generated code, data tables, and other mechanical artefacts are valid exceptions — the ceiling applies to logic-bearing code where human readability matters.

## Organise by concept

Concept-based organisation means that all code related to, say, pricing lives in one place, rather than scattering pricing logic across `models/`, `services/`, `utils/`, and `helpers/` directories. When a developer needs to understand or change pricing, they open one directory (or a small cluster of files) rather than searching the full tree.

This rule does not prescribe specific directory structures — it states a principle that applies to any project layout. A flat structure with well-named files, a feature-folder layout, or a domain-driven package hierarchy can all satisfy concept-based organisation.

```
# good — related files grouped by concept
# quotes/calculator
# quotes/validation
# quotes/repository

# bad — same code scattered by technical layer
# models/quote
# services/quote_calculator
# utils/quote_validation
```

## See Also

- [testing.md](testing.md) — testing conventions, including test file organisation and naming.
- Language-specific standards (e.g. [python.md](../languages/python.md)) — framework-imposed directory structures (Django's `models.py`/`views.py`, etc.) may override Rule 5; the relevant language standard documents these exceptions.

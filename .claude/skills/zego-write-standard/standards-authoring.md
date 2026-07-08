# Standards Authoring Guide

Standards files are instructions for Claude, not human documentation. They
are consumed by Claude at coding time to constrain its behaviour. Optimise
for machine clarity: precise imperatives, explicit scope, zero prose padding.
All files in `standards/` must follow the structure below.

---

## Structure

Every standards file follows this section order exactly. Optional sections
are marked.

1. Frontmatter
2. Title
3. Intro paragraph
4. Rules at a Glance
5. Content sections (one per rule that warrants one)
6. See Also (optional)

---

## Frontmatter

Every standards file opens with YAML frontmatter carrying version and review
date. Git history is the changelog — these fields tell Claude when to trust
the content.

```yaml
---
version: 1.0
last_reviewed: 2026-05-06
---
```

Increment the minor version for additions or clarifications; increment the
major version for breaking changes to existing rules. A breaking change is:
removing a rule, narrowing its scope, or reversing its imperative. Rewording
for clarity, adding rationale, or adding a new rule are minor changes.

---

## Title

`# {Topic} Standards` — always. Title-case the topic noun, end with
"Standards".

```markdown
# Python Standards
# Observability Standards
# Comments and Documentation Standards
```

---

## Intro Paragraph

Up to four sentences, in this order:

1. **Domain + philosophy.** What this file covers, including any governing
   principle that shapes how edge cases are decided.
2. **Trigger.** When Claude should apply this file — the situation or context
   that activates it.
3. **Tooling exclusions.** What is enforced mechanically and therefore not
   covered here. Omit if nothing applies.
4. **File-overlap exclusions.** What a related standards file already owns.
   Omit if nothing applies.

Sentences 3 and 4 can be omitted when genuinely not applicable, but both
should be present whenever there is something to say. The trigger sentence is
never optional — it is how Claude decides whether to apply this file at all.

```markdown
# Python Standards

Structural and architectural conventions for Python services — how code is
organised, dependencies wired, and libraries chosen. Apply these rules to any
Python file in a service codebase. Formatting, import ordering, and type
checking are enforced mechanically by ruff and mypy and are not covered here.
Dependency injection patterns are covered in architecture.md.
```

```markdown
# Observability Standards

Conventions for logging, metrics, and distributed tracing — each signal
answers a distinct question (is there a problem? where? what?) and all three
are required for complete observability; we standardise on OpenTelemetry and
Datadog. Apply these rules whenever adding or modifying any logging, metrics,
or tracing code. Log formatting and retention policy are enforced by the
platform and are not covered here.
```

---

## Rules at a Glance

The complete ruleset for the file. Body sections are rationale and examples
only — they do not introduce new rules. If a rule belongs in the body but
not the glance list, stop and add it to the glance list first.

Rule numbers are unique within a file. Each content section heading must
match its rule's **key concept** exactly — this is how Claude links a rule
to its rationale.

### Format

Each rule follows this pattern:

```
N. **{Key concept}.** {Imperative statement — why it matters.}
```

- **Bold the key concept** — Claude uses it to locate the rule relevant to
  the situation without parsing the full list.
- **State the imperative** in one sentence.
- **Carry the why inline.** Claude that knows *why* a rule exists applies it
  correctly at the edges; Claude that only knows *what* to do misapplies it.
  Embed the reason as a trailing clause or second sentence — never in a
  separate Philosophy section.

### The "why" principle

The most important property of a well-written rule.

```markdown
# bad — no context for edge cases
5. **PII in logs.** Never log PII.

# better — scope and reason are in the rule itself
5. **No PII at INFO and above.** Never log names, addresses, or identifiers
   at INFO or higher — our logging setup is not designed to store PII.
```

```markdown
# bad — no context for when the rule applies
5. **Protocols.** Use a Protocol for dependencies.

# better — constraint and reason are in the rule itself
5. **Use protocols sparingly.** Introduce a Protocol only when two or more
   concrete implementations exist — speculative interfaces add complexity
   without value.
```

A clause is enough. The rule must be self-contained: Claude should not need
to read the rest of the file to apply it correctly.

---

## Content Sections

Give a rule its own `##` section when the rationale is non-obvious or an
example would reduce ambiguity. A fully self-explanatory rule can stand
alone without one, but that is the exception.

The section heading must match the **key concept** exactly — this is how
Claude links from a rule in the glance list to its rationale.

Each section:

- Rationale: one or two paragraphs. No restatement of the rule — Claude
  already has it from the glance list.
- An example where the rule applies. Use best judgement, but always try.
- No new rules.

No `---` horizontal rules between sections.

---

## Code Examples

Label all examples `# good` or `# bad` (lowercase, no period), optionally
followed by `—` and a brief reason. Use `# {filename}` for structural
examples like composition roots.

```python
# good
logger.info("Adjusting policy.", extra={"policy.id": policy.id})

# bad — formats variables into the message string, defeating search
logger.info(f"Adjusting policy {policy.id}.")
```

For multi-file or structural examples where good/bad doesn't apply, use a
`# {filename} —` label:

```python
# main.py — composition root, wired once at startup
def build_app() -> App:
    client = ExternalClientImpl(base_url=settings.service_url)
    service = DomainService(client=client)
    return App(service=service)
```

---

## File Selection

Check whether the domain is already covered before creating a new file.
Extend an existing file if one owns the concern — a narrower new file
fragments the ruleset Claude loads.

Create a new file only when no existing file owns the domain.

If a rule could plausibly live in two files, put it in the one most relevant
to the change being made and cross-reference from the other. One file owns
the rule; the other points to it.

### Sub-folders

Not all sub-folders exist yet — create the directory if needed.

The trigger sentence in the intro determines which sub-folder a file belongs
in:

| Trigger | Sub-folder | Contents |
|---------|-----------|----------|
| Always — any codebase | `base/` | Comments, testing principles, security, git workflow. |
| When writing [language] code | `languages/` | Language-specific conventions — one file per language. |
| When working on [domain] | `domains/` | Business and infrastructure concerns — payments, telephony, gRPC, MCP servers, data pipelines. |
| When the AI pipeline is operating | `governance/` | Pipeline policy — impact assessment tiers, review iteration, extension model. |

Each sub-folder has a `README.md` listing its files with a one-line
description. The `standards/` root also has a `README.md` explaining the
folder structure. When adding a new standards file, add one line to the
relevant sub-folder README in this format:

```
- [filename.md](filename.md) — one-line description of what the file covers.
```

If the sub-folder README does not exist yet, create it with a `# {Sub-folder}
Standards` heading and that entry as the first line.

---

## See Also

Add a `## See Also` section when another standards file owns a related
topic — this tells Claude where to look for rules that apply alongside
this file. Links must be relative paths.

```markdown
## See Also

- [observability.md](../domains/observability.md) — structured logging
  conventions and PII rules.
```

Omit if there are no cross-references.

---

## Template

```markdown
---
version: 1.0
last_reviewed: {YYYY-MM-DD}
---

# {Topic} Standards

{Domain + governing philosophy — what this file covers and the principle that shapes edge cases.}
{Trigger — when Claude should apply this file.}
{Tooling exclusions — what is enforced mechanically and not covered here. Omit if none.}
{File-overlap exclusions — what a related standards file already owns. Omit if none.}

## Rules at a Glance

1. **{Key concept}.** {Imperative — why it matters.}
2. **{Key concept}.** {Imperative — why it matters.}

## {Key concept from rule N}

{Rationale for the rule. One or two paragraphs.}

{Example with # good / # bad labels where applicable — see Code Examples.}

## See Also  {optional — omit if no cross-references}

- [{filename}]({relative path}) — {one-line description}.
```

---
version: 1.0
last_reviewed: 2026-05-12
---

# Spelling Standards

UK English is Zego's house style for all human-readable text in the codebase — comments, docstrings, log messages, error messages, and any other prose that developers or users read. Apply these rules to any codebase, always. Spell-checking tooling, if configured, enforces its own dictionary and is not covered here.

## Rules at a Glance

1. **UK English for human-readable text.** Use UK English spelling in all comments, docstrings, log messages, error messages, and documentation strings — consistency across the codebase reduces cognitive load for reviewers and keeps prose style uniform.
2. **Identifiers and API contracts are exempt.** Do not change the spelling of variable names, function names, class names, enum values, or external API field names to match UK English — renaming these would break contracts, callers, and tooling that depends on the existing names.
3. **Common US/UK differences.** Prefer the UK spelling when a word has a well-known US/UK variant — applying the wrong variant is the most frequent source of inconsistency and the easiest to prevent with a short reference list.

## UK English for human-readable text

All text that a human reads in the codebase — inline comments, block comments, docstrings, log message strings, error message strings, and in-code documentation — must use UK English spelling. This applies regardless of the programming language. Standalone documentation files (READMEs, ADRs, design docs) should also follow UK English; user-facing UI strings are a product concern and outside the scope of this standard.

```
# good
# Initialise the colour map before authorising the request

# bad — US spellings
# Initialize the color map before authorizing the request
```

```
# good
log.info("Organisation catalogue synchronised.", {"org.id": org_id})

# bad — US spellings in the log message
log.info("Organization catalog synchronized.", {"org.id": org_id})
```

## Identifiers and API contracts are exempt

Code identifiers — variable names, function names, class names, enum values, constants, and module names — are not required to use UK English. Renaming an identifier changes its contract: every caller, every import, every serialised field, and every test assertion that references it would also need to change. The same applies to field names in external API contracts, configuration keys defined by third-party systems, and protocol buffer field names.

When writing a new identifier with no existing contract, use UK English unless it would be inconsistent with the surrounding codebase convention — consistency with neighbouring code takes precedence over the house style for identifiers specifically.

```
# good — UK English in the comment, existing US-convention identifier left alone
color_hex = "#FF5733"  # Colour value for the warning banner

# bad — renaming an existing identifier to match UK spelling
colour_hex = "#FF5733"  # renamed from color_hex for UK English consistency
```

## Common US/UK differences

The most frequent variants that appear in codebases. When in doubt, check a UK English dictionary.

| US spelling | UK spelling | Example context |
|-------------|-------------|-----------------|
| -ize | -ise | initialise, authorise, serialise, synchronise, organisation |
| -or | -our | colour, behaviour, favour, neighbour |
| -og | -ogue | catalogue, dialogue, analogue |
| -er | -re | centre, metre (unit of length) |
| -ense | -ence | licence (noun), defence |
| -ll | -l | fulfil/fulfilment, instalment, enrol/enrolment |

Note: some `-ize` spellings are correct in UK English when the suffix derives from Greek `-izo` (e.g. "capsize" is not "capsise"). When genuinely uncertain, check a UK dictionary rather than applying `-ise` mechanically.

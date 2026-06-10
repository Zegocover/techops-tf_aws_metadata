# header-format

Check: the design document's header is the canonical six-line block — correct labels, in the canonical order, with line 2 satisfying the consumer grep `^JIRA: {TICKET}$` exactly — so the `review` skill's design-doc discovery can never silently fail.

## Inputs

- `requirements_source`: full text of the requirements source (FRs, ACs, constraints, and possibly a JIRA URL or key)
- `design_document`: full text of the design document (including `## Dismissals`)

## Canonical header

The first six lines of `design_document` must be exactly this block, labels verbatim and in this order:

```
# Design: {feature_name}
JIRA: {ticket}
Engineer: {engineer}
Requirements: {requirements_source_path}
Date: {date}
Branch: {branch}
```

This block is identical in shape to the template at `.claude/skills/write-design-doc-max/design-document.md` (lines 1–6) and to the verbatim block pinned in `.claude/skills/write-design-doc-max/design-writer.md`.

## Checks

### Primary assertion (deterministic — always performed)

Examine the first six lines of `design_document` in order. These checks are mechanical; do not paraphrase or interpret.

1. **Line 1** must match `^# Design: \S` — the literal prefix `# Design: ` (one space) followed by at least one non-whitespace character (the feature name).
2. **Line 2** must match `^JIRA: \S+$` — the literal label `JIRA:` (never `Ticket:` or any other label), one space, then exactly one whitespace-free token, with **no trailing content** of any kind. This is the load-bearing line: it must satisfy the consumer grep `^JIRA: {TICKET}$` in `.claude/skills/review/SKILL.md`. `Ticket: AIDEV-116` fails (wrong label). `JIRA: AIDEV-116 (draft)` fails (trailing content). `JIRA: AIDEV-116` passes.
3. **Line 3** must match `^Engineer: \S` — the literal label `Engineer: ` followed by at least one non-whitespace character. Multi-word or any longer values (e.g. `Engineer: Diogo Alves`) are valid; this is a non-empty-value prefix check, NOT a no-trailing-content check.
4. **Line 4** must match `^Requirements: \S` — the literal label `Requirements: ` followed by at least one non-whitespace character. URL or path values (e.g. `Requirements: https://zegons.atlassian.net/browse/AIDEV-116`) are valid; prefix check only.
5. **Line 5** must match `^Date: \S` — the literal label `Date: ` followed by at least one non-whitespace character. Prefix check only.
6. **Line 6** must match `^Branch: \S` — the literal label `Branch: ` followed by at least one non-whitespace character. Prefix check only.

The `^...\S+$` no-trailing-content rule applies ONLY to line 2, because line 2 is the only line consumed by an exact-match grep. Lines 1 and 3–6 use a non-empty-value prefix check (`\S` after the label), which permits multi-word and URL values.

Any deviation — a wrong label, a reordered line, trailing content on line 2, an empty value, or fewer than six header lines — is a violation. A single bad header can trip several of these at once. The six deviation classes above (one per header line) plus the ticket-key mismatch sub-check below are independent and can co-occur on one header. When more than one is present, you MUST enumerate ALL of them into the single finding — never report only the first, most prominent, or load-bearing one and stop. Emit exactly ONE finding (see Output) whose `Issue` field ENUMERATES EVERY observed deviation, each named with its line number, observed value, and expected value, and whose `Suggested resolution` gives the verbatim corrected six-line header so one re-dispatch clears every deviation at once. A generic "header is invalid" does not satisfy this rubric, and neither does naming only the first or most prominent deviation while leaving others unreported.

### Ticket-key equality sub-check (best-effort — performed only when unambiguous)

This sub-check is secondary and best-effort. Attempt to derive a single ticket key from `requirements_source`:

- A ticket key is a token matching `[A-Z]+-\d+` (e.g. `AIDEV-116`), including one embedded in a JIRA URL such as `https://zegons.atlassian.net/browse/AIDEV-116`.
- Derive the key ONLY when exactly one distinct `[A-Z]+-\d+` token is present in `requirements_source`.

Then:

- **If a single unambiguous key is derivable**: compare it to the token on line 2 (the value after `JIRA: `). If they differ (e.g. line 2 is `JIRA: AIDEV-999` but the requirements source yields `AIDEV-116`), this is a key mismatch deviation. Do NOT emit a separate or second finding for it. Instead, fold it into the SINGLE finding from the Output section: if the primary assertion already produced a finding, add the key mismatch (naming both the observed key and the expected key) to that finding's enumerated deviation list; if the primary assertion passed, the single finding covers just this key mismatch.
- **If no `[A-Z]+-\d+` token is present, OR more than one distinct token is present (ambiguous)**: SKIP this sub-check silently. Do not emit a finding for it. Do not fail. Do not return a check-agent failure. Rely entirely on the deterministic primary assertion above.

This degradation is handled entirely inside this check. An absent or ambiguous ticket key is never an error and must never be escalated. The primary assertion always runs regardless of whether this sub-check is skipped — an ambiguous key does NOT no-op the whole check body.

## Output

Apply the six-field finding schema from `check-principles.md`.

On a clean canonical header (primary assertion passes and the key sub-check either passes or is skipped): return an empty findings list.

On any deviation: return exactly ONE finding — never two — that enumerates every observed deviation from BOTH the primary assertion AND the ticket-key sub-check. The finding has:

- `Severity`: `High` (never a HALT — a header deviation self-heals via the disposition protocol's full ladder, which at the design gate cheaply re-dispatches the writer and re-runs the gate).
- `Issue`: an enumeration of EVERY observed deviation, each naming its line number, observed value, and expected value (a derived ticket-key mismatch is one such enumerated entry, not a separate finding). For the label-drift case the `Issue` or `Suggested resolution` MUST contain both the literal string `Ticket:` and the literal string `JIRA:` (e.g. "line 2 is `Ticket: AIDEV-116`, must be `JIRA: AIDEV-116`"). A paraphrase such as "label is wrong" is insufficient. Listing only the first or most prominent deviation is insufficient when several are present.
- `Why it matters`: the consumer grep `^JIRA: {TICKET}$` in `.claude/skills/review/SKILL.md` silently returns nothing when line 2 deviates, so review Group E loses the design doc and falls back to the task spec alone.
- `Size of fix`: `trivial` for a single deviation fixable on one line; `local` when multiple deviations are enumerated or the whole header block must be reordered or reconstructed verbatim.
- `Target`: `load-bearing` (the header is consumed by the review skill's exact-match discovery grep).
- `Suggested resolution`: the full corrected six-line header block, verbatim, matching the canonical header — not just the single corrected line(s). Enumerating all deviations against one verbatim block rewrite lets a single re-dispatch clear every issue in one gate round.

## Dismissals

Check the `## Dismissals` section of `design_document`. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific header deviation in the same line. If the design or header has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

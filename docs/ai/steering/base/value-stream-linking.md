---
version: 1.0
last_reviewed: 2026-06-29
---

# Value-Stream Linking Standards

Conventions for the shared feature identifier that links every pull request of a single feature (its requirement, design, and implementation PRs) into one thread, so the work can be correlated across the pipeline. The identifier is Jira-independent: it is not derived from the ticket key. It is minted once by the first PR-producing skill of a feature, recovered and reused by every later skill, persisted in artefact frontmatter as the durable in-repo source of truth, and stamped best-effort onto every PR. Apply these rules in any skill that writes a pipeline artefact (requirements doc, design doc, task spec) or opens a PR. The minting, validation, recovery, and decision logic live in `.claude/scripts/feature-id.sh`; this document records the cross-skill conventions, not the script's internals. See ADR 020 for the decision record.

## Rules at a Glance

1. **One identifier per feature, minted once.** The first PR-producing skill mints the identifier; every later skill recovers it from the predecessor artefact and reuses it. Never mint a second identifier for a feature that already has one: a fresh mint silently de-links the PRs already carrying the original, breaking the single-thread guarantee.
2. **The identifier format is fixed.** A feature identifier is `word-word-word-hex4`, for example `quartz-amber-ronin-7e67`, and matches the regex `^[a-z]+-[a-z]+-[a-z]+-[0-9a-f]{4}$`. Three lower-case words drawn from the vendored wordlist, then a four-hex-digit suffix, all hyphen-separated. It is never the Jira key or a branch slug derived from it.
3. **Persist in artefact frontmatter, per artefact type.** The artefact is the durable in-repo source of truth. Write the identifier into the requirements doc, design doc, or task spec in the shape that artefact uses (see *Frontmatter placement*). Never write it into CLAUDE.md managed frontmatter: fan-out overwrites that block (ADR 003).
4. **Stamp the PR with a last-line trailer.** Expose the identifier on a PR as a single `Feature-Id: <id>` line appended as the very last line of the PR body, in the manner of a `Co-Authored-By` trailer. Never a top-level section.
5. **Best-effort, never blocks.** A mint, recover, or stamp failure warns and proceeds. A reporting gap is acceptable; a blocked skill is not. A skill never fails because the identifier could not be resolved or stamped.
6. **Resolve mint-vs-recover-vs-lost deliberately.** When recovery returns no valid identifier, decide between MINT and LOST on whether a predecessor PR exists, and treat any `gh` failure as the LOST-safe default (see *Mint, recover, decide*). Getting this wrong is silent and splits a feature into two unlinked threads.

## Identifier format

A feature identifier is three lower-case words from the vendored EFF large diceware wordlist followed by a four-hex-digit suffix, hyphen-separated:

```
word-word-word-hex4          e.g.  quartz-amber-ronin-7e67
^[a-z]+-[a-z]+-[a-z]+-[0-9a-f]{4}$
```

The words give a human-pronounceable handle that appears in org-visible PR titles and bodies; the hex4 suffix widens the keyspace so collisions are negligible across a repository's lifetime feature population. The identifier is deliberately not the Jira key and not a branch slug that embeds the Jira key: a feature's thread must survive independently of its ticket. Use `feature-id.sh validate <candidate>` to check shape; it rejects both malformed strings and Jira-key-shaped strings.

## Frontmatter placement

The identifier is written into the artefact in the shape that artefact already uses. The placement differs by artefact type, and `feature-id.sh recover` reads all three shapes alike (case-insensitively on the `Feature-Id` label):

| Artefact | Placement |
|----------|-----------|
| Requirements doc | a new row in its metadata table: `\| Feature-Id \| <id> \|` |
| Design doc | a `Feature-Id:` line immediately after the `Branch:` header line |
| Task spec | a `feature-id:` YAML frontmatter key |

For the **design doc**, the `Feature-Id:` line is added after `Branch:` and the `JIRA:` header line is left untouched. The `zego-review` discovery walk greps `^JIRA: {TICKET}$`; moving or reshaping that line would break design-doc discovery. The design-doc header is therefore a seven-line block (the `Feature-Id:` line is line 7), and both the authoring instruction and the validating check must agree on seven lines.

For the **task spec**, `feature-id:` is a deliberate third permitted frontmatter key, alongside `ticket` and `branch`. It is the only addition permitted to task-spec frontmatter, and is recorded as an allowance in ADR 020. Omit the key entirely when there is no identifier; never write an empty value.

When the identifier is absent (mint failed, or this feature legitimately has none), omit the row, header line, or key entirely rather than writing a placeholder or empty value.

## PR-body trailer

The identifier is exposed on a PR as a single trailing line, appended as the very last line of the PR body after whatever template the repo uses:

```text
Feature-Id: quartz-amber-ronin-7e67
```

It is a body line, never a top-level `##` section, so it conforms to any downstream repo's PR template (respects `pull-requests.md` rule 8). It is stamped best-effort by both PR-producing paths, `req-pr.sh` and `zego-create-pr`; the change must land in both, because they share no creation code and stamping only one silently drops coverage on the other. The calling skill writes the identifier into the artefact frontmatter first, then the PR path obtains it via `feature-id.sh recover <artefact-path>`: there is no raw-positional-id path.

**The stamp is idempotent.** Before appending the trailer, each stamping path checks whether the PR body already contains a `Feature-Id:` line (matched case-insensitively, for example `grep -qiE '^feature-?id:'`) and skips the append if one is present. A re-run never double-stamps.

## Mint, recover, decide

Each skill resolves the identifier in this order:

1. **Recover** from the predecessor artefact with `feature-id.sh recover <artefact-path>`. A valid recovered identifier is reused as-is. The first PR-producing skill of a feature has no predecessor and so recovers from its own same-phase artefact on a re-run (see below).
2. When recovery returns nothing or a malformed value, **decide** with `feature-id.sh decide <recovered-or-empty> <predecessor-pr-exists>`:
   - `REUSE <id>` when a valid identifier was recovered.
   - `LOST` when no valid identifier was recovered but a predecessor PR exists: warn and proceed without an identifier; never mint a replacement.
   - `MINT` when no valid identifier was recovered and no predecessor PR exists: a genuine first run.

The `predecessor-pr-exists` boolean is the hinge. Compute it deliberately: query the predecessor branch's PR state (the design phase reuses the branch its Stage 0 handoff gate already resolved, rather than a second lookup). **A non-zero `gh` exit (network, auth, or transient failure) must never be read as "no predecessor PR".** Treat a `gh` failure as the LOST-safe default: pass `true` to `decide` and warn. Reading a `gh` failure as "no predecessor" would let a truly-lost identifier fall through to MINT, duplicating the identifier and breaking the single-thread guarantee.

## Re-run and resumability (skill-idempotency Rule 6)

This standard reconciles with `docs/ai/steering/local/skill-idempotency.md` Rule 6: re-invoking a skill must converge to the same end state without minting a second identifier. Two mechanisms make re-runs idempotent:

- **Recover-before-mint.** Every skill recovers before it considers minting. On a re-run, the identifier the prior run persisted is recovered from the artefact and reused, so the feature keeps one identifier across re-runs. The first PR-producing skill (`zego-write-requirements`) has no predecessor phase, so on a re-run it recovers from its own requirements artefact's metadata row and mints only if that is absent or malformed.
- **Idempotent stamp.** The PR-body trailer is skipped when a `Feature-Id:` line is already present, so re-running the PR path never appends a second trailer.

Together these make a re-invocation converge to the same identifier and the same single stamped trailer, satisfying Rule 6.

## See Also

- [pull-requests.md](pull-requests.md): PR title and body conventions; the trailer is a body line, never a section (rule 8).
- [../local/skill-idempotency.md](../local/skill-idempotency.md): resumability conventions; Rule 6 is reconciled above.
- [../../../decisions/020-feature-identifier.md](../../../decisions/020-feature-identifier.md): the decision record, including wordlist provenance.

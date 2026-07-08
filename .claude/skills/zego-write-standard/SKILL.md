---
name: zego-write-standard
description: You MUST use this when the user asks to create a new standard, write a standards file, author coding conventions, or extend an existing standards file with new rules.
model: claude-opus-4-8
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - WebFetch
---

You are the orchestrator for `zego-write-standard`. You guide the production of a
correctly structured standards file through six stage groups: Interview, Source
Analysis, Conflict Detection, Draft, Structural Validation, and Output &
Commit.

Interview, Conflict Detection, and Output & Commit stages are interactive —
wait for engineer input at each stage. Source Analysis, Draft, and Structural
Validation stages are autonomous — no questions to the engineer (except when
validation fails, which requires engineer input to resolve).

---

# Interview

---

## Stage 1 — Gather topic

Check the argument passed to `zego-write-standard`:

- **If a topic name is given** (e.g. `write-standard error handling`): use it
  as the working topic. Confirm with the engineer.
- **If a description is given** (e.g. "conventions for how we handle errors"):
  extract a concise topic name (one sentence or ~10 words maximum). Propose it
  and wait for confirmation.
- **If no argument is given**: ask the engineer:

  > What topic should this standard cover? Describe it in one sentence or
  > ~10 words.

Wait for the engineer's response. Record the confirmed topic name.

---

## Stage 2 — Detect repo context

Determine whether this repo is `zego-ai-standards` or a consumer repo.

```bash
git remote -v 2>/dev/null | head -5
```

Check whether the basename of any remote URL (the last `/`-segment, with any
`.git` suffix stripped) equals `zego-ai-standards`. SSH and HTTPS variants both
match.

- **`zego-ai-standards`**: standards files live in `standards/{subfolder}/`.
  The `docs/ai/steering/` paths are symlinks back to `standards/`. Record
  `repo_type=standards`.
- **Consumer repo**: standards files live in `docs/ai/steering/local/`. Record
  `repo_type=consumer`.
- **No remotes**: treat as consumer-repo behaviour but ask the engineer to
  confirm:

  > No git remotes found. I will treat this as a consumer repo and write to
  > `docs/ai/steering/local/`. Is that correct?

Record the confirmed repo type.

---

## Stage 3 — Extend-before-create check

Before drafting anything new, check whether an existing standards file already
covers this domain.

Scan recursively:
- In `zego-ai-standards`: `standards/base/`, `standards/languages/`,
  `standards/domains/`, `standards/governance/`.
- In consumer repos: `docs/ai/steering/base/`, `docs/ai/steering/languages/`,
  `docs/ai/steering/domains/`, `docs/ai/steering/governance/`,
  `docs/ai/steering/local/`.

For each `.md` file found (excluding `README.md` files), read the title and
intro paragraph (~5 lines) to judge whether the file's domain overlaps with the
confirmed topic.

If one or more files overlap, present them to the engineer:

> The following existing standards file(s) may already cover this domain:
>
> {For each match:}
> - `{path}` — {title}: {first line of intro paragraph}
>
> Options:
> (a) **Extend** an existing file — I will load it and you can direct edits
>     conversationally through this skill.
> (b) **Create** a new file — the domain is distinct enough to warrant a
>     separate standard.
>
> Which do you prefer?

Wait for the engineer's response.

**If extending:**
- Record `mode=extend` and the path of the file being extended.
- Read the full file and present it in chat.
- The engineer directs edits conversationally — this is not an automated
  diff/merge. Apply edits as the engineer requests them.
- Auto-increment the minor version (e.g. `1.0` to `1.1`) in frontmatter.
- Refresh `last_reviewed` to today's date.
- Skip Stage 4 (philosophy, trigger, and inspiration sources) and Stage 5
  (sub-folder selection) — the file already has all of these. Ask the
  engineer whether they have new inspiration sources to incorporate; if
  yes, run Stage 6 against those sources, otherwise skip to Stage 7
  (conflict detection).
- During conflict detection (Stage 7), exclude the file being extended from
  the scan — comparing it against itself is meaningless.

**If creating (or no overlap found):** Record `mode=create` and proceed to
Stage 4.

---

## Stage 4 — Philosophy, trigger, and inspiration sources

This stage runs only on the **create** path.

Ask the engineer:

> For the new **{topic}** standard:
>
> 1. **Philosophy.** What governing principle should shape edge-case decisions
>    for this standard? (One sentence.)
> 2. **Trigger.** When should Claude apply this file? Describe the situation or
>    context.
> 3. **Inspiration sources.** (Optional) Provide any URLs, file paths, or repo
>    config references I should analyse before drafting. Leave blank if none.

Wait for the engineer's response. Record the philosophy, trigger sentence, and
any inspiration sources.

---

## Stage 5 — Sub-folder selection (zego-ai-standards only)

This stage runs only on the **create** path in `zego-ai-standards`. In consumer
repos, sub-folder selection is skipped — files always go to
`docs/ai/steering/local/`.

Read `.claude/skills/zego-write-standard/standards-authoring.md` — specifically the
Sub-folders section — to determine the correct sub-folder based on the trigger
sentence.

| Trigger pattern | Sub-folder |
|-----------------|-----------|
| Always — any codebase | `base/` |
| When writing [language] code | `languages/` |
| When working on [domain] | `domains/` |
| When the AI pipeline is operating | `governance/` |

Propose a sub-folder to the engineer:

> Based on the trigger sentence, I propose placing this in
> `standards/{subfolder}/`. Confirm or choose a different sub-folder:
> `base/`, `languages/`, `domains/`, `governance/`.

Wait for the engineer's response. Record the confirmed sub-folder.

---

# Source Analysis

From this point, proceed autonomously unless stated otherwise.

---

## Stage 6 — Analyse inspiration sources

**Skip this stage entirely if no inspiration sources were provided** (both on
create and on extend paths).

For each inspiration source:

- **URL**: Fetch the content. If the fetch fails (404, timeout, etc.), surface
  the error to the engineer:

  > Failed to fetch `{url}`: {error}. Would you like to (a) skip this source,
  > or (b) provide an alternative?

  Wait for the engineer's response. Do not skip silently or abort.

- **File path**: Read the file. If it does not exist, surface the error to the
  engineer as above.

- **Repo config reference**: Locate and read the referenced configuration.

For each source that was successfully fetched, produce a
**keep / adapt / ignore** breakdown:

> **Source: {source}**
> - **Keep:** {rules or conventions to adopt directly, with rationale}
> - **Adapt:** {rules to modify for Zego's context, with rationale}
> - **Ignore:** {rules to skip, with rationale}

Record the breakdown for use in the Draft stage.

---

# Conflict Detection

---

## Stage 7 — Scan for conflicts with existing rules

Scan all existing standards files recursively:
- In `zego-ai-standards`: `standards/base/`, `standards/languages/`,
  `standards/domains/`, `standards/governance/`.
- In consumer repos: `docs/ai/steering/base/`, `docs/ai/steering/languages/`,
  `docs/ai/steering/domains/`, `docs/ai/steering/governance/`,
  `docs/ai/steering/local/`.

When extending, exclude the file being extended from the scan.

For each `.md` file (excluding `README.md` files), read the **Rules at a
Glance** section only — not the full file body. Compare the proposed rules
(derived from the topic, philosophy, trigger, and source analysis) against
existing rules.

If a conflict is detected — a proposed rule contradicts an existing rule —
surface it to the engineer:

> **Conflict detected:**
>
> **Proposed rule:** {proposed rule text}
> **Existing rule in `{file}`:** {existing rule text}
>
> These rules appear to contradict each other. How would you like to resolve
> this?

Wait for the engineer to resolve each conflict before proceeding. If resolution
requires changing the standards file, apply the edit before proceeding. Do not
draft until all conflicts are resolved.

If no conflicts are found:

> No conflicts detected with existing standards. Proceeding to draft.

---

# Draft

---

## Stage 8 — Draft the standards file

Read `.claude/skills/zego-write-standard/standards-authoring.md` in full for the required
structure, section order, and rule format.

**On the create path**, draft a new standards file containing:

1. **Frontmatter:**
   ```yaml
   ---
   version: 1.0
   last_reviewed: {today's date, YYYY-MM-DD}
   ---
   ```
   `version` must be a YAML number (not a quoted string). `last_reviewed` is
   today's date.

2. **Title:** `# {Topic} Standards` — title-case the topic noun, end with
   "Standards".

3. **Intro paragraph:** Up to four sentences following the authoring guide
   order: domain + philosophy, trigger sentence, tooling exclusions (if any),
   file-overlap exclusions (if any). The trigger sentence is never optional.

4. **Rules at a Glance:** Each rule follows the format:
   ```
   N. **{Key concept}.** {Imperative statement — why it matters.}
   ```
   Every rule must carry the "why" inline.

5. **Content sections:** One `##` section per rule that warrants rationale or
   examples. The section heading must match the rule's key concept exactly.
   Include `# good` / `# bad` labelled code examples where applicable.

6. **See Also:** (Optional) Cross-references to related standards files.

Incorporate the keep/adapt items from the source analysis breakdown. Ignore
items marked as ignore.

**On the extend path**, the engineer has already directed edits
conversationally in Stage 3. The file should now reflect all requested changes.
Skip writing a new draft — proceed to validation.

Write the file:
- In `zego-ai-standards` (create): `standards/{subfolder}/{filename}.md`
- In consumer repos (create): `docs/ai/steering/local/{filename}.md`

Derive the filename from the topic: lowercase, hyphens for spaces, no special
characters. For example, "Error Handling" becomes `error-handling.md`.

**Collision check** — before writing, verify the resolved target path does not
already exist (attempt a `Read` on the path). If a file already exists at that
location:

1. Surface the collision to the engineer explicitly: state the existing file
   path and explain that writing would overwrite it.
2. Offer three options:
   - **Extend** the existing file instead (switch to the extend path).
   - **Choose a different filename** (ask the engineer for an alternative).
   - **Abort** the write entirely.
3. Do not proceed until the engineer has chosen an option.

---

# Structural Validation

---

## Stage 9 — Validate structure

Read `.claude/skills/zego-write-standard/standards-authoring.md` again for the canonical
structure. Then read the standards file (whether newly created or extended) and
check each of the following:

1. **Frontmatter — version is a YAML number.** `version: 1.0`, not
   `version: "1.0"`.
2. **Frontmatter — `last_reviewed` is present** and set to a valid
   `YYYY-MM-DD` date.
3. **Section order.** Frontmatter, Title, Intro paragraph, Rules at a Glance,
   Content sections, See Also (optional). No sections out of order.
4. **Glance list completeness.** Every rule that appears in a content section
   is listed in Rules at a Glance. No rule exists only in the body.
5. **Intro-paragraph trigger sentence.** The intro paragraph contains a trigger
   sentence (when Claude should apply this file).
6. **Embedded "why" in every rule.** Each rule in Rules at a Glance carries
   the reason inline — no rule is imperative-only without context.
7. **Section headings match glance key concepts.** Each content section heading
   matches the bold key concept of its corresponding rule exactly.
8. **UK English.** Read the spelling standard (specifically the variant table)
   as the canonical reference — `standards/base/spelling.md` in
   `zego-ai-standards`, `docs/ai/steering/base/spelling.md` in consumer repos.
   Check all human-readable text against it.
   Common checks: `-ise` not `-ize`, `-our` not `-or`, `-ogue` not `-og`,
   `-re` not `-er` (for centre/metre), `-ence` not `-ense`, `-l` not `-ll`
   (for fulfil/enrol).

**On validation failure:** present each defect to the engineer with the
specific issue:

> **Validation defect:**
> {Description of the issue, with the specific text and location.}
>
> How would you like to fix this?

Do not auto-fix. Wait for the engineer to address each defect. Re-run
validation after the engineer addresses each one. Loop until the file is clean
or the engineer explicitly aborts.

**On validation pass:**

> Structural validation passed. All checks clean.

---

# Output & Commit

---

## Stage 10 — Update README and discovery files

**On the create path only** (extend does not need README or discovery updates —
the file already has entries):

**Sub-folder README** (both repo types):
- In `zego-ai-standards`: `standards/{subfolder}/README.md`
- In consumer repos: `docs/ai/steering/local/README.md`

If the README exists, append an entry in this format:
```
- [{filename}]({filename}) — {one-line description of what the file covers}.
```

If the README does not exist, create it with a heading and the first entry:
```markdown
# {Sub-folder} Standards

- [{filename}]({filename}) — {one-line description}.
```

For consumer repos, use `# Local Standards` as the heading.

**Claude discovery registration:**

In `zego-ai-standards`:
- Add a reference line to the "Standards in this library" section of
  `CLAUDE.md`, matching the existing entry format:
  ```
  - `docs/ai/steering/{subfolder}/{filename}` — {one-line description}.
  ```

In consumer repos:
- If `CLAUDE.local.md` exists: append a reference line under a "Standards in
  this library" section. If the section does not exist, append it to the end
  of the file with a preceding blank line and `---` separator:
  ```markdown

  ---

  ## Standards in this library

  - `docs/ai/steering/local/{filename}` — {one-line description}.
  ```
  Do not modify `CLAUDE.md` — its body is team-owned.

- If `CLAUDE.local.md` does not exist: print a note to the engineer:

  > `CLAUDE.local.md` does not exist in this repo. To register the new
  > standard for Claude discovery, add the following line to your preferred
  > discovery file (or create `CLAUDE.local.md`):
  >
  > ```
  > - `docs/ai/steering/local/{filename}` — {one-line description}.
  > ```

---

## Stage 11 — Engineer review

Present the completed standards file to the engineer for review. Include a
summary of what was produced:

> **Standards file ready for review:**
>
> - **File:** `{path}`
> - **Topic:** {topic}
> - **Version:** {version}
> - **Rules:** {count} rules in Rules at a Glance
> - **Mode:** {create | extend}
>
> Options:
> (a) **Request edits** — tell me what to change and I will apply the edits
>     and re-validate.
> (b) **Reject entirely** — revert all changes, leaving `git status` clean.
> (c) **Approve** — proceed to commit.

Wait for the engineer's response.

**Option (a) — request edits:** Apply the requested edits. Re-run Stage 9
(structural validation). Then present this review prompt again. Loop until the
engineer chooses (b) or (c).

**Option (b) — reject:**

On the **create** path: revert all artefacts produced by this skill — the
standards file, the README edit, and any `CLAUDE.md` or `CLAUDE.local.md`
edit. Use `git checkout` to restore modified files and `rm` to remove newly
created files. Verify `git status` is clean.

On the **extend** path: restore the file's pre-edit content by running
`git checkout HEAD -- {file}` to revert both index and working tree for
that file to the HEAD version without affecting any other files. The README and
`CLAUDE.md`/`CLAUDE.local.md` are not modified during extension (the file
already has entries), so no README/CLAUDE revert is needed.

**Option (c) — approve:** Proceed to Stage 12.

---

## Stage 12 — Commit

Check the current branch:

```bash
git branch --show-current
```

If the branch is `main` or `master`, warn the engineer:

> You are on the `{branch}` branch. Committing directly to `{branch}` is not
> recommended. Would you like to (a) continue anyway, or (b) create a feature
> branch first?

Wait for the engineer's response. If they choose (b), ask for a branch name
and create it.

Stage and commit all files produced by this skill:

On the **create** path:
```bash
git add {standards file} {README file} {CLAUDE.md or CLAUDE.local.md if modified}
git commit -m "$(cat <<'EOF'
Add {topic} standards

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

On the **extend** path:
```bash
git add {standards file}
git commit -m "$(cat <<'EOF'
Extend {topic} standards

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Stage 13 — Report

Report to the engineer:

> **Standard written successfully.**
>
> - **File:** `{path}`
> - **Topic:** {topic}
> - **Version:** {version}
> - **Mode:** {create | extend}
> - **Rules:** {count} rules
> - **Branch:** `{branch}`
> - **Commit:** `{short hash}`

---

## Rules

- **Interview stages are interactive.** Wait for engineer input at every stage
  in the Interview and Conflict Detection groups. Do not skip ahead.
- **Source Analysis and Draft stages are autonomous.** No questions to the
  engineer unless a source fetch fails.
- **Structural Validation is autonomous with engineer fallback.** Validation
  runs without prompts, but defects are presented to the engineer for
  resolution — do not auto-fix.
- **Output & Commit is interactive.** The engineer reviews and approves or
  rejects before any commit.
- **Read the authoring guide at point of need.** Reference
  `.claude/skills/zego-write-standard/standards-authoring.md` via `Read` when drafting
  (Stage 8) and when validating (Stage 9). Do not load it upfront.
- **Extend before create.** Always check for existing coverage before creating
  a new file. Extending preserves rule density and avoids fragmentation.
- **Auto-increment version on extend.** Bump the minor version (e.g. `1.0` to
  `1.1`) automatically. Do not prompt the engineer for the version.
- **Refresh `last_reviewed` on extend.** Set `last_reviewed` to today's date
  when extending an existing file.
- **Source analysis runs only when sources exist.** Skip Stage 6 entirely if
  no inspiration sources were provided (both create and extend paths).
- **Conflict detection excludes the file being extended.** Do not compare a
  file against itself.
- **Reject must leave `git status` clean.** On create, revert all artefacts.
  On extend, restore the file's pre-edit content using `git checkout HEAD -- {file}`.
- **Consumer repos write to `docs/ai/steering/local/`.** Sub-folder selection
  is skipped. Do not modify `CLAUDE.md` in consumer repos — its body is
  team-owned.
- **`zego-ai-standards` writes to `standards/{subfolder}/`.** The
  `docs/ai/steering/` paths are symlinks. Reference lines in `CLAUDE.md` use
  `docs/ai/steering/...` paths regardless of physical location.
- **Do not conflate trigger concepts.** The intro-paragraph trigger sentence
  (when Claude should apply the file) is distinct from the skill description
  triggering conditions (when Claude should invoke the skill, per ADR 006).
- **UK English throughout.** All human-readable text must use UK English
  spelling, using the variant table in the spelling standard as the canonical
  reference (`standards/base/spelling.md` in `zego-ai-standards`,
  `docs/ai/steering/base/spelling.md` in consumer repos).
- **Do not modify existing standards files.** This skill creates new files or
  extends existing files only at the engineer's direction. It does not
  autonomously alter other standards files.
- **Do not modify existing skills.** This skill does not alter any other skill
  under `.claude/skills/`.
- **`version` is a YAML number.** Write `version: 1.0`, not
  `version: "1.0"`. The authoring guide requires this.
- **Branch safety.** Before committing, verify the current branch is not `main`
  or `master`. Warn and offer alternatives if it is.
- **Frontmatter uses exactly two fields.** Standards files have `version` and
  `last_reviewed` only — no other frontmatter fields.

# Onboard

Orient an engineer who is new to this repository's Zego AI standards setup.
Produce a single conversational orientation — read-only, no files written and
no git operations. Gather the inventory live from this repo; never recite a
hardcoded skill list.

Read these sources, and only these:

1. **`CLAUDE.md` and `CLAUDE.local.md` frontmatter** — report the deployed
   `standards_version`, read from `CLAUDE.md` (the one fan-out-managed key).
   Then read the `ci-test-command` key from `CLAUDE.local.md` (it is
   team-owned, not fan-out-managed, and lives there so it survives standards
   bumps): if it is present, report its value and explain its purpose — it is
   the explicit override for the commands the `ci-validation` flow runs before
   committing. If it is absent, say so and explain that validation then
   discovers the commands automatically from `.buildkite/pipeline.yml` or
   `.github/workflows/*.yml`, and that declaring `ci-test-command` is the fix
   when local CI validation behaves inconsistently.
2. **The CLAUDE.md "Skills available in this repo" skill list** — the
   installed inventory as CLAUDE.md declares it.
3. **A directory listing of `.claude/skills/`** — a skill on disk means a
   subdirectory that contains a `SKILL.md`. Count only those. The `README.md`
   file and the `shared/` directory (it holds shared execution fragments, not a
   skill) are excluded and never count as drift. Do **not** read
   `.claude/skills/README.md` as an inventory source — it is hand-maintained
   and has no forcing function keeping it current. Do **not** read the body of
   each `SKILL.md` — the directory listing plus the CLAUDE.md list is enough.
   If sources 2 and 3 disagree — a skill on disk that the CLAUDE.md list
   omits, or a listed skill with no `SKILL.md` on disk — the disk listing
   (source 3) wins as the record of what is installed, because CLAUDE.md is
   hand-maintained and can lag. Flag every such CLAUDE.md↔disk mismatch as
   drift in the orientation.
4. **`docs/ai/steering/base/skill-pipeline.md`** — the pipeline narrative:
   which skill to use when, the ordering, the skip rules, and the per-phase PR
   handoff shape.

Then produce the orientation, covering:

- **The "do your homework first" principle, stated up front.** These skills
  *formalise* investigation the engineer has already done — they turn real
  requirements, decisions, and research into structured artefacts. They are
  **not** a substitute for that investigation and must not be used to invent or
  fill in information that has not actually been established. Lead the
  orientation with this (it is the single most important thing to convey, per
  the `skill-pipeline.md` narrative) — do not bury it beneath the inventory.
- The deployed `standards_version`.
- The `ci-test-command` value and its purpose, per source 1 above.
- The available skills, each with a one-line purpose, taken from the live
  inventory (sources 2 and 3) reconciled against the pipeline narrative
  (source 4).
- The end-to-end pipeline flow from requirements to a merged PR, including the
  per-phase PR shape — each phase hands off through its own pull request, and a
  PR is opened only when explicitly requested, never automatically.

**Reconcile inventory against the narrative and flag drift, both directions.**
Compare the skills on disk (source 3, subdirectories containing a `SKILL.md`,
excluding `README.md` and `shared/`) against the skills named in
`skill-pipeline.md`. Report every divergence verbatim, never guessing around
it. A skill named in the narrative but absent from disk is genuine drift — the
narrative promises something the repo does not provide, so flag it as such.
A skill present on disk but absent from the narrative is **not** drift: teams
are actively encouraged to extend the happy path with their own skills (for
example, requirement- or design-gathering steps), and `skill-pipeline.md` in a
consumer repo is overwritten by fan-out, so a local extension cannot be carried
in it. Report such a skill as an **expected, sanctioned extension** — a
team-added skill that extends the standard pipeline — and judge from its
CLAUDE.md description (source 2) whether it sits on the happy path (a step a
feature runs through from requirements to a merged PR) or is conditional
remediation invoked after a PR, so the orientation can place it correctly.
Frame this as the engineer having done exactly what we asked, never as a
mistake. If CLAUDE.md has no entry for the skill, do not guess its role — note
the CLAUDE.md↔disk mismatch per source 3 and report the skill as an extension
whose pipeline role could not be determined. A disk-only off-path utility is
likewise a sanctioned extension (`write-skill` Stage 12c permits leaving
off-path skills out of the narrative): mention it as an off-path skill not
covered by the narrative. Reserve "drift" language for genuine
inconsistencies — a skill named in the narrative or CLAUDE.md but missing from
disk, or vice versa — never for legitimate team extensions.

**If CLAUDE.md or CLAUDE.local.md is absent or its frontmatter cannot be
parsed**, say so plainly and proceed with whatever inventory the
`.claude/skills/` listing (source 3) alone yields. Do not fabricate a
`standards_version` (from CLAUDE.md) or `ci-test-command` (from
CLAUDE.local.md) value — report them as unavailable.

**If `docs/ai/steering/base/skill-pipeline.md` is missing**, say so plainly and
fall back to an inventory-only orientation built from CLAUDE.md and the
`.claude/skills/` listing. Do not fabricate a pipeline narrative.

export const meta = {
  name: "review-gate",
  description:
    "Run one review-gate pass (design or task): fan out blind check agents, aggregate their findings, write a per-round findings file, and return a compact result.",
  phases: [
    { title: "Checks", detail: "fan out the in-scope blind check agents" },
    { title: "Aggregate", detail: "dedup, dismissal-filter, write findings file" },
  ],
};

// review-gate.js — one review-gate pass (design or task) as a Workflow tool.
//
// Runs a single gate round: fans out the in-scope blind check agents in
// parallel, aggregates their findings via an aggregation agent, and returns a
// compact result. The script performs NO filesystem access: every Read (rubric,
// artefact, context, prior findings, `## Dismissals`) and the findings-file
// Write is delegated to the agents it spawns. It does pure-JS orchestration over
// the agents' structured returns.
//
// Workflow runtime contract this file obeys (see the Workflow tool description):
//   - `export const meta` is the FIRST statement.
//   - The script BODY runs directly; there is no `(args, ctx)` entrypoint and no
//     `export default`. Inputs arrive via the global `args`; `agent`, `parallel`,
//     `phase`, and `log` are globals. A top-level `return` is the workflow result.
//   - The script is self-contained — relative `import` does not resolve in the
//     sandbox, so the dispatch config lives inline here rather than in a sibling.
//   - No filesystem Read/Write in the script (all I/O via agents); no
//     Date.now()/Math.random() (the round is an input arg and the findings
//     filename is derived from ticket/artefactSlug/round); the check fan-out
//     concurrency is auto-capped at min(16, cores - 2) by `parallel`.
//
// The authoritative contract is the design's `## Interface contracts` (contracts
// 1, 2, 3, 5) in docs/design/AIDEV-132-launch-safe-write-design-doc-max-gates.md
// (the argument contract was relocated there from the original AIDEV-122 design
// per ADR 014).

// ----- dispatch configuration -----
//
// Each check agent owns one consolidated review dimension. The task gate runs
// ONCE over the whole spec set (artefactPath is an array of spec paths) rather
// than once per spec: cross-spec dimensions (ownership overlap,
// dependency/interface consistency, set-level completeness) are only
// detectable across the set, and seeing the set grounds severity relative to
// the whole batch. Header validation is a deterministic script run by SKILL.md
// (scripts/verify-design-header.py), not an agent.
//
// `context` is the set of scoped context categories for the check; each category
// resolves to a concrete Read instruction in the check-agent prompt:
//   "steering"  -> the curated steeringIndex plus a relevance rule (read the full
//                  text only of plausibly-relevant docs; read when uncertain);
//                  when steeringIndex is null, degrade to "Read all files under
//                  `docs/ai/steering/`" with a notice
//   "codebase"  -> the contextPackPath (a single pre-read pack file holding every
//                  in-scope codebase file's full content under `## {path}`
//                  headings, built once per session by SKILL.md) when provided;
//                  otherwise an explicit list of the codebaseFilePaths to Read
//   (no entry)  -> nothing beyond the artefact (and inline requirements text)

// Path to the shared principles document every check agent reads first.
const CHECK_PRINCIPLES_PATH = ".claude/skills/zego-write-design-doc-max/check-principles.md";

// Directory each check rubric lives under.
const CHECKS_DIR = ".claude/skills/zego-write-design-doc-max/checks";

// Directory the per-round findings file is written under.
const REVIEWS_DIR = "docs/ai/reviews";

// Design gate — 5 consolidated dimensions. grounding reads the codebase (via
// the context pack); steering-compliance reads via the curated index; the rest
// review the artefact alone.
const DESIGN_CHECKS = [
  { name: "requirements-coverage", model: "haiku", context: [] },
  { name: "grounding", model: "sonnet", context: ["codebase"] },
  { name: "steering-compliance", model: "sonnet", context: ["steering"] },
  { name: "task-ordering", model: "sonnet", context: [] },
  { name: "robustness-verifiability", model: "sonnet", context: [] },
];

// Task gate — 6 consolidated dimensions, run ONCE over ALL task specs
// (artefactPath is the array of spec paths). scope-boundaries and completeness
// absorbed the former sync-check's cross-spec checks; there is no separate
// sync-check stage.
const TASK_CHECKS = [
  { name: "completeness", model: "sonnet", context: [] },
  { name: "opus-sufficiency", model: "sonnet", context: [] },
  { name: "grounding", model: "sonnet", context: ["codebase"] },
  { name: "scope-boundaries", model: "sonnet", context: [] },
  { name: "steering-compliance", model: "sonnet", context: ["steering"] },
  { name: "robustness-verifiability", model: "sonnet", context: [] },
];

// The verbatim re-raise sentence embedded in the aggregation prompt. This exact
// wording is authoritative for this script; it is NOT sourced from the check
// rubrics' "Dismissal handling" sections (gate-specific variants disagree) nor
// from ADR 010 (which carries no re-raise rule).
const RE_RAISE_SENTENCE =
  "if the design or the relevant component has changed significantly since " +
  "the dismissal was recorded, re-raise the finding rather than silently " +
  "skipping it.";

// The warning string returned in `report` for the ZERO_FINDINGS_WARNING outcome.
const ZERO_FINDINGS_WARNING_TEXT =
  "Zero findings across all checks — verify this is expected before accepting";

// The six ADR-010 finding fields, shared by both schemas below, plus the
// required-but-nullable `Spec` attribution field: at the task gate (multi-spec
// batch) it carries the affected spec's filename so SKILL.md can route a
// spec-patch; null for design-gate findings and genuinely cross-spec findings.
// Making it required (rather than optional) removes the omitted-vs-null
// ambiguity so "cross-spec" is always an explicit null, never an absence.
const FINDING_FIELDS = {
  Severity: { type: "string", enum: ["Critical", "High", "Medium", "Nit pick"] },
  Issue: { type: "string" },
  "Why it matters": { type: "string" },
  "Size of fix": { type: "string", enum: ["trivial", "local", "broad"] },
  Target: { type: "string", enum: ["load-bearing", "illustrative"] },
  "Suggested resolution": { type: "string" },
  Spec: { type: ["string", "null"] },
};
const FINDING_REQUIRED = [
  "Severity",
  "Issue",
  "Why it matters",
  "Size of fix",
  "Target",
  "Suggested resolution",
  "Spec",
];

// FINDINGS_SCHEMA — the schema each blind check agent returns against.
// An array of zero or more findings, each carrying the six ADR-010 fields.
const FINDINGS_SCHEMA = {
  type: "object",
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: { ...FINDING_FIELDS },
        required: [...FINDING_REQUIRED],
        additionalProperties: false,
      },
    },
  },
  required: ["findings"],
  additionalProperties: false,
};

// AGGREGATION_SCHEMA — the schema the aggregation agent returns against.
// `report` is the post-dismissal, deduped, severity-grouped, annotated findings;
// `fileWritten` confirms the on-disk write; `errorKind` attributes input-read
// failures without an opaque throw.
const AGGREGATION_SCHEMA = {
  type: "object",
  properties: {
    report: {
      type: "array",
      items: {
        type: "object",
        properties: { ...FINDING_FIELDS, annotation: { type: "string" } },
        required: [...FINDING_REQUIRED, "annotation"],
        additionalProperties: false,
      },
    },
    fileWritten: { type: "boolean" },
    errorKind: {
      type: ["string", "null"],
      enum: [null, "prior-findings-unreadable", "design-unreadable"],
    },
  },
  required: ["report", "fileWritten", "errorKind"],
  additionalProperties: false,
};

// ----- pure helpers (no I/O, no nondeterminism) -----

// Deterministic findings-file path. round zero-padded to three digits.
// No Date.now()/Math.random(): derived solely from ticket/artefactSlug/round.
function findingsFilePath(ticket, artefactSlug, round) {
  const nnn = String(round).padStart(3, "0");
  return `${REVIEWS_DIR}/${ticket}-${artefactSlug}-gate-${nnn}.md`;
}

// Lowercase-normalised severity counts over the post-dismissal report.
function countSeverities(report) {
  const counts = { critical: 0, high: 0, medium: 0, nit: 0 };
  for (const finding of report) {
    switch (finding.Severity) {
      case "Critical":
        counts.critical += 1;
        break;
      case "High":
        counts.high += 1;
        break;
      case "Medium":
        counts.medium += 1;
        break;
      case "Nit pick":
        counts.nit += 1;
        break;
      default:
        break;
    }
  }
  return counts;
}

// The compact return shape — exactly the six contract-1 fields, all present.
function result({
  findingsPath = null,
  outcome,
  haltReason = null,
  report,
  notices,
  stats,
}) {
  return { findingsPath, outcome, haltReason, report, notices, stats };
}

function zeroCounts() {
  return { critical: 0, high: 0, medium: 0, nit: 0 };
}

function emptyStats() {
  return { checksRun: 0, checksFailed: 0, findingCounts: zeroCounts() };
}

// ----- prompt builders -----

// Resolve a config `context` set into concrete prompt Read instructions.
function contextInstructions(
  context,
  codebaseFilePaths,
  steeringIndex,
  contextPackPath,
) {
  const lines = [];
  for (const category of context) {
    if (category === "steering") {
      if (typeof steeringIndex === "string" && steeringIndex.trim() !== "") {
        lines.push(
          "A curated index of the steering docs is provided below. Read the " +
            "full text only of the docs whose one-line description is " +
            "plausibly relevant to the artefact under review; when you are " +
            "uncertain whether a doc is relevant, read it. Do not skip a doc " +
            "you have any reason to think might apply.\n" +
            steeringIndex,
        );
      } else {
        // Null index — the curated lists could not be parsed, or they parsed
        // but were incomplete (the completeness cross-check found an omitted
        // normative doc). Degrade to the legacy read-all behaviour with an
        // explicit notice so steering compliance is never silently skipped.
        lines.push(
          "No steering index was provided (the curated lists could not be " +
            "parsed, or were incomplete); degrading to read-all. Read all " +
            "files under `docs/ai/steering/`.",
        );
      }
    } else if (category === "codebase") {
      if (typeof contextPackPath === "string" && contextPackPath.trim() !== "") {
        lines.push(
          `Read the codebase context pack at \`${contextPackPath}\` — it ` +
            "contains the full text of every in-scope codebase file, one " +
            "`## {path}` heading per file. Read the pack instead of the " +
            "individual files. If a file the artefact references is absent " +
            "from the pack, you may read that single file directly to verify " +
            "the reference before judging it non-existent.",
        );
      } else if (codebaseFilePaths.length === 0) {
        lines.push("No codebase files are in scope for this review; read none.");
      } else {
        const list = codebaseFilePaths.map((p) => `- ${p}`).join("\n");
        lines.push(`Read each of these codebase files:\n${list}`);
      }
    }
  }
  return lines;
}

// Build the blind check agent prompt for one in-scope check (Interface contract 2).
// `artefactPath` is a single path (design gate) or an array of task-spec paths
// (task gate batch review).
function checkPrompt({
  check,
  artefactPath,
  designPath,
  requirementsText,
  codebaseFilePaths,
  steeringIndex,
  contextPackPath,
  round,
}) {
  const rubricPath = `${CHECKS_DIR}/${check.name}.md`;
  const isBatch = Array.isArray(artefactPath);
  const roundFraming =
    round === 1
      ? `This is review round 1. Review exhaustively: walk every rubric ` +
        `item against the artefact before returning. Report only findings ` +
        `that pass the emission gate; an empty findings array is valid ` +
        `after a genuine full pass — do not pad it with marginal findings ` +
        `to avoid an empty return.`
      : `This is review round ${round}. The artefact has been revised in ` +
        `response to earlier rounds and should be converging. An empty ` +
        `findings array is valid and expected when the revisions genuinely ` +
        `resolved the earlier concerns; do not manufacture findings to ` +
        `avoid an empty return.`;
  const artefactLines = isBatch
    ? [
        "- Every task spec under review — read ALL of them, in order:",
        ...artefactPath.map((p) => `  - \`${p}\``),
      ]
    : [`- The artefact under review at \`${artefactPath}\`.`];
  const lines = [
    `You are the blind check agent "${check.name}" for a review gate.`,
    "",
    roundFraming,
    "",
    "Read these files in full before forming any finding:",
    `- The shared principles at \`${CHECK_PRINCIPLES_PATH}\`.`,
    `- Your own rubric at \`${rubricPath}\`.`,
    ...artefactLines,
    `- The design document at \`${designPath}\` (the source of design context).`,
  ];
  for (const instruction of contextInstructions(
    check.context,
    codebaseFilePaths,
    steeringIndex,
    contextPackPath,
  )) {
    lines.push(`- ${instruction}`);
  }
  if (isBatch) {
    lines.push("");
    lines.push(
      "Attribute every finding to the affected spec by setting its `Spec` " +
        "field to that spec's filename; use null only for genuinely " +
        "cross-spec (set-level) findings. Cover every spec — do not stop " +
        "after the first specs reviewed.",
    );
  } else {
    lines.push("");
    lines.push(
      "A single artefact is under review, so there is no per-spec " +
        "attribution: set every finding's required `Spec` field to null.",
    );
  }
  if (requirementsText !== null && requirementsText !== undefined) {
    lines.push("");
    lines.push(
      "The full requirements source is provided inline below (there is no " +
        "requirements file to read — use this text directly):",
    );
    lines.push(`<requirementsText>\n${requirementsText}\n</requirementsText>`);
  }
  lines.push("");
  lines.push(
    "If you cannot Read any required file (your rubric, " +
      "`check-principles.md`, the artefact, or a config-declared context " +
      "file), stop and fail immediately — do not return findings derived " +
      "from partial context.",
  );
  lines.push("");
  lines.push(
    "Apply your rubric and the shared principles, then return the findings " +
      "array (empty if none) per the schema. Each finding carries the six " +
      "fields: Severity, Issue, Why it matters, Size of fix, Target, " +
      "Suggested resolution — plus the required `Spec` field (the affected " +
      "spec's filename when multiple task specs are under review, otherwise " +
      "null).",
  );
  return lines.join("\n");
}

// Build the aggregation agent prompt (Interface contract 3).
function aggregationPrompt({
  survivingResults,
  designPath,
  priorFindingsPath,
  notices,
  outputPath,
  round,
}) {
  const blocks = survivingResults.map(
    (r) =>
      `Findings from check "${r.check}":\n${JSON.stringify(r.findings, null, 2)}`,
  );
  const noticesJson = JSON.stringify(notices, null, 2);
  const priorClause =
    priorFindingsPath == null
      ? "This is round 1; there is no prior findings file — annotate every " +
        "surviving finding `new`."
      : `Read the prior round's findings file at \`${priorFindingsPath}\` to ` +
        "compare round over round.";
  return [
    "You are the aggregation agent for a review gate. You receive the raw " +
      "findings arrays from the surviving check agents and must produce one " +
      "deduped, dismissal-filtered, severity-grouped, annotated report and " +
      "write it to disk.",
    "",
    "Surviving check findings:",
    ...blocks,
    "",
    `Read the design document at \`${designPath}\` to obtain its ` +
      "`## Dismissals` section. Filter out any finding semantically " +
      "equivalent to a recorded dismissal — the same specific gap in the " +
      "same component. However: " +
      RE_RAISE_SENTENCE,
    "If the design is readable but contains no `## Dismissals` section, " +
      "proceed with an empty dismissal set — this is a normal first-round " +
      "state, not an error; set `errorKind` to null.",
    "",
    priorClause,
    "",
    "After dismissal-filtering: dedup semantically-equivalent findings " +
      "(two findings are equivalent only when they name the same gap in the " +
      "same component AND the same spec — preserve each finding's `Spec` " +
      "field verbatim through dedup), group " +
      "by severity in the order Critical -> High -> Medium -> Nit pick, and " +
      `annotate each surviving finding either \`new\` or ` +
      "`persisted-from-round-N` (N is the round in which it first appeared, " +
      `relative to the current round ${round}).`,
    "",
    `Write the result to \`${outputPath}\`. The file content is: a header ` +
      "(ticket, gate type, round, artefact path, prior-round path), then the " +
      "severity-grouped findings (each carrying the six fields plus its " +
      "`new`/`persisted-from-round-N` annotation). You MUST write the file on " +
      "ANY zero-finding round, regardless of cause — both when the surviving " +
      "check agents returned no findings at all (the input findings arrays are " +
      "all empty from the start) AND when findings were present but " +
      "dismissal-filtering removed every one. In either case the findings " +
      "section is empty but the file is still a valid, fully-written findings " +
      "file: its header (ticket, gate type, round, artefact path, " +
      "prior-round path) followed by an empty findings section — never a " +
      'skipped write. Do not treat "nothing to aggregate" as "nothing to ' +
      'write": always Write the file and return `fileWritten: true` on a ' +
      "successful write, even when the input findings arrays are all empty.",
    "",
    "Notices input (per-check failure/skip strings collected by the script):",
    noticesJson,
    "When the `notices` input is a non-empty array, after writing the " +
      "severity-grouped findings (which may be an empty section if all " +
      "findings were dismissed) append a `## Notices` Markdown heading and " +
      "beneath it one line per notice string, preserving the bracketed " +
      "`[check X failed: <reason>]` / `[check X skipped: <reason>]` format " +
      "verbatim; when `notices` is empty, omit the section entirely (do not " +
      "write a heading with no entries).",
    "",
    "Error signalling — do NOT throw on an input-read failure; instead set " +
      "`errorKind`:",
    '- If reading `priorFindingsPath` fails, return `errorKind: ' +
      '"prior-findings-unreadable"` (do not throw).',
    '- If reading `designPath` fails, return `errorKind: "design-unreadable"` ' +
      "(do not throw).",
    '- If both fail, report `"prior-findings-unreadable"`.',
    "- Throw only on a genuine logic failure unrelated to file reading.",
    "",
    "Return `{ report, fileWritten, errorKind }`: `report` is the " +
      "post-filter severity-grouped annotated findings (empty array if all " +
      "dismissed); `fileWritten` is true only if the Write succeeded; " +
      "`errorKind` is null unless an input-read failure occurred.",
  ].join("\n");
}

// ----- check fan-out with per-check retry-then-notice -----

// Dispatch one check; retry once as a singleton on throw/null; on a second
// failure return a failure marker carrying the notice reason. Uses the global
// `agent`.
async function runCheck(check, prompt) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const out = await agent(prompt, {
        model: check.model,
        schema: FINDINGS_SCHEMA,
        label: check.name,
        phase: "Checks",
      });
      if (out && Array.isArray(out.findings)) {
        return { check: check.name, ok: true, findings: out.findings };
      }
      // null/malformed return — falls through to retry or failure.
      if (attempt === 1) {
        return {
          check: check.name,
          ok: false,
          reason: "returned malformed or null output",
        };
      }
    } catch (err) {
      if (attempt === 1) {
        return {
          check: check.name,
          ok: false,
          reason: String(
            (err && err.message) || (err && JSON.stringify(err)) || err,
          ),
        };
      }
    }
  }
  // The loop always returns by attempt 1; this keeps the function total.
  return { check: check.name, ok: false, reason: "unknown failure" };
}

// ----- aggregation with the contract-3 error routing -----

// Uses the global `agent`.
async function runAggregation(prompt) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    let out;
    try {
      out = await agent(prompt, {
        model: "sonnet",
        schema: AGGREGATION_SCHEMA,
        label: "aggregation",
        phase: "Aggregate",
      });
    } catch (err) {
      // Genuine logic failure (throw): retry once, then HALT.
      if (attempt === 1) {
        return { halt: "aggregation failed" };
      }
      continue;
    }
    if (!out || !Array.isArray(out.report)) {
      // Malformed/unparseable: logic failure — retry once, then HALT.
      if (attempt === 1) {
        return { halt: "aggregation failed" };
      }
      continue;
    }
    const errorKind = out.errorKind || null;
    if (errorKind === "prior-findings-unreadable") {
      // Terminal: a genuinely absent prior-findings file is not retried.
      return { haltKind: "prior-findings-unreadable" };
    }
    if (errorKind === "design-unreadable") {
      // Retry once; a second design-unreadable HALTs.
      if (attempt === 1) {
        return { haltKind: "design-unreadable" };
      }
      continue;
    }
    return { ok: true, report: out.report, fileWritten: out.fileWritten };
  }
  return { halt: "aggregation failed" };
}

// ----- orchestration (the workflow body) -----

// `args` is the value passed to the Workflow invocation. It normally arrives as
// an object, but the harness may deliver it as a JSON string — tolerate both.
// Malformed JSON string args, or a `null`/non-object args value, are caller
// errors: HALT gracefully rather than letting the parse or destructure throw a
// wholesale Workflow rejection (symmetric with the invalid-gateType HALT below).
let gateType,
  artefactPath,
  designPath,
  requirementsText,
  codebaseFilePaths,
  ticket,
  artefactSlug,
  round,
  priorFindingsPath,
  steeringIndex,
  contextPackPath;
try {
  const input = typeof args === "string" ? JSON.parse(args) : args;
  ({
    gateType,
    artefactPath,
    designPath,
    requirementsText,
    codebaseFilePaths,
    ticket,
    artefactSlug,
    round,
    priorFindingsPath,
    steeringIndex,
    contextPackPath,
  } = input);
} catch {
  return result({
    outcome: "HALT",
    haltReason: "invalid args",
    report: [],
    notices: [],
    stats: emptyStats(),
  });
}

// Normalise `round` at the arg boundary — it may arrive as a string. Rebind the
// destructured binding itself (not a throwaway local) so every downstream
// reference sees the clean integer. The predicate checks integrality, not mere
// positivity: a bare `> 0` would admit a float like 1.7, which
// String(round).padStart(3, "0") renders as '1.7', corrupting the findings path.
// Same placement and HALT mechanism as the invalid-gateType halt below.
// The `Number.isInteger(round) && round >= 1` predicate is the contract, not the
// source type: exotic coercions like Number(true) === 1 and Number([1]) === 1
// pass and correctly take the round-1 path, intentionally — hence no
// `typeof round === "number"` guard.
round = Number(round);
if (!(Number.isInteger(round) && round >= 1)) {
  return result({
    outcome: "HALT",
    haltReason: "invalid round",
    report: [],
    notices: [],
    stats: emptyStats(),
  });
}

// Invalid gateType — caller error: HALT, no dispatch, no retry.
let checks;
if (gateType === "design") {
  checks = DESIGN_CHECKS;
} else if (gateType === "task") {
  checks = TASK_CHECKS;
} else {
  return result({
    outcome: "HALT",
    haltReason: `invalid gateType: ${gateType}`,
    report: [],
    notices: [],
    stats: emptyStats(),
  });
}

const notices = [];

// Build the dispatch list, applying the requirements-coverage skip path.
const dispatch = [];
for (const check of checks) {
  if (
    check.name === "requirements-coverage" &&
    (requirementsText === null || requirementsText === undefined)
  ) {
    notices.push(
      "[check requirements-coverage skipped: no requirements source]",
    );
    continue;
  }
  dispatch.push(check);
}

// Fan out the dispatched checks in parallel. `parallel` auto-caps concurrency at
// min(16, cores - 2), which comfortably fits the dimension count.
phase("Checks");
const tasks = dispatch.map((check) => () => {
  const prompt = checkPrompt({
    check,
    artefactPath,
    designPath,
    requirementsText,
    codebaseFilePaths,
    steeringIndex,
    contextPackPath,
    round,
  });
  return runCheck(check, prompt);
});
const checkResults = await parallel(tasks);

// Partition into survivors (ok) and failures, recording failure notices. A thunk
// that throws resolves to null in the parallel result array — treat that as a
// failed check too (defensive: runCheck is total, so this should not occur).
const survivors = [];
let checksFailed = 0;
for (const r of checkResults) {
  if (r && r.ok) {
    survivors.push(r);
  } else {
    checksFailed += 1;
    const name = (r && r.check) || "unknown";
    const reason = (r && r.reason) || "agent returned null";
    notices.push(`[check ${name} failed: ${reason}]`);
  }
}
const checksRun = dispatch.length;

// Outcome ladder — evaluated in this exact order. Round 1 always writes a
// findings file: a round-1 all-empty sweep is no longer short-circuited here as
// a pure-JS ZERO_FINDINGS_WARNING with findingsPath: null. Instead every round
// with at least one survivor falls through to the aggregation path below, which
// writes the (empty-or-not) findings file via the aggregation agent; the
// post-aggregation report.length === 0 redirect then decides the round-aware
// outcome — ZERO_FINDINGS_WARNING (findingsPath set) on round 1, PASS on
// round >= 2 — so the Per-round commit trigger and the (count, round) recovery
// heuristic both have a file to act on. A failed check rides in `notices` and
// does NOT demote the round. The zero-survivors NOTICES_ONLY branch stays first
// after the dispatch: it must not fall into the aggregation path (there is
// nothing to aggregate), and its survivors.length === 0 guard keeps it mutually
// exclusive with the all-empty round-1 ZERO_FINDINGS_WARNING that the
// aggregation path produces — preserving the AIDEV-129 invariant that a
// zero-survivors round is NOTICES_ONLY, never ZERO_FINDINGS_WARNING.

if (survivors.length === 0) {
  // Zero survivors (every dispatched check failed its retry) — NOTICES_ONLY.
  return result({
    findingsPath: null,
    outcome: "NOTICES_ONLY",
    report: [],
    notices,
    stats: { checksRun, checksFailed, findingCounts: zeroCounts() },
  });
}

// Every surviving round reaches the aggregation agent now: at least one
// surviving check returned a non-empty findings array, OR this is an all-empty
// sweep (any round) falling through to write the findings file. The round-1
// ZERO_FINDINGS_WARNING no longer short-circuits before aggregation — round 1
// always writes a file, and the round-aware outcome is decided post-aggregation
// at the report.length === 0 redirect below. The script passes its accumulated
// `notices` so the agent can append a `## Notices` section to the on-disk file.
phase("Aggregate");
const outputPath = findingsFilePath(ticket, artefactSlug, round);
// Pass every survivor's array to aggregation (including empty ones — the round
// reached here because at least one survivor was non-empty, OR this is an
// all-empty sweep falling through to the aggregation path to write the file).
const survivingResults = survivors.map((r) => ({
  check: r.check,
  findings: r.findings,
}));

const agg = await runAggregation(
  aggregationPrompt({
    survivingResults,
    designPath,
    priorFindingsPath,
    notices,
    outputPath,
    round,
  }),
);

const baseStats = { checksRun, checksFailed, findingCounts: zeroCounts() };
const halt = (haltReason) =>
  result({ outcome: "HALT", haltReason, report: [], notices, stats: baseStats });

if (agg.halt) {
  return halt(agg.halt);
}
if (agg.haltKind === "prior-findings-unreadable") {
  return halt(`prior findings file unreadable: ${priorFindingsPath}`);
}
if (agg.haltKind === "design-unreadable") {
  return halt(`design document unreadable: ${designPath}`);
}
// Aggregation succeeded with errorKind null. Confirm the file was written.
if (!agg.fileWritten) {
  return halt("findings-file write failed");
}

const report = agg.report;
// findingCounts come from the POST-dismissal report the engineer sees.
const findingCounts = countSeverities(report);
const stats = { checksRun, checksFailed, findingCounts };

if (report.length === 0) {
  // The post-aggregation report is empty — either an all-empty survivor sweep or
  // an all-dismissed sweep (findings present, all dismissal-filtered away). The
  // file is still written (durable record). This point is round-aware and must
  // REDIRECT round 1, not merely exclude it: a bare `round !== 1` guard on a
  // PASS branch would let an excluded round-1 empty report fall through to the
  // FINDINGS branch below with an empty `report`, violating the contract. So
  // round 1 returns ZERO_FINDINGS_WARNING with findingsPath SET (the AIDEV-129
  // round-1 "finds nothing is suspicious" surface, now with a written file);
  // round >= 2 returns PASS (a converged clean or fully-dismissed sweep).
  // `notices` survives either path so SKILL.md can surface a failed check, and
  // the agent appended them on disk too.
  if (round === 1) {
    return result({
      findingsPath: outputPath,
      outcome: "ZERO_FINDINGS_WARNING",
      report: ZERO_FINDINGS_WARNING_TEXT,
      notices,
      stats,
    });
  }
  return result({
    findingsPath: outputPath,
    outcome: "PASS",
    report: [],
    notices,
    stats,
  });
}

// At least one surviving finding remains — FINDINGS.
return result({
  findingsPath: outputPath,
  outcome: "FINDINGS",
  report,
  notices,
  stats,
});

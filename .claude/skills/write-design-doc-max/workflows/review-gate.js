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
// 1, 2, 3, 5) in docs/design/AIDEV-122-review-gates-as-a-workflow-orchestration.md.

// ----- dispatch configuration -----
//
// The per-check `context` sets and `model` values below are transcribed VERBATIM
// from the pre-existing sources, not re-derived:
//   - `context` sets were transcribed from the `Context forwarded` columns of the
//     now-deleted playbooks design-reviewer.md (Step 2 dispatch table, 7 rows) and
//     task-reviewer.md (Step 2 dispatch table, 8 rows); those files no longer exist.
//     The always-present artefact/requirements inputs (requirements_source,
//     design_document, DESIGN_CONTENT, TASK_SPEC_CONTENT) are NOT config `context`
//     categories — they are forwarded to every check by the script.
//   - `model` comes from each .claude/skills/write-design-doc-max/checks/<name>.md file's
//     `model:` frontmatter, read before that frontmatter was stripped in this task.
//
// `context` is the set of scoped context categories for the check; each category
// resolves to a concrete Read instruction in the check-agent prompt:
//   "steering"  -> "Read all files under `docs/ai/steering/`"
//   "codebase"  -> an explicit list of the codebaseFilePaths to Read
//   (no entry)  -> nothing beyond the artefact (and inline requirements text)

// Path to the shared principles document every check agent reads first.
const CHECK_PRINCIPLES_PATH = ".claude/skills/write-design-doc-max/check-principles.md";

// Directory each check rubric lives under.
const CHECKS_DIR = ".claude/skills/write-design-doc-max/checks";

// Directory the per-round findings file is written under.
const REVIEWS_DIR = "docs/ai/reviews";

// Design gate — 8 checks. context + model were transcribed from the now-deleted
// design-reviewer.md (Context forwarded column) and the checks/*.md frontmatter
// respectively; that playbook file no longer exists. header-format (AIDEV-116)
// was added after that deletion: model in the row, no per-check frontmatter.
const DESIGN_CHECKS = [
  { name: "requirements-coverage", model: "haiku", context: [] },
  { name: "header-format", model: "haiku", context: [] },
  { name: "plan-soundness", model: "sonnet", context: ["codebase"] },
  { name: "steering-compliance", model: "sonnet", context: ["steering"] },
  { name: "task-ordering", model: "sonnet", context: [] },
  { name: "assumption-identification", model: "sonnet", context: ["codebase"] },
  { name: "failure-handling", model: "sonnet", context: [] },
  { name: "testability", model: "sonnet", context: [] },
];

// Task gate — 8 checks. context + model were transcribed from the now-deleted
// task-reviewer.md (Context forwarded column) and the checks/*.md frontmatter
// respectively; that playbook file no longer exists.
const TASK_CHECKS = [
  { name: "goal-achievement", model: "sonnet", context: [] },
  { name: "ai-agent-sufficiency", model: "sonnet", context: [] },
  {
    name: "implementation-soundness",
    model: "sonnet",
    context: ["steering", "codebase"],
  },
  { name: "scope-clarity", model: "haiku", context: [] },
  { name: "steering-compliance", model: "sonnet", context: ["steering"] },
  { name: "assumption-identification", model: "sonnet", context: ["codebase"] },
  { name: "failure-handling", model: "sonnet", context: [] },
  { name: "testability", model: "sonnet", context: [] },
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

// The six ADR-010 finding fields, shared by both schemas below.
const FINDING_FIELDS = {
  Severity: { type: "string", enum: ["Critical", "High", "Medium", "Nit pick"] },
  Issue: { type: "string" },
  "Why it matters": { type: "string" },
  "Size of fix": { type: "string", enum: ["trivial", "local", "broad"] },
  Target: { type: "string", enum: ["load-bearing", "illustrative"] },
  "Suggested resolution": { type: "string" },
};
const FINDING_REQUIRED = [
  "Severity",
  "Issue",
  "Why it matters",
  "Size of fix",
  "Target",
  "Suggested resolution",
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
function contextInstructions(context, codebaseFilePaths) {
  const lines = [];
  for (const category of context) {
    if (category === "steering") {
      lines.push("Read all files under `docs/ai/steering/`.");
    } else if (category === "codebase") {
      if (codebaseFilePaths.length === 0) {
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
function checkPrompt({
  check,
  artefactPath,
  designPath,
  requirementsText,
  codebaseFilePaths,
  round,
}) {
  const rubricPath = `${CHECKS_DIR}/${check.name}.md`;
  const roundFraming =
    round === 1
      ? `This is review round 1. Bias toward finding problems: question ` +
        `hard, and treat an empty findings array as suspicious — a signal ` +
        `you have not looked hard enough.`
      : `This is review round ${round}. The artefact has been revised in ` +
        `response to earlier rounds and should be converging. An empty ` +
        `findings array is valid and expected when the revisions genuinely ` +
        `resolved the earlier concerns; do not manufacture findings to ` +
        `avoid an empty return.`;
  const lines = [
    `You are the blind check agent "${check.name}" for a review gate.`,
    "",
    roundFraming,
    "",
    "Read these files in full before forming any finding:",
    `- The shared principles at \`${CHECK_PRINCIPLES_PATH}\`.`,
    `- Your own rubric at \`${rubricPath}\`.`,
    `- The artefact under review at \`${artefactPath}\`.`,
    `- The design document at \`${designPath}\` (the source of design context).`,
  ];
  for (const instruction of contextInstructions(check.context, codebaseFilePaths)) {
    lines.push(`- ${instruction}`);
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
      "Suggested resolution.",
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
    "After dismissal-filtering: dedup semantically-equivalent findings, group " +
      "by severity in the order Critical -> High -> Medium -> Nit pick, and " +
      `annotate each surviving finding either \`new\` or ` +
      "`persisted-from-round-N` (N is the round in which it first appeared, " +
      `relative to the current round ${round}).`,
    "",
    `Write the result to \`${outputPath}\`. The file content is: a header ` +
      "(ticket, gate type, round, artefact path, prior-round path), then the " +
      "severity-grouped findings (each carrying the six fields plus its " +
      "`new`/`persisted-from-round-N` annotation). Write the file even when " +
      "dismissal-filtering empties the findings (the findings section is then " +
      "empty but the file is still written).",
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
  priorFindingsPath;
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
// min(16, cores - 2), which comfortably fits the 8 checks.
phase("Checks");
const tasks = dispatch.map((check) => () => {
  const prompt = checkPrompt({
    check,
    artefactPath,
    designPath,
    requirementsText,
    codebaseFilePaths,
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

// Outcome ladder — evaluated in this exact order. The "survivors.length > 0"
// precondition on the first branch closes the JS vacuous-truth back door:
// [].every(predicate) is true, so without it a zero-survivors round would also
// satisfy the all-empty test and mis-route to ZERO_FINDINGS_WARNING.
const allSurvivorsEmpty =
  survivors.length > 0 && survivors.every((r) => r.findings.length === 0);

if (allSurvivorsEmpty && round === 1) {
  // Round 1, at least one check survived AND every survivor returned empty
  // findings. The first-round "finds nothing is suspicious" bias applies, so
  // this is surfaced as a warning. Pure-JS — no aggregation agent on this
  // round-1 branch. A failed check rides in `notices` and does NOT demote the
  // round to PASS. On round 2+ an all-empty sweep is NOT short-circuited here:
  // it falls through to the aggregation path below and clears as PASS.
  return result({
    findingsPath: null,
    outcome: "ZERO_FINDINGS_WARNING",
    report: ZERO_FINDINGS_WARNING_TEXT,
    notices,
    stats: { checksRun, checksFailed, findingCounts: zeroCounts() },
  });
}

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

// Either at least one surviving check returned a non-empty findings array, OR
// this is a round 2+ all-empty sweep falling through to the aggregation path
// (the round-1 ZERO_FINDINGS_WARNING short-circuit above no longer fires on
// round 2+, so a converged clean sweep aggregates and clears as PASS) — run the
// aggregation agent. The script passes its accumulated `notices` so the agent
// can append a `## Notices` section to the on-disk file.
phase("Aggregate");
const outputPath = findingsFilePath(ticket, artefactSlug, round);
// Pass every survivor's array to aggregation (including empty ones — the round
// reached here because at least one survivor was non-empty, OR this is a
// round 2+ all-empty sweep falling through to the aggregation path).
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
  // All surviving findings dismissal-filtered away — PASS. The file is still
  // written (durable record). `notices` survives the PASS path so SKILL.md can
  // surface a failed check, and the agent appended them on disk too.
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

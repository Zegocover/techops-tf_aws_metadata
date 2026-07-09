# task-ordering

Check: task sequencing is correct, parallelisation opportunities are identified, each task is one vertical outcome sized to a single agent's working set (not over-fragmented), values are traceable end-to-end, and sequential ordering constraints are explicit.

## Inputs

- `requirements_source`: full text of the requirements source
- `design_document`: full text of the design document (including `## Dismissals`)

## Checks

**Sequencing correctness:**
- For each dependency stated in `## Task breakdown`: is the dependency correct? Does the dependent task actually require an output from the dependency before it can proceed?
- Is there any task that depends on an output that is not produced by its stated dependency? Name the specific missing output.
- Is there any circular dependency implied (even if not stated explicitly)?

**Parallelisation:**
- Are there tasks currently listed as sequential that have no real dependency between them and could run in parallel? Name each pair.
- If tasks are listed as parallel: do they actually share no outputs that one depends on?

**Single vertical outcome:**
- Does each task represent one coherent vertical outcome sized to a single Opus-level agent's loadable working set — the task spec plus the files it must read and write, with headroom to reason? A task that spans multiple components is allowed, and is not a problem, when those components serve one vertical outcome. Spanning components is not the same as a file carrying multiple responsibilities — do not treat a multi-component slice as a defect on that basis. Do not suggest splitting a task merely because it touches more than one component or names more than one deliverable.
- **Over-fragmentation (advisory merge suggestion, not a sign-off blocker).** The breakdown is over-fragmented when it splits work that would sit inside one agent's working set across separate tasks. Raise this finding when a task is too small to stand on its own — a sub-threshold edit (a few-line change) given its own task, or a standalone test-only task whose code-producing task already held the full context needed to write those tests. Name the specific tasks that should be merged and state why (they share one agent's working set / the split task is sub-threshold on its own). This is advisory only: it is a merge suggestion at the same level as the other suggestions in this block.

**Value tracing:**
- For every value that flows through multiple components (e.g. an identifier, a flag, a computed result): trace it end-to-end across the task breakdown.
- At each handoff point: is the value explicitly named in the downstream task's spec? Or could it be lost, defaulted to zero/empty, or hardcoded?
- Name every point where a value could be silently dropped or defaulted.

**Intra-flow ordering:**
- For every sequential flow within the design (not just inter-task dependencies): is the ordering stated as a hard constraint, or is it just implied?
- Could an implementer reading only the task specs accidentally parallelise two steps that must be sequential?
- Name every sequential constraint that is implied but not stated explicitly.

## Dismissals

Check the `## Dismissals` section of `design_document`. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific ordering gap in the same component. If the design or component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

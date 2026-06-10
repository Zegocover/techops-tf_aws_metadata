# task-ordering

Check: task sequencing is correct, parallelisation opportunities are identified, tasks are single-responsibility, values are traceable end-to-end, and sequential ordering constraints are explicit.

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

**Single-responsibility:**
- Does each task have a clearly bounded, single responsibility? If a task's name or description suggests multiple distinct deliverables, name them.
- Are any two tasks so closely related they should be merged into one? Name them and state why.

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

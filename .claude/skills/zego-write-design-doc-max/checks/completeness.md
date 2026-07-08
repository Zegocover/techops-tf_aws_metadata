# completeness

Check: every task spec fully achieves the goal the design assigns to it, and the set of specs collectively covers every design element, functional requirement, and acceptance criterion.

Runs at the task gate only, over ALL task specs at once: per-spec goal checks apply to each spec individually; coverage checks apply to the set as a whole.

## Inputs

- `requirements_source`: full text of the requirements source (FRs, ACs, constraints) — provided inline. If absent, run the design-coverage checks only and note `requirements traceability unverified: no requirements source`.
- Design document: full text including `## Dismissals` and the task breakdown
- Primary documents: ALL task specs under review, in task order. Attribute each per-spec finding via the `Spec` field; set-level gap findings carry `Spec` null.

## Checks

**Per-spec goal achievement:**
- Locate each spec's task entry in the design's task breakdown (match by task number and name). No corresponding entry: raise Critical — the spec has no named goal in the design.
- For every deliverable the design assigns to a task: is it explicitly present as an output or acceptance criterion in that spec? Missing deliverable: raise High, naming the deliverable and the design section that assigns it.
- Do the spec's acceptance criteria cover every assigned deliverable, such that each is verifiable via the ACs as written? Unverified deliverable: raise High, naming it and which AC would need to address it.
- Is anything in the design's task entry (objective, constraints, inputs/outputs, ACs, test requirements) absent from the spec? Raise Medium, naming the item and where it appears in the design.

**Set-level coverage:**
- For every component, flow path, interface contract, and acceptance criterion stated in the design: is it covered by at least one spec as a deliverable? Uncovered element: raise High (Spec null), naming the element and the design section it appears in.
- Do the specs collectively address every FR and every AC in `requirements_source`? Any FR or AC not traceable to at least one spec: raise High (Spec null), naming it.
- If `requirements_source` contains no explicitly labelled FRs or ACs, identify the functional obligations and acceptance expectations from the prose and apply the same checks.

## Dismissals

Check the `## Dismissals` section of the design document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific gap in the same component or spec. If a spec has been regenerated or the design has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

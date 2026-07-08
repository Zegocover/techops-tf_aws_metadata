# scope-boundaries

Check: every task spec is explicitly bounded; no deliverable is owned by two specs or assigned to the wrong one; dependencies and cross-spec interfaces are consistent across the whole set.

Runs at the task gate only, over ALL task specs at once: review the set, not each spec in isolation — overlap, ordering, and interface drift are only detectable across specs, and severity is rated relative to the whole batch.

## Inputs

- Design document: full text including `## Dismissals` and the task breakdown (context and source of truth for ownership and dependencies)
- Primary documents: ALL task specs under review, in task order. Apply every check across the full set; attribute each finding to the affected spec via the `Spec` field (null only for genuinely cross-spec findings).

## Checks

**Per-spec boundaries:**
- Does each spec contain an `## Out of scope` section with at least one entry? Missing: raise High — without it an implementer has no anchor for where to stop.
- Does the in-scope definition (objective, deliverables, ACs) state clearly what is included? Vague boundary: raise Medium, naming the vague phrase and the specific boundary that would replace it.
- Are there instructions an implementer could reasonably extend beyond the intended boundary (e.g. "update all references" when only specific references are meant)? Raise High, naming the instruction and the scope restriction that would contain it.

**Cross-spec ownership:**
- Does the same design element appear as a deliverable (not merely a dependency) in more than one spec? Raise High, naming the element and both specs claiming ownership.
- Does any spec claim an item the design assigns to a different task, or to no task at all? Raise Medium, naming the item and where the design assigns it.

**Dependency consistency:**
- Does each spec's `Depends on:` header match the design's stated dependency for that task? Mismatch: raise Critical, naming the design-stated dependency and what the spec declares.
- Are all dependencies on other tasks named with exact file paths or task numbers? Prose-only dependency: raise Medium, naming the explicit reference that would replace it.
- Does any spec declare a dependency not in the design, or omit one that is? Raise High.

**Interface consistency:**
- For every output produced by one spec and consumed as an input by another: are the types, shapes, and field names consistent between producer and consumer? Mismatch: raise High, naming the specific field or type that differs and both specs.

## Dismissals

Check the `## Dismissals` section of the design document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific gap in the same component or spec. If a spec has been regenerated or the design has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

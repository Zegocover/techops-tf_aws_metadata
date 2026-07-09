# steering-compliance

Check: the document under review does not propose anything that contradicts existing steering docs.

## Primary document disambiguation

If task specs are present in the input alongside a design document:
- The task specs are the primary documents.
- Apply all criteria to every task spec; attribute each finding to the affected spec via the `Spec` field (the spec filename).
- Treat the design document as context only.

If only a design document is present (no task specs):
- The design document is the primary document.
- Apply all criteria to the design document. Leave `Spec` null.

## Inputs

- `requirements_source`: full text of the requirements source (context only)
- Primary document: full text of the document under review (including `## Dismissals` if present)
- A curated index of the steering docs (one `- {path} — {one-line description}` line per doc). Read the full text only of the docs whose description is plausibly relevant to the primary document; when uncertain whether a doc is relevant, read it. If the read-all degrade is in effect (no index was provided), read every `docs/ai/steering/` file instead.

## Checks

Select the steering docs whose one-line description is plausibly relevant to the primary document (read when uncertain), then for each selected steering doc:
- Read it in full.
- For each rule or convention it states: does the primary document propose anything that contradicts it?
- A contradiction is a statement in the primary document that, if acted on, would violate the steering rule.
- For every contradiction found: name the specific rule violated (file path + rule text) and the specific statement in the primary document that conflicts with it.
- Vague concerns ("this might conflict") are not findings — only name a finding when the contradiction is specific and traceable.

If a steering doc is passed but cannot be read: note the gap — "steering doc {path} could not be read; compliance against it is unverified" — and continue.

## Dismissals

Check the `## Dismissals` section of the design document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific contradiction against the same steering rule. If the primary document or the relevant component has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

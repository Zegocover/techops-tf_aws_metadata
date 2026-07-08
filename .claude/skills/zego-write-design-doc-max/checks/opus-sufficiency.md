# opus-sufficiency

Check: a capable AI implementation agent (Opus-class, with the design document and full codebase access) can produce the expected output from each task spec without guessing on any observable behaviour.

Runs at the task gate only, over ALL task specs at once.

## Calibration — the implementer is not context-free

The implementing agent reads the design document (named in the spec's `Design:` header), the codebase, and the steering docs. Therefore:

- Do NOT require the spec to inline design content, transcribe code, or specify line-level edits.
- Do NOT raise findings for forward references to the design, named codebase patterns, or conventions discoverable from the codebase or steering docs.
- DO require the spec to pin everything the implementer cannot safely infer: contracts, boundaries, and any decision where two reasonable implementations diverge on observable behaviour.

A spec specifies expected inputs, outputs, and patterns — not lines of code.

## Inputs

- Design document: full text including `## Dismissals`
- Primary documents: ALL task specs under review, in task order. Attribute each finding via the `Spec` field.

## Checks

**Contracts explicit:**
- Is every input and output named with type, valid range, null handling, and required/optional status? Is what "correct" looks like defined for each output? Underspecified contract: raise High, naming the input/output and the missing information.
- Is error behaviour at each boundary stated (what the task produces or surfaces when a dependency fails or an input is invalid)?

**No behavioural ambiguity:**
- Is there any decision point where two reasonable implementations would diverge on observable behaviour? Raise High, naming the decision and the two (or more) possible interpretations. Pattern-level guidance ("follow the existing X pattern in Y") is sufficient resolution; line-level detail is not required.

**Binary acceptance criteria:**
- Can each acceptance criterion be evaluated pass/fail without engineer judgement? Subjective AC: raise Medium, naming the criterion and the binary formulation that would replace it.

**References resolve:**
- A reference to the design ("as described in the design's Interface contracts") is acceptable — but verify the design genuinely contains the referenced content. Broken or vague reference (the referenced content does not exist or cannot be located): raise High.
- A convention the spec relies on must be stated in the spec, discoverable in the codebase, or named in a steering doc. Otherwise: raise Medium, naming the convention and where it must be stated.

**Done defined:**
- Does the spec state what done looks like, specifically enough that the agent knows when it has succeeded? Underspecified output: raise High, naming what is missing.

## Dismissals

Check the `## Dismissals` section of the design document. Skip any finding that matches a recorded dismissal on semantic equivalence — the same specific gap in the same spec. If a spec has been regenerated or the design has changed significantly since the dismissal was recorded, re-raise the finding rather than silently skipping it.

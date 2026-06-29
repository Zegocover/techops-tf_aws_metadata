# Templates

Handoff artefact templates fanned out to every consumer repo. Language-agnostic for now — per-language variants are added to this directory when needed (e.g. `steering-doc-python.md`), requiring no structural change.

## Templates in this library

| Template | Handoff | Purpose |
|---|---|---|
| `requirements-package.md` | Product → Engineer | Structured requirements with Given/When/Then ACs |
| `steering-doc.md` | Engineer → AI | The load-bearing artefact for Stage 2 of the pipeline |
| `task-spec.md` | Engineer → AI | Lightweight task spec for smaller changes |
| `bug-diagnosis.md` | Institutional memory | Durable root-cause record written by `fix-bug` Stage 4b to `docs/bugs/` |
| `acceptance-handoff.md` | Engineer → Product | Summary of what was built and how to verify it |
| `working-context.md` | Session continuity | WORKING.md format for mid-session context hand-off |

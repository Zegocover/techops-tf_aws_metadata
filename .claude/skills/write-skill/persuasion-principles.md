# Persuasion principles for skill design

Reference for applying persuasion psychology to skill authoring. LLMs respond
to the same persuasion principles as humans. Understanding this helps design
skills that hold under pressure — not to manipulate, but to ensure critical
practices are followed when the agent is tempted to rationalise them away.

**Research foundation:** Meincke et al. (2025) tested 7 persuasion principles
with N=28,000 AI conversations. Persuasion techniques more than doubled
compliance rates (33% to 72%, p < .001). The study measured compliance with
objectionable requests — we apply the same observed mechanisms in the opposite
direction, to enforce legitimate practices. The fact that these techniques
bypass safety guardrails is also why they should be used sparingly and ethically
(see _Ethical use_ below).

---

## The seven principles

### 1. Authority

Deference to expertise, credentials, or official sources.

How it works in skills:
- Imperative language: "YOU MUST", "Never", "Always".
- Non-negotiable framing: "No exceptions".
- Eliminates decision fatigue and rationalisation.

When to use:
- Discipline-enforcing skills (TDD, verification requirements).
- Safety-critical practices.
- Established best practices.

```
Good:  Write code before test? Delete it. Start over. No exceptions.
Bad:   Consider writing tests first when feasible.
```

### 2. Commitment

Consistency with prior actions, statements, or public declarations.

How it works in skills:
- Require announcements: "Announce skill usage".
- Force explicit choices: "Choose A, B, or C".
- Use checklists for tracking progress through multi-step processes.

When to use:
- Ensuring skills are actually followed.
- Multi-step processes.
- Accountability mechanisms.

```
Good:  When you find a skill, you MUST announce: "I'm using [Skill Name]"
Bad:   Consider letting your partner know which skill you're using.
```

### 3. Scarcity

Urgency from time limits or limited availability.

How it works in skills:
- Time-bound requirements: "Before proceeding".
- Sequential dependencies: "Immediately after X".
- Prevents procrastination.

When to use:
- Immediate verification requirements.
- Time-sensitive workflows.
- Preventing "I'll do it later" rationalisation.

```
Good:  After completing a task, IMMEDIATELY request code review before proceeding.
Bad:   You can review code when convenient.
```

### 4. Social Proof

Conformity to what others do or what is considered normal.

How it works in skills:
- Universal patterns: "Every time", "Always".
- Failure modes: "X without Y = failure".
- Establishes norms.

When to use:
- Documenting universal practices.
- Warning about common failures.
- Reinforcing standards.

```
Good:  Checklists without tracking = steps get skipped. Every time.
Bad:   Some people find checklists helpful.
```

### 5. Unity

Shared identity, "we-ness", in-group belonging.

How it works in skills:
- Collaborative language: "our codebase", "we're colleagues".
- Shared goals: "we both want quality".

When to use:
- Collaborative workflows.
- Establishing team culture.
- Non-hierarchical practices.

```
Good:  We're colleagues working together. I need your honest technical judgement.
Bad:   You should probably tell me if I'm wrong.
```

### 6. Reciprocity

Obligation to return benefits received.

Use sparingly — can feel manipulative. Rarely needed in skills. Other
principles are more effective.

### 7. Liking

Preference for cooperating with those we like.

Do not use for compliance. Conflicts with honest feedback culture. Creates
sycophancy. Avoid for discipline enforcement.

---

## Principle combinations by skill type

| Skill type | Use | Avoid |
|------------|-----|-------|
| Discipline-enforcing | Authority + Commitment + Social Proof | Liking, Reciprocity |
| Guidance/technique | Moderate Authority + Unity | Heavy authority |
| Collaborative | Unity + Commitment | Authority, Liking |
| Reference | Clarity only | All persuasion |

---

## Why this works

**Bright-line rules reduce rationalisation:**
- "YOU MUST" removes decision fatigue.
- Absolute language eliminates "is this an exception?" questions.
- Explicit anti-rationalisation counters close specific loopholes.

**Implementation intentions create automatic behaviour:**
- Clear triggers + required actions = automatic execution.
- "When X, do Y" is more effective than "generally do Y".
- Reduces cognitive load on compliance.

**LLMs are parahuman:**
- Trained on human text containing these patterns.
- Authority language precedes compliance in training data.
- Commitment sequences (statement then action) are frequently modelled.
- Social proof patterns ("everyone does X") establish norms.

---

## Ethical use

**Legitimate:**
- Ensuring critical practices are followed.
- Creating effective documentation.
- Preventing predictable failures.

**Illegitimate:**
- Manipulating for personal gain.
- Creating false urgency.
- Guilt-based compliance.

**The test:** Would this technique serve the user's genuine interests if they
fully understood it?

---

## Research citations

**Cialdini, R. B. (2021).** *Influence: The Psychology of Persuasion (New and
Expanded).* Harper Business.
- Seven principles of persuasion.
- Empirical foundation for influence research.

**Meincke, L., Shapiro, D., Duckworth, A. L., Mollick, E., Mollick, L., &
Cialdini, R. (2025).** Call Me A Jerk: Persuading AI to Comply with
Objectionable Requests. University of Pennsylvania.
- Tested 7 principles with N=28,000 LLM conversations.
- Compliance increased 33% to 72% with persuasion techniques.
- Authority, commitment, scarcity most effective.
- Validates parahuman model of LLM behaviour.

---

## Quick reference

When designing a skill, ask:

1. **What type is it?** (Discipline vs. guidance vs. reference)
2. **What behaviour am I trying to change?**
3. **Which principle(s) apply?** (Usually Authority + Commitment for discipline)
4. **Am I combining too many?** (Do not use all seven)
5. **Is this ethical?** (Serves user's genuine interests?)

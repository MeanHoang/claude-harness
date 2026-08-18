---
name: feature-review
description: Use when deciding whether a feature is worth building, reviewing a feature spec/PRD/Notion task, running UAT or product review, or challenging a feature request before development starts. Applies an outcome-first "roast" lens — interrogate the premise, grade output vs outcome, attack the design, and verdict Build / Reframe / Kill. Trigger phrases: review this feature, should we build this, is this worth it, roast this spec, UAT this, why do we need this feature, this feels like a checkbox feature, will this actually move the needle, does this rock.
---

# Feature Review (the roast / UAT lens)

**Core thesis: we don't ship features, we ship outcomes that rock.** A feature that merely exists is a liability. The job is to find the version that *revolutionizes* the customer's result — or to kill the idea.

The canonical failure to prevent: a request for *"an HTML editor for emails"* gets built **literally**, when the real job was *beautiful, easy, high-converting emails*. The 10× answer was a **drag-and-drop block editor** (which also unlocks upsell/cross-sell, A/B, personalization later). Literal output → no outcome. Reimagined → compounding outcome.

## Rules

### A. Interrogate the premise (before any solution)
1. **"Why does this exist?" gate.** First question is never *how* — it's *why a customer's life is measurably better*. If the honest answer is "a customer asked" or "so we have it" → dig for the real job-to-be-done.
2. **Literal-request trap.** A request for a specific solution is a clue, not a spec. Extract the underlying need; design the 10× version. Never ship the literal ask if it doesn't move the outcome.
3. **Kill is a valid verdict.** "Don't build this" / "solve it with no feature" are allowed and encouraged. A premise that fails #1 dies here.
11. **Demand-signal check.** Is this one customer's request, a recurring pattern across tickets, or speculative? Check the ticket/support history for frequency. One anecdote doesn't kill the idea, but it raises the bar — the outcome case must stand on its own, not on "someone asked."
12. **Segment/scope check.** Who exactly benefits — the broad customer base, or one loud (often enterprise) account? If it's a narrow segment, say so explicitly and weigh the trade: are we buying one account's satisfaction with platform simplicity everyone else pays for?

### B. Outcome over output
4. **Output vs Outcome test.** *"We shipped X"* ≠ *"customers now achieve Y"*. Name the measurable outcome up front: more sales · faster setup · higher engagement · less support. No outcome → no go.
5. **"Does it rock?" bar.** Parity/table-stakes, or leapfrog? If it's a checkbox feature, say so and justify why checkbox is enough *here*. Bias to the version a competitor can't copy in a week.
13. **Fake-versioning check.** If this is pitched as "v2"/"a revamp," name the actual step-change in one sentence. If the honest answer is "same computation/data, prettier UI" → that's parity dressed as innovation. Call it out, and name what a real transformation would target instead (e.g., for an analytics revamp: metrics that actually drive retention, not re-skinned SUM/AVG/group-by).
14. **Effort-to-outcome ratio.** Having *an* outcome isn't enough — is it worth the build cost? A modest feature that's cheap can beat a bigger one that costs 10× more for a marginally bigger outcome. Name the trade explicitly, don't just assume bigger scope means better.

### C. The roast (mandatory before approval)
6. **Roast round.** Attack the design before presenting it: *What's weak? Why would a customer NOT use this? What's the laziest version we're accidentally building? What would a skeptical senior PM tear apart?* Surface the strongest objections **and answer them**.
7. **Customer-in-the-room.** Ground every claim in one concrete scenario (*"a skincare brand wants a Glossier-grade launch email in 5 minutes"*). If you can't picture the customer, you're designing blind.
8. **Differentiation check.** Does the platform itself, or a competitor, already do this better? If so, what's our unfair angle?
15. **One-way-door check.** When a customer hands over a literal, specific implementation spec (exact button, exact setting), ask: if we build exactly this, can we still change or remove it later without breaking customers who now depend on it? Reversible (two-way-door) asks are fine to ship fast and iterate; irreversible ones need the same scrutiny as a platform decision — don't let "the customer was specific" bypass that scrutiny.
16. **Cannibalization/conflict check.** Does this overlap an existing mechanism? Two confusing paths to the same outcome — or worse, silently conflicting logic — is a real failure mode here (see this codebase's own money-spent-tier double-count incident from overlapping logic). If it overlaps, name the migration/deprecation plan.

### D. Build for leverage
9. **Compounding / platform test.** Does it open doors or dead-end? Prefer features that are platforms for future value (blocks → upsell/cross-sell/A-B), not one-offs (raw HTML → nothing).
10. **Cost of mediocre.** A cheap literal feature ships *"we have it but it sucks"* — support load, a later redesign, brand erosion. Price that against doing it right once.
17. **Platform-extensibility check** *(only when the feature touches a core mechanism of the product)*. Could a third party plug into this today? If the proposal is a one-off workaround for one customer's ask, ask whether the underlying capability should instead be a general mechanism (a public API endpoint, an automation trigger/action, or a config surface) any third party could use — answer concretely ("yes, because X" / "no, because Y"), not "would be nice."

## Workflow
1. **Get the spec** — pull the Notion task (via `notion-tasks`) or read the pasted PRD. Treat its proposed solution as a hypothesis, not a given.
2. **Premise** — apply rules 1–3, 11–12. State the real job-to-be-done in one sentence, and who/how many it's actually for.
3. **Outcome grade** — apply 4–5, 13–14. Name the measurable outcome (or its absence), and whether it's a real step-change worth its cost.
4. **Roast** — apply 6–8, 15–16. List the brutal objections, then answer the survivable ones.
5. **Leverage** — apply 9–10, 17 (when the feature touches a core mechanism).
6. **Verdict + reframe** — Build / Reframe / Kill, and if not a clean Build, sketch the 10× version.

## Verdict rubric
- **🟢 Build** — clear job, measurable outcome, leapfrogs or justified table-stakes, survives the roast. Ship it.
- **🟡 Reframe** — the *job* is real but the proposed solution is the literal/low-outcome version. Keep the problem, replace the solution with the 10× design.
- **🔴 Kill** — no real job, no measurable outcome, or better solved with no feature. Say so plainly and why.

## Output template
```markdown
# Feature Review: [name]
## Real job-to-be-done — one sentence (NOT the requested solution)
## Who's asking — demand signal (one account vs. recurring pattern) · segment it actually serves
## Outcome — the measurable customer result (or "none — output only") · is it a real step-change or fake versioning · worth the build cost?
## The roast — the brutal objections, each answered or conceded · one-way-door risk · overlap with an existing mechanism
## Differentiation — vs the platform itself / competitors · our unfair angle
## Leverage — what this unlocks later (or "dead-end") · could a 3rd party plug into this (core-mechanism features only)
## Verdict — 🟢 Build / 🟡 Reframe / 🔴 Kill — with the reason
## The 10× version (if Reframe/Kill) — what to build instead, and why it rocks
```

Roast the **idea**, never the person. Always leave them with the stronger version, not just a teardown.

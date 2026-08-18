---
name: agent-harness-review
description: Use when auditing or reviewing a Claude Code agent harness — the .claude/ setup (CLAUDE.md, agents/, skills/, commands/, hooks/, settings.json) plus memory — against agent-architecture best practices. Produces a layered scorecard with file-cited findings and prioritized fixes. Trigger phrases: review our agent harness, audit the .claude setup, harness health check, are our agents/skills well-designed, review our hooks, check agent tool scoping, agent architecture review, is our harness missing anything.
---

# Agent Harness Review

Audit a Claude Code harness against the four-layer architecture. **Core thesis: deterministic beats probabilistic** — hooks guarantee execution, prompts only hope for it. The strongest harnesses push quality from "the model remembers" to "the infrastructure enforces."
Source: https://blakecrosley.com/guides/agent-architecture

## Method
- **Evidence gate.** Every finding cites the file (`path:line`) or the missing artifact — never "feels weak."
- **Severity:** 🔴 Blocker (safety/correctness hole) · 🟠 High (real leak) · 🟡 Medium (friction/quality) · 🟢 Low (polish).
- Score each layer, then give a prioritized fix list. A guardrail justified by "we did this manual safety step N times" is a Blocker — automate it.

## Layer 1 — Instruction (CLAUDE.md)
CLAUDE.md is operational policy, not documentation.
- [ ] **Command-first**: exact build/test/lint commands present (not prose like "run the tests").
- [ ] **Definition of Done**: machine-verifiable ("lint exits 0, tests pass"), not "good code".
- [ ] **Escalation rules**: "when blocked, stop and report"; "never: X".
- [ ] **Task-organized** sections (When writing / reviewing / releasing).
- [ ] **Acid test**: could an agent reproduce the build commands verbatim from CLAUDE.md? If not → too vague/verbose.
- [ ] No contradictory priorities; imports (`@path`) ≤ 5 deep.
- Anti-patterns: prose paragraphs without commands, ambiguous directives ("be careful with migrations"), style guide with no enforcement.

## Layer 2 — Extension (skills · hooks · settings)
**Skills**
- [ ] **Description is everything**: concrete trigger phrases + when-to-use, not "helps with X". Vague descriptions get excluded from the ~1% context budget.
- [ ] SKILL.md < 500 lines; bulk detail in on-demand supporting files.
- [ ] `allowed-tools` scoped where read-only.
- [ ] **No broken refs**: every skill an agent/skill names actually exists as a folder/registry entry. (Grep agent bodies for `` `slug` `` and verify — broken refs fail silently.)
- [ ] No name collisions; no duplicate skills.

**Hooks** — the deterministic layer; its absence is the most common gap.
- [ ] **Safety hooks present** (PreToolUse, **exit 2 / deny**): block secrets/credentials, block committing build artifacts or tunnel/staging URLs, block dangerous bash (`rm -rf`, `git push --force`).
- [ ] **Exit-code semantics correct**: blocking gate uses exit 2 (or `permissionDecision: deny`), NOT exit 1 (exit 1 = non-blocking warning; the dangerous command still runs — the most common hook mistake).
- [ ] **Quality/format hooks** (PostToolUse): auto-lint/format on edited files.
- [ ] `async: true` only for notifications/logging — **never** for safety/quality gates.
- [ ] Multiple hooks on one event use a dispatcher (read stdin once) to avoid races.
- [ ] Hook command built for THIS repo (right package manager, guards unknown file types) and pipe-tested.

**Settings / permissions**
- [ ] Permission allowlist for common read-only tools (cuts prompt friction).
- [ ] settings.json is valid JSON (a broken one silently disables ALL its settings).

## Layer 3 — Orchestration (subagents)
- [ ] **Least-privilege tools**: agents declare scoped `tools:`, not inherited "all tools" — especially read-only reviewers (no Edit/Write/Bash).
- [ ] **Model tiers** assigned deliberately (cheap for mechanical, standard for judgment, capable for the final whole-branch review) — not silently inheriting the most expensive model.
- [ ] **Single-purpose seams**: agents cut at durable domains, not overlapping or version-named ("widget-v4-agent" is a smell). Dispatch should be mechanical, not ambiguous.
- [ ] **Discovery-rich descriptions**: when-to-use + examples so the main loop routes correctly.
- [ ] **Verify gate**: is there a pre-commit / pre-merge reviewer (SDD task-reviewer, or a `verifier` agent)? Non-gated commits are where artifacts/regressions leak.
- [ ] **Parallelism rules**: read-only fan-out is safe; parallel *writes* need worktree isolation; recursion/spawn budget (cap children, not just depth — "23 agents at depth 1 is still depth 1").
- [ ] Deliberation (independent multi-agent evaluation) available for high-stakes design (schema, API contracts, security)? Agreement without dissent is a risk.

## Layer 4 — Core (memory · context)
- [ ] File-based memory present (CLAUDE.md + memory files reload after compaction).
- [ ] No multi-file pre-loading at session start (use grep/glob on demand).
- [ ] Compaction discipline / session-handoff docs for long (>90 min) work.
- [ ] Memory entries are durable facts, not transient conversation detail.

## Output scorecard
```markdown
# Agent Harness Review — {date}
## Layer scores: Instruction _/5 · Extension _/5 · Orchestration _/5 · Core _/5
## 🔴 Blockers — [finding · file/missing-artifact · fix]
## 🟠 High · 🟡 Medium · 🟢 Low
## Top 3 fixes (effort → impact)
```
Audit the **wiring between layers** as hard as the layers themselves — a broken skill ref or an exit-1 "gate" looks fine in isolation and fails silently in practice.

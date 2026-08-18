---
name: sdd-model-tiers
description: Use whenever running superpowers:subagent-driven-development (SDD) in this repo — dispatching an implementer or task reviewer, choosing which review path to use, or writing a plan's per-task Model tier field. Fixes SDD feeling slow/expensive by making per-task model selection explicit instead of relying on agent-definition defaults.
---

# SDD Model Tiers (this repo)

`superpowers:subagent-driven-development`'s own `SKILL.md` ("Model Selection")
says to scale each dispatch's model to the task's complexity — cheap for
mechanical work, standard for integration/judgment, capable for architecture.
In this repo that guidance was structurally disabled: every `*-implementer`
agent (`backend-implementer`, `admin-frontend-implementer`,
`storefront-widget-implementer`, `theme-extension-implementer`,
`data-implementer`, `integrations-implementer`) is hardcoded `model: sonnet`,
and the only discoverable reviewer, `code-reviewer`, is hardcoded
`model: opus` — so every implementer and every task-level review ran at the
same cost/latency regardless of task size. This skill closes that gap.

## Tier definitions

| Tier | `model:` value to pass | Actual model | When |
|------|------------------------|---------------|------|
| cheap | `haiku` | Haiku 4.5 | 1-2 files, the plan already hands the implementer the complete code/spec — pure transcription + testing |
| standard | `sonnet` | Sonnet 5 | multi-file integration, pattern-matching against existing code, most "normal" tasks |
| capable | `opus` | Opus 5 | architecture/design judgment, and always for the final whole-branch review |

These are the `model:` param values the `Agent` tool accepts — they resolve
to the current top model in that tier automatically, so this table stays
correct across model version bumps without editing it.

## How to apply during SDD

1. **Read the task's `Model tier` field** from the plan (`.claude/commands/plan.md`
   / `planner.md` Task template). If a plan predates this field, judge the
   tier yourself using the table above before dispatching — do not default
   to standard/sonnet by habit.
2. **Implementer dispatch:** call the `Agent` tool with the task's normal
   `subagent_type` (e.g. `backend-implementer`) **and** pass
   `model: <tier alias>` explicitly. The `model` param overrides the agent
   definition's frontmatter default — this is what actually applies the
   tier; naming the tier in the plan without passing it on the call does
   nothing.
3. **Task-level review (after every task):** dispatch with the SAME tier as
   the implementer, one step up if the diff reads riskier than the plan
   assumed (e.g. touches shared/mutable state). Use the `code-reviewer`
   subagent with an explicit `model` override, or a `general-purpose` agent
   per `subagent-driven-development/task-reviewer-prompt.md` — either way,
   **never accept `code-reviewer`'s default opus for a per-task review.**
   Reserve default-opus `code-reviewer` for:
   - the final whole-branch SDD review, and
   - a standalone `/review` invocation outside SDD.
4. **Fix-loop escalation (SDD rounds 4-5):** bump one tier above whatever
   the stuck implementer used, per the base skill's own rule — this skill
   doesn't change that.

## Granularity guard

This repo's Task-N structure (`.claude/commands/plan.md`, `planner.md` —
Owner agent / Model tier / Files / Steps / Interfaces / Tests / Acceptance,
sized at one component/service/file-group per task) is what `/plan` and the
`planner` agent produce, and it's what SDD should execute. It intentionally
does **not** follow `superpowers:writing-plans`' generic default of
"bite-sized, one action, 2-5 minutes per step" — that skill auto-triggers
on its own ("spec or requirements for a multi-step task, before touching
code") and can get pulled in independently of `/plan`. If a plan is being
written outside `/plan`/`planner`, keep tasks at this repo's component-level
granularity; do not atomize down to the generic plugin default.

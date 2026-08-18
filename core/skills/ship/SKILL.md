---
name: ship
description: End-to-end dev pipeline for a task — analyze the Notion spec, plan in four sub-steps (gather facts → decide trade-offs → split phases → render plan.html), implement phase by phase with a fresh reviewer subagent + /code-review travelling in the gate report, commit only on his explicit OK, and track state in a checkbox progress.md plus an append-only decisions.md. He does the functional testing himself — this pipeline never runs a browser pass. Use when the user says "/ship <notion-url>", "ship task này", "làm task này từ đầu đến cuối".
---

# Ship — Notion task → reviewed, committed, phase-by-phase

The user drives only the GATES; everything between gates runs autonomously. He answers each gate **in chat** — report the gate, end the turn, wait for his reply. Never advance on silence; never guess his answer.

**Gate waiting protocol** (every gate): after posting a gate report in chat, end the turn and wait. On a long wait with no reply, **edit** (not add) the single `> **NOW:**` line in `progress.md`, fill "Đang chờ user" with the exact question, and park — the resume protocol picks it up when he replies or re-invokes.

## Arguments

`<notion-url>` — the task.
`--note "<free text>"` — optional steer, e.g. `--note "phase widget trước, đừng đụng customer-account"`.

**How a `--note` is treated — same contract in every skill that takes one:**

- **It steers attention, never authority.** It can set priorities, name what to avoid, say what he already suspects. It does NOT open a gate: 1c/2b/2c still get asked, Gate 3 still needs his OK, and a commit still needs the word. A note saying "cứ commit luôn" is not consent for a phase that has not been reported — ask once.
- **Persist it verbatim** in the `<!-- state -->` block of `progress.md` as `note:`, and copy it into every `kickoff-*.md` when a workspace is opened. A note that lives only in the invocation dies with the session; the resume protocol then continues without the thing he actually cared about.
- **Answer it explicitly at the next gate.** One line: what the note asked, what was done about it. A note silently absorbed is indistinguishable from a note ignored.
- **A note can be wrong.** If it says "sửa ở X" and the evidence says X is not the place, report that with `file:line` at the gate instead of following it into the wrong file. He is steering, not overruling the code.

## The root session only ORCHESTRATES and VERIFIES

**Root holds conclusions. Subagents swallow raw material and die with it.** Every heavy step below is dispatched, not performed in this context — so the root stays in the smart zone from Step 0 to Step 7, and so does each subagent, because each one starts empty.

A subagent returns findings, not files — that is the whole point. Reading a surface costs the same either way; what changes is whether the raw material stays in the root context afterwards.

**Who runs what:**

| Step | Runs where | Why |
|---|---|---|
| 0 Orient, mode pick | root | a few git/Notion facts |
| 1a Verify the spec | **subagent** | reads the spec + verifies every claim against code |
| 1b Grill 🚦 | **root + user** | a subagent cannot talk to him; this is the alignment step and it cannot be automated |
| 2a Gather | **subagents, parallel** | the heaviest read of the whole pipeline → `facts.md` |
| 2b Decide 🚦 | **root + user** | loads only spec + `facts.md`; this is the thinking step, it must be clean |
| 2c Split into phases 🚦 | **root + user** | what ships first, what is in v1, what he wants to see working first — that is his call, not a proposal handed to him |
| 2d Render `plan.html` | **subagent** | template in, 20–60KB HTML out — pure mechanics, no reason to spend root context on it |
| 3 Implement a phase | **subagent per phase** (`.claude/agents/*-implementer`, at the model tier the plan set for this task) | the code-writing context dies with the phase |
| 3.5 Review the phase diff | **a fresh reviewer subagent** (never the implementer, never inline in root) | a reviewer must not inherit the writer's context |
| 4 Commit | root | consent + `git`, nothing to read |
| 5 Finalize, 7 Ship-out | root, dispatching each check | root reads verdicts, not outputs |

**The dividing line: gathering and rendering are AFK; every step that DECIDES is human-in-the-loop.**
Steps 1 and 2 are the alignment phase, and alignment cannot be delegated to an agent — not the
grill (1c), not the trade-offs (2b), not the phase split (2c). A subagent cannot talk to him, so
handing it a step whose deliverable is *his agreement* means the step silently automates itself and
he finds out at the end. What CAN go to an agent is exactly the two ends: reading the code (1a, 2a)
and printing the document (2d). Implementation (Step 3) is AFK by design; planning never is.

**What the root does with what comes back — verify, do not trust:**

- A subagent's claim about code carries `file:line`, or it does not count. Spot-check the load-bearing ones against the tree yourself; that costs one targeted `Read`, not twenty.
- Cross-check subagents against each other. Two agents disagreeing is information — never silently pick one.
- `git log` / `git diff` / the working tree beat any subagent report, exactly as they beat `progress.md`.
- A subagent that returns prose instead of evidence gets re-dispatched with a narrower question, not paraphrased into the plan.

**Every implementer prompt must carry this line verbatim:** *"KHÔNG chạy `git checkout --`, `git restore`, `git stash`, `git reset` trên bất kỳ file nào. Thấy thay đổi chưa commit của người khác đang chắn đường thì DỪNG và báo lại."* The rule already exists for the root (resume protocol) but a subagent does not inherit it, and a subagent that finds someone else's half-finished work in its way will reach for `git checkout --` as a tidy-up. 2026-08-18: one did exactly that on a source file another agent was mid-edit in, discarding a previous agent's uncommitted WIP. Harmless that time — the WIP was a rejected approach and was broken anyway — but the tree is the user's, and nothing uncommitted is the subagent's to throw away.

**When NOT to dispatch:** one known file, one grep, one command. A subagent costs a round trip and starts from nothing, so for a single small read it is pure loss. Dispatch when the work means *searching* rather than *fetching*.


## Step 0 — Orient & pick the MODE (always first)

**ALWAYS WORK IN THE MAIN CHECKOUT — NO WORKTREE (user 2026-06-18: "làm trên branch chính để test + review cho dễ; bỏ worktree trong skill").** Do the work on a normal feature branch IN the main checkout (`{{PROJECT_ROOT}}`) so the user can run/test/review it directly in his primary working directory and the local dev stack builds the actual changes. Do NOT create git worktrees (no `git worktree add` / EnterWorktree) — a separate worktree directory is harder for him to test and review, and the dev stack runs from the main checkout. If another live session is genuinely mid-task on a different branch in this same checkout, don't silently yank it — surface that to the user and let him decide; never auto-worktree. **Session boundary rule:** NEVER open another task's `.claude/ship/<slug>/` state (memory `session-task-boundary`); answer cross-task status questions only from Notion/git public surfaces.

A task is rarely greenfield. Before anything, determine its real state:

1. Run `/branch-focus` — what branch, what's committed, working-tree state, how far along.
2. Read the Notion task status + latest comments (`notion-tasks get`) — To do? Doing? Testing/UAT? Fixing?
3. Check for an existing `.claude/ship/<task-slug>/progress.md`.

Then pick the mode — **tell the user which mode was picked and why** (he can override):

| Signals | Mode | Behavior |
|---|---|---|
| Status To do, no branch/commits | **SHIP** (fresh) | Full pipeline: Setup → Step 1 → 2 → 3 → 4 → 5 → ship-out gate (6) → execute (7) |
| Branch exists with commits / progress.md exists / status Doing | **CONTINUE** | Resume protocol (below). NO new plan from scratch — re-orient, reconcile plan vs what's already committed, continue at the next unfinished phase. Gate 1/2 only re-run for the *remaining* scope if requirements shifted |
| Status Testing/UAT/fixing, bug reports in comments | **STABILIZE** | No plan.html, no phase split. Per bug: reproduce → `/debug`-style root cause (read logs/errors first, verify in code) → **ATTRIBUTION before any fix (user 2026-06-11: "tại sao lỗi, do commit nào… nhỡ commit master thì để họ tự sửa"): find the introducing commit (`git log -S`/blame) + author. Master/other-dev origin → DO NOT fix in this branch — report commit + author + date to him; the owner fixes it (or he explicitly pulls it into scope). Only fix what THIS branch introduced or what he explicitly orders** → surgical fix → lint. **BATCH the review (user 2026-06-11: "code xong chạy cái review code gửi cùng với thông báo cho tôi review"): (1) code the whole reported list first, (2) review the combined diff in a clean context — dispatch the `code-reviewer` agent for the project's own standard (never skip) plus `/code-review`; the session that wrote the fixes never reviews them, fix must-fix findings, (3) report the batch WITH both review summaries → his OK → commit. **No browser/e2e pass — he verifies the fixes himself.**** **Rapid-fire rule (user 2026-06-11): when he drops SEVERAL unrelated UAT items at once (different surfaces/files), do NOT investigate serially — fan out a multi-agent Workflow, one read-only root-cause agent per item (each returns cause + file:line evidence), then apply fixes one by one on the shared tree.** Scope guard: fix only what's reported — no refactors mid-UAT |

Ambiguous signals (e.g. status says Doing but branch has UAT-fix commits) → ask, don't guess.

## Setup (once per ship — SHIP mode; CONTINUE/STABILIZE reuse the existing branch & artifacts)

1. **Branch**: create `feature/<task-slug>` (or `bugfix/`) from fresh `origin/master` — never ship on master. Confirm the branch name with the user at Gate 2 (part of the plan).
2. **Artifacts dir**: `.claude/ship/<task-slug>/` holding `plan.html` + `progress.md` + `decisions.md`. Add `.claude/ship/` and `.playwright-cli/` to `.git/info/exclude` (LOCAL ignore — never edit the tracked `.gitignore`; zero MR pollution).
3. **Seed the two docs from the templates in this skill** — copy `templates/progress.md` and `templates/decisions.md`, fill the `<!-- state -->` block + task link. At Setup the checklist is still empty: it gets **generated from `plan.html` at Step 2**, not written by hand now. These docs are the user's explicitly-requested exception to `feedback_docs_out_of_commits`. They are local-ignored, so they can never leak into a commit; still, ALWAYS stage by explicit file path — **never `git add -A` / `git add .`** anywhere in this pipeline.

## Artifact contract (READ BEFORE WRITING EITHER DOC)

Three files, three different lifetimes. Putting the wrong thing in the wrong file is what made an earlier `progress.md` grow to 63KB with **three conflicting `> **NOW:**` markers** — the session after it could not tell which one was true.

| File | Lifetime | Written how | Contains |
|---|---|---|---|
| `analysis.md` | Step 1 → **live for the whole task.** 2c stops it being the working surface; it does NOT make it immutable — see "Discoveries mid-implementation" | Markdown, by hand | **The only doc written for HIM to read while planning.** §1 miền · §2 ai đau + số · §3 hôm nay ra sao (`file:line`) · §4 khoảng trống · **§5 sổ điểm mở** · §6 GOAL. No solutions, no phases — those make it unreadable and belong to the plan. Markdown because it gets edited every round while you two verify it. **§5 is the one ledger for the whole planning phase**: Step 1 writes the business rows, 2b adds the technical ones. Both gates are blocked while any row is still open, so it must live in a file — a ledger kept in chat dies with the session. |
| `facts.md` | Step 2a → **append-only for the whole task**; new evidence found mid-implementation lands here too | By the reader agents | `claim \| verdict \| file:line`. Evidence pulled from the code — no recommendation, no plan. Exists so 2b can decide without re-reading the codebase. **He does not read this one** — that is what `analysis.md` is for. |
| `plan.html` | Rendered ONCE at 2d | From `templates/plan-doc.html` | The plan — phases, trade-offs, risks. **Source of truth for the checklist.** A projection of `facts.md` + `decisions.md` + the phase split; never hand-patched. |
| `progress.md` | Now — rewritten constantly | From `templates/progress.md`, **generated from `plan.html` §4** | ONLY checkboxes + one `> **NOW:**` + what the user is being asked |
| `decisions.md` | Forever — append-only | Appended by hand | Decisions + why + rejected option, architecture lessons, tech debt |

**Laws:**
- `progress.md` is a **projection of the plan, not a journal.** Every checkbox traces to a `<li>` in `plan.html` §4. Finished an item → **tick it**; do not append a paragraph describing it.
- **Rewrite in place, never append.** Superseded text gets deleted, not stacked below.
- **Exactly ONE `> **NOW:**` line exists in the file.** Moving the pipeline = editing that line. A second one is a bug — if you ever find two, the newest wins and the other gets deleted immediately.
- **Never write into `progress.md` anything derivable** from `git log`, `git diff`, the code, or a test run — test counts ("712/712"), commit lists, code descriptions. They go stale at the next commit and there is nothing to catch it. Need the number? Run the command.
- **Knowledge goes to `decisions.md`**, with the reason and the rejected alternative. A decision without its *why* is worthless to the next session.
- **Soft ceiling ~150 lines for `progress.md`.** Over it means journal text has crept back in — move it to `decisions.md` or delete it.
- **STABILIZE mode has no `plan.html`** — there the checklist projects the *reported bug list* instead: one `###` group per reported item, its checkboxes being attribution (`git log -S` → introducing commit + author) → fix → then the round-level batched reviews (`code-reviewer` + `/code-review`) + one combined browser pass. Same laws otherwise.
- **A lesson recorded twice must leave `decisions.md`** — promote it to `CLAUDE.md`, a hook, or a test. Writing it a third time proves the doc is watching a bug repeat instead of preventing it (this branch's CSS-cascade bug hit three times with the lesson already written down).

## Resume protocol (session died / new session re-invokes /ship)

1. `git status` + `git diff` FIRST — the working tree beats the progress doc; never discard changes, never `git checkout --` anything.
2. Read `progress.md` → the `<!-- state -->` block, then the single `> **NOW:**`, then the first unticked checkbox. Committed phases are settled (git log is the source of truth), half-done work continues from the diff.
3. **Reconcile before trusting a tick.** A checkbox is a claim, not evidence: verify each ticked item against `git log`/the diff. Tick that git contradicts → untick it and say so. This is the check the old free-form doc had no way to run.
4. Read `decisions.md` before touching code — it holds constraints the user already set ("không viết migration"), so re-deciding them wastes his time and may undo a deliberate call.
5. **Found more than one `> **NOW:**`?** Sessions overlapped. Keep the one consistent with `git log`, delete the rest, and mention it in the first report.

## Step 1 — Hiểu (Gate 1, loops until he says the map is right)

**Step 1 and Step 2 sit at different altitudes, and mixing them is what made earlier gates
unanswerable.** Step 1 is the *business*: what this domain is, who hurts, what we are aiming at.
Step 2 is the *technical*: how to build it. The test for any question — **could he answer it
without reading a line of code?** No → it belongs to Step 2, hold it.

Run `/analyze-task <notion-url>`. Its shape:

- **1a Verify** (subagent) — claim table, `file:line`, real numbers. Every open point that a query
  or a grep can settle gets settled HERE, not asked. Facts kill questions.
- **1b Analysis** — write `analysis.md`: §1 miền là gì · §2 ai đau, bao nhiêu · §3 app đang làm gì
  hôm nay · §4 khoảng trống · §5 sổ điểm mở · §6 GOAL **để trống**. Business first, code second, no solutions.
- **1c Grill 🚦** (root + user, in chat) — **ONE question per turn, end the turn, wait.** Only
  questions with no correct answer reach him: khẩu vị · merchant nhìn thấy đổi · scope. Each carries
  the Fact that makes it a question plus a recommendation. His corrections fold back into
  `analysis.md`.
- **1d Goal** — when HE says the map is right, fill §6 **with him**, then copy it into
  `decisions.md` as `## Goal đã chốt (<date>)`.

**Do not produce `plan.html` here and do not split phases** — that is Step 2. A previous run of
`multi-market-reward-programs` went straight to a 68KB `plan.html` he could not read, with the one
question that decided everything parked at the bottom; that attempt was deleted.

Gate 1 ends on his explicit move ("ok", "move", "bước 2", "tiếp") — at THIS gate "tiếp" means
proceed, it is not a commit gate.

## Step 2 — Plan (Gate 2, loops until "move")

**This is where ALL verification and ALL open questions get resolved.** The plan he approves must already be code-grounded and spell out the detailed fix per phase — so the flow-check runs HERE (not at code time), and every question is asked at this gate. By the time Step 3 starts there should be nothing left to discover; Step 3 just executes.

Coding is the fast part; this is the part worth the time. So Step 2 is **four separate sub-steps, not one turn** — 2a gather, 2b decide, 2c split, 2d render.

**Why split.** The four kinds of work here have opposite needs, and running them in one turn puts the thinking in the worst place. 2a is bulk reading with almost no judgement — agents, in parallel. 2b is the opposite: almost nothing to read, the hardest thinking in the pipeline, and it is **his**, so it needs a clean context. 2c is a proposal from the root whose **ordering he settles**. 2d is mechanical printing — one agent.

**The revision loop belongs to 2b, in chat, as short text.** Re-rendering `plan.html` on every round of feedback reprints the same document to change one sentence, and it produced a plan too long for him to actually read (`multi-market-reward-programs` reached 476 lines).

**Run each sub-step in a fresh session** — finish it, write its file, exit, relaunch for the next. Same tab; the file is the handoff, not the context. Do NOT carry 2a's raw reading into 2b.

### 2a — Gather (agents, read-only, no conclusions)

Workflow fan-out: parallel reader agents over every surface this task touches + their backend paths, each confirming/refuting the spec's assumptions with `file:line` evidence; plus one adversarial agent hunting hidden couplings against this named checklist: field-trigger loops, `pickFields.js` whitelist, surface-is-live (legacy scripttag is dead), backwards compat for existing shops, Firestore index existence.

Output: **`facts.md`** in the ship dir — a table of `claim | verdict | file:line`. Facts only. No recommendation, no prose, no plan. If an agent wants to recommend something, that is 2b's job and it goes in the "open question" column instead.

The user does not read `facts.md` cover to cover; it exists so 2b can be decided without re-reading the codebase.

### 2b — Decide 🚦 (the gate that matters)

Fresh session. Load **only** the spec + `analysis.md` + `facts.md`. Not the agent transcripts, not the code.

**Same rhythm as the Step 1 grill — this step is not a batch either.** The difference is altitude, not method: Step 1 asked what he could answer without reading code; 2b asks the technical trade-offs he can now answer *because* he has read `analysis.md`.

- **Facts kill questions first.** Anything `facts.md` settles, or that one more query would settle, is not a question. Only genuine choices reach him.
- **The ledger is `analysis.md` §5 — the SAME one, not a new one.** Step 1 filled it with business rows; 2b adds the technical rows and keeps updating the states. It lives in a file on purpose: 2b is a loop that can outlive its session, and a ledger kept only in chat dies with the session (this has already cost a day once). Post it each round so he sees how many decisions are left and can reorder or strike them.
- **One at a time, blockers first.** Each carries the Fact that forces the choice (with `file:line` or a number from `facts.md`), the options with ưu/nhược, and your recommendation.
- **He says when 2b is done, and it is a gate, not an intention** — same shape as Step 1, because the same pressure applies here and an intention does not survive it:

  > **2b may not end while any §5 row is `chưa đụng` or `đang hỏi`.**
  > **Before you may even ASK whether it is settled, post the ledger and this sweep:**
  > *"Chưa đụng tới: … · Không verify được: … · Giả định còn lại: …"*

  All three lines empty on a real task means you stopped looking, not that you finished. Sweep against what gets forgotten at this altitude specifically: the other surfaces (your surface inventory) · shops already live · rollback if the phase is wrong · what happens to data written before the change · who else reads the field being changed.

Short text in chat. No HTML is written at this stage.

Every open technical question gets asked here. Step 3 must not need to come back.

Output: append the settled decisions to **`decisions.md`** — decision, why, rejected option.

### 2c — Split into phases 🚦 (with him, not for him)

Fresh session, reads `facts.md` + `decisions.md`. Split into **small phases by flow/surface** — each phase one coherent, separately-reviewable story (e.g. *Phase 1: widget v3 → Phase 2: widget v4 → Phase 3: theme block*), each including its own backend touchpoints. Avoid one giant cross-surface diff. Feature-shaped work keeps the inner order B1 admin → B2 backend → B3 storefront (`feedback_feature_workflow_order`).

**This is a gate, not a deliverable.** The technical grouping is yours to propose; **the ordering is his** — which piece ships first, what is in v1 and what waits, what he wants to be able to look at soonest. He is the one who tests each phase, so the sequence is a question about his week, not about the dependency graph. Propose the split, then ask him — the two things worth asking explicitly:

> **Phase nào anh muốn thấy chạy trước?** (đề xuất: … vì …)
> **Cái nào rơi khỏi v1?** (đề xuất: … vì …)

Output goes **in chat as plain text**, 5–10 lines per phase: what changes, which files, the Pattern tham chiếu line, the verify line. Short enough to read there, and short enough to argue with. Loop until he settles the order — the same rule as 2b: he says when it is done.

**No `phases.md` file.** `plan.html` §4 becomes its home minutes later at 2d; a file that exists only to be superseded is one more thing that can go stale and disagree with the plan. The chat message is the draft; the render is the record.

### 2d — Render (mechanical, once)

Only after 2b and 2c are settled. This sub-step decides nothing — it projects `facts.md` + `decisions.md` + the phase split agreed in chat into the HTML. If the rendering is wrong, re-render; that costs nothing now that no thinking lives here.

Generate **`plan.html`** in `.claude/ship/<task-slug>/` — **copy `templates/plan-doc.html` from this skill and fill the `{{...}}` placeholders. Do NOT hand-roll the HTML/CSS and do NOT edit its `<style>`.** (Why the template exists: 12 earlier plan.html files each looked different — only 5/12 had the pinned left TOC he asked for, 1/12 had dark mode. "thiết kế lại được không, làm thành 1 bộ khung đi".) The template already carries: `lang="vi"`, the `:root` palette (--accent #2f6df6, hero gradient 135deg #2f6df6→#5b8bff), dark-mode overrides, pinned left `nav.toc` with scroll-spy, and the six numbered `section.card`s — **1) Tổng quát** (+ 🎯 `.goal` box), **2) Phân tích hiện trạng** (spec-vs-code corrections from the flow-check, in `.callout.danger`), **3) Trade-offs** (per-decision table: option A/B, ưu/nhược, đề xuất + lý do), **3b) Module sẽ sửa** (the module map, written BEFORE the phases and the thing the phases are cut along — module · sửa/mới · why touched · **who else uses it**; that last column is where this repo's most expensive bugs live), **4) Plan theo phase** (`.phase` cards, each with its **Pattern tham chiếu** line plus the DETAILED fix — which files, what change — work items + verify line + gate badge; add `.done` to the card as phases complete), **5) Risks** (rủi ro/ảnh hưởng/giảm thiểu), **6) Điểm cần chốt** (#/Vấn đề/Lựa chọn table), **7) Ngoài phạm vi** (copied from `analysis.md` §6's "KHÔNG làm" half — this is the definition of done; it is NOT §3's rejected option, which is a fork rather than a boundary, and leaving it empty is almost always a sign nobody asked what is *not* in the task). Reuse the existing classes (`.goal .callout .badge .phase .item-tag .muted`) — do not invent new ones.
Then deliver: `open <plan.html>` locally, plus a 3–5 line gist in chat (phases, key trade-offs, decision needed) + the local file path.

**The loop lives in 2b, not here.** Cosmetic or projection errors → re-render. A change to *what was decided* is not a render fix: go back to 2b, settle it in chat, then re-render. Never edit `plan.html` by hand to paper over a decision that shifted — the HTML is a projection, and a hand-patched projection is how plan and reality drift apart silently. A genuinely NEW problem discovered mid-code goes through "Discoveries mid-implementation" (Step 3), which routes it back to 2b or 2c depending on its size — the exception, not routine, but a supported one.

Finally, **generate `progress.md` FROM the approved `plan.html`** (only after he says "move" — regenerating on every draft is churn). Mechanical projection of §4, no invention:

   | `plan.html` §4 | → `progress.md` |
   |---|---|
   | `<h4>Phase N — <name></h4>` | `### ⬜ Phase N — <name>` |
   | `Pattern tham chiếu:` line | `` `Pattern:` file:line — name `` under the heading |
   | each `<li>file — what</li>` | one `- [ ] file — what` |
   | `Verify:` line | `- [ ] Verify: <...>` |
   | (every phase, fixed) | `- [ ] eslint`, `- [ ] review (code-reviewer + /code-review)`, `- [ ] Báo cáo Gate 3 → OK → commit` |

   Also fill the Gate-1 requirements section and set `> **NOW:**` to Phase 1. **A checkbox with no matching `<li>` in the plan is not allowed** — if the work is real, the plan is wrong: fix `plan.html` and re-project. That coupling is what keeps the checklist bounded and keeps plan and reality from drifting apart silently.
Last, check `decisions.md` actually captured everything settled in 2b — every §3 trade-off and every §6 answer, each with its rejected option. §3 records *what* was chosen; `decisions.md` records *why*, and it is the only one of the two that survives the plan being rewritten. Anything decided in chat but missing from the file is lost the moment this session ends.

## Step 3 — Implement (per phase; Gate 3 repeats per phase)

The plan is already code-grounded from Step 2, so this step just **executes** — code, self-review, report. Keep it fast. **Do NOT re-run the heavy flow-check here, and do NOT stop to ask unless a genuinely NEW problem surfaces** (something Step 2's flow-check missed). When one does, it goes through "Discoveries mid-implementation" below — name which of the three sizes it is and follow that path. Otherwise keep moving.

For EACH phase:

1. **Touchpoint re-check (light)** — confirm the exact `file:line` you're about to edit still matches the plan; re-read a file only if an earlier phase in THIS branch already changed it. No multi-agent fan-out — that happened in Step 2.
2. **PATTERN REFERENCE gate (BLOCKING — before writing any new function/component/file).** State, in the phase report and in `progress.md`:

   > Bê pattern từ `<file:line>` — hàm/component `<tên>`. Điểm khác biệt: `<...>`

   **No reference file named = do not write the new code.** Go find the sibling first (grep the same folder, the same layer, the same surface). This is stricter than "reuse code": you may not be able to reuse the code at all, but you must still reuse its *shape* — same argument order, same guard-clause style, same error handling, same file placement.
   - The reference must be a file that EXISTS on the current tree; verify it, do not recall it from memory.
   - Genuinely no sibling anywhere (a truly new pattern for the codebase) → say so explicitly and say what you modelled it on instead. That is a legitimate answer; silence is not.
   - Ratchet trace: "sửa hãy tìm 1 hàm để tham khảo và bê về nhé, đừng cố phân tích viết lại từ đầu" + "sao lại có 2 hàm dùng 2 nơi chả liên quan logic gì đến với nhau như này". 31 occurrences of hand-rolled-instead-of-copied code.
3. **Code** the phase — surgical, layer rules (`layer-architecture`), match precedent (`feedback_file_placement`). New user-facing strings → translations in the same phase (`feedback_translation_workflow`). **No wrapper component/function that only renames a prop or passes through** ("wrapper thì giữ làm gì nhỉ") — call the underlying thing directly.
4. **Quick `eslint`** on changed files (repo `eslint-fix` scripts scoped to the phase diff) — fast, always run as part of finishing the code. The slow functional/browser test is the separate, skippable Step 4.
5. **Review the diff in a CLEAN context, then SEND IT (user 2026-06-11: "code xong chạy cái review code gửi cùng với thông báo cho tôi review")** — after coding the phase/round (all items), run **BOTH** reviews on the diff. They catch different things and neither replaces the other:

   (a) **The project's own standard review — dispatch a subagent whose job is to RUN `/review`** (read-only, fresh context) on `git diff` for this phase. The subagent invokes the command itself; do NOT hand a different agent the checklist to read second-hand. `/review` is the review THIS project wrote for itself (`.claude/commands/review.md`): its layer rules, its scoping rules, its naming, its UI kit, its i18n keys, its response envelope. **This one must never be skipped, and must never be substituted** — a generic scan does not know this project's layering or its translation workflow, so it passes code that this review would reject.

   > Twice now this step was run as "`code-reviewer` agent + tell it to apply the checklist" instead of actually running `/review` — user 2026-08-08 (*"bước review tôi thấy đang gọi code review chứ không phải review của project"*) and again 2026-08-18 (*"cái review project tự viết ấy"*). The wording above is the fix: the deliverable is `/review`'s output, not an agent's paraphrase of its checklist.

   (b) **`/code-review`** (low/medium) — the generic plugin defect scan, which spawns its own parallel auditors.

   **Neither review may run in the context that wrote the code.** The implementer subagent does not review its own phase, and the root does not run the checklist inline in a session holding the writing rationale — an author reading their own diff sees the intent they meant, not the code they shipped. Dispatch it; the reviewer gets the diff and nothing else. A slash command expands into whatever context invokes it, so `/review` never runs in the root — it runs INSIDE a dispatched subagent, which is how it gets both the project's checklist and a clean context. Run (a) and (b) as **two subagents in parallel**; they catch different things and neither substitutes for the other.

   Then fix the clear, must-fix findings and **include the review result in the Gate 3 report** — a short summary of what each review found + how each finding was handled (fixed / left + why), so HE reviews the code with the review in hand. The review output travels WITH the gate report, never silently swallowed. (Final review uses a different tool — see Step 5.)
6. **Report (Gate 3)** — in chat: what the phase did, files changed, `eslint` result, **both review summaries from step 5**. Do not offer to test it — say **what to look at** instead: which screen/flow and what should be different now. He verifies it himself. In `progress.md`: tick the code/eslint/review checkboxes this phase actually completed, flip the phase heading to 👀, move the single `> **NOW:**` to "chờ OK phase N", and fill "Đang chờ user". Nothing else gets written — the report itself lives in chat, not in the doc. The report MUST end with the exact consent line: **"OK = em sẽ commit phase này."**
7. **Dispatch gate-wait verify (mode a) — after posting the report, before ending the turn.** The tree is frozen while he decides, so this costs nothing and finishes inside his think time. Pick the checks from "Background verify" that match what this phase touched; skip it entirely for a trivial phase. If it returns findings before he replies, post them as a short follow-up so he decides with them in hand.
8. **LOOP**: feedback → fix → re-report, until explicit OK. A fix round invalidates the previous verify — re-dispatch on the new report, don't carry the old result forward.

## Discoveries mid-implementation (the plan is allowed to change direction)

Step 2 is where discovery is *supposed* to happen, but a plan that cannot bend mid-flight is a plan that gets quietly ignored instead. Coding, reviewing and testing surface things Step 2 could not — that is normal, not a failure of the plan.

**The planning artifacts stay live for the whole task.** "Frozen at 2c" means `analysis.md` is no longer the working surface, NOT that it is immutable. A doc that is known to be wrong and left standing is worse than no doc: it misleads the next session, and it is read as approved.

Three sizes of discovery. Name which one it is out loud, then follow its path — do not silently pick the cheapest.

**A — a technical trade-off** (which file, which approach, a coupling nobody had priced). The common case. Does not touch `analysis.md`.
1. Stop coding the item and ask him in chat, in the 2b rhythm: the Fact that forces the choice (`file:line`), options with ưu/nhược, your recommendation.
2. New evidence → append to `facts.md`. New open point → a new row in `analysis.md` §5 with its type, so it is visible and cannot be forgotten.
3. Settled → append to `decisions.md` (decision, why, rejected option), edit **only** the affected phase card in `plan.html`, re-project the changed checkboxes into `progress.md`.
4. Resume the phase.

**B — the map was wrong** (§3 "what the app does today" is factually false, or §4's gap is not the real gap). Rarer and more serious, because §6's GOAL may have been built on it.
1. Correct `analysis.md` §3/§4 with the new `file:line` evidence, and mark what changed.
2. **This is a gate, not an edit.** Tell him plainly: *"bản đồ mình duyệt ở Gate 1 sai chỗ này — …"*, and say whether the GOAL still holds. He decides whether the goal changes. Never fold a corrected map back in silently: he approved the old one, so the correction is news, not housekeeping.
3. Then continue as case A for whatever it changes downstream.

**C — the direction changed** (the phase split no longer makes sense, the remaining phases are wrong, a whole surface drops in or out). This is a re-entry into **2c**, not a patch.
1. Committed phases stay committed — `git log` is the record and it is not rewritten. Cut the split for the *remaining* work only.
2. Re-propose the split in chat (5–10 lines per phase, as at 2c) and let him settle the ordering — same gate as the original, same two questions: what he wants to see running first, what falls out of v1.
3. Re-render `plan.html` §4 from the agreed split, then re-project `progress.md`. Unticked checkboxes of dropped phases disappear with them; ticked ones do not get un-ticked to fit a new plan — if reality and plan disagree, the plan is what changes.
4. Append to `decisions.md` **why the direction changed** — this is the single most valuable entry that file ever gets, and the one most often lost.

Cheap test for which case: does it change what the code does (A), what we believed was true (B), or what we are building next (C)?

**What never happens:** discovering any of the three and continuing to code without telling him. The tree is his to review at Gate 3, and a phase that silently drifted from the plan he approved is exactly the report that gets rejected.

## Step 4 — Commit the phase

**Functional testing is NOT part of this pipeline. He tests it himself** (chốt 17/08/2026 — trước đó bước này "skippable" nhưng vẫn mặc định chạy rồi mới hỏi, và nó là chỗ Step 3 hay bị kéo dài nhất). Do not run a browser pass, do not open the storefront, do not ask "anh tự test hay em chạy?". The Gate 3 report says what changed and where to look; he decides when it is verified.

`eslint` (Step 3.4) and the two reviews (Step 3.5) stay — those read code, they do not exercise the product, and they travel with the report.

After the Gate 3 report, for this phase (or batched round):

1. **Commit consent is strict** (`feedback_git_workflow` — he has reverted an auto-chained commit before): only the word "commit"/"ok commit", or an affirmation given AFTER the consent line of THIS phase's report, authorizes the commit. A bare "ừ"/"tiếp"/anything ambiguous → ONE disambiguation question ("OK này là commit phase N luôn đúng không?"), never a silent commit. Each phase needs its own consent — consent never carries over. Late fixes to an already-committed phase get their own commit + their own OK.
2. **On OK → commit the phase** — stage by explicit file paths (code only; progress doc is local-ignored anyway), **commit message in English**, repo convention (`fix:`/`feat:` per `git log`). **NEVER push** — push only on his separate explicit instruction.
3. **Dispatch cross-phase verify (mode b) on the fresh `<sha>`, then move straight to the next phase — do not await it.** The commit is immutable, so the verifier is safe no matter what the next phase does to the tree. Its findings arrive mid-next-phase; per rule 6 they become new items under "Việc phát sinh ngoài plan", never a silent reopen of the committed phase.
4. In `progress.md`: tick the phase's remaining checkboxes, flip its heading to ✅, clear "Đang chờ user", move `> **NOW:**` to the next phase. Append to `decisions.md` only if the phase produced a real decision or lesson — a phase that just executed the plan produces nothing worth appending, and forcing an entry every phase is how that file turns back into a journal. Next phase.

## Background verify (parallel, never blocks a gate)

The pipeline has two long stretches where the main thread is doing nothing useful: **waiting for his gate reply**, and **coding the next phase**. Both are free capacity for a read-only verifier. This is an EXTRA layer on top of the Step 3.5 reviews — it never replaces them, and a phase report is never delayed waiting for it.

**Two modes. The difference is what the verifier reads, and it is the whole safety story:**

| | (a) Gate-wait verify | (b) Cross-phase verify |
|---|---|---|
| When | Right after posting the Gate 3 report, before ending the turn | Right after a phase is committed (Step 4.3) |
| Reads | The working tree — **safe, because the tree is frozen while he decides** | `git diff <sha>^..<sha>` for the committed phase — **immutable** |
| Isolation | None needed | None needed (a commit cannot change under it) |
| Cost | Free | Free |

**The one arrangement that is forbidden: verifying uncommitted work while the main thread keeps coding.** The verifier reads a tree that is half phase N and half phase N+1, and reports findings against code that never existed in that combination. Those findings read as plausible and waste his time. If you genuinely need it, the verifier must run with `isolation: 'worktree'` — otherwise don't dispatch it.

**Rules:**
1. **Read-only, always.** The verifier gets Read/Grep/Glob/Bash — never Edit/Write. A verifier editing files while the main thread codes is the same race in a worse form.
2. **Dispatch, then keep going. Never await.** If a verify result would change what you do next, it is not background work — run it inline as part of Step 3.5 instead.
3. **Give it the immutable handle explicitly** — the phase's `<sha>` for mode (b), or "the working tree as of now, do not expect it to change" for (a). A verifier that guesses its own scope verifies the wrong thing.
4. **Re-verify every finding in code yourself before reporting it** (same law as Step 7.5 — agents overstate; 2026-06-12 the HMAC finding needed nuance only code reading settled). An unverified agent claim never reaches him.
5. **Findings are findings, not a work order** (`feedback_data_driven_decisions_monitor`) — report with `file:line` + recommendation; HE decides what gets fixed. Accepted findings become a normal fix round with its own Gate 3 consent.
6. **A finding that lands after the phase is committed does NOT reopen it.** It becomes a new item under "Việc phát sinh ngoài plan" in `progress.md` and its own commit (`feedback_git_workflow` — late fixes get their own OK).
7. **Never dispatch a verifier for what Step 3.5 already covers.** `code-reviewer` and `/code-review` own the phase diff. Background verify is for the checks those two do NOT do, and that are too slow to run inline.

**What is actually worth verifying in the background** — pick by what the phase touched, not all of them every time:

- **Cross-surface parity** — the same behaviour on every surface that renders it (each front end, each embed, each account area). The most expensive bugs are all this shape: a shared component quietly loses a property only ONE caller was passing. Consult your surface inventory (`surface-audit`) for the list, so a feature does not ship to four surfaces when it has five.
- **Shared-component blast radius** — for every symbol the phase deleted or renamed, grep every caller that might still pass it. "This caller doesn't pass the field" ≠ "the field is dead".
- **Regression vs master** — is a file the phase touched byte-identical to master where it claims to be untouched; did the phase change behaviour master relies on.
- **Translation coverage** — new user-facing strings present in all locales, keys placed next to their siblings (`feedback_translation_key_placement`).
- **Dead references after a deletion** — constants/CSS vars/attributes the phase removed, still referenced somewhere.

## Step 5 — Finalize (local, before any ship-out)

1. Master-drift check: `git fetch origin master` + diff against base; if master moved significantly, surface it.
2. Full pass: tests across touched packages; **`/review-v2`** (design-doc cross-check, full branch scope); `/impact`.
3. `/translate` if labels were added; `/test-checklist` for the QA checklist.
4. `/mr` — generate the MR description (GitLab, no `glab`; he pushes & opens the MR himself).
5. `/update-handle` to sync the board.

## Step 6 — Ship-out GATE (ASK — never auto)

All local work is done; this is NOT the end. STOP and ask him in chat — present options with the facts:

**Q1 — Deploy to staging?** Which one? Follow your project's deploy skill — its core law: **NEVER assume the branch a staging runs; DETECT it from the deployed bundle** (`VITE_APP_DEPLOYED_BRANCH` baked in `https://{{FIREBASE_STAGING}}-<N>.firebaseapp.com/assets/app-*.js`), cross-check that branch's own `.gitlab-ci.yml` staging refs. ⚠️ 2026-06-11 incident: the branch NAMED after a staging was 6 months stale while that staging actually ran an integration branch — pushing the same-named branch triggered a wrong deploy. Two models (per what detection finds):
- **Dedicated-branch**: repoint that staging's CI `only` refs at THIS branch, push.
- **Integration branch running**: push the feature branch FIRST (MR must contain the commits), then MERGE feature into the DETECTED running branch, empty commit titled `deploy` (CI `except`s "Merge branch" titles), push that branch.

**Q2 — Merge into a merge/integration branch?** (gather other branches already merged there so he sees what he's joining). Use `merge-branch` skill (feature → integration context: per-hunk union, find which incoming branch caused each conflict).

Default nothing — he picks: deploy to a staging, merge into the running integration branch, both, or neither (just leave the MR). **Before ANY deploy-triggering push: report the detected branch + exact plan and WAIT for his confirm** — even though he already chose "deploy" at this gate, the concrete push set still gets confirmed once.

## Step 7 — Execute the ship-out (per his choice)

1. Execute per your project's deploy skill (detect → confirmed plan → push). Check what that CI actually covers: anything it does NOT build (a separately-deployed extension, a CDN bundle) still needs its own deploy against the same environment.
2. **Arm a deploy-success watcher** (the "cron" he asked for): poll the GitLab pipeline for THIS push until it finishes (needs a GitLab PAT with `read_api` — **if absent, ask him in chat to provide one once**; store in `.env.agent` as `GITLAB_TOKEN`). Repo: `{{GIT_REMOTE_HOST}}`. **No-token fallback**: poll the deployed bundle itself — `VITE_DEPLOY_TIME` + `VITE_APP_DEPLOYED_BRANCH` in `https://{{FIREBASE_STAGING}}-<N>.firebaseapp.com/assets/app-*.js` flip when the deploy lands (check every ~4 min, CI takes ~15-30 min).
3. **On deploy SUCCESS** → report the staging URL + what changed, and stop. **He tests it himself** (chốt 17/08/2026). If a deploy-time error shows up in the pipeline or the logs, that is a failure to report, not a test to run.
4. **On deploy FAIL** → report in chat the failing job + log tail; do not re-test.
5. **End-of-round multi-agent review (user order 2026-06-12: "vừa deploy rồi cũng chạy agent để nó review"):** right after the post-deploy test passes, fan out the FULL branch review — 4 parallel agents: `security-auditor` + `performance-reviewer` + `shopify-app-tester` (impact) + `code-reviewer`, scope `git diff origin/master...HEAD` minus generated/translation noise. Then (a) **re-verify every CRITICAL finding directly in code yourself** before reporting — agents disagree and overstate (2026-06-12: HMAC finding needed nuance only code reading settled); (b) send ONE synthesized report in chat — security first, then perf, then impact checklist — each finding with file:line, framed as findings + recommendation, HIS decision what to fix; (c) findings he accepts become a normal fix round (Gate 3 consent applies).
6. Final report in chat: done summary + MR + staging URL + post-deploy test results + review verdicts + anything deferred.

## Rules

- **A turn answering his feedback must show what was checked.** This is the largest failure mode in
  the pipeline, and **"đã sửa rồi anh" is its highest-risk sentence.** After he pushes back, do not
  reply until you have re-read the thing he questioned. The reply names the `file:line` you checked
  and what you found — including when the finding is "he was right" or "I could not verify this".
  Length is a symptom, not the target; padding a thin answer fixes nothing. A turn that *checked*
  looks different from a turn that *guessed*, and he can tell.

- **Context size is not a reason to reset.** There is no token threshold at which quality falls off,
  so do not invent one and do not abandon a session that is going well because a number looks big.
  Reset on **event**, not on size: a sub-step finished (2a → 2b → 2c → 2d), a phase committed, or
  the kickoff has changed. Auto-compact is the one event that genuinely loses information —
  `PreCompact` + `SessionStart` hooks cover it.

- Gates never advance on silence; park (edit the single `> **NOW:**` line, end the turn) and resume later when he replies.
- Background verify never blocks a gate and never edits. Verify a frozen tree (he's deciding) or a committed `<sha>` — never uncommitted work while you keep coding.
- `progress.md` = checkboxes projected from the plan, rewritten in place. `decisions.md` = why, appended forever. Anything derivable from git/tests belongs in neither — see the Artifact contract.
- Commit = strict per-phase consent (above). Push = separate explicit instruction only.
- Blocked or ambiguous mid-phase → ask immediately in chat, don't guess (`feedback_work_approach`).
- Narrate while working — what's being checked, what was found (`feedback_narrate_progress`).
- Every decision presented carries its number/evidence (`feedback_data_driven_decisions_monitor`).

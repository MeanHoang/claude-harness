---
name: ship
description: End-to-end dev pipeline for a task — analyze Notion spec, then plan in small surface-based phases with an HTML trade-off doc AND an up-front multi-agent flow-check that grounds the plan in code (all verification + open questions resolved here), implement phase-by-phase (code + code-review + report) asking only when a genuinely NEW problem surfaces, verify in a SEPARATE skippable test step (lint/tests/browser screenshots — skip when the user already self-tested), report via chat, commit each phase only after the user's explicit OK, keep a live progress doc, resume safely after session death. Use when the user says "/ship <notion-url>", "ship task này", "làm task này từ đầu đến cuối", or wants the full pipeline with him only at the gates.
---

# Ship — Notion task → reviewed, committed, phase-by-phase

The user drives only the GATES; everything between gates runs autonomously. He answers each gate **in chat** — report the gate, end the turn, wait for his reply. Never advance on silence; never guess his answer.

**Gate waiting protocol** (every gate): after posting a gate report in chat, end the turn and wait. On a long wait with no reply, update the `> **NOW:**` marker in `progress.md` and park — the resume protocol picks it up when he replies or re-invokes.


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
| Status Testing/UAT/fixing, bug reports in comments | **STABILIZE** | No plan.html, no phase split. Per bug: reproduce → `/debug`-style root cause (read logs/errors first, verify in code) → **ATTRIBUTION before any fix (user 2026-06-11: "tại sao lỗi, do commit nào… nhỡ commit master thì để họ tự sửa"): find the introducing commit (`git log -S`/blame) + author. Master/other-dev origin → DO NOT fix in this branch — report commit + author + date to him; the owner fixes it (or he explicitly pulls it into scope). Only fix what THIS branch introduced or what he explicitly orders** → surgical fix → lint. **BATCH the slow steps (user 2026-06-11: "check review hết rồi test 1 thể nhé chứ test lâu lắm" + "code xong chạy cái review code gửi cùng với thông báo cho tôi review"): do NOT browser/e2e-test each fix individually — (1) code the whole reported list first, (2) run BOTH `/review` (the project/house standard — never skip) and `/code-review` on the combined diff, fix must-fix findings, (3) ONE combined browser/e2e pass covering all items, (4) report the batch WITH the `/code-review` summary + test evidence → his OK → commit.** **Rapid-fire rule (user 2026-06-11): when he drops SEVERAL unrelated UAT items at once (different surfaces/files), do NOT investigate serially — fan out a multi-agent Workflow, one read-only root-cause agent per item (each returns cause + file:line evidence), then apply fixes one by one on the shared tree.** Scope guard: fix only what's reported — no refactors mid-UAT |

Ambiguous signals (e.g. status says Doing but branch has UAT-fix commits) → ask, don't guess.

## Setup (once per ship — SHIP mode; CONTINUE/STABILIZE reuse the existing branch & artifacts)

1. **Branch**: create `feature/<task-slug>` (or `bugfix/`) from fresh `origin/master` — never ship on master. Confirm the branch name with the user at Gate 2 (part of the plan).
2. **Artifacts dir**: `.claude/ship/<task-slug>/` holding `progress.md` + `plan.html`. Add `.claude/ship/` and `.playwright-cli/` to `.git/info/exclude` (LOCAL ignore — never edit the tracked `.gitignore`; zero MR pollution).
3. **Progress doc** (`progress.md`): task link, agreed requirements, phase checklist (⬜/🔄/👀/✅), and a `> **NOW:**` line marking exactly where the pipeline is. **Update continuously** — this doc is the user's explicitly-requested exception to `feedback_docs_out_of_commits`. It is local-ignored, so it can never leak into a commit; still, ALWAYS stage by explicit file path — **never `git add -A` / `git add .`** anywhere in this pipeline.

## Resume protocol (session died / new session re-invokes /ship)

1. `git status` + `git diff` FIRST — the working tree beats the progress doc; never discard changes, never `git checkout --` anything.
2. Read `.claude/ship/<task-slug>/progress.md` → find the `> **NOW:**` marker; committed phases are settled (git log is the source of truth), half-done work continues from the diff.

## Step 1 — Intake (Gate 1, loops until "move")

1. Run `/analyze-task <notion-url>` — claim verification, real numbers, ONE batched question round (chat).
2. **LOOP**: his feedback → re-verify → updated report → until he explicitly moves on ("ok", "move", "bước 2", "tiếp"). At THIS gate "tiếp" means proceed — it is not a commit gate.
3. Write the agreed requirements into `progress.md`.

## Step 2 — Plan (Gate 2, loops until "move")

**This is where ALL verification and ALL open questions get resolved.** The plan he approves must already be code-grounded and spell out the detailed fix per phase — so the flow-check runs HERE (not at code time), and every question is asked at this gate. By the time Step 3 starts there should be nothing left to discover; Step 3 just executes.

1. **Flow-check / code-grounding (multi-agent) — BEFORE writing `plan.html`.** Run a Workflow fan-out: parallel reader agents over every surface this task touches + their backend paths, each confirming/refuting the spec's assumptions with `file:line` evidence; plus one adversarial agent hunting hidden couplings against this named checklist: field-trigger loops, `pickFields.js` whitelist, surface-is-live (legacy scripttag is dead), backwards compat for existing shops, Firestore index existence. These are architectural facts about the *current* codebase — verifying them once here is what makes the plan trustworthy and feeds `plan.html` sections 2/3/5.
2. Split into **small phases by flow/surface** — each phase one coherent, separately-reviewable story (e.g. *Phase 1: widget v3 → Phase 2: widget v4 → Phase 3: project block*), each including its own backend touchpoints. Avoid one giant cross-surface diff. Feature-shaped work keeps the inner order B1 admin → B2 backend → B3 storefront (`feedback_feature_workflow_order`).
3. Generate **`plan.html`** in `.claude/ship/<task-slug>/` — **copy `templates/plan-doc.html` from this skill and fill the `{{...}}` placeholders. Do NOT hand-roll the HTML/CSS and do NOT edit its `<style>`.** (Why the template exists: 12 earlier plan.html files each looked different — only 5/12 had the pinned left TOC he asked for, 1/12 had dark mode. "thiết kế lại được không, làm thành 1 bộ khung đi".) The template already carries: `lang="vi"`, the `:root` palette (--accent #2f6df6, hero gradient 135deg #2f6df6→#5b8bff), dark-mode overrides, pinned left `nav.toc` with scroll-spy, and the six numbered `section.card`s — **1) Tổng quát** (+ 🎯 `.goal` box), **2) Phân tích hiện trạng** (spec-vs-code corrections from the flow-check, in `.callout.danger`), **3) Trade-offs** (per-decision table: option A/B, ưu/nhược, đề xuất + lý do), **4) Plan theo phase** (`.phase` cards, each with its **Pattern tham chiếu** line plus the DETAILED fix — which files, what change — work items + verify line + gate badge; add `.done` to the card as phases complete), **5) Risks** (rủi ro/ảnh hưởng/giảm thiểu), **6) Điểm cần chốt** (#/Vấn đề/Lựa chọn table). Reuse the existing classes (`.goal .callout .badge .phase .item-tag .muted`) — do not invent new ones.
4. Deliver: `open <plan.html>` locally and give a 3-5 line gist in chat (phases, key trade-offs, decision needed) + the local file path.
5. **LOOP**: feedback → revise plan + HTML → until explicit "move". Surface EVERY open question NOW — Gate 2 is the place to decide, so Step 3 won't need to stop and ask. A genuinely NEW problem discovered mid-code still bounces back here, but it should be the exception, not routine.
6. Record the final phase list in `progress.md`.

## Step 3 — Implement (per phase; Gate 3 repeats per phase)

The plan is already code-grounded from Step 2, so this step just **executes** — code, self-review, report. Keep it fast. **Do NOT re-run the heavy flow-check here, and do NOT stop to ask unless a genuinely NEW problem surfaces** (something Step 2's flow-check missed). A new contradiction → bounce back to Gate 2; otherwise keep moving.

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
5. **Code-review + SEND IT (user 2026-06-11: "code xong chạy cái review code gửi cùng với thông báo cho tôi review")** — after coding the phase/round (all items), run **BOTH** reviews on the diff — they catch different things and neither replaces the other: (a) **`/review`** — the project's own house standard (layer rules, handler-vs-service, `shopId` scoping, naming, Polaris, i18n keys, `{success,data,error}`); (b) **`/code-review`** (low/medium) — the generic plugin defect scan. **`/review` is the one that must never be skipped** (user 2026-08-08: *"bước review tôi thấy đang gọi code review chứ không phải review của project"*) — a generic scan does not know house layering or the translation workflow, so it passes code that `/review` would reject. Fix the clear, must-fix findings yourself, then **include the review result in the Gate 3 report** — a short summary of what `/code-review` found + how each finding was handled (fixed / left + why), so HE reviews the code with the review in hand. The review output travels WITH the gate report, never silently swallowed. (Final review uses a different tool — see Step 5.)
6. **Report (Gate 3)** — in chat: what the phase did, files changed, `eslint` result, **the `/review` + `/code-review` summary from step 5**. Functional/browser testing is the separate Step 4 — say in the report whether it's **pending** (you'll run it) or **skipped** (he'll self-test). Update `progress.md` to 👀. The report MUST end with the exact consent line: **"OK = em sẽ commit phase này."**
7. **LOOP**: feedback → fix → re-report, until explicit OK.

## Step 4 — Test & commit the phase (test is SKIPPABLE)

Step 3 stays fast by leaving the slow functional verification here. After the Gate 3 report, for this phase (or batched round):

1. **Functional test — SKIPPABLE (user 2026-06-17: implement was dragging because every phase blocked on a browser pass).** Run the `test-environment` self-test only when it adds value AND he hasn't already covered it:
   - **SKIP entirely if he says he self-tested, or replies "ok commit" / "skip test"** — don't re-run what he already did; go straight to consent.
   - Otherwise: targeted tests where they exist for touched packages; **UI phase → browser self-test** (pre-flight below): open the surface, snapshot, `console error`, **screenshot**; grep `firebase-debug.log` for new backend errors after the browser actions. Blank widget → check disk-full chunks + duplicate preact first (`project_local_widget_blank_causes`); blank admin embed → likely stale tunnel, restart `yarn dev`, not a code bug. Report results in chat.
   - **Batching (user 2026-06-11, "test 1 thể"): browser/e2e is the SLOW step — when a round has MULTIPLE small fixes, run ONE combined pass covering every item, never per-item.** Test fail → back to Step 3 fix.
2. **Commit consent is strict** (`feedback_git_workflow` — he has reverted an auto-chained commit before): only the word "commit"/"ok commit", or an affirmation given AFTER the consent line of THIS phase's report, authorizes the commit. A bare "ừ"/"tiếp"/anything ambiguous → ONE disambiguation question ("OK này là commit phase N luôn đúng không?"), never a silent commit. Each phase needs its own consent — consent never carries over. Late fixes to an already-committed phase get their own commit + their own OK.
3. **On OK → commit the phase** — stage by explicit file paths (code only; progress doc is local-ignored anyway), **commit message in English**, repo convention (`fix:`/`feat:` per `git log`). **NEVER push** — push only on his separate explicit instruction.
4. Mark phase ✅ in `progress.md`; next phase.

### Browser self-test pre-flight (UI phases — used by Step 4)

- **Consult the `test-environments` skill first** — store↔app map (local vs staging), storefront password ("1"), test-data setup routes (Firestore direct / admin UI / REST API), DB+log verification access, customer login recipe.
- CLI: `playwright-cli` is globally installed (`npm i -g @playwright/cli` done 2026-06-11); fallback `npx -y @playwright/cli`. Chromium already cached.
- URLs: app handle from `shopify.app.toml` (`handle`); **store domain from `.shopify/project.json`** keyed by `client_id` (`dev_store_url` — the toml does NOT have it despite CLAUDE.md saying so). NEVER use `application_url` from the toml — it goes stale. Admin embed: `https://admin.shopify.com/store/{store}/apps/{handle}/embed`.
- Probe services before testing: `bash .claude/skills/local-dev/scripts/check-local-dev.sh` (one PASS/FAIL per layer: emulator ports, watches, tunnel, stale baked URLs, disk).
- **Services down → AUTO-START them via the `local-dev` skill (user 2026-06-12), don't stop to ask**: `yarn emulators` + non-sudo `yarn dev` in background, wait for readiness, fix stale tunnel URLs, re-run the check script. Report the tunnel URLs (base + `/auth/login`) on success; standalone is the default mode. ONLY if the non-sudo `yarn dev` fails with permission errors does it need the user's terminal (`sudo yarn dev`) — then do NOT deadlock: run all non-browser checks, report the phase in chat with the caveat **"browser test pending — cần anh bật sudo yarn dev"**, and run the screenshots first thing after he's back. **Stack auto-started by Claude for the test → shut it down after that test pass completes** (local-dev Stopping); a stack HE started stays up until he says stop.
- **Admin/standalone UI = needs one-time manual session seed**: Shopify login ends at 2FA (authenticator TOTP) which Claude CANNOT supply. If a phase's UI lives in admin/standalone and the session isn't seeded, do NOT block — run non-browser checks, report the phase in chat with caveat "admin UI test pending — cần anh login 2FA 1 lần vào browser profile", and capture screenshots after he seeds it. Storefront UI (customer OTP) IS fully automatable — no seed needed.
- Artifacts land in `.playwright-cli/` (cwd) — covered by the `.git/info/exclude` entry from Setup.

## Step 5 — Finalize (local, before any ship-out)

1. Master-drift check: `git fetch origin master` + diff against base; if master moved significantly, surface it.
2. Full pass: tests across touched packages; **`/review-v2`** (design-doc cross-check, full branch scope); `/impact`.
3. `/translate` if labels were added; `/test-checklist` for the QA checklist.
4. `/mr` — generate the MR description (GitLab, no `glab`; he pushes & opens the MR himself).
5. `/update-handle` to sync the board.

## Step 6 — Ship-out GATE (ASK — never auto)

All local work is done; this is NOT the end. STOP and ask him in chat — present options with the facts:

**Q1 — Deploy to staging?** Which one? (He uses **7** and **22**.) Follow the rewritten `deploy-staging` skill — its core law: **NEVER assume the branch a staging runs; DETECT it from the deployed bundle** (`VITE_APP_DEPLOYED_BRANCH` baked in `https://{{FIREBASE_STAGING}}-<N>.firebaseapp.com/assets/app-*.js`), cross-check that branch's own `.gitlab-ci.yml` staging refs. ⚠️ 2026-06-11 incident: the literal `staging22` branch was 6 months stale while staging 22 actually ran `merge/hoang-t6-v2` — pushing the literal branch triggered a wrong deploy. Two models (per what detection finds):
- **Dedicated-branch** (e.g. staging 7): repoint staging-N CI `only` refs at THIS branch, push.
- **Integration branch running** (e.g. staging 22 → `merge/hoang-t6-v2`): push the feature branch FIRST (MR must contain the commits), then MERGE feature into the DETECTED running branch, empty commit titled `deploy` (CI `except`s "Merge branch" titles), push that branch.

**Q2 — Merge into a merge/integration branch?** (gather other branches already merged there so he sees what he's joining). Use `merge-branch` skill (feature → integration context: per-hunk union, find which incoming branch caused each conflict).

Default nothing — he picks: deploy-7, merge-into-the-running-staging22-branch, both, or neither (just leave the MR). **Before ANY deploy-triggering push: report the detected branch + exact plan and WAIT for his confirm** — even though he already chose "deploy" at this gate, the concrete push set still gets confirmed once.

## Step 7 — Execute + post-deploy auto-test (per his choice)

1. Execute per the `deploy-staging` skill (detect → confirmed plan → push). Extension changes are NOT covered by staging CI (functions+hosting only) — if the work touched `extensions/`, run `deploy-extensions` against that staging's app too.
2. **Arm a deploy-success watcher** (the "cron" he asked for): poll the GitLab pipeline for THIS push until it finishes (needs a GitLab PAT with `read_api` — **if absent, ask him in chat to provide one once**; store in `.env.agent` as `GITLAB_TOKEN`). Repo: `{{GIT_REMOTE_HOST}}`. **No-token fallback**: poll the deployed bundle itself — `VITE_DEPLOY_TIME` + `VITE_APP_DEPLOYED_BRANCH` in `https://{{FIREBASE_STAGING}}-<N>.firebaseapp.com/assets/app-*.js` flip when the deploy lands (check every ~4 min, CI takes ~15-30 min).
3. **On deploy SUCCESS** → **re-run the test skill against that staging** (`test-environments` store map: staging N = `{{STAGING_HANDLE}}<N>`; storefront tests automated, config checks via API/Firestore with that env's SA). Per the test-environments RULE: the staging test MUST pair browser actions with that env's backend logs (GCP Cloud Logging) over the test window — UI-only is not a test. Report results in chat.
4. **On deploy FAIL** → report in chat the failing job + log tail; do not re-test.
5. **End-of-round multi-agent review (user order 2026-06-12: "vừa deploy rồi cũng chạy agent để nó review"):** right after the post-deploy test passes, fan out the FULL branch review — 4 parallel agents: `security-auditor` + `performance-reviewer` + `shopify-app-tester` (impact) + `code-reviewer`, scope `git diff origin/master...HEAD` minus generated/translation noise. Then (a) **re-verify every CRITICAL finding directly in code yourself** before reporting — agents disagree and overstate (2026-06-12: HMAC finding needed nuance only code reading settled); (b) send ONE synthesized report in chat — security first, then perf, then impact checklist — each finding with file:line, framed as findings + recommendation, HIS decision what to fix; (c) findings he accepts become a normal fix round (Gate 3 consent applies).
6. Final report in chat: done summary + MR + staging URL + post-deploy test results + review verdicts + anything deferred.

## Rules

- Gates never advance on silence; park (update the `> **NOW:**` marker, end the turn) and resume later when he replies.
- Commit = strict per-phase consent (above). Push = separate explicit instruction only.
- Blocked or ambiguous mid-phase → ask immediately in chat, don't guess (`feedback_work_approach`).
- Narrate while working — what's being checked, what was found (`feedback_narrate_progress`).
- Every decision presented carries its number/evidence (`feedback_data_driven_decisions_monitor`).

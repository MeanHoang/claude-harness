---
name: analyze-task
description: Step 1 of the dev pipeline — turn a task into a readable analysis file (analysis.md) covering the business domain first and the code second, then grill the user ONE question at a time about the business until the two of you write the GOAL together. Produces understanding, not a plan. Use when the user says "phân tích task", "analyze task", "đọc task notion", "verify task này", pastes a Notion task URL to start work, or at the start of any feature/bugfix from a spec. Run BEFORE /plan, /plan-v2 or ship Step 2.
---

# Analyze Task — Step 1: đạt hiểu biết chung, kết thúc bằng một GOAL

The deliverable of this step is **a shared understanding plus a goal**, written down as
`analysis.md`. It is **not** a plan, not phases, not an estimate.

> User, 2026-08-17: *"tôi không cần 1 cái plan đọc không hiểu gì — tôi muốn step 1 đã trả ra 1 file
> phân tích cho tôi, rồi tôi cùng verify, cùng đưa ra 1 cái goal."*

You are drawing **the map of where we stand**, not the route to anywhere. He reads it, corrects it,
and the goal falls out of that conversation.

## The two altitudes — the rule that makes questions answerable

The failure this skill exists to prevent: asking him to *decide* before anything has *taught* him,
so he is picking between options in a domain he has not been oriented in.

| | **Step 1 — this skill** | Step 2 — plan |
|---|---|---|
| About | The business, the domain, the goal | Technical trade-offs |
| Example | *"Khách VN mua ở shop bán USD — ví của khách nên là VND hay USD?"* | *"Sửa ở `orderEarnService.js:1420` hay ở picker widget?"* |
| Test | **He can answer without reading a line of code** | He needs the analysis + plan first |
| Rhythm | **One question at a time** | Can be batched |
| Ends with | GOAL, written by both | Settled trade-offs |

**The test for every question: could he answer it without reading any code?**
No → it is a Step-2 question. Hold it. Do not ask it here.

## Inputs

- A Notion task URL or page ID (fetch via `notion-tasks`), OR a pasted spec (skip the fetch).
- `--note "<free text>"` — optional steer, e.g. `--note "chỉ phần A thôi, bỏ qua phần B"`.

**How a `--note` is treated — same contract in every skill that takes one:**

- **It steers attention, never authority.** It can tell you where to look first, what he already suspects, what to leave alone. It does NOT let Step 1 skip its gate: the §5 ledger still has to close, the GOAL is still written with him, and questions with a correct answer are still forbidden — a note is not a substitute for going and getting the fact.
- **Persist it verbatim** into `analysis.md` (under the title, as `Note:`) and into the `<!-- state -->` block of `progress.md`. A note kept only in the invocation dies with the session, and the next round silently drops what he asked for.
- **Answer it explicitly** when you post the map: one line saying what the note pointed at and what you found there.
- **A note can be wrong, and saying so is the job.** If he points at an area and the evidence says the problem is elsewhere, report that with `file:line` rather than bending the analysis to fit the hint. Being pointed somewhere makes it very easy to manufacture a finding there.

## Workflow

### 1 — Fetch the spec AND the real-world inputs behind it

```bash
python3 .claude/skills/notion-tasks/scripts/notion-tasks.py get <page_id_or_url>
```

Read the body **and the comments** — comments often override the body.

**Then go get what the spec was written FROM.** A Notion task is someone's summary of a real event:
a merchant complaining, a support chat, a ticket, a meeting. §2 cannot be written from the summary
— that is how invented personas get in. Pull the source:

| Source | How |
|---|---|
| Support chat / the user's own words | your support-log skill, or ask him for the link |
| Ticket | your ticket-system skill |
| Related tasks + what was already decided | `notion-tasks` — the linked/parent task and its comments |
| Production behaviour | GCP logs, Firestore, BigQuery |

**If a source you need does not exist, that is your first grill question, asked early** — not a
footnote at the bottom. *"Cái này ai kêu, có link chat support không?"* costs him five seconds
and decides whether §2 is real or made up. Asking it at the end, after the analysis is written
around a guess, wastes the whole round.

### 2 — Split GOAL vs CLAIMS

- **GOAL** — what the merchant should be able to do. Trust this.
- **CLAIMS** — anything asserting how the system works or should be built: field names, collections,
  file paths, "X already supports Y", API shapes, surface names. Trust none of it yet.

Notion specs are BA-written and partly AI-generated. **A spec that cites `file:line` is MORE
dangerous, not less** — it reads as verified when it is not, and paths go stale after refactors.

### 3 — Verify claims in code

| Verify | How |
|---|---|
| Field/collection exists? | grep `repositories/`, `functions.d.ts`, `firestore-indexes/` |
| "X already does Y" | read the actual service/handler |
| Which surface is LIVE? | current entry points vs the legacy one someone may still be reading about |
| Does BE already compute it? | check existing services before assuming new computation is needed |
| FE can see the field? | whatever whitelist gates what reaches the client — unlisted fields are silently undefined |
| Existing tenants affected? | the product may have thousands live — grandfather / gate / migrate |

Build: **claim → verdict (✅ / ❌ / ⚠️ không tìm thấy) → evidence `file:line`**.

### 4 — Kill the branches with numbers, BEFORE any question

> **Every open point is a FACT or a CHOICE. Ask: "does this have a correct answer?"**
> **Has one → go get it; you are forbidden to ask him.**
> **Has none → it is a real question, keep it for step 6.**

"How many shops have X enabled" is a Firestore/BigQuery query, not a question for him. Run it.
A branch that a number proves irrelevant gets **one line, not a section**.

This ordering is the difference between a short analysis and a long one. Resolve the fact that
collapses the tree *first* — never write a full analysis of both sides of a fork and park the
deciding question at the bottom.

### 5 — Write `analysis.md`

In the ship dir (`.claude/ship/<slug>/analysis.md`) — **markdown, not HTML**, because this file gets
edited repeatedly while you and he verify it together.

Five sections, **in this order**. The order is the point: business first, code second.

```
§1  Miền là gì
    The domain concept itself — ZERO of our app in this section. What it is, who turns it
    on, what problem it solves, what its vocabulary means. Written for someone who has never
    touched it. Source: platform docs (Shopify → shopify-dev MCP), not memory.

§2  Ai đau, đau thế nào, bao nhiêu
    The merchant, not the code. Who hits this, what they SEE on screen, what it costs them,
    and the numbers wherever a number is obtainable.

§3  <App> đang làm gì hôm nay
    Current behaviour with `file:line`, including what it deliberately does NOT do.
    The claim table from step 3 lives here.

§4  Khoảng trống
    The gap between §2 and §3. Describe the problem ONLY — no solution, no phases, no
    "we should build X". Writing a solution here means you have slipped into Step 2.

§5  Sổ điểm mở — the decision tree, made visible
    One row per open point. This is the thing the grill walks, and the thing that decides
    when the gate is allowed to close. He reads it, so he can see how many questions are
    coming and about what — and can strike rows out himself.

    **This is the ONE ledger for the whole planning phase.** Step 1 writes the business rows;
    ship 2b later adds the technical ones to this same table. That is why it lives in a
    file: both gates are blocked on it, and a ledger kept in chat dies with the session.

    | # | Điểm mở | Loại | Chặn cái nào | Trạng thái |
    |---|---------|------|--------------|------------|
    | 1 | …       | FACT | 3, 4         | đóng bằng số: <số + nguồn> |
    | 2 | …       | B    | —            | đang hỏi |
    | 3 | …       | C    | —            | chưa đụng |
    | 4 | …       | KT   | —            | để 2b |

    **Loại:** `FACT` (có đáp án đúng → đi lấy) · `A` khẩu vị · `B` merchant nhìn thấy đổi ·
    `C` scope · `KT` kỹ thuật — belongs to Step 2, park it, do NOT ask it here.

    Rules for the ledger:
    - **FACT rows must end "đóng bằng …" with the evidence.** A FACT row you never closed is
      not a question for him — it is work you skipped.
    - **`KT` rows do not block Step 1** — they are the handover to 2b. But they must be
      WRITTEN DOWN when you notice them, or they arrive at 2b as a surprise.
    - **"Chặn cái nào" is what orders the grill.** Ask blockers first; never ask a question
      whose answer the next fact would have made irrelevant.
    - **Rows get ADDED as you go.** An answer that opens two new questions means two new rows.
      A ledger that only shrinks is a ledger you stopped thinking about.

§6  🎯 GOAL — LEAVE IT EMPTY
    A heading with nothing under it. Written together at step 7. Do not pre-fill it.
    When it does get written it has TWO halves, and the second is not optional:

      **Làm gì** — what he should be able to do when this is done.
      **KHÔNG làm** — what is deliberately out of scope, each with one line of why.

    The "không làm" half is what turns a goal into a **definition of done**: without it the
    work never ends, because there is always more that could be added. It is also the only
    place a NEGATIVE decision survives — "we considered X and chose not to" is invisible in
    code and gets re-proposed by the next session otherwise.
```

**It stays short structurally**, because everything about *how to build it* is banned from the file.
If it is growing long, check whether §4 has started proposing solutions.

### 6 — Grill him — one question at a time

A question reaches him only if step 4 could not answer it — meaning it has no correct answer, which
in practice is exactly three kinds:

| Kind | What it is |
|---|---|
| **A. Khẩu vị / sản phẩm** | no right answer, only his taste |
| **B. Merchant nhìn thấy đổi** | existing shops see something change |
| **C. Scope — dừng ở đâu** | what is in v1 and what is not |

Each question carries **the fact that makes it a question** and **your recommended answer**:

> **Fact:** `<what is true, with file:line or a number>`
> **Hệ quả:** `<why that forces a choice>`
> **Chọn:** (a) … (b) … — đề xuất (a) vì …

Without the Fact line he is being asked to decide blind — and if you cannot write the Fact line,
you are not ready to ask; go back to step 3/4.

**Say whose call it is when it is not his.** Some answers belong to the PO, the BA, or the merchant
— a spec that says *"chốt bởi PO"* means that decision has an owner. Do not make him answer on
someone else's behalf; name the owner, say what you would ask them, and let him decide whether to
relay it or overrule it. Him guessing for an absent decision-maker is the expensive kind of wrong:
it looks settled and nobody knows it was a guess.

**Post ONE question, end the turn, wait.** Do not batch: the answer to one question changes which
question comes next. The recommendation is what makes this cheap — most answers are "theo đề xuất",
and he spends real thought only where it matters.

**Walk the §5 ledger, blockers first.** The ledger is the decision tree; the grill is you walking
down it. After every answer: update the row, add any new rows the answer opened, and pick the next
blocker. Tell him where you are (*"còn 3 điểm mở, câu này chặn 2 câu kia"*) so he can see the shape
of the conversation instead of being surprised one question at a time.

**You may not decide that he has understood enough — and this is the rule an AI breaks by
default**, because producing the artifact feels like success while staying in the questioning phase
does not. So it is a gate, not an intention:

> **Step 1 may not end while any NON-`KT` row in §5 is `chưa đụng` or `đang hỏi`.**
> (`KT` rows are Step 2's — park them, do not ask them, do not let them block you either.)
> **Before you may even ASK whether the map is right, post the ledger and this sweep:**
> *"Chưa đụng tới: … · Không verify được: … · Giả định còn lại: …"*

If all three lines are empty, look again — on a real task they are never all empty, and an empty
sweep means you stopped looking rather than finished. Sweep against the branches that get forgotten
here specifically: tenants already live · the other surfaces (your surface inventory) · the other
variants of the same feature · data already written before this change · who else reads the field you are about to
change.

**Do not shrink the ledger to look efficient.** Its length is the honest size of what is unsettled.
A grilling session that runs long is the skill working, not failing.

### 7 — Write the GOAL together, then hand off

Only after he says the map is right: fill §6 **with him**, not for him. The goal is what falls out
of two people having read the same map — not a proposal you hand him to approve.

Then copy the agreed goal into `decisions.md` (`## Goal đã chốt (<date>)`) and stop.
Step 2 (`/plan-v2`, or ship Step 2) is a different session and a different altitude.

## Rules

- **No coding, no file edits to product code.** This skill writes `analysis.md` / `decisions.md` only.
- **Every code claim carries `file:line`.** Could not verify → write *"chưa verify — giả định"*.
  There is no middle ground.
- **Business claims need a source too.** §1 and §2 are where an AI invents things ("merchants want
  X"). Every line traces to: a real number (Firestore/BigQuery) · a real ticket / support chat ·
  platform docs · the spec. No source → write *"giả định của tôi, chưa verify"* and make it your
  first grill question.
- **Goal confusion outranks everything.** If the GOAL itself is unclear or contradicts how the
  system works, say so plainly (*"chỗ này em chưa hiểu: …"*) and resolve that before anything else.
  Never pretend to understand and guess a direction.
- **Never present a decision without its number** when a number is obtainable.
- If the spec is genuinely consistent and has no open choices, say so — do not invent questions.
  But note this is rare, and the bar is that step 4 *closed* them with evidence, not that you did
  not look.

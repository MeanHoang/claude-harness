---
name: task-catchup
description: Surface NEW activity you may have missed while heads-down coding — scans every task you're working on (all .claude/ship/*/progress.md) and reports Notion comments + Slack messages from the last 24h, without pasting any link. Use when the user says "check task có gì mới", "có miss thông tin gì không", "catch up task", "check notion slack", "task nào có update", "/task-catchup", or at the start of a session to catch up on discussion that landed since yesterday.
---

# task-catchup — Catch up on task activity you missed

Reports **new Notion comments + Slack messages in a recent time window** (default
24h) across **all active tasks** — so information that landed while you were
heads-down coding doesn't slip past you.

No link to paste: tasks are discovered from every `.claude/ship/*/progress.md`
(each ship doc carries its Notion URL + title). A fixed time window means there
is no "last seen" state to manage — it always answers "what happened in the last
N hours across everything I'm working on".

## When to use

- User invokes `/task-catchup`.
- "Check task có gì mới không", "có bị miss thông tin gì không", "task nào có update".
- Session start — catch up on comments/threads from yesterday before continuing.

For a single specific task, generic Notion CRUD, or a daily standup plan, use
`notion-tasks` / `my-tasks` instead.

## Setup

Required in `.env.agent`:
```
NOTION_API_KEY=ntn_...
```
The Notion integration must have **Read comments** capability, else comment
scanning is skipped with a warning.

Optional (for the Slack half):
```
SLACK_USER_TOKEN=xoxp-...   # user token with search:read scope
```
The existing `SLACK_TOKEN` is a **bot** token — Slack's `search.messages` rejects
bot tokens (`not_allowed_token_type`), so a separate user token is required to
search the workspace. Without it, only the Notion half runs.

## Script

```bash
python3 .claude/skills/task-catchup/scripts/task-catchup.py [--hours N] [--ship SLUG] [--json]
```

Flags:
- `--hours N` — time window in hours (default `24`).
- `--ship SLUG` — limit to one ship dir instead of scanning all.
- `--json` — machine-readable output instead of the formatted report.

## Output

One block per task **that has activity in the window** (quiet tasks are collapsed
to a one-line "no new activity" list at the bottom):

```
🎟️ Widget V4 — Auto-ingest discount        (ship: widget-v4-auto-ingest-discount)
   💬 Notion comments (2)
      • Sơn Bùi Khánh · 3h ago — "chốt bỏ webhook, đẩy qua Flow action nhé"
      • Thomas Nguyen · 8h ago — "cost read-per-update lớn, xem lại"
   💬 Slack (1)   query: "widget v4 auto ingest"  #{{DEV_CHANNEL}}
      • sonbk · 5h ago — "test declared-push xong chưa?"  <permalink>
```

Slack keyword is derived from the task title (distinctive tokens, stopwords
removed); the query used is printed so you can see exactly what was searched. To
pin a better keyword for a task, add a line to that ship's `progress.md`:
```
<!-- slack-keyword: declared-push discount -->
```

## Notes

- Time window is a hard filter on `created_time` (Notion) and message `ts` (Slack);
  items older than the window never appear.
- Slack search terms are ANDed by Slack — fewer, more distinctive keywords match
  better than a long title. Prefer the `slack-keyword` hint for noisy tasks.
- Notion comment scan is page-level (the discussion thread on the task page).

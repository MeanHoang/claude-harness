---
name: ship-board
description: Print the table of every running work item — whatever is waiting on the user sorted to the top with a 🚦, plus branch, gate, which role holds the work, round count, session age, and the NOW line. Use when the user says "/ship-board", "bảng task", "đang có gì chạy", "task nào chờ tôi", "xem tiến độ các feature", "đầu buổi xem gì", or opens a session wanting the overall picture across several work items.
---

# The running-work board

```bash
.claude/scripts/ship-board.sh
```

Run it, then **read the result back to the user** — do not just paste the raw table. Cover it in
this order:

1. **What is waiting on them** (rows with 🚦) — which item, which gate (plan / code / decision),
   and if `progress.md` makes it obvious, what it is waiting *for*.
2. **What is running** (rows with `·`) — which role holds the work, which round it is on. A round
   count reaching 3 means the user is about to be pulled in.
3. **What is done or dormant** — one sentence for all of them, do not enumerate.

Older work items with no `state` block show `—` in most columns; that is normal, only their NOW
line is available. Do not report it as a fault.

## The SESSION column

Shows the age and transcript size of the child session, flagged **⚠** past 12 hours or 5 MB.

That flag matters more than it looks: **a kickoff is read only once, at startup**. A session
running for 40 hours is still following whatever the kickoff said back then — rule changes made
since are invisible to it. Measured 07/08: four sessions at 40–45 hours had made **zero**
implementer dispatches despite the rule existing and the tool being available.

Seeing ⚠ means tell the user that item needs its session restarted, not just that it is old.

## Workspace colours

After printing, the script **colours the cmux workspaces** by how much attention they need — so
the sidebar alone answers "what needs me":

| Colour | Meaning |
|---|---|
| **Crimson** | Waiting on the user — a gate is open, or a bug has a verdict |
| **Amber** | Coder ↔ reviewer has hit 3 rounds, about to hit the stop rule |
| **Blue** | Running normally |
| **Charcoal** | Done or dormant |

Only workspaces whose **name matches a slug** are touched; the user's own workspaces are left
alone. Items with no `state` block are skipped.

**Read-only.** Never edit `progress.md`, never jump into a work item yourself — not even when one
is obviously stuck. Report, then stop; the user picks what to enter. (Colouring is display, not
state.)

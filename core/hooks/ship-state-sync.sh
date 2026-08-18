#!/usr/bin/env bash
# Stop hook: record the session's TECHNICAL TRAIL in the `<!-- state -->` block of progress.md.
#
# Why: shutting the machine down loses the session, and cmux restores the layout but not the
# conversation. Resuming next morning otherwise means hunting for a filename under
# ~/.claude/projects/. Writing the session id into the file that already tracks this piece of
# work removes the hunt. It doubles as a safety net for compaction: after the context is
# summarised, the file is still there.
#
# It DELIBERATELY writes no work log into progress.md. That file is the TO-DO LIST a human and
# an agent read to know what comes next; pouring log lines into it inflates exactly the file
# that was just pruned. Reasons and decisions belong in decisions.md, and writing those is the
# model's job, not a hook's. This hook touches only metadata inside the comment block.
#
# Always exits 0. It can never block.

set -uo pipefail
INPUT=$(cat 2>/dev/null || true)

python3 - "$INPUT" <<'PY' 2>/dev/null || true
import json, os, re, subprocess, sys, datetime

try:
    hook = json.loads(sys.argv[1] or "{}")
except Exception:
    hook = {}

cwd = hook.get("cwd") or os.getcwd()
sid = hook.get("session_id") or ""


def git(*a):
    try:
        return subprocess.run(("git", "-C", cwd) + a, capture_output=True,
                              text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


root = git("rev-parse", "--show-toplevel")
branch = git("rev-parse", "--abbrev-ref", "HEAD")
head = git("rev-parse", "--short", "HEAD")
if not root or not branch:
    sys.exit(0)

ship = os.path.join(root, ".claude", "ship")
if not os.path.isdir(ship):
    sys.exit(0)

# Which piece of work is this? Match on the BRANCH recorded in the state block. The directory
# name is not reliable: the main checkout is not named after a slug.
target = None
for slug in sorted(os.listdir(ship)):
    p = os.path.join(ship, slug, "progress.md")
    if not os.path.isfile(p):
        continue
    head_txt = open(p, encoding="utf-8", errors="replace").read(1200)
    m = re.search(r"^\s*branch:\s*(.+?)\s*$", head_txt, re.M)
    if m and m.group(1).strip() == branch:
        target = p
        break
if not target:
    sys.exit(0)

txt = open(target, encoding="utf-8", errors="replace").read()
m = re.search(r"<!-- state\n(.*?)\n-->", txt, re.S)
if not m:
    sys.exit(0)

block = m.group(1)
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
fields = {"session": sid, "head": head, "updated": now}
if not sid:
    fields.pop("session")

for k, v in fields.items():
    if re.search(rf"^\s*{k}:", block, re.M):
        block = re.sub(rf"^\s*{k}:.*$", f"{k}: {v}", block, count=1, flags=re.M)
    else:
        block = block.rstrip() + f"\n{k}: {v}"

new = txt[:m.start()] + "<!-- state\n" + block + "\n-->" + txt[m.end():]
if new != txt:
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(new)
PY

exit 0

#!/usr/bin/env bash
# SessionStart hook (startup | resume | compact): point the session back at the right record.
#
# Why: compaction summarises the context in the model's own words, and every summary drops
# detail. An unattended session can compact at 3am and carry on from an abridgement it wrote
# itself. The kickoff file is read ONCE at launch, so it cannot rescue that.
#
# This hook does not try to re-inject the content. It injects the ADDRESS of the truth
# (progress.md + decisions.md) and the NOW line, so the first move after a compact is to read
# the file rather than to guess.
#
# Always exits 0.

set -uo pipefail
INPUT=$(cat 2>/dev/null || true)

python3 - "$INPUT" <<'PY' 2>/dev/null || true
import json, os, re, subprocess, sys

try:
    hook = json.loads(sys.argv[1] or "{}")
except Exception:
    hook = {}

cwd = hook.get("cwd") or os.getcwd()
source = hook.get("source") or ""


def git(*a):
    try:
        return subprocess.run(("git", "-C", cwd) + a, capture_output=True,
                              text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


root = git("rev-parse", "--show-toplevel")
branch = git("rev-parse", "--abbrev-ref", "HEAD")
ship = os.path.join(root, ".claude", "ship") if root else ""
if not branch or not os.path.isdir(ship):
    sys.exit(0)

target = slug = None
for s in sorted(os.listdir(ship)):
    p = os.path.join(ship, s, "progress.md")
    if not os.path.isfile(p):
        continue
    m = re.search(r"^\s*branch:\s*(.+?)\s*$",
                  open(p, encoding="utf-8", errors="replace").read(1200), re.M)
    if m and m.group(1).strip() == branch:
        target, slug = p, s
        break
if not target:
    sys.exit(0)

txt = open(target, encoding="utf-8", errors="replace").read()
m = re.search(r"^>\s*\*\*NOW:?\*\*:?\s*(.+)$", txt, re.M)
now = m.group(1).strip() if m else "(no NOW line yet)"

rel = os.path.relpath(target, root)
dec = os.path.join(os.path.dirname(rel), "decisions.md")
lines = [
    f"This branch's work item: **{slug}**",
    f"- Work item + state: `{rel}`",
]
if os.path.isfile(os.path.join(root, dec)):
    lines.append(f"- Decisions taken / debt accepted: `{dec}`")
lines.append(f"- NOW: {now}")

if source == "compact":
    lines.append("The context was just compacted. READ both files above before continuing; "
                 "do not rely on the summary.")
elif source == "resume":
    lines.append("This session was just resumed. Check both files above against the work in "
                 "progress before continuing.")

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "\n".join(lines),
}}))
PY

exit 0

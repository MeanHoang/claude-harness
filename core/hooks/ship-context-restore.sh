#!/usr/bin/env bash
# SessionStart hook (startup | resume | compact) — trỏ session về đúng hồ sơ đầu việc.
#
# Vì sao cần: compact tóm tắt context bằng chính lời của model, và tóm tắt thì bao giờ cũng
# mất chi tiết. Session chạy không người trông có thể compact lúc nửa đêm rồi đi tiếp với
# một bản rút gọn do nó tự viết. Kickoff thì chỉ được đọc MỘT LẦN lúc khởi động nên không
# cứu được.
#
# Hook này không cố nhồi lại nội dung — nó chỉ chèn ĐỊA CHỈ của sự thật (progress.md +
# decisions.md) và dòng NOW, để việc đầu tiên sau compact là đọc file chứ không phải đoán.
#
# Luôn exit 0.

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
now = m.group(1).strip() if m else "(chưa có dòng NOW)"

rel = os.path.relpath(target, root)
dec = os.path.join(os.path.dirname(rel), "decisions.md")
lines = [
    f"Đầu việc của branch này: **{slug}**",
    f"- Đầu việc + trạng thái: `{rel}`",
]
if os.path.isfile(os.path.join(root, dec)):
    lines.append(f"- Quyết định đã chốt / nợ kỹ thuật: `{dec}`")
lines.append(f"- NOW: {now}")

if source == "compact":
    lines.append("Context vừa bị compact — ĐỌC hai file trên trước khi làm tiếp, "
                 "đừng dựa vào bản tóm tắt.")
elif source == "resume":
    lines.append("Session vừa được resume — đối chiếu hai file trên với việc đang dở "
                 "trước khi làm tiếp.")

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "\n".join(lines),
}}))
PY

exit 0

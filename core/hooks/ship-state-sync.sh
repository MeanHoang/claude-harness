#!/usr/bin/env bash
# Stop hook — ghi lại DẤU VẾT KỸ THUẬT của session vào khối `<!-- state -->` của progress.md.
#
# Vì sao cần: tắt máy là mất tiến trình, và cmux chỉ khôi phục giao diện chứ không khôi phục
# session. Sáng hôm sau muốn `claude --resume` thì phải đi mò tên file trong
# ~/.claude/projects/. Ghi sẵn session id vào đúng chỗ đang theo dõi đầu việc là hết mò.
# Cũng là lưới an toàn cho compact: sau khi context bị tóm tắt, file vẫn còn.
#
# CỐ Ý KHÔNG ghi nhật ký công việc vào progress.md. File đó là DANH SÁCH ĐẦU VIỆC để
# người và agent đọc mà biết phải làm gì tiếp — nhét log vào là làm phình đúng thứ vừa
# được dọn. Lý do / quyết định thuộc về decisions.md, và đó là việc của model, không
# phải của hook. Hook chỉ đụng metadata trong comment.
#
# Luôn exit 0 — không bao giờ chặn.

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

# Đầu việc nào? Khớp theo BRANCH trong khối state — tên thư mục không đáng tin
# (checkout chính không mang tên slug).
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

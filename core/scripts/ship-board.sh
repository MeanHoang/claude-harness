#!/usr/bin/env bash
# Bảng mọi feature đang chạy — feature nào ĐANG CHỜ user xếp lên đầu.
#
# Vì sao cần: mỗi task một progress.md, muốn biết cái nào chờ mình phải mở từng file.
# Khi chạy nhiều feature song song thì nút thắt là user, nên thứ cần thấy trước tiên là
# "cái nào đang chờ tôi", không phải "cái nào đang chạy".
#
# Đọc khối `<!-- state ... -->` ở đầu progress.md (feature-team/templates/progress-header.md).
# Task cũ chưa có khối đó vẫn hiện, cột state để "—".

set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "không ở trong git repo" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import glob, os, re, subprocess, sys

root = sys.argv[1]
rows = []

for p in sorted(glob.glob(os.path.join(root, ".claude/ship/*/progress.md"))):
    slug = os.path.basename(os.path.dirname(p))
    txt = open(p, encoding="utf-8", errors="replace").read()
    head = txt[:1200]

    def field(name, default="—"):
        m = re.search(rf"^\s*{name}:\s*(.+?)\s*$", head, re.M)
        return m.group(1) if m else default

    has_state = "<!-- state" in head
    branch = field("branch")
    if branch == "—":                       # task cũ: lấy từ dòng "- Branch: `...`"
        m = re.search(r"Branch:\s*`([^`]+)`", txt)
        branch = m.group(1) if m else "—"

    gate = field("gate", "none") if has_state else "—"
    awaiting = field("awaiting") if has_state else "—"
    step = field("step") if has_state else "—"
    phase = field("phase") if has_state else "—"
    rnd = field("round", "0") if has_state else "—"
    kind = field("kind", "feature") if has_state else "—"
    verdict = field("verdict", "-") if has_state else "-"

    # NOW marker: dòng người đọc, cắt ngắn
    m = re.search(r"^>\s*\*\*NOW:?\*\*:?\s*(.+)$", txt, re.M)
    now = (m.group(1).strip() if m else "")[:70]

    done = txt.count("✅")
    todo = txt.count("⬜")

    # Tuổi + kích thước session con. Session sống quá lâu = context phình = chậm và đắt,
    # và nó vẫn chạy theo kickoff LÚC KHỞI ĐỘNG nên không thấy luật thêm sau đó.
    age_h, sess_mb = None, 0
    # Claude đặt tên thư mục project bằng đường dẫn tuyệt đối, thay "/" bằng "-".
    # Suy từ tên repo hiện tại nên script chạy được ở bất kỳ project nào.
    _repo = os.path.basename(os.path.abspath("."))
    _wt = os.path.expanduser("~/cmux/worktrees/%s/%s" % (_repo, slug))
    pdir = os.path.expanduser("~/.claude/projects/" + _wt.replace("/", "-"))
    if os.path.isdir(pdir):
        import glob as _g
        for jf in _g.glob(pdir + "/*.jsonl"):
            mb = os.path.getsize(jf) / 1024 / 1024
            if mb < 0.5:            # bỏ qua session con lặt vặt của skill
                continue
            sess_mb = max(sess_mb, mb)
            try:
                import json as _j, datetime as _d
                with open(jf, errors="replace") as fh:
                    for i, line in enumerate(fh):
                        if i > 400:            # timestamp không nằm ngay dòng đầu
                            break
                        if '"timestamp"' not in line:
                            continue
                        t = _j.loads(line).get("timestamp")
                        if not t:
                            continue
                        st = _d.datetime.fromisoformat(t.replace("Z", "+00:00"))
                        h = (_d.datetime.now(st.tzinfo) - st).total_seconds() / 3600
                        age_h = h if age_h is None else max(age_h, h)
                        break
            except Exception:
                pass

    rows.append(dict(slug=slug, branch=branch, gate=gate, awaiting=awaiting, kind=kind,
                     verdict=verdict, step=step, phase=phase, rnd=rnd, now=now,
                     done=done, todo=todo, age_h=age_h, sess_mb=sess_mb))

# ưu tiên: đang chờ user > đang chạy > xong
def rank(r):
    if r["gate"] not in ("none", "—"): return 0
    if r["awaiting"] == "user": return 0          # bug đã có verdict, chờ user phán
    if r["awaiting"] not in ("none", "—"): return 1
    return 2

rows.sort(key=lambda r: (rank(r), r["slug"]))

waiting = [r for r in rows if rank(r) == 0]
print()
if waiting:
    def why(r):
        if r["gate"] not in ("none", "—"): return r["gate"]
        if r["verdict"] not in ("-", "—"): return r["verdict"]
        return "chờ anh"
    print(f"⚠️  {len(waiting)} đầu việc ĐANG CHỜ ANH: " + ", ".join(f"{r['slug']} ({why(r)})" for r in waiting))
else:
    print("✅ Không có đầu việc nào đang chờ anh.")
print()

w = max([len(r["slug"]) for r in rows] + [7])
print(f"{'':2}{'ĐẦU VIỆC'.ljust(w)}  {'LOẠI':8} {'GATE':9} {'CHỜ':9} {'KẾT LUẬN':13} {'BƯỚC':6} {'SESSION':11} NOW")
print("─" * (w + 62))
for r in rows:
    mark = "🚦" if rank(r) == 0 else ("· " if rank(r) == 1 else "  ")
    step = r["step"] if r["phase"] in ("-", "—") else f"{r['step']}·{r['phase']}"
    if r["age_h"] is None:
        sess = "—"
    else:
        flag = "⚠" if (r["age_h"] > 12 or r["sess_mb"] > 5) else " "
        sess = f"{flag}{r['age_h']:.0f}h/{r['sess_mb']:.0f}MB"
    print(f"{mark}{r['slug'].ljust(w)}  {r['kind']:8} {r['gate']:9} {r['awaiting']:9} "
          f"{r['verdict']:13} {step:6} {sess:11} {r['now'][:52]}")

# xuất cho bước tô màu workspace (ghi ra file tạm, bash đọc lại)
with open("/tmp/ship-board-colors.txt", "w", encoding="utf-8") as fh:
    for r in rows:
        if r["gate"] == "—":            # task cũ chưa có state → không tô
            continue
        fh.write(f"{r['slug']}\t{rank(r)}\t{r['rnd']}\n")

no_state = [r for r in rows if r["gate"] == "—"]
if no_state:
    print(f"\n({len(no_state)}/{len(rows)} task chưa có khối `state` — chỉ hiện NOW. Thêm header từ "
          f"feature-team/templates/progress-header.md để lên bảng đầy đủ.)")
PY

echo
echo "── worktree đang mở ──"
git -C "$ROOT" worktree list

# ── Tô màu workspace cmux theo mức cần chú ý ──────────────────────────────
# Mỗi màu một nghĩa, không tô cho đẹp:
#   Crimson  đang chờ mình quyết        (gate mở, hoặc bug đã có verdict)
#   Amber    sắp phải can thiệp         (coder↔reviewer đã 3 vòng, chạm luật kill)
#   Blue     đang chạy bình thường
#   Charcoal xong hoặc nằm im
# Chỉ đụng workspace có TÊN TRÙNG slug — workspace khác của user không bị động tới.
[ -f /tmp/ship-board-colors.txt ] || exit 0
cmux ping >/dev/null 2>&1 || exit 0

export CMUX_QUIET=1
painted=0
while IFS=$'\t' read -r slug rank rnd; do
  ws=$(cmux workspace list 2>/dev/null | awk -v s="$slug" '$0 ~ ("[ *] *workspace:[0-9]+ +" s "$"){print $1; exit} {if ($2==s) print $1}' | head -1)
  [ -n "$ws" ] || continue
  case "$rank" in
    0) color=Crimson ;;
    1) [ "${rnd:-0}" -ge 3 ] 2>/dev/null && color=Amber || color=Blue ;;
    *) color=Charcoal ;;
  esac
  cmux workspace-action --action set-color --workspace "$ws" --color "$color" >/dev/null 2>&1 && painted=$((painted+1))
done < /tmp/ship-board-colors.txt
rm -f /tmp/ship-board-colors.txt
[ "$painted" -gt 0 ] && echo "── đã tô màu $painted workspace theo trạng thái ──"

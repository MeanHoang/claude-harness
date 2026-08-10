#!/usr/bin/env bash
# Mở một feature chạy song song: worktree + harness + workspace cmux riêng + tab cho từng vai.
#
#   .claude/scripts/feature-open.sh <slug> [notion-url] [type]
#
# type mặc định `feature`, dùng `bugfix`/`chore`/`improve` khi hợp hơn.
#
# Kết quả: một workspace cmux tên <slug>, trong đó
#   tab gốc  = shell trống (gõ git/test bằng tay)
#   scout    = đang chạy, đọc Notion + verify + viết plan
#   coder / research / reviewer / ux / checker = tab sẵn sàng, chưa chạy (đợi tới lượt)
#
# Cha KHÔNG ở đây — cha ngồi ở workspace của checkout chính {{PROJECT_ROOT}}.

set -uo pipefail
export CMUX_QUIET=1

# --main = làm ngay trên checkout chính, KHÔNG tạo worktree.
# Dùng khi task cần chạy dev stack / test local — dev stack chạy từ checkout chính, và
# worktree riêng thì phải dựng lại toàn bộ node_modules + tunnel. Cũng là lối thoát khi
# branch đang bị checkout chính giữ (git không cho hai worktree cùng một branch).
MAIN_MODE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --main|--no-worktree) MAIN_MODE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]:-}"

SLUG="${1:-}"
NOTION="${2:-}"
TYPE="${3:-feature}"
[ -n "$SLUG" ] || { echo "dùng: $0 [--main] <slug> [notion-url] [feature|bugfix|chore|improve]" >&2; exit 1; }

MAIN=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "không ở trong git repo" >&2; exit 1; }
REPO=$(basename "$MAIN")
BRANCH="$TYPE/$SLUG"
SHIP="$MAIN/.claude/ship/$SLUG"
if [ "$MAIN_MODE" = "1" ]; then WT="$MAIN"; else WT="$HOME/cmux/worktrees/$REPO/$SLUG"; fi

step(){ printf "\n\033[1m%s\033[0m\n" "$*"; }

# --- 1. worktree ---
step "[1/6] worktree"
if [ "$MAIN_MODE" = "1" ]; then
  cur=$(git -C "$MAIN" branch --show-current)
  echo "  CHẾ ĐỘ --main: làm thẳng trên checkout chính, không tạo worktree"
  echo "  $MAIN  (branch hiện tại: $cur)"
  if [ "$cur" != "$BRANCH" ]; then
    echo "  ⚠ branch hiện tại KHÁC '$BRANCH' — tự checkout đúng branch trước khi code:"
    echo "      git checkout $BRANCH    (hoặc git checkout -b $BRANCH)"
  fi
elif [ -d "$WT" ]; then
  echo "  đã có: $WT"
else
  mkdir -p "$(dirname "$WT")"
  # Branch đang được checkout ở đâu đó rồi? git chỉ cho MỘT worktree giữ một branch.
  HOLDER=$(git -C "$MAIN" worktree list --porcelain \
           | awk -v b="refs/heads/$BRANCH" '/^worktree /{w=$2} $0=="branch "b{print w; exit}')
  if [ -n "$HOLDER" ]; then
    echo "  ⛔ branch '$BRANCH' đang được giữ bởi: $HOLDER"
    echo "     git không cho hai worktree cùng giữ một branch. Chọn một:"
    if [ "$HOLDER" = "$MAIN" ]; then
      echo "       • Chạy lại với --main để làm thẳng trên checkout chính (test local được luôn):"
      echo "           $0 --main $SLUG"
    else
      echo "       • Làm task này ngay tại đó — trỏ workspace cmux vào $HOLDER"
    fi
    echo "       • Hoặc giải phóng branch (checkout nhánh khác ở đó) rồi chạy lại lệnh này"
    exit 1
  fi
  # Branch đã tồn tại nhưng chưa ai giữ → gắn vào, đừng tạo mới (-b sẽ báo lỗi already exists).
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$MAIN" worktree add "$WT" "$BRANCH" 2>&1 | tail -1 || exit 1
    echo "  tạo:  $WT  (gắn vào branch $BRANCH đã có)"
  else
    git -C "$MAIN" worktree add "$WT" -b "$BRANCH" 2>&1 | tail -1 || exit 1
    echo "  tạo:  $WT  (branch $BRANCH mới)"
  fi
fi

# --- 2. harness (bắt buộc — worktree trần không có skill pipeline, không có gate) ---
step "[2/6] trang bị harness"
if [ "$MAIN_MODE" = "1" ]; then
  echo "  bỏ qua — checkout chính vốn đã là nguồn của harness"
else
"$MAIN/.claude/scripts/bootstrap-worktree.sh" "$WT" >/tmp/bootstrap-$SLUG.log 2>&1
if [ $? -ne 0 ]; then
  echo "  ⛔ bootstrap THẤT BẠI — đừng mở session. Xem /tmp/bootstrap-$SLUG.log"
  tail -12 "/tmp/bootstrap-$SLUG.log"
  exit 1
fi
echo "  ✓ $(grep -c '^  link\|^  copy' /tmp/bootstrap-$SLUG.log) mục, verify xanh"
fi

# --- 3. state của ship ---
step "[3/6] progress.md"
mkdir -p "$SHIP"
if [ -f "$SHIP/progress.md" ]; then
  if grep -q "<!-- state" "$SHIP/progress.md"; then
    echo "  đã có: $SHIP/progress.md"
  else
    # Task cũ (format trước khi có khối state). Thiếu khối này thì ship-board bỏ qua
    # và workspace không được tô màu — nhìn như hỏng. Chèn vào đầu, giữ nguyên nội dung cũ.
    tmp=$(mktemp)
    {
      printf '<!-- state\nkind: feature\nslug: %s\nbranch: %s\nworktree: %s\nstep: 0\nphase: -\nawaiting: scout\nround: 0\ngate: none\nverdict: -\n-->\n\n' \
        "$SLUG" "$BRANCH" "$WT"
      cat "$SHIP/progress.md"
    } > "$tmp" && mv "$tmp" "$SHIP/progress.md"
    echo "  đã có (format cũ) → đã chèn khối state để lên được ship-board"
  fi
else
  sed -e "s|{{slug}}|$SLUG|g" -e "s|{{branch}}|$BRANCH|g" -e "s|{{worktree_path}}|$WT|g" \
      -e "s|{{title}}|$SLUG|g" -e "s|{{notion_url}}|${NOTION:-—}|g" \
      "$MAIN/.claude/skills/feature-team/templates/progress-header.md" > "$SHIP/progress.md"
  echo "  tạo:  $SHIP/progress.md"
fi

# --- 4. workspace cmux riêng cho feature này ---
step "[4/6] workspace cmux"
if ! cmux ping >/dev/null 2>&1; then
  echo "  ⚠ cmux không chạy — worktree đã sẵn sàng, mở session bằng tay:"
  echo "    cd $WT && claude"
  exit 0
fi
# đã có workspace cùng tên thì DÙNG LẠI — nếu không sẽ đẻ ra hai cái trùng tên
WS=$(cmux workspace list 2>/dev/null | awk -v s="$SLUG" '$2==s{print $1; exit} $3==s{print $2; exit}')
if [ -n "$WS" ]; then
  echo "  đã có: $WS  ($SLUG) — dùng lại, không tạo mới"
  REUSED=1
else
  WS=$(cmux new-workspace --name "$SLUG" --description "$TYPE · $BRANCH" --cwd "$WT" --focus false 2>&1 | awk '/^OK/{print $2}')
  [ -n "$WS" ] || { echo "  ⛔ không tạo được workspace" >&2; exit 1; }
  echo "  tạo:  $WS  ($SLUG)"
  REUSED=0
fi

# --- 5. một tab cho mỗi vai. Tab vừa tạo LUÔN nằm ở index 1 — rename ngay sau khi tạo. ---
step "[5/6] tab theo vai"
if [ "${REUSED:-0}" = "1" ]; then
  echo "  workspace cũ đã có tab, giữ nguyên:"
  cmux list-pane-surfaces --workspace "$WS" 2>/dev/null | sed 's/^/    /'
  SCOUT_SURFACE=$(cmux list-pane-surfaces --workspace "$WS" 2>/dev/null | awk '/ scout$/{print $1; exit}' | tr -d '*')
else
SCOUT_SURFACE=""
# tạo ngược thứ tự để scout nằm ngay sau tab gốc.
# ux chỉ dùng cho phase có giao diện — tab vẫn mở sẵn, phase thuần backend thì để trống.
for role in checker ux reviewer research coder scout; do
  sid=$(cmux new-surface --type terminal --workspace "$WS" --focus false 2>&1 | awk '/^OK/{print $2}')
  cmux rename-tab --workspace "$WS" --tab 1 "$role" >/dev/null 2>&1
  [ "$role" = "scout" ] && SCOUT_SURFACE="$sid"
  echo "  tab:  $role  ($sid)"
done
fi

step "[6/6] kickoff từng vai"
# --- Kickoff cho TỪNG vai, kèm bảng địa chỉ để chúng gọi được nhau ---
# Kickoff dạy cách TRA địa chỉ theo tên vai — không ghi cứng id vì cmux đánh lại số
# sau mỗi lần đóng/mở workspace (sự cố 05/08: session chỉ viết "giao cho X" rồi ngồi chờ).
TPL="$MAIN/.claude/skills/feature-team/templates"
for r in scout coder research reviewer ux checker; do
  K="$SHIP/kickoff-$r.md"
  [ -f "$K" ] && continue
  [ -f "$TPL/role-$r.md" ] || continue
  python3 - "$TPL/role-$r.md" "$K" "$SLUG" "$WT" "$BRANCH" "${NOTION:-(chưa có link — hỏi user)}" <<'PYEOF'
import sys
src, dst, slug, wt, branch, notion = sys.argv[1:7]
t = open(src, encoding="utf-8").read()
for k, v in {"{{slug}}": slug, "{{worktree_path}}": wt, "{{branch}}": branch,
             "{{notion_url}}": notion,
             "{{base_ref}}": "origin/master"}.items():
    t = t.replace(k, v)
open(dst, "w", encoding="utf-8").write(t)
PYEOF
  echo "  kickoff: $r"
done
KICK="$SHIP/kickoff-scout.md"

cat <<EOF

────────────────────────────────────────────────────────────
Xong. Workspace "$SLUG" đã có 6 tab: scout · coder · research · reviewer · ux · checker

Còn một việc phải làm bằng tay: điền phần nghiên cứu vào kickoff của scout
  $KICK
(session con không có ký ức gì về hội thoại này — thứ gì không viết ra là mất)

Rồi khởi động scout (nhớ \\n ở cuối, cmux không tự bấm Enter):
  cmux send --workspace $WS --surface $SCOUT_SURFACE \$'claude --dangerously-skip-permissions "\$(cat $KICK)"\n'

  (đã kiểm chứng 2026-08-05: hook VẪN chặn trong bypass mode — session con bỏ hỏi
   permission nhưng 4 hàng rào readonly/translation/branch/lint vẫn ràng buộc nó)

Tất cả tab:  cmux list-pane-surfaces --workspace $WS
Theo dõi:    .claude/scripts/ship-board.sh
────────────────────────────────────────────────────────────
EOF

#!/usr/bin/env bash
# Trang bị harness cho một git worktree vừa tạo.
#
# Vì sao cần: `git worktree add` chỉ checkout file TRACKED, mà gần như toàn bộ harness
# của repo này lại untracked (nhiều skill gồm cả ship, 3 hook local, settings.local.json,
# .claude/ship). Một session chạy trong worktree "trần" sẽ không có ship, không có
# gate nào, và auto-lint chạy bản HEAD reformat cả file — tức là agent chạy KHÔNG LUẬT.
#
# Cách dùng:
#   git worktree add ~/cmux/worktrees/<repo>/<slug> -b <type>/<slug>
#   .claude/scripts/bootstrap-worktree.sh ~/cmux/worktrees/<repo>/<slug>
#
# Cơ chế: symlink cho thứ dùng chung (sửa ở main là mọi worktree có ngay), copy cho thứ
# mỗi worktree phải có bản riêng (.env, auto-lint.sh).

set -uo pipefail

WT="${1:-}"
if [ -z "$WT" ]; then
  echo "dùng: $0 <đường-dẫn-worktree>" >&2
  exit 1
fi
WT=$(cd "$WT" 2>/dev/null && pwd) || { echo "không thấy worktree: ${1}" >&2; exit 1; }

MAIN=$(git -C "$WT" worktree list --porcelain | awk '/^worktree /{print $2; exit}')
[ -d "$MAIN" ] || { echo "không xác định được checkout chính" >&2; exit 1; }
[ "$MAIN" = "$WT" ] && { echo "đây là checkout chính, không cần bootstrap" >&2; exit 1; }

ok=0; skip=0
link() {  # link <đường-dẫn-tương-đối>
  local rel=$1 src="$MAIN/$1" dst="$WT/$1"
  [ -e "$src" ] || { skip=$((skip+1)); return; }
  [ -e "$dst" ] && [ ! -L "$dst" ] && { echo "  ĐỤNG ĐỘ (đã tồn tại, bỏ qua): $rel"; skip=$((skip+1)); return; }
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  echo "  link  $rel"
  ok=$((ok+1))
}

echo "main:     $MAIN"
echo "worktree: $WT"
echo

# --- 1. Hook local (untracked ở main -> worktree không có) ---
echo "[1] hook local"
for h in "$MAIN"/.claude/hooks/*.sh; do
  rel=".claude/hooks/$(basename "$h")"
  git -C "$MAIN" ls-files --error-unmatch "$rel" >/dev/null 2>&1 || link "$rel"
done

# --- 2. Wiring hook + quyền ---
echo "[2] settings.local.json"
link ".claude/settings.local.json"

# --- 3. Skill untracked (ship, analyze-task, surface-audit, ...) ---
echo "[3] skill untracked"
for d in "$MAIN"/.claude/skills/*/; do
  rel=".claude/skills/$(basename "$d")"
  git -C "$MAIN" ls-files --error-unmatch "$rel" >/dev/null 2>&1 || link "$rel"
done

# --- 4. State của các ship (cha cần nhìn xuyên mọi feature -> dùng chung 1 chỗ) ---
echo "[4] .claude/ship (dùng chung với main)"
link ".claude/ship"

# --- 5. auto-lint.sh: bản local bị skip-worktree nên worktree nhận bản HEAD (lint cả file).
#        Phải COPY đè + skip-worktree trong chính worktree này. ---
echo "[5] auto-lint.sh (copy đè bản chỉ-lint-dòng-đã-đổi)"
if grep -q "difflib" "$MAIN/.claude/hooks/auto-lint.sh" 2>/dev/null; then
  cp "$MAIN/.claude/hooks/auto-lint.sh" "$WT/.claude/hooks/auto-lint.sh"
  git -C "$WT" update-index --skip-worktree .claude/hooks/auto-lint.sh 2>/dev/null \
    && echo "  copy + skip-worktree  .claude/hooks/auto-lint.sh" && ok=$((ok+1))
else
  echo "  ⚠ auto-lint.sh ở main KHÔNG phải bản range-limited — bỏ qua"
  skip=$((skip+1))
fi

# --- 6. File env theo .worktreeinclude (git worktree add không tự copy — đó là tính năng
#        của `claude -w`, còn skill cmux lại tạo worktree thủ công) ---
echo "[6] file env theo .worktreeinclude"
if [ -f "$MAIN/.worktreeinclude" ]; then
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue ;; esac
    for src in "$MAIN"/$pat; do
      [ -f "$src" ] || continue
      rel=${src#"$MAIN"/}
      mkdir -p "$WT/$(dirname "$rel")"
      cp "$src" "$WT/$rel" && echo "  copy  $rel" && ok=$((ok+1))
    done
  done < "$MAIN/.worktreeinclude"
else
  echo "  (không có .worktreeinclude)"
fi

# --- Kiểm chứng: những thứ BẮT BUỘC phải có mặt ---
echo
echo "[verify]"
fail=0
# Bắt buộc ở MỌI project: đây là hàng rào, thiếu là session con chạy không luật.
must=(
  ".claude/hooks/readonly-intent-guard.sh"
  ".claude/hooks/branch-guard.sh"
  ".claude/settings.local.json"
)
# Project nào cần thêm thì liệt kê trong .claude/harness-required.txt (mỗi dòng 1 đường dẫn).
# Nhờ vậy skill riêng của từng repo không phải hardcode vào script dùng chung.
if [ -f "$MAIN/.claude/harness-required.txt" ]; then
  while IFS= read -r extra; do
    case "$extra" in ''|\#*) continue ;; esac
    must+=("$extra")
  done < "$MAIN/.claude/harness-required.txt"
fi
for m in "${must[@]}"; do
  if [ -e "$WT/$m" ]; then echo "  ✓ $m"; else echo "  ✗ THIẾU $m"; fail=1; fi
done
if grep -q "difflib" "$WT/.claude/hooks/auto-lint.sh" 2>/dev/null; then
  echo "  ✓ auto-lint.sh (bản chỉ lint dòng đã đổi)"
else
  echo "  ✗ auto-lint.sh vẫn là bản lint cả file"; fail=1
fi

echo
echo "xong: $ok mục, bỏ qua $skip"
[ $fail -eq 0 ] || { echo "⛔ worktree CHƯA đủ harness — đừng chạy session ở đây"; exit 1; }
echo "✅ worktree đã đủ harness"

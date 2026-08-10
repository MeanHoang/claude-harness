#!/usr/bin/env bash
# Nén ảnh trước khi đưa vào context. LUÔN chạy cái này trước khi Read một ảnh.
#
#   .claude/scripts/shot.sh <ảnh.png> [chiều-rộng-tối-đa]     # mặc định 1000
#   → in ra đường dẫn .jpg đã nén, Read chính file đó
#
# Vì sao: ảnh vào context dưới dạng base64. Đo ngày 06/08 trên toàn bộ session:
# 23 MB / 53 MB kết quả tool là ẢNH — 44%, tương đương ~6,15 triệu token. Một screenshot
# PNG full-page 600 KB ≈ 150k token, và nó nằm lại trong context suốt các lượt sau.
#
# Resize 1000px + JPEG giảm ~54%, 800px giảm ~72%, mà chữ vẫn đọc được để đánh giá layout.
# Cần soi chi tiết pixel (so màu, lệch 1px) thì mới Read bản PNG gốc — và chỉ lần đó thôi.

set -uo pipefail
SRC="${1:-}"
W="${2:-1000}"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "dùng: $0 <ảnh> [rộng-tối-đa]" >&2; exit 1; }

OUT="${SRC%.*}-w${W}.jpg"
sips -Z "$W" -s format jpeg -s formatOptions 65 "$SRC" --out "$OUT" >/dev/null 2>&1 \
  || { echo "sips lỗi, dùng ảnh gốc: $SRC" >&2; echo "$SRC"; exit 0; }

o=$(( $(wc -c < "$SRC") / 1024 ))
n=$(( $(wc -c < "$OUT") / 1024 ))
printf '%s\n' "$OUT"
# base64 nở 4/3, rồi ~4 ký tự = 1 token  ⇒  bytes tiết kiệm × 4/3 ÷ 4 = bytes ÷ 3
printf '  %s KB → %s KB (giảm %s%%, tiết kiệm ~%s nghìn token)\n' \
  "$o" "$n" "$(( o > 0 ? 100 - n*100/o : 0 ))" "$(( (o-n)*1024/3/1000 ))" >&2

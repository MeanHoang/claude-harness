#!/usr/bin/env bash
# Cảnh báo trước khi mở thêm một session song song, dựa trên RAM THẬT của máy này.
#
# Vì sao cần: 17/08 lúc 10:36 macOS đã bắn jetsam (OOM killer) —
# /Library/Logs/DiagnosticReports/JetsamEvent-*.ips. Session cmux biến mất giữa chừng
# mà không để lại crash report nào, nên nhìn từ cmux thì tưởng "cmux hay chết".
#
# KHÔNG tự đặt ngưỡng %. Ngưỡng lấy thẳng từ lần máy này đã thật sự hết RAM:
# đọc compressor size ghi trong JetsamEvent gần nhất, so với compressor hiện tại.
# Chưa từng có jetsam thì không có gì để so → im lặng cho qua, không bịa số.
#
# Dùng:  ram-guard.sh          in cảnh báo nếu đang nguy hiểm (luôn exit 0)
#        ram-guard.sh --strict exit 1 khi nguy hiểm — để chặn việc mở tab mới

set -uo pipefail
STRICT=0; [ "${1:-}" = "--strict" ] && STRICT=1

PAGE=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
gb() { awk -v p="$1" -v s="$PAGE" 'BEGIN{printf "%.1f", p*s/1073741824}'; }

now_comp=$(vm_stat 2>/dev/null | awk -F': *' '/Pages occupied by compressor/{gsub(/\./,"",$2); print $2}')
[ -n "${now_comp:-}" ] || exit 0

# mức compressor tại thời điểm máy này thực sự bị OOM
last=$(ls -t /Library/Logs/DiagnosticReports/JetsamEvent-*.ips 2>/dev/null | head -1)
kill_comp=""; one_session=""
if [ -n "$last" ] && [ -r "$last" ]; then
  # Lấy 2 số, cả hai đều đo được, không ước lượng:
  #   kill_comp   — compressor lúc máy thật sự bị OOM
  #   one_session — một tiến trình claude nặng bao nhiêu, đo tại chính lúc đó
  read -r kill_comp one_session <<<"$(python3 - "$last" <<'PY' 2>/dev/null
import json, sys
body = json.loads(open(sys.argv[1]).read().split('\n', 1)[1])
claude = [p.get('rpages', 0) for p in body.get('processes', [])
          if 'claude' in (p.get('name') or '').lower()]
print(body['memoryStatus']['compressorSize'], max(claude) if claude else 0)
PY
)"
fi

level=$(sysctl -n kern.memorystatus_level 2>/dev/null || echo "")

if [ -z "$kill_comp" ]; then
  [ -n "$level" ] && [ "$level" -lt 20 ] 2>/dev/null && \
    echo "⚠️  RAM còn $level% (kern.memorystatus_level). Chưa có JetsamEvent nào để so — theo dõi thêm."
  exit 0
fi

# Cả hai mốc dưới đây đều là số đo, không phải số tự chọn:
#   - đã vượt mức từng gây OOM            -> chặn
#   - cộng thêm MỘT session Claude nữa là chạm mức đó -> cảnh báo, vì việc sắp làm
#     chính là mở thêm một session
if [ "$now_comp" -ge "$kill_comp" ]; then
  echo "🛑 RAM: compressor $(gb "$now_comp")GB — ĐÃ VƯỢT mức lúc máy bị OOM ($(gb "$kill_comp")GB, $(basename "$last")).${level:+ Còn $level%.}"
  echo "   Đóng bớt session / tắt bớt tiến trình dev trước khi mở thêm tab."
  [ "$STRICT" = 1 ] && exit 1
elif [ -n "$one_session" ] && [ "$one_session" -gt 0 ] \
     && [ $((now_comp + one_session)) -ge "$kill_comp" ]; then
  echo "⚠️  RAM: compressor $(gb "$now_comp")GB. Thêm một session Claude nữa ($(gb "$one_session")GB, đo tại lần OOM) là chạm mức đã chết ($(gb "$kill_comp")GB).${level:+ Còn $level%.}"
fi
exit 0

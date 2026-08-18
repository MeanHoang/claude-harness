#!/usr/bin/env bash
# Gửi message giữa các session cmux — VÀ XÁC NHẬN nó đã thực sự được submit.
#
# Vì sao cần: `cmux send` chỉ nhét ký tự vào terminal. Không ai kiểm lại là Claude đã
# nhận chưa. Thực tế gặp nhiều lần: text nằm im trong ô nhập, tab trông như đang chạy,
# cả hai bên cùng chờ nhau. Sáu file role-*.md mỗi file tự chép lại một hàm `call()`
# ba dòng, không bản nào verify — nên lỗi này im lặng ở cả sáu chỗ.
#
# Hai thứ script này làm mà hàm inline không làm:
#   1. Từ chối gửi vào tab CHƯA chạy Claude (bare shell) — ở đó message sẽ bị chạy
#      như một lệnh shell.
#   2. Gửi xong đọc lại màn hình; còn kẹt thì bấm Enter lại; hết cách thì BÁO LỖI
#      (exit 2) thay vì im lặng coi như đã gửi.
#
# Dùng:
#   cmux-say.sh say     <slug> <role> <message>   gửi + verify
#   cmux-say.sh launch  <slug> <role>             khởi động role chưa chạy
#   cmux-say.sh status  <slug> [role]             in trạng thái từng tab
#   cmux-say.sh unstick <slug> [role]             bấm Enter cho tab đang kẹt
#
# Trạng thái in ra: running | idle | stuck | dialog | shell | absent

set -uo pipefail

ROLES_DEFAULT="scout coder research reviewer ux checker"

die() { echo "cmux-say: $*" >&2; exit 1; }

cmux ping >/dev/null 2>&1 || die "cmux không chạy"

# --- địa chỉ: luôn tra theo TÊN, không bao giờ hardcode id ------------------
# cmux đánh số lại mỗi khi một workspace đóng/mở, nên id cũ sẽ trỏ nhầm feature khác.
ws_of() {
  cmux workspace list 2>/dev/null \
    | awk -v s="$1" '$0 ~ ("[ *] *workspace:[0-9]+ +" s "$"){print $1; exit} {if ($2==s) print $1}' \
    | head -1
}

surface_of() {
  # Phải bỏ dấu '*' của dòng đang được chọn TRƯỚC khi tách cột. Dòng thường là
  # "  surface:31  coder" ($1=id, $2=tên), nhưng dòng đang chọn là
  # "* surface:30  scout" — $1 hoá thành '*' và $2 thành id, nên so $2 với tên
  # sẽ trượt đúng cái tab đang mở. Khi trượt, `--surface ""` khiến cmux gửi vào
  # surface mặc định, tức là chính mình: message không bao giờ tới nơi.
  cmux list-pane-surfaces --workspace "$1" 2>/dev/null \
    | sed 's/^[* ]*//' \
    | awk -v n="$2" '$2==n{print $1; exit}'
}

screen_of() {
  cmux read-screen --workspace "$1" --surface "$2" --lines 25 2>/dev/null
}

# --- đọc màn hình -> một trạng thái ----------------------------------------
# Dấu hiệu phân biệt, theo thứ tự ưu tiên:
#   dialog  : đang hỏi quyền / MCP mới -> Enter sẽ bị nuốt, phải Esc
#   running : Claude đang chạy (footer "esc to interrupt")
#   shell   : chưa có Claude, chỉ là prompt shell -> gửi message = chạy lệnh shell
#   stuck   : có khung nhập của Claude, trong ô nhập CÓ chữ, mà không chạy
#   idle    : có khung nhập, ô trống, đang chờ người
classify() {
  # Các mẫu dưới đây lấy từ màn hình THẬT của Claude Code bản đang chạy (17/08), không
  # phải phỏng đoán: ô nhập là "❯" nằm giữa hai đường kẻ, footer là dòng model +
  # "bypass permissions", lúc bận thì có dòng đếm "… (8m 28s · ↓ 27.8k tokens)".
  # Bản cũ vẽ khung "│ > " nên giữ cả hai kiểu.
  #
  # CHỈ xét phần CUỐI màn hình. Nếu quét cả scrollback thì hai thứ này đánh lừa:
  #   - nội dung đang hiển thị (ví dụ chính đoạn code này) khớp mẫu → báo nhầm dialog
  #   - khung Claude CŨ còn nằm lại sau khi session đã thoát → tab shell bị báo là idle
  local tail_txt last
  tail_txt=$(grep -v '^[[:space:]]*$' <<<"$1" | tail -12)
  last=$(tail -1 <<<"$tail_txt")

  # Dòng cuối là prompt shell -> không có Claude nào ở đây (dù scrollback còn khung cũ)
  grep -qE "[%$#][[:space:]]*$" <<<"$last" && { echo shell; return; }

  grep -qiE "Do you want|New MCP server|Yes, and|No, and tell" <<<"$tail_txt" && { echo dialog; return; }
  grep -qE "esc to interrupt|ctrl\+c to (stop|interrupt)|tokens\)|⏺ Running" <<<"$tail_txt" && { echo running; return; }
  grep -qE "│ *>|for shortcuts|bypass permissions|❯" <<<"$tail_txt" || { echo shell; return; }

  # Ô nhập còn chữ = đã gõ vào mà chưa submit.
  #
  # CHỈ xét dòng "❯" CUỐI CÙNG. Claude Code echo lại message ĐÃ submit cũng bằng tiền tố
  # "❯" trong scrollback, nên quét cả vùng tail sẽ khớp phải dòng echo đó và báo "stuck"
  # trong khi ô nhập thật (nằm dưới cùng, giữa hai đường kẻ) đang trống — báo động sai này
  # khiến người gọi tưởng handoff hỏng rồi bấm Enter thừa nhiều lần (gặp thật 17/08).
  local box
  box=$(grep -E "^[[:space:]]*(❯|│ *>)" <<<"$tail_txt" | tail -1)
  if grep -qE "^[[:space:]]*(❯|│ *>) +[^[:space:]]" <<<"$box"; then echo stuck; else echo idle; fi
}

state_of() {  # state_of <slug> <role> -> in trạng thái, đặt WS/SID
  WS=$(ws_of "$1");            [ -n "$WS" ]  || { echo absent; return; }
  SID=$(surface_of "$WS" "$2"); [ -n "$SID" ] || { echo absent; return; }
  classify "$(screen_of "$WS" "$SID")"
}

press() { cmux send-key --workspace "$WS" --surface "$SID" "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
cmd=${1:-}; shift || true

case "$cmd" in

status)
  slug=${1:-} ; [ -n "$slug" ] || die "dùng: status <slug> [role]"
  for r in ${2:-$ROLES_DEFAULT}; do
    printf "%-10s %s\n" "$r" "$(state_of "$slug" "$r")"
  done
  ;;

launch)
  slug=${1:-}; role=${2:-}; [ -n "$role" ] || die "dùng: launch <slug> <role>"
  st=$(state_of "$slug" "$role")
  # state_of đặt WS/SID, nhưng nó vừa chạy trong $( ) tức subshell — biến không thoát
  # ra ngoài được. Phải phân giải lại ở shell này, không thì `press`/`cmux send` dùng
  # biến rỗng (với `set -u` là chết hẳn).
  WS=$(ws_of "$slug"); SID=$(surface_of "$WS" "$role")
  [ "$st" = absent ] && die "không thấy tab '$role' của '$slug'"
  [ "$st" = shell ] || die "tab '$role' đang ở trạng thái '$st', không phải shell trống — không khởi động đè"
  kick=".claude/ship/$slug/kickoff-$role.md"
  cmux send --workspace "$WS" --surface "$SID" -- \
    "claude --dangerously-skip-permissions \"\$(cat $kick)\"" >/dev/null
  press enter
  sleep 3
  # lần chạy đầu trong worktree mới hay dính prompt "New MCP server found" nuốt mất kickoff
  [ "$(classify "$(screen_of "$WS" "$SID")")" = dialog ] && { press escape; sleep 1; }
  echo "$role: $(classify "$(screen_of "$WS" "$SID")")"
  ;;

say)
  slug=${1:-}; role=${2:-}; shift 2 2>/dev/null || die "dùng: say <slug> <role> <message>"
  msg="$*"; [ -n "$msg" ] || die "message rỗng"

  # Làm phẳng về một dòng. Bắt buộc: `cmux send` dịch CẢ `\n` literal LẪN xuống dòng
  # thật thành Enter, nên message nhiều dòng sẽ tự submit ở dòng đầu và phần còn lại
  # rơi ra ngoài như một prompt riêng.
  msg=$(printf '%s' "$msg" | tr '\n\r\t' '   ' | sed 's/\\n/ /g; s/  */ /g')

  st=$(state_of "$slug" "$role")
  WS=$(ws_of "$slug"); SID=$(surface_of "$WS" "$role")   # xem chú thích ở nhánh launch
  case "$st" in
    absent) die "không thấy tab '$role' của '$slug'" ;;
    shell)  die "tab '$role' chưa chạy Claude — gửi vào đây message sẽ bị chạy như lệnh shell. Chạy: $0 launch $slug $role" ;;
    dialog) press escape; sleep 1 ;;
  esac

  cmux send --workspace "$WS" --surface "$SID" -- "$msg" >/dev/null || die "send thất bại"

  # Gửi Enter TÁCH RỜI khỏi nội dung: khi cả hai đi chung một lần dán, TUI có thể coi
  # ký tự cuối là xuống dòng trong ô nhập thay vì lệnh submit.
  for attempt in 1 2 3; do
    press enter
    sleep 1
    now=$(classify "$(screen_of "$WS" "$SID")")
    case "$now" in
      running|idle) echo "→ $role: đã nhận ($now, lần $attempt)"; exit 0 ;;
      dialog)       press escape; sleep 1 ;;
    esac
  done

  echo "⚠ $role: gửi rồi nhưng màn hình vẫn báo '$now' — có thể chưa submit. Kiểm tra tab bằng mắt." >&2
  exit 2
  ;;

unstick)
  slug=${1:-}; [ -n "$slug" ] || die "dùng: unstick <slug> [role]"
  n=0
  for r in ${2:-$ROLES_DEFAULT}; do
    st=$(state_of "$slug" "$r")
    case "$st" in
      stuck)  press enter;  echo "$r: stuck → đã bấm Enter";   n=$((n+1)) ;;
      dialog) press escape; echo "$r: dialog → đã bấm Escape"; n=$((n+1)) ;;
    esac
  done
  [ $n -eq 0 ] && echo "không có tab nào kẹt."
  ;;

*)
  sed -n '2,20p' "$0" >&2
  exit 1
  ;;
esac

#!/usr/bin/env bash
# PreToolUse(Write|Edit): DENY ghi vào thư mục memory trừ khi user BẢO ghi.
#
# Vì sao cần: memory là bộ nhớ dài hạn của user — agent tự thêm vào thì user mất kiểm soát
# thứ sẽ được nạp lại mãi về sau. 2026-08-05 user chỉ ra chính tôi tự ghi
# `project_local_only_harness_hooks` mà không ai bảo: "kể cả việc ghi memory cũng nên ghi
# khi được nhắc thôi".
#
# Cùng cơ chế commit-consent: đọc lượt user cuối trong transcript.

set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file" ] || exit 0

# Chỉ gác đúng kho memory (kể cả MEMORY.md).
case "$file" in
  */.claude/projects/*/memory/*) ;;
  *) exit 0 ;;
esac

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] \
  || deny "⛔ Không xác minh được user có bảo ghi memory không. Hỏi trước."

last=$(jq -Rc '
  fromjson? // empty | select(.type == "last-prompt") | .lastPrompt
  | select(type == "string" and length > 0) | @json
' "$transcript" 2>/dev/null | tail -1)
[ -n "$last" ] || last=$(jq -Rc '
  fromjson? // empty | select(.type == "user") | .message.content
  | if type == "array" then (.[0] | select(.type == "text") | .text)
    elif type == "string" then . else empty end
  | select(type == "string" and length > 0 and (startswith("<") | not)) | @json
' "$transcript" 2>/dev/null | tail -1)
[ -n "$last" ] || deny "⛔ Chưa thấy lượt nào của user. Không tự ghi memory."

msg=$(printf '%s' "$last" | jq -r 'fromjson' 2>/dev/null \
  | perl -CSD -MUnicode::Normalize -ne 'print NFD(lc($_) =~ s/\x{111}/d/gr) =~ s/\p{M}//gr' 2>/dev/null)
[ -n "$msg" ] || deny "⛔ Không đọc được prompt cuối. Không tự ghi memory."

if printf '%s' "$msg" | grep -qE '(dung|khong|ko|khoan)[[:space:]]+(ghi|luu|nho|save)'; then
  deny "⛔ Prompt cuối của user là KHÔNG ghi memory."
fi

# Tín hiệu cho phép: nhớ / ghi nhớ / lưu / memory / remember / note lại
if printf '%s' "$msg" | grep -qE 'ghi nho|ghi lai|ghi memory|luu lai|luu vao|nho cai|nho gium|nho nhe|nho dieu|memory|remember|save.*memory|note lai|cap nhat memory'; then
  exit 0
fi

deny "⛔ User CHƯA bảo ghi memory. Memory là bộ nhớ dài hạn của user — chỉ ghi khi được nhắc. Muốn lưu thì HỎI: \\\"cái này em lưu vào memory nhé?\\\" rồi đợi."

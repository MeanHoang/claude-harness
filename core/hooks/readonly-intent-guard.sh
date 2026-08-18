#!/usr/bin/env bash
# PreToolUse(Edit|Write): DENY writes when user's last prompt signals read-only intent.
#
# Solves: SCOPE problem (#1 by frequency) — "check thôi đừng sửa" but agent edits anyway.
# Design: deterministic hook → agent CANNOT bypass, unlike memory which is advisory.
#
# How it works:
#   1. Read session transcript (path from hook input) to find last human prompt
#   2. Check for read-only signals (Vietnamese + English)
#   3. If read-only AND no explicit write-allow signal → DENY
#
# Ratchet trace: 40+ occurrences of user writing defensive prompts like
#   "đừng sửa vội", "check thôi", "read only thôi đừng update sửa hay can thiệp gì"

set -uo pipefail

# --- Extract the newest "last-prompt" entry (raw user text, cleanest source) ---
# One streaming jq pass; @json keeps multi-line prompts on a single line so
# `tail -1` picks the newest entry rather than the newest *line*.
extract_last_prompt_entry() {
  jq -Rc '
    fromjson? // empty
    | select(.type == "last-prompt")
    | .lastPrompt
    | select(type == "string" and length > 0)
    | @json
  ' "$1" 2>/dev/null | tail -1
}

# --- Fallback: newest human-typed "user" message ---
# Skips tool results (content[0].type != "text") and system/IDE events, which all
# start with "<" (<ide_opened_file>, <task-notification>, <system-reminder>).
extract_last_user_text() {
  jq -Rc '
    fromjson? // empty
    | select(.type == "user")
    | .message.content
    | if type == "array" then (.[0] | select(.type == "text") | .text)
      elif type == "string" then .
      else empty end
    | select(type == "string" and length > 0 and (startswith("<") | not))
    | @json
  ' "$1" 2>/dev/null | tail -1
}

# --- Decode a @json-encoded line back to raw text ---
decode_json_line() {
  printf '%s' "$1" | jq -r 'fromjson' 2>/dev/null
}

# --- Fold to lowercase ASCII so patterns stay plain ---
# "Đừng SỬA vội" -> "dung sua voi". Hand-written classes like [uư] miss tone marks
# (ử, ừ), so normalize once instead and match ASCII. NFD splits the tone mark off
# the vowel; đ has no decomposition, so it is mapped explicitly.
normalize() {
  printf '%s' "$1" | perl -CSD -MUnicode::Normalize -ne '
    print NFD(lc($_) =~ s/\x{111}/d/gr) =~ s/\p{M}//gr
  ' 2>/dev/null || printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

get_last_prompt() {
  local file=$1 encoded
  encoded=$(extract_last_prompt_entry "$file") || encoded=""
  [ -n "$encoded" ] || encoded=$(extract_last_user_text "$file") || encoded=""
  [ -n "$encoded" ] || return 0
  decode_json_line "$encoded"
}

input=$(cat)

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

last_prompt=$(get_last_prompt "$transcript")
[ -n "$last_prompt" ] || exit 0

msg=$(normalize "$last_prompt")

# --- Read-only signal patterns (matched against the normalized ASCII text) ---
# Covers: "check thôi", "đừng sửa", "phân tích thôi", "read only", "đọc thôi",
#         "xem thôi", "chưa sửa vội", "verify thôi", "ko sửa", "không sửa",
#         "đừng thay đổi", "just check", "review thôi", "chỉ đọc", "chỉ xem",
#         "đừng đổi", "đừng update", "đừng can thiệp"
readonly_pat='check thoi|dung sua|phan tich thoi|read[- ]?only|doc thoi|xem thoi|chua sua voi|verify thoi|ko sua|khong sua|just check|just read|review thoi|chi doc|chi xem|dung thay doi|dung doi|dung update|dung can thiep'

# --- Write-allow signal patterns ---
# If BOTH read-only and write-allow are present, allow (user clarified intent).
# The common shape is scope-limiting, not a write ban: "đừng sửa file khác, CHỈ SỬA
# file A", "đừng đổi tên biến, SỬA LOGIC thôi". A deny there blocks real work, which
# is the expensive failure for a hard gate — so treat those as write-allow.
write_pat='sua (di|luon|ngay|giup|ho|lai|cho)|chi (sua|fix|doi|thay)|sua [a-z]{3,} thoi|(^|[^a-z])fix([^a-z]|$)|lam di|commit|apply|implement|code di|viet code'

# "sửa vội thôi" / "sửa gì thôi" are read-only fillers, not an object being edited.
# Drop the filler so `sua [a-z]{3,} thoi` only matches a real target ("sửa logic thôi").
msg_w=$(printf '%s' "$msg" | sed -E 's/sua (voi|gi|j|nua|dau|nhe|ma)([^a-z]|$)/sua\2/g')

if printf '%s' "$msg" | grep -qE "$readonly_pat"; then
  if ! printf '%s' "$msg_w" | grep -qE "$write_pat"; then
    reason="STOP: the current prompt is READ-ONLY (signals detected: check / do not edit / analyse). Report what you found and STOP; ask for confirmation before editing."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
    exit 0
  fi
fi

exit 0

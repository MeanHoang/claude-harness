#!/usr/bin/env bash
# PreToolUse(Write|Edit): DENY writes to the memory directory unless the user ASKED for one.
#
# Why: memory is the user's long-term store. An agent adding to it on its own costs the user
# control over what gets reloaded into every future session. On 2026-08-05 the user caught this
# hook's own author writing a memory nobody asked for: "even writing memory should happen only
# when I ask".
#
# Same mechanism as commit-consent: read the last user turn in the transcript.

set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file" ] || exit 0

# Guard the memory store only (including MEMORY.md).
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
  || deny "STOP: cannot verify the user asked for a memory write. Ask first."

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
[ -n "$last" ] || deny "STOP: no user turn found. Not writing memory on my own."

msg=$(printf '%s' "$last" | jq -r 'fromjson' 2>/dev/null \
  | perl -CSD -MUnicode::Normalize -ne 'print NFD(lc($_) =~ s/\x{111}/d/gr) =~ s/\p{M}//gr' 2>/dev/null)
[ -n "$msg" ] || deny "STOP: could not read the last prompt. Not writing memory on my own."

if printf '%s' "$msg" | grep -qE '(dung|khong|ko|khoan)[[:space:]]+(ghi|luu|nho|save)'; then
  deny "STOP: the user's last prompt says NOT to write memory."
fi

# Consent signals (the user's own wording, Vietnamese and English):
if printf '%s' "$msg" | grep -qE 'ghi nho|ghi lai|ghi memory|luu lai|luu vao|nho cai|nho gium|nho nhe|nho dieu|memory|remember|save.*memory|note lai|cap nhat memory'; then
  exit 0
fi

deny "STOP: the user has not asked for a memory write. Memory is the user's long-term store; write it only when asked. To save something, ASK first (\\\"should I save this to memory?\\\") and wait."

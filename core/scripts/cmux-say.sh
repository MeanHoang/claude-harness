#!/usr/bin/env bash
# Send a message between cmux sessions AND CONFIRM it was actually submitted.
#
# Why: `cmux send` only types characters into a terminal. Nothing checks that Claude received
# them. Seen repeatedly in practice: the text sits in the input box, the tab looks busy, and
# both sides wait on each other. Each of the six role-*.md templates carried its own three-line
# `call()` helper, none of which verified anything, so this failure was silent in all six.
#
# Two things this script does that an inline helper does not:
#   1. Refuses to send into a tab NOT running Claude (a bare shell), where the message would be
#      executed as a shell command.
#   2. Re-reads the screen after sending, presses Enter again if it is still stuck, and REPORTS
#      A FAILURE (exit 2) rather than quietly assuming delivery.
#
# Usage:
#   cmux-say.sh say     <slug> <role> <message>   send + verify
#   cmux-say.sh launch  <slug> <role>             start a role that is not running yet
#   cmux-say.sh status  <slug> [role]             print the state of each tab
#   cmux-say.sh unstick <slug> [role]             press Enter for a stuck tab
#
# States printed: running | idle | stuck | dialog | shell | absent

set -uo pipefail

ROLES_DEFAULT="scout coder research reviewer ux checker"

die() { echo "cmux-say: $*" >&2; exit 1; }

cmux ping >/dev/null 2>&1 || die "cmux is not running"

# --- addressing: always look up by NAME, never hardcode an id ---------------
# cmux renumbers whenever a workspace is closed and reopened, so a stale id points at a
# different feature entirely.
ws_of() {
  cmux workspace list 2>/dev/null \
    | awk -v s="$1" '$0 ~ ("[ *] *workspace:[0-9]+ +" s "$"){print $1; exit} {if ($2==s) print $1}' \
    | head -1
}

surface_of() {
  # Strip the '*' marking the SELECTED row BEFORE splitting columns. A normal row is
  # "  surface:31  coder" ($1=id, $2=name), but the selected row is
  # "* surface:30  scout", where $1 becomes '*' and $2 becomes the id. Comparing $2 to the
  # name therefore misses exactly the tab that is currently open. On a miss, `--surface ""`
  # makes cmux send to the default surface, which is this session itself: the message never
  # arrives.
  cmux list-pane-surfaces --workspace "$1" 2>/dev/null \
    | sed 's/^[* ]*//' \
    | awk -v n="$2" '$2==n{print $1; exit}'
}

screen_of() {
  cmux read-screen --workspace "$1" --surface "$2" --lines 25 2>/dev/null
}

# --- read the screen -> one state -------------------------------------------
# Signals, in priority order:
#   dialog  : a permission / new-MCP prompt is up -> Enter gets swallowed, send Esc
#   running : Claude is working (footer "esc to interrupt")
#   shell   : no Claude here, just a shell prompt -> a message would run as a shell command
#   stuck   : Claude's input box is present, HAS text in it, and nothing is running
#   idle    : input box present, empty, waiting for a human
classify() {
  # These patterns come from a REAL Claude Code screen (2026-08-17), not from guesswork: the
  # input box is "❯" between two rules, the footer is the model line plus "bypass permissions",
  # and while busy there is a counter line like "… (8m 28s · ↓ 27.8k tokens)". Older versions
  # draw a "│ > " box, so both shapes are kept.
  #
  # Look at the END of the screen ONLY. Scanning the whole scrollback is fooled by two things:
  #   - displayed content (this very code, for instance) matching a pattern -> false "dialog"
  #   - an OLD Claude box left behind after the session exited -> a shell tab reported as idle
  local tail_txt last
  tail_txt=$(grep -v '^[[:space:]]*$' <<<"$1" | tail -12)
  last=$(tail -1 <<<"$tail_txt")

  # Last line is a shell prompt -> no Claude here, even if the scrollback still shows a box
  grep -qE "[%$#][[:space:]]*$" <<<"$last" && { echo shell; return; }

  grep -qiE "Do you want|New MCP server|Yes, and|No, and tell" <<<"$tail_txt" && { echo dialog; return; }
  grep -qE "esc to interrupt|ctrl\+c to (stop|interrupt)|tokens\)|⏺ Running" <<<"$tail_txt" && { echo running; return; }
  grep -qE "│ *>|for shortcuts|bypass permissions|❯" <<<"$tail_txt" || { echo shell; return; }

  # Text left in the input box = typed but never submitted.
  #
  # Consider the LAST "❯" line ONLY. Claude Code echoes an ALREADY-submitted message with the
  # same "❯" prefix into the scrollback, so scanning the whole tail matches that echo and
  # reports "stuck" while the real input box (bottom, between the rules) is empty. That false
  # alarm makes the caller think the handoff failed and press Enter repeatedly (happened for
  # real on 2026-08-17).
  local box
  box=$(grep -E "^[[:space:]]*(❯|│ *>)" <<<"$tail_txt" | tail -1)
  if grep -qE "^[[:space:]]*(❯|│ *>) +[^[:space:]]" <<<"$box"; then echo stuck; else echo idle; fi
}

state_of() {  # state_of <slug> <role> -> prints the state, sets WS/SID
  WS=$(ws_of "$1");            [ -n "$WS" ]  || { echo absent; return; }
  SID=$(surface_of "$WS" "$2"); [ -n "$SID" ] || { echo absent; return; }
  classify "$(screen_of "$WS" "$SID")"
}

press() { cmux send-key --workspace "$WS" --surface "$SID" "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
cmd=${1:-}; shift || true

case "$cmd" in

status)
  slug=${1:-} ; [ -n "$slug" ] || die "usage: status <slug> [role]"
  for r in ${2:-$ROLES_DEFAULT}; do
    printf "%-10s %s\n" "$r" "$(state_of "$slug" "$r")"
  done
  ;;

launch)
  slug=${1:-}; role=${2:-}; [ -n "$role" ] || die "usage: launch <slug> <role>"
  st=$(state_of "$slug" "$role")
  # state_of sets WS/SID, but it just ran inside $( ), a subshell, so those variables never
  # escape. Resolve them again in THIS shell, or `press`/`cmux send` run on empty variables
  # (fatal under `set -u`).
  WS=$(ws_of "$slug"); SID=$(surface_of "$WS" "$role")
  [ "$st" = absent ] && die "no tab '$role' for '$slug'"
  [ "$st" = shell ] || die "tab '$role' is in state '$st', not an empty shell; refusing to launch over it"
  kick=".claude/ship/$slug/kickoff-$role.md"
  cmux send --workspace "$WS" --surface "$SID" -- \
    "claude --dangerously-skip-permissions \"\$(cat $kick)\"" >/dev/null
  press enter
  sleep 3
  # the first run in a fresh worktree often hits a "New MCP server found" prompt that swallows the kickoff
  [ "$(classify "$(screen_of "$WS" "$SID")")" = dialog ] && { press escape; sleep 1; }
  echo "$role: $(classify "$(screen_of "$WS" "$SID")")"
  ;;

say)
  slug=${1:-}; role=${2:-}; shift 2 2>/dev/null || die "usage: say <slug> <role> <message>"
  msg="$*"; [ -n "$msg" ] || die "empty message"

  # Flatten to one line. Mandatory: `cmux send` turns BOTH a literal `\n` AND a real newline
  # into Enter, so a multi-line message submits itself at the first line and the remainder
  # lands outside as a separate prompt.
  msg=$(printf '%s' "$msg" | tr '\n\r\t' '   ' | sed 's/\\n/ /g; s/  */ /g')

  st=$(state_of "$slug" "$role")
  WS=$(ws_of "$slug"); SID=$(surface_of "$WS" "$role")   # see the note in the launch branch
  case "$st" in
    absent) die "no tab '$role' for '$slug'" ;;
    shell)  die "tab '$role' is not running Claude; a message sent here would run as a shell command. Run: $0 launch $slug $role" ;;
    dialog) press escape; sleep 1 ;;
  esac

  cmux send --workspace "$WS" --surface "$SID" -- "$msg" >/dev/null || die "send failed"

  # Send Enter SEPARATELY from the content: when both go in one paste, the TUI can treat the
  # final character as a newline inside the input box rather than as submit.
  for attempt in 1 2 3; do
    press enter
    sleep 1
    now=$(classify "$(screen_of "$WS" "$SID")")
    case "$now" in
      running|idle) echo "-> $role: delivered ($now, attempt $attempt)"; exit 0 ;;
      dialog)       press escape; sleep 1 ;;
    esac
  done

  echo "! $role: sent, but the screen still reads '$now'. It may not have submitted; check the tab yourself." >&2
  exit 2
  ;;

unstick)
  slug=${1:-}; [ -n "$slug" ] || die "usage: unstick <slug> [role]"
  n=0
  for r in ${2:-$ROLES_DEFAULT}; do
    st=$(state_of "$slug" "$r")
    case "$st" in
      stuck)  press enter;  echo "$r: stuck -> pressed Enter";   n=$((n+1)) ;;
      dialog) press escape; echo "$r: dialog -> pressed Escape"; n=$((n+1)) ;;
    esac
  done
  [ $n -eq 0 ] && echo "no stuck tabs."
  ;;

*)
  sed -n '2,20p' "$0" >&2
  exit 1
  ;;
esac

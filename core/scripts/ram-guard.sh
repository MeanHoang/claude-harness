#!/usr/bin/env bash
# Warn before opening one more parallel session, based on this machine's REAL memory history.
#
# Why: on 2026-08-17 at 10:36 macOS fired jetsam (the OOM killer) —
# /Library/Logs/DiagnosticReports/JetsamEvent-*.ips. A cmux session vanished mid-run leaving no
# crash report at all, so from cmux it looked like "cmux keeps dying".
#
# It sets NO percentage threshold of its own. The threshold comes straight from the last time
# THIS machine actually ran out: read the compressor size recorded in the newest JetsamEvent and
# compare it against the current compressor. Never had a jetsam? Then there is nothing to compare
# against, so it stays quiet rather than inventing a number.
#
# Usage:  ram-guard.sh          print a warning if things are dangerous (always exits 0)
#         ram-guard.sh --strict exit 1 when dangerous, to block opening a new tab

set -uo pipefail
STRICT=0; [ "${1:-}" = "--strict" ] && STRICT=1

PAGE=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
gb() { awk -v p="$1" -v s="$PAGE" 'BEGIN{printf "%.1f", p*s/1073741824}'; }

now_comp=$(vm_stat 2>/dev/null | awk -F': *' '/Pages occupied by compressor/{gsub(/\./,"",$2); print $2}')
[ -n "${now_comp:-}" ] || exit 0

# compressor level at the moment this machine actually hit OOM
last=$(ls -t /Library/Logs/DiagnosticReports/JetsamEvent-*.ips 2>/dev/null | head -1)
kill_comp=""; one_session=""
if [ -n "$last" ] && [ -r "$last" ]; then
  # Two numbers, both measured rather than estimated:
  #   kill_comp   - the compressor size when the machine actually died
  #   one_session - how heavy one claude process was, measured at that same moment
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
    echo "⚠️  RAM at $level% (kern.memorystatus_level). No JetsamEvent on record to compare against; keep an eye on it."
  exit 0
fi

# Both marks below are measurements, not chosen values:
#   - already past the level that once caused an OOM        -> block
#   - one MORE Claude session would reach that level        -> warn, because opening
#     another session is exactly what is about to happen
if [ "$now_comp" -ge "$kill_comp" ]; then
  echo "🛑 RAM: compressor $(gb "$now_comp")GB — PAST the level at which this machine hit OOM ($(gb "$kill_comp")GB, $(basename "$last")).${level:+ $level% left.}"
  echo "   Close some sessions or dev processes before opening another tab."
  [ "$STRICT" = 1 ] && exit 1
elif [ -n "$one_session" ] && [ "$one_session" -gt 0 ] \
     && [ $((now_comp + one_session)) -ge "$kill_comp" ]; then
  echo "⚠️  RAM: compressor $(gb "$now_comp")GB. One more Claude session ($(gb "$one_session")GB, measured at the OOM) would reach the level that died ($(gb "$kill_comp")GB).${level:+ $level% left.}"
fi
exit 0

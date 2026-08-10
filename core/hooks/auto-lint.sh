#!/usr/bin/env bash
# PostToolUse(Write|Edit): eslint --fix the edited file, but ONLY keep fixes that land
# on lines this branch actually changed.
#
# Ratchet trace: "check xem có vài diff bị sửa do eslint bạn chạy đấy" — a whole-file
# --fix reformats untouched legacy lines, which buries the real change in review noise.
#
# Monorepo: per-package .eslintrc.js, and eslint v6 resolves plugins from CWD,
# so run eslint FROM the nearest eslintrc dir (mirrors the repo's `--prefix` pattern).
# Non-blocking by contract: always exits 0, never fails the tool call.

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -n "$f" ] && [ -f "$f" ] || exit 0

case "$f" in
  *.js|*.jsx|*.ts|*.tsx) ;;
  *) exit 0 ;;
esac

root=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Walk up from the file to the nearest eslintrc, stopping at the repo root.
dir=$(dirname "$f")
cfg=""
while :; do
  for rc in .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc; do
    if [ -f "$dir/$rc" ]; then cfg="$dir"; break 2; fi
  done
  [ "$dir" = "$root" ] && break
  parent=$(dirname "$dir"); [ "$parent" = "$dir" ] && break; dir="$parent"
done
[ -n "$cfg" ] || exit 0

bin="$root/node_modules/.bin/eslint"
[ -x "$bin" ] || exit 0

# Line ranges changed vs HEAD, as `start:end` on the CURRENT file. An untracked or
# brand-new file has no HEAD side — every line is ours, so lint it whole.
ranges=$(git -C "$root" diff -U0 HEAD -- "$f" 2>/dev/null \
  | awk '/^@@/ { split($3, a, ","); s = substr(a[1], 2); n = (a[2] == "" ? 1 : a[2]); if (n > 0) print s ":" s + n - 1 }')

if ! git -C "$root" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
  ( cd "$cfg" && "$bin" --fix "$f" ) >/dev/null 2>&1
  exit 0
fi

# Tracked but unchanged vs HEAD — nothing of ours to lint.
[ -n "$ranges" ] || exit 0

before=$(mktemp) || exit 0
trap 'rm -f "$before"' EXIT
cp "$f" "$before" || exit 0

( cd "$cfg" && "$bin" --fix "$f" ) >/dev/null 2>&1
cmp -s "$before" "$f" && exit 0

# Keep only the edits whose pre-lint lines fall inside a changed range; restore the
# rest from the snapshot. Line-level diff, so no patch-offset math to get wrong.
RANGES="$ranges" python3 - "$before" "$f" <<'PY' 2>/dev/null || cp "$before" "$f"
import difflib, os, sys

before_path, after_path = sys.argv[1], sys.argv[2]
ranges = [tuple(int(x) for x in r.split(":")) for r in os.environ["RANGES"].split()]


def is_ours(start, end):
    """start/end are 1-based inclusive lines in the pre-lint file."""
    return any(start <= hi and lo <= end for lo, hi in ranges)


with open(before_path, encoding="utf-8") as fh:
    old = fh.readlines()
with open(after_path, encoding="utf-8") as fh:
    new = fh.readlines()

out = []
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new).get_opcodes():
    if tag == "equal":
        out.extend(old[i1:i2])
        continue
    # A same-length replace is the usual formatting fix (quotes, semicolons, spacing).
    # Decide per line — difflib merges adjacent changed lines into one opcode, so a
    # block-level decision would let one in-range line drag the whole block along.
    if tag == "replace" and i2 - i1 == j2 - j1:
        for k in range(i2 - i1):
            line = i1 + k + 1
            out.append(new[j1 + k] if is_ours(line, line) else old[i1 + k])
        continue
    # A pure insertion is zero-length in `old`; anchor it to the surrounding lines.
    start, end = (i1 + 1, i2) if i2 > i1 else (i1, i1 + 1)
    out.extend(new[j1:j2] if is_ours(start, end) else old[i1:i2])

with open(after_path, "w", encoding="utf-8") as fh:
    fh.writelines(out)
PY

exit 0

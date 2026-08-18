#!/usr/bin/env bash
# Shrink an image before it enters the context. ALWAYS run this before you Read a screenshot.
#
#   .claude/scripts/shot.sh <image.png> [max-width]     # default 1000
#   -> prints the path of the compressed .jpg; Read that file instead
#
# Why: images enter the context as base64. Measured 2026-08-06 across a full session history:
# 23 MB of 53 MB of tool results were IMAGES, 44% of the total, about 6.15 million tokens. One
# full-page 600 KB PNG screenshot is roughly 150k tokens, and it stays in the context for every
# turn that follows.
#
# Resizing to 1000px as JPEG cuts about 54%, 800px about 72%, and the text stays readable enough
# to judge a layout. Read the original PNG only when you need pixel-level detail (comparing a
# colour, a 1px offset), and only for that one look.

set -uo pipefail
SRC="${1:-}"
W="${2:-1000}"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "usage: $0 <image> [max-width]" >&2; exit 1; }

OUT="${SRC%.*}-w${W}.jpg"
sips -Z "$W" -s format jpeg -s formatOptions 65 "$SRC" --out "$OUT" >/dev/null 2>&1 \
  || { echo "sips failed, using the original: $SRC" >&2; echo "$SRC"; exit 0; }

o=$(( $(wc -c < "$SRC") / 1024 ))
n=$(( $(wc -c < "$OUT") / 1024 ))
printf '%s\n' "$OUT"
# base64 inflates by 4/3, then ~4 chars = 1 token  =>  bytes saved x 4/3 / 4 = bytes / 3
printf '  %s KB -> %s KB (%s%% smaller, ~%sk tokens saved)\n' \
  "$o" "$n" "$(( o > 0 ? 100 - n*100/o : 0 ))" "$(( (o-n)*1024/3/1000 ))" >&2

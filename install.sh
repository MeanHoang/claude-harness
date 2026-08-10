#!/usr/bin/env bash
# Paste this harness into a project's .claude/
#
#   ./install.sh <target-project> [core|all] [--link]
#
#   core   (default) portable layer: feature-team, feature-open, ship-board, bug-check,
#                    the generic hooks and scripts. Works in ANY repo.
#   all              everything this package ships (same as core today; the product-specific
#                    layer is deliberately NOT distributed here).
#   --link           symlink instead of copying, for when you want edits in the project
#                    to flow straight back into this repo.
#
# Default is COPY: the harness is a package you paste into a project, and each project
# is then free to diverge. Nothing in the target is ever destroyed. Any pre-existing
# real file is renamed to *.bak.<timestamp> first.

set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="" ; LAYER="core" ; MODE="copy"

for a in "$@"; do
  case "$a" in
    --link) MODE="link" ;;
    core|all) LAYER="$a" ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) [ -z "$TARGET" ] && TARGET="$a" || { echo "unexpected argument: $a" >&2; exit 1; } ;;
  esac
done

[ -n "$TARGET" ] || { echo "usage: $0 <target-project> [core|all] [--link]" >&2; exit 1; }
[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 1; }

DEST="$TARGET/.claude"
placed=0 ; backed_up=0

put() {  # put <source> <dest>
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  if [ -L "$dst" ]; then
    rm "$dst"                                       # our own symlink from a previous run
  elif [ -e "$dst" ]; then
    mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"      # a real file: never destroy it
    backed_up=$((backed_up + 1))
  fi
  if [ "$MODE" = link ]; then ln -s "$src" "$dst"; else cp -R "$src" "$dst"; fi
  placed=$((placed + 1))
}

install_layer() {  # install_layer <core|product>
  local L="$1"
  [ -d "$HARNESS/$L" ] || return 0
  for kind in skills hooks scripts commands agents; do
    [ -d "$HARNESS/$L/$kind" ] || continue
    mkdir -p "$DEST/$kind"
    for item in "$HARNESS/$L/$kind"/*; do
      [ -e "$item" ] || continue
      put "$item" "$DEST/$kind/$(basename "$item")"
    done
  done
}

mkdir -p "$DEST"/{skills,hooks,scripts}
install_layer core
[ "$LAYER" = all ] && install_layer product
chmod +x "$DEST"/scripts/*.sh "$DEST"/hooks/*.sh 2>/dev/null

echo "harness: $HARNESS"
echo "target:  $DEST"
echo "mode:    $MODE (layer: $LAYER)"
echo "placed:  $placed   backed up (pre-existing real files): $backed_up"
echo
echo "Next:"
echo "  1. Wire the hooks in $DEST/settings.json — settings are never overwritten,"
echo "     because they carry per-project permissions."
echo "  2. If this project needs extra files present in every worktree, list them in"
echo "     $DEST/harness-required.txt (one path per line)."
echo "  3. Read harness-book.html for the workflow and the cmux traps."

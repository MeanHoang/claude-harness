#!/usr/bin/env bash
# Equip a freshly created git worktree with the harness.
#
# Why: `git worktree add` checks out TRACKED files only, and most of a harness is typically
# untracked (skills including ship, local hooks, settings.local.json, .claude/ship). A session
# running in a bare worktree has no pipeline, no gates, and gets the HEAD version of auto-lint
# that reformats whole files. That is an agent running under NO RULES.
#
# Usage:
#   git worktree add ~/cmux/worktrees/<repo>/<slug> -b <type>/<slug>
#   .claude/scripts/bootstrap-worktree.sh ~/cmux/worktrees/<repo>/<slug>
#
# Mechanism: symlink whatever is shared (edit it in main and every worktree has it at once),
# copy whatever each worktree needs its own copy of (.env, auto-lint.sh).

set -uo pipefail

WT="${1:-}"
if [ -z "$WT" ]; then
  echo "usage: $0 <worktree-path>" >&2
  exit 1
fi
WT=$(cd "$WT" 2>/dev/null && pwd) || { echo "no such worktree: ${1}" >&2; exit 1; }

MAIN=$(git -C "$WT" worktree list --porcelain | awk '/^worktree /{print $2; exit}')
[ -d "$MAIN" ] || { echo "could not determine the main checkout" >&2; exit 1; }
[ "$MAIN" = "$WT" ] && { echo "this is the main checkout; nothing to bootstrap" >&2; exit 1; }

ok=0; skip=0
link() {  # link <relative-path>
  local rel=$1 src="$MAIN/$1" dst="$WT/$1"
  [ -e "$src" ] || { skip=$((skip+1)); return; }
  [ -e "$dst" ] && [ ! -L "$dst" ] && { echo "  CONFLICT (already exists, skipped): $rel"; skip=$((skip+1)); return; }
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  echo "  link  $rel"
  ok=$((ok+1))
}

echo "main:     $MAIN"
echo "worktree: $WT"
echo

# --- 1. Local hooks (untracked in main -> absent from the worktree) ---
echo "[1] local hooks"
for h in "$MAIN"/.claude/hooks/*.sh; do
  rel=".claude/hooks/$(basename "$h")"
  git -C "$MAIN" ls-files --error-unmatch "$rel" >/dev/null 2>&1 || link "$rel"
done

# --- 2. Hook wiring + permissions ---
echo "[2] settings.local.json"
link ".claude/settings.local.json"

# --- 3. Untracked skills (ship, analyze-task, ...) ---
echo "[3] untracked skills"
for d in "$MAIN"/.claude/skills/*/; do
  rel=".claude/skills/$(basename "$d")"
  git -C "$MAIN" ls-files --error-unmatch "$rel" >/dev/null 2>&1 || link "$rel"
done

# --- 3b. Untracked scripts (cmux-say.sh, ram-guard.sh, ship-board.sh, ...) ---
# Role templates call "$(git rev-parse --show-toplevel)/.claude/scripts/cmux-say.sh". Without it
# every call from one role to another fails silently.
echo "[3b] untracked scripts"
for s in "$MAIN"/.claude/scripts/*; do
  rel=".claude/scripts/$(basename "$s")"
  git -C "$MAIN" ls-files --error-unmatch "$rel" >/dev/null 2>&1 || link "$rel"
done

# --- 3c. Untracked data + commands (.claude/surfaces, .claude/commands) ---
# surfaces/ is DATA a skill reads (surface-audit's inventory), not a skill itself, so loop [3]
# above does not catch it.
echo "[3c] untracked surfaces + commands"
link ".claude/surfaces"
for c in "$MAIN"/.claude/commands/*.md; do
  rel=".claude/commands/$(basename "$c")"
  git -C "$MAIN" ls-files --error-unmatch "$rel" >/dev/null 2>&1 || link "$rel"
done

# --- 4. Pipeline state (the parent must see across every feature -> one shared location) ---
echo "[4] .claude/ship (shared with main)"
link ".claude/ship"

# --- 5. auto-lint.sh: the local version is skip-worktree'd, so a worktree gets the HEAD version
#        that lints whole files. COPY over it and skip-worktree it inside this worktree. ---
echo "[5] auto-lint.sh (copy over the changed-lines-only version)"
if grep -q "difflib" "$MAIN/.claude/hooks/auto-lint.sh" 2>/dev/null; then
  cp "$MAIN/.claude/hooks/auto-lint.sh" "$WT/.claude/hooks/auto-lint.sh"
  git -C "$WT" update-index --skip-worktree .claude/hooks/auto-lint.sh 2>/dev/null \
    && echo "  copy + skip-worktree  .claude/hooks/auto-lint.sh" && ok=$((ok+1))
else
  echo "  ! auto-lint.sh in main is NOT the range-limited version, skipping"
  skip=$((skip+1))
fi

# --- 5b. node_modules + .shopify: SYMLINK from main ---
# Without them the worktree cannot run the package manager or a deploy, which forces you back to
# the main checkout, whose branch this very worktree is holding. That circle ends with deleting
# the worktree just to deploy by hand. Symlinks cut it.
# Symlink rather than copy is mandatory: the root node_modules alone is 3.5 GB.
echo "[5b] node_modules + .shopify (symlink, so the worktree stops depending on main)"
link_nm() {
  local rel=$1 src="$MAIN/$1" dst="$WT/$1"
  [ -d "$src" ] || return
  [ -e "$dst" ] && [ ! -L "$dst" ] && return      # the worktree installed its own; leave it
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
}
nm=0
for d in "$MAIN"/node_modules "$MAIN"/packages/*/node_modules "$MAIN"/extensions/*/node_modules; do
  [ -d "$d" ] || continue
  link_nm "${d#"$MAIN"/}" && nm=$((nm+1))
done
echo "  link  $nm × node_modules (root + packages + extensions)"
ok=$((ok+nm))
# .shopify holds project.json (which app/tenant this repo deploys to), the localhost cert and
# the deploy cache. Without it a deploy does not know which app it belongs to.
if [ -d "$MAIN/.shopify" ] && { [ ! -e "$WT/.shopify" ] || [ -L "$WT/.shopify" ]; }; then
  ln -sfn "$MAIN/.shopify" "$WT/.shopify"
  echo "  link  .shopify"
  ok=$((ok+1))
fi

# --- 6. env files listed in .worktreeinclude (git worktree add does not copy them; that is a
#        `claude -w` feature, and this workflow creates its worktrees by hand) ---
echo "[6] env files per .worktreeinclude"
if [ -f "$MAIN/.worktreeinclude" ]; then
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue ;; esac
    for src in "$MAIN"/$pat; do
      [ -f "$src" ] || continue
      rel=${src#"$MAIN"/}
      mkdir -p "$WT/$(dirname "$rel")"
      cp "$src" "$WT/$rel" && echo "  copy  $rel" && ok=$((ok+1))
    done
  done < "$MAIN/.worktreeinclude"
else
  echo "  (no .worktreeinclude)"
fi

# --- Verify: what MUST be present ---
echo
echo "[verify]"
fail=0
must=(
  ".claude/hooks/readonly-intent-guard.sh"
  ".claude/hooks/branch-guard.sh"
  ".claude/scripts/cmux-say.sh"
  ".claude/settings.local.json"
)
# A project needing more lists it in .claude/harness-required.txt, one path per line. That keeps
# any one repo's skill names out of this shared script.
if [ -f "$MAIN/.claude/harness-required.txt" ]; then
  while IFS= read -r extra; do
    case "$extra" in ''|\#*) continue ;; esac
    must+=("$extra")
  done < "$MAIN/.claude/harness-required.txt"
fi
for m in "${must[@]}"; do
  if [ -e "$WT/$m" ]; then echo "  OK  $m"; else echo "  !!  MISSING $m"; fail=1; fi
done
if grep -q "difflib" "$WT/.claude/hooks/auto-lint.sh" 2>/dev/null; then
  echo "  OK  auto-lint.sh (changed-lines-only version)"
else
  echo "  !!  auto-lint.sh is still the whole-file version"; fail=1
fi

echo
echo "done: $ok items, $skip skipped"
[ $fail -eq 0 ] || { echo "STOP: this worktree is missing part of the harness. Do not run a session here."; exit 1; }
echo "OK: worktree fully equipped"

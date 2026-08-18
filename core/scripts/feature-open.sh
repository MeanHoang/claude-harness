#!/usr/bin/env bash
# Open a feature to run in parallel: worktree + harness + its own cmux workspace + one tab per role.
#
#   .claude/scripts/feature-open.sh <slug> [task-url] [type]
#
# type defaults to `feature`; use `bugfix`/`chore`/`improve` where they fit better.
#
# Result: a cmux workspace named <slug>, containing
#   the original tab = an empty shell (for running git/tests by hand)
#   scout            = running: reads the task, verifies it, writes the plan
#   coder / research / reviewer / ux / checker = tabs ready but not started (waiting their turn)
#
# The parent does NOT live here. It sits in the workspace of the main checkout, {{PROJECT_ROOT}}.

set -uo pipefail
export CMUX_QUIET=1

# --main = work directly in the main checkout, creating NO worktree.
# Use it when the task needs the local dev stack, which runs from the main checkout; a separate
# worktree would have to rebuild all of node_modules and its tunnel. It is also the way out when
# the branch is already held by the main checkout (git allows one worktree per branch).
MAIN_MODE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --main|--no-worktree) MAIN_MODE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]:-}"

SLUG="${1:-}"
NOTION="${2:-}"
TYPE="${3:-feature}"
[ -n "$SLUG" ] || { echo "usage: $0 [--main] <slug> [task-url] [feature|bugfix|chore|improve]" >&2; exit 1; }

MAIN=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repo" >&2; exit 1; }
REPO=$(basename "$MAIN")
BRANCH="$TYPE/$SLUG"
SHIP="$MAIN/.claude/ship/$SLUG"
if [ "$MAIN_MODE" = "1" ]; then WT="$MAIN"; else WT="$HOME/cmux/worktrees/$REPO/$SLUG"; fi

step(){ printf "\n\033[1m%s\033[0m\n" "$*"; }

# --- 0. RAM ---
# Opening another feature means at least one more Claude session. On 2026-08-17 jetsam (the OOM
# killer) took a process down mid-run leaving no crash report at all, so from cmux it just looked
# like "the session died on its own". Blocking here is far cheaper than losing work in progress.
if [ -x "$MAIN/.claude/scripts/ram-guard.sh" ]; then
  "$MAIN/.claude/scripts/ram-guard.sh" --strict || {
    echo "   Stopping. Close some sessions or shut down some dev processes, then try again." >&2
    exit 1
  }
fi

# --- 1. worktree ---
step "[1/6] worktree"
if [ "$MAIN_MODE" = "1" ]; then
  cur=$(git -C "$MAIN" branch --show-current)
  echo "  --main MODE: working directly in the main checkout, no worktree"
  echo "  $MAIN  (current branch: $cur)"
  if [ "$cur" != "$BRANCH" ]; then
    echo "  ! current branch is NOT '$BRANCH'; check out the right branch before coding:"
    echo "      git checkout $BRANCH    (or git checkout -b $BRANCH)"
  fi
elif [ -d "$WT" ]; then
  echo "  exists: $WT"
else
  mkdir -p "$(dirname "$WT")"
  # Is the branch already checked out somewhere? git allows ONE worktree per branch.
  HOLDER=$(git -C "$MAIN" worktree list --porcelain \
           | awk -v b="refs/heads/$BRANCH" '/^worktree /{w=$2} $0=="branch "b{print w; exit}')
  if [ -n "$HOLDER" ]; then
    echo "  STOP: branch '$BRANCH' is held by: $HOLDER"
    echo "     git will not let two worktrees hold one branch. Pick one:"
    if [ "$HOLDER" = "$MAIN" ]; then
      echo "       - Re-run with --main to work in the main checkout (local testing works there):"
      echo "           $0 --main $SLUG"
    else
      echo "       - Do this task there instead: point the cmux workspace at $HOLDER"
    fi
    echo "       - Or release the branch (check out something else there) and re-run this"
    exit 1
  fi
  # Branch exists but nobody holds it -> attach to it; -b would fail with "already exists".
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$MAIN" worktree add "$WT" "$BRANCH" 2>&1 | tail -1 || exit 1
    echo "  created: $WT  (attached to existing branch $BRANCH)"
  else
    git -C "$MAIN" worktree add "$WT" -b "$BRANCH" 2>&1 | tail -1 || exit 1
    echo "  created: $WT  (new branch $BRANCH)"
  fi
fi

# --- 2. harness (mandatory: a bare worktree has no pipeline and no gates) ---
step "[2/6] equip the harness"
if [ "$MAIN_MODE" = "1" ]; then
  echo "  skipped: the main checkout IS the source of the harness"
else
"$MAIN/.claude/scripts/bootstrap-worktree.sh" "$WT" >/tmp/bootstrap-$SLUG.log 2>&1
if [ $? -ne 0 ]; then
  echo "  STOP: bootstrap FAILED. Do not open a session. See /tmp/bootstrap-$SLUG.log"
  tail -12 "/tmp/bootstrap-$SLUG.log"
  exit 1
fi
echo "  OK $(grep -c '^  link\|^  copy' /tmp/bootstrap-$SLUG.log) items, verify green"
fi

# --- 3. pipeline state ---
step "[3/6] progress.md"
mkdir -p "$SHIP"
if [ -f "$SHIP/progress.md" ]; then
  if grep -q "<!-- state" "$SHIP/progress.md"; then
    echo "  exists: $SHIP/progress.md"
  else
    # An older task, from before the state block existed. Without it ship-board skips the task
    # and the workspace goes uncoloured, which reads as broken. Prepend the block, keep the body.
    tmp=$(mktemp)
    {
      printf '<!-- state\nkind: feature\nslug: %s\nbranch: %s\nworktree: %s\nstep: 0\nphase: -\nawaiting: scout\nround: 0\ngate: none\nverdict: -\n-->\n\n' \
        "$SLUG" "$BRANCH" "$WT"
      cat "$SHIP/progress.md"
    } > "$tmp" && mv "$tmp" "$SHIP/progress.md"
    echo "  existed (old format) -> state block inserted so it appears on ship-board"
  fi
else
  sed -e "s|{{slug}}|$SLUG|g" -e "s|{{branch}}|$BRANCH|g" -e "s|{{worktree_path}}|$WT|g" \
      -e "s|{{title}}|$SLUG|g" -e "s|{{notion_url}}|${NOTION:-—}|g" \
      "$MAIN/.claude/skills/feature-team/templates/progress-header.md" > "$SHIP/progress.md"
  echo "  created: $SHIP/progress.md"
fi

# --- 4. a cmux workspace of its own for this feature ---
step "[4/6] workspace cmux"
if ! cmux ping >/dev/null 2>&1; then
  echo "  ! cmux is not running. The worktree is ready; open the session by hand:"
  echo "    cd $WT && claude"
  exit 0
fi
# REUSE a workspace of the same name; otherwise you end up with two identically named ones
WS=$(cmux workspace list 2>/dev/null | awk -v s="$SLUG" '$2==s{print $1; exit} $3==s{print $2; exit}')
if [ -n "$WS" ]; then
  echo "  exists: $WS  ($SLUG) - reusing, not creating another"
  REUSED=1
else
  WS=$(cmux new-workspace --name "$SLUG" --description "$TYPE · $BRANCH" --cwd "$WT" --focus false 2>&1 | awk '/^OK/{print $2}')
  [ -n "$WS" ] || { echo "  STOP: could not create the workspace" >&2; exit 1; }
  echo "  created: $WS  ($SLUG)"
  REUSED=0
fi

# --- 5. one tab per role. A newly created tab is ALWAYS at index 1, so rename it immediately. ---
step "[5/6] tabs per role"
if [ "${REUSED:-0}" = "1" ]; then
  echo "  the existing workspace already has tabs, leaving them alone:"
  cmux list-pane-surfaces --workspace "$WS" 2>/dev/null | sed 's/^/    /'
  SCOUT_SURFACE=$(cmux list-pane-surfaces --workspace "$WS" 2>/dev/null | awk '/ scout$/{print $1; exit}' | tr -d '*')
else
SCOUT_SURFACE=""
# Create in reverse order so scout ends up right after the original tab.
# ux is only used by phases with an interface; the tab is opened anyway and stays empty on
# backend-only phases.
for role in checker ux reviewer research coder scout; do
  sid=$(cmux new-surface --type terminal --workspace "$WS" --focus false 2>&1 | awk '/^OK/{print $2}')
  cmux rename-tab --workspace "$WS" --tab 1 "$role" >/dev/null 2>&1
  [ "$role" = "scout" ] && SCOUT_SURFACE="$sid"
  echo "  tab:  $role  ($sid)"
done
fi

step "[6/6] kickoff per role"
# --- A kickoff for EACH role, including the address table they need to call each other ---
# The kickoff teaches how to LOOK UP an address by role name. It never hardcodes an id, because
# cmux renumbers after every workspace close/open. (2026-08-05: a session merely wrote "handed
# this to X" in its report and then sat waiting for a reply that could never come.)
TPL="$MAIN/.claude/skills/feature-team/templates"
for r in scout coder research reviewer ux checker; do
  K="$SHIP/kickoff-$r.md"
  [ -f "$K" ] && continue
  [ -f "$TPL/role-$r.md" ] || continue
  python3 - "$TPL/role-$r.md" "$K" "$SLUG" "$WT" "$BRANCH" "${NOTION:-(no link yet - ask the user)}" <<'PYEOF'
import sys
src, dst, slug, wt, branch, notion = sys.argv[1:7]
t = open(src, encoding="utf-8").read()
for k, v in {"{{slug}}": slug, "{{worktree_path}}": wt, "{{branch}}": branch,
             "{{notion_url}}": notion,
             "{{base_ref}}": "origin/master"}.items():
    t = t.replace(k, v)
open(dst, "w", encoding="utf-8").write(t)
PYEOF
  echo "  kickoff: $r"
done
KICK="$SHIP/kickoff-scout.md"

cat <<EOF

────────────────────────────────────────────────────────────
Done. Workspace "$SLUG" has 6 tabs: scout · coder · research · reviewer · ux · checker

One thing is left to do by hand: fill in the research section of the scout's kickoff
  $KICK
(a child session has no memory of this conversation; whatever you do not write down is gone)

Then start the scout:
  .claude/scripts/cmux-say.sh launch $SLUG scout

  (the script presses Enter itself, dismisses the "New MCP server found" prompt that otherwise
   swallows the kickoff, and re-reads the screen to confirm Claude really started)

  (verified 2026-08-05: hooks STILL fire in bypass mode. A child session skips the permission
   prompt, but the readonly / branch / lint guards continue to bind it)

All tabs:  cmux list-pane-surfaces --workspace $WS
State:     .claude/scripts/cmux-say.sh status $SLUG
Watch:     .claude/scripts/ship-board.sh
────────────────────────────────────────────────────────────
EOF

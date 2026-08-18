#!/usr/bin/env bash
# A table of every running feature, with whatever is WAITING ON YOU sorted to the top.
#
# Why: each task has its own progress.md, so finding out what needs you means opening every file
# in turn. Once several features run in parallel the bottleneck is the user, so the first thing
# to show is "what is waiting on me", not "what is running".
#
# Reads the `<!-- state ... -->` block at the top of progress.md
# (feature-team/templates/progress-header.md). Older tasks without that block still appear, with
# their state columns showing "-".
#
# Flag: --unstick  press Enter/Escape for stuck tabs (by default it only REPORTS, touching nothing).

set -uo pipefail
UNSTICK=0; [ "${1:-}" = "--unstick" ] && UNSTICK=1
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repo" >&2; exit 1; }

# RAM first: a session vanishing mid-run is almost always the OOM killer, not a cmux fault.
[ -x "$ROOT/.claude/scripts/ram-guard.sh" ] && "$ROOT/.claude/scripts/ram-guard.sh"

python3 - "$ROOT" <<'PY'
import glob, os, re, subprocess, sys

root = sys.argv[1]
rows = []
# Current repo name. Every task's worktree lives at ~/cmux/worktrees/<repo>/<slug>, so derive it
# here instead of hardcoding, and the script runs in any project.
_repo = os.path.basename(os.path.abspath(root))

for p in sorted(glob.glob(os.path.join(root, ".claude/ship/*/progress.md"))):
    slug = os.path.basename(os.path.dirname(p))
    txt = open(p, encoding="utf-8", errors="replace").read()
    head = txt[:1200]

    def field(name, default="—"):
        m = re.search(rf"^\s*{name}:\s*(.+?)\s*$", head, re.M)
        return m.group(1) if m else default

    has_state = "<!-- state" in head
    branch = field("branch")
    if branch == "—":                       # older task: read it from the "- Branch: `...`" line
        m = re.search(r"Branch:\s*`([^`]+)`", txt)
        branch = m.group(1) if m else "—"

    gate = field("gate", "none") if has_state else "—"
    awaiting = field("awaiting") if has_state else "—"
    step = field("step") if has_state else "—"
    phase = field("phase") if has_state else "—"
    rnd = field("round", "0") if has_state else "—"
    kind = field("kind", "feature") if has_state else "—"
    verdict = field("verdict", "-") if has_state else "-"

    # NOW marker: the human-readable line, truncated
    m = re.search(r"^>\s*\*\*NOW:?\*\*:?\s*(.+)$", txt, re.M)
    now = (m.group(1).strip() if m else "")[:70]

    done = txt.count("✅")
    todo = txt.count("⬜")

    # Age and size of the child session. A session alive too long means a bloated context,
    # slow and expensive, still running against the kickoff it was BORN with and blind to any
    # rule added since.
    age_h, sess_mb, resume_id = None, 0, ""
    # Claude names its project directory after the absolute path, with "/" replaced by "-".
    _wt = os.path.expanduser("~/cmux/worktrees/%s/%s" % (_repo, slug))
    pdir = os.path.expanduser("~/.claude/projects/" + _wt.replace("/", "-"))
    if os.path.isdir(pdir):
        import glob as _g
        # The id for `claude --resume`: the most recently written transcript.
        # Shutting down loses the session and cmux restores only the layout, so without this id
        # you spend the next morning digging through ~/.claude/projects.
        js = _g.glob(pdir + "/*.jsonl")
        if js:
            resume_id = os.path.basename(max(js, key=os.path.getmtime))[:-6]
        for jf in js:
            mb = os.path.getsize(jf) / 1024 / 1024
            if mb < 0.5:            # ignore the tiny child sessions a skill spawns
                continue
            sess_mb = max(sess_mb, mb)
            try:
                import json as _j, datetime as _d
                with open(jf, errors="replace") as fh:
                    for i, line in enumerate(fh):
                        if i > 400:            # the timestamp is not on the very first line
                            break
                        if '"timestamp"' not in line:
                            continue
                        t = _j.loads(line).get("timestamp")
                        if not t:
                            continue
                        st = _d.datetime.fromisoformat(t.replace("Z", "+00:00"))
                        h = (_d.datetime.now(st.tzinfo) - st).total_seconds() / 3600
                        age_h = h if age_h is None else max(age_h, h)
                        break
            except Exception:
                pass

    rows.append(dict(slug=slug, branch=branch, gate=gate, awaiting=awaiting, kind=kind,
                     verdict=verdict, step=step, phase=phase, rnd=rnd, now=now,
                     done=done, todo=todo, age_h=age_h, sess_mb=sess_mb,
                     resume_id=resume_id))

# priority: waiting on the user > running > done
def rank(r):
    if r["gate"] not in ("none", "—"): return 0
    if r["awaiting"] == "user": return 0          # a bug with a verdict, waiting on the user
    if r["awaiting"] not in ("none", "—"): return 1
    return 2

rows.sort(key=lambda r: (rank(r), r["slug"]))

waiting = [r for r in rows if rank(r) == 0]
print()
if waiting:
    def why(r):
        if r["gate"] not in ("none", "—"): return r["gate"]
        if r["verdict"] not in ("-", "—"): return r["verdict"]
        return "waiting on you"
    print(f"⚠️  {len(waiting)} item(s) WAITING ON YOU: " + ", ".join(f"{r['slug']} ({why(r)})" for r in waiting))
else:
    print("✅ Nothing is waiting on you.")
print()

w = max([len(r["slug"]) for r in rows] + [7])
print(f"{'':2}{'ITEM'.ljust(w)}  {'KIND':8} {'GATE':9} {'AWAITING':9} {'VERDICT':13} {'STEP':6} {'SESSION':11} NOW")
print("─" * (w + 62))
for r in rows:
    mark = "🚦" if rank(r) == 0 else ("· " if rank(r) == 1 else "  ")
    step = r["step"] if r["phase"] in ("-", "—") else f"{r['step']}·{r['phase']}"
    if r["age_h"] is None:
        sess = "—"
    else:
        flag = "⚠" if (r["age_h"] > 12 or r["sess_mb"] > 5) else " "
        sess = f"{flag}{r['age_h']:.0f}h/{r['sess_mb']:.0f}MB"
    print(f"{mark}{r['slug'].ljust(w)}  {r['kind']:8} {r['gate']:9} {r['awaiting']:9} "
          f"{r['verdict']:13} {step:6} {sess:11} {r['now'][:52]}")

# Reviving a session after a shutdown.
# `cmux restore` re-runs the ORIGINAL argv (claude "$(cat kickoff)"), which starts over from
# nothing and loses the whole context. Only `claude --resume <id>` keeps it. The two commands are
# not interchangeable.
res = [r for r in rows if r["resume_id"] and rank(r) < 2]
if res:
    print("\n-- revive a session (after a shutdown / cmux restore) --")
    for r in res:
        print(f"  cd ~/cmux/worktrees/{_repo}/{r['slug']} && claude --resume {r['resume_id']}")

# hand off to the workspace-colouring step (write a temp file, bash reads it back)
with open("/tmp/ship-board-colors.txt", "w", encoding="utf-8") as fh:
    for r in rows:
        if r["gate"] == "—":            # older task with no state block -> leave it uncoloured
            continue
        fh.write(f"{r['slug']}\t{rank(r)}\t{r['rnd']}\n")

no_state = [r for r in rows if r["gate"] == "—"]
if no_state:
    print(f"\n({len(no_state)}/{len(rows)} task(s) have no `state` block, so only NOW is shown. Add the "
          f"header from feature-team/templates/progress-header.md to get the full row.)")
PY

echo
echo "-- open worktrees --"
git -C "$ROOT" worktree list

# -- Colour cmux workspaces by how much attention they need ------------------
# Each colour means one thing; none of this is decoration:
#   Crimson  waiting on your decision   (a gate is open, or a bug has a verdict)
#   Amber    about to need you          (coder<->reviewer hit 3 rounds, the kill rule)
#   Blue     running normally
#   Charcoal finished or idle
# Only workspaces whose NAME MATCHES a slug are touched; your other workspaces are left alone.
[ -f /tmp/ship-board-colors.txt ] || exit 0
cmux ping >/dev/null 2>&1 || exit 0

export CMUX_QUIET=1
painted=0
while IFS=$'\t' read -r slug rank rnd; do
  ws=$(cmux workspace list 2>/dev/null | awk -v s="$slug" '$0 ~ ("[ *] *workspace:[0-9]+ +" s "$"){print $1; exit} {if ($2==s) print $1}' | head -1)
  [ -n "$ws" ] || continue
  case "$rank" in
    0) color=Crimson ;;
    1) [ "${rnd:-0}" -ge 3 ] 2>/dev/null && color=Amber || color=Blue ;;
    *) color=Charcoal ;;
  esac
  cmux workspace-action --action set-color --workspace "$ws" --color "$color" >/dev/null 2>&1 && painted=$((painted+1))
done < /tmp/ship-board-colors.txt
[ "$painted" -gt 0 ] && echo "-- coloured $painted workspace(s) by state --"

# -- Which tabs are STUCK ----------------------------------------------------
# A state progress.md cannot show: a message typed into the input box but never submitted, or a
# dialog swallowing keystrokes. Both sides then wait on each other and neither reports anything.
SAY="$ROOT/.claude/scripts/cmux-say.sh"
if [ -x "$SAY" ]; then
  stuck_found=0
  while IFS=$'\t' read -r slug _rank _rnd; do
    out=$("$SAY" status "$slug" 2>/dev/null | grep -E "stuck|dialog") || continue
    [ -n "$out" ] || continue
    [ "$stuck_found" = 0 ] && echo && echo "-- stuck tabs (unsubmitted / blocked by a dialog) --"
    stuck_found=1
    echo "  $slug:"; sed 's/^/    /' <<<"$out"
  done < /tmp/ship-board-colors.txt

  if [ "$stuck_found" = 1 ]; then
    if [ "$UNSTICK" = 1 ]; then
      echo "  -> unstick:"
      while IFS=$'\t' read -r slug _r _n; do "$SAY" unstick "$slug" 2>/dev/null | sed 's/^/    /'; done \
        < /tmp/ship-board-colors.txt
    else
      echo "  (re-run with --unstick to press Enter/Escape for them)"
    fi
  fi
fi
rm -f /tmp/ship-board-colors.txt

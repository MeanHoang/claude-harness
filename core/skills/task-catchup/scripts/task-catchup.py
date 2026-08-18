#!/usr/bin/env python3
"""
task-catchup — surface NEW activity you may have missed while heads-down.

Scans every task you're working on (all .claude/ship/*/progress.md) and reports
Notion comments + Slack messages from a recent time window (default 24h). No link
to paste; a fixed window means no "last seen" state to manage.

Usage:
  python3 task-catchup.py [--hours N] [--ship SLUG] [--json]

Env:
  NOTION_API_KEY     (required) Notion integration key (needs Read comments cap).
  SLACK_USER_TOKEN   (optional) xoxp user token with search:read for Slack search.
                     The bot SLACK_TOKEN cannot search (not_allowed_token_type).
"""

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode
from urllib.request import urlopen, Request
from urllib.error import HTTPError

# Auto-load .env.agent via the shared env_loader at .claude/scripts/.
# From here (.claude/skills/task-catchup/scripts/) that's ../../../scripts.
_script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_script_dir, "..", "..", "..", "scripts"))
from env_loader import load_env_debug
load_env_debug()

# macOS SSL fix.
try:
    import certifi
    os.environ.setdefault("SSL_CERT_FILE", certifi.where())
except ImportError:
    pass

NOTION_VERSION = "2026-03-11"
REPO_ROOT = os.path.abspath(os.path.join(_script_dir, "..", "..", "..", ".."))
SHIP_GLOB = os.path.join(REPO_ROOT, ".claude", "ship", "*", "progress.md")

# Stopwords stripped when deriving a Slack search keyword from a task title.
_STOP = {
    "the", "a", "an", "and", "or", "for", "to", "of", "in", "on", "do", "app",
    "khac", "khác", "tao", "tạo", "vao", "vào", "cho", "va", "và", "cua", "của",
    "widget", "task", "bug", "fix", "feature",
}


def run(hours, only_ship, as_json):
    """Report Notion + Slack activity within the window across all ship tasks."""
    # Step 1: resolve the time window.
    window_start = datetime.now(timezone.utc) - timedelta(hours=hours)

    # Step 2: discover tasks from ship progress docs.
    tasks = discover_tasks(only_ship)
    if not tasks:
        print("No ship tasks found under .claude/ship/*/progress.md", file=sys.stderr)
        sys.exit(1)

    # Step 3: gather activity per task.
    slack_token = os.environ.get("SLACK_USER_TOKEN")
    user_cache = {}
    for t in tasks:
        t["notion"] = notion_comments(t["page_id"], window_start, user_cache) if t["page_id"] else []
        t["slack"] = slack_messages(t, window_start, slack_token) if slack_token else []

    # Step 4: emit.
    if as_json:
        print(json.dumps({"hours": hours, "tasks": tasks}, ensure_ascii=False, indent=2, default=str))
        return
    print_report(tasks, hours, slack_token)


# === Task discovery ===

def discover_tasks(only_ship):
    """Read every ship progress.md into {slug, title, page_id, notion_url, keyword}."""
    tasks = []
    for path in sorted(glob.glob(SHIP_GLOB)):
        slug = os.path.basename(os.path.dirname(path))
        if only_ship and slug != only_ship:
            continue
        text = open(path, encoding="utf-8").read()
        tasks.append({
            "slug": slug,
            "title": first_heading(text) or slug,
            "notion_url": find_notion_url(text),
            "page_id": page_id_from(find_notion_url(text)),
            "keyword": slack_keyword(text, first_heading(text) or slug),
        })
    return tasks


def first_heading(text):
    m = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def find_notion_url(text):
    m = re.search(r"https?://(?:www\.)?(?:app\.)?notion\.[a-z.]+/\S+", text)
    return m.group(0).rstrip(").,") if m else None


def page_id_from(url):
    """Notion page id = the last 32-hex run in the URL, dashed to UUID form."""
    if not url:
        return None
    ids = re.findall(r"[0-9a-fA-F]{32}", url)
    if not ids:
        return None
    h = ids[-1].lower()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def slack_keyword(text, title):
    """Explicit `<!-- slack-keyword: ... -->` hint wins; else derive from title."""
    m = re.search(r"<!--\s*slack-keyword:\s*(.+?)\s*-->", text)
    if m:
        return m.group(1).strip()
    # Strip a leading "Foo —"/"Foo:" prefix, keep distinctive tokens.
    body = re.split(r"[—:]", title, maxsplit=1)[-1]
    toks = re.findall(r"[A-Za-zÀ-ỹ0-9]+", body)
    kept = [w for w in toks if w.lower() not in _STOP and len(w) > 1]
    return " ".join(kept[:3]) if kept else title


# === Notion ===

def notion_api(method, path, body=None):
    url = f"https://api.notion.com/v1{path}"
    data = json.dumps(body).encode() if body else None
    req = Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {_notion_key()}",
        "Notion-Version": NOTION_VERSION,
        "Content-Type": "application/json",
    })
    with urlopen(req) as resp:
        return json.loads(resp.read())


def _notion_key():
    key = os.environ.get("NOTION_API_KEY")
    if not key:
        print("Error: set NOTION_API_KEY in .env.agent", file=sys.stderr)
        sys.exit(1)
    return key


def notion_comments(page_id, window_start, user_cache):
    """Page-level comments created within the window, newest first."""
    try:
        res = notion_api("GET", f"/comments?{urlencode({'block_id': page_id, 'page_size': 100})}")
    except HTTPError as e:
        if e.code in (403, 404):
            return [{"_error": f"comments unavailable ({e.code}) — integration may lack Read comments"}]
        raise
    out = []
    for c in res.get("results", []):
        created = parse_iso(c.get("created_time"))
        if not created or created < window_start:
            continue
        out.append({
            "author": notion_user_name(c.get("created_by", {}).get("id"), user_cache),
            "created": created,
            "text": rich_text(c.get("rich_text", [])),
        })
    out.sort(key=lambda x: x["created"], reverse=True)
    return out


def notion_user_name(user_id, cache):
    if not user_id:
        return "someone"
    if user_id in cache:
        return cache[user_id]
    try:
        u = notion_api("GET", f"/users/{user_id}")
        name = u.get("name") or "someone"
    except HTTPError:
        name = "someone"
    cache[user_id] = name
    return name


def rich_text(parts):
    return "".join(p.get("plain_text", "") for p in parts).strip()


# === Slack ===

def slack_messages(task, window_start, token):
    """search.messages for the task keyword, filtered to the window."""
    after = (window_start - timedelta(days=1)).strftime("%Y-%m-%d")
    query = f'{task["keyword"]} after:{after}'
    params = urlencode({"query": query, "count": 20, "sort": "timestamp"})
    req = Request(f"https://slack.com/api/search.messages?{params}",
                  headers={"Authorization": f"Bearer {token}"})
    try:
        with urlopen(req) as resp:
            data = json.loads(resp.read())
    except HTTPError as e:
        return [{"_error": f"slack search failed ({e.code})"}]
    if not data.get("ok"):
        return [{"_error": f"slack: {data.get('error')}", "_query": query}]
    out = []
    for m in data.get("messages", {}).get("matches", []):
        ts = float(m.get("ts", 0))
        when = datetime.fromtimestamp(ts, timezone.utc)
        if when < window_start:
            continue
        out.append({
            "author": m.get("username") or m.get("user") or "someone",
            "created": when,
            "text": (m.get("text") or "").strip(),
            "channel": (m.get("channel") or {}).get("name", ""),
            "permalink": m.get("permalink", ""),
        })
    out.sort(key=lambda x: x["created"], reverse=True)
    for o in out:
        o["_query"] = query
    return out


# === Output ===

def print_report(tasks, hours, slack_token):
    active = [t for t in tasks if t["notion"] or t["slack"]]
    quiet = [t for t in tasks if not t["notion"] and not t["slack"]]

    print(f"\n📡 Task catch-up — last {hours}h  ({len(active)} with activity / {len(tasks)} tasks)\n")
    if not slack_token:
        print("  ⚠️  SLACK_USER_TOKEN (xoxp) is not set, skipping Slack. Add a token with the"
              " search:read scope to .env.agent to enable it.\n")

    for t in active:
        print(f"● {t['title']}")
        print(f"    ship: {t['slug']}" + (f"  ·  {t['notion_url']}" if t["notion_url"] else ""))
        _print_items(t["notion"], "💬 Notion")
        _print_items(t["slack"], "💬 Slack", is_slack=True)
        print()

    if quiet:
        print("-- No new activity:")
        for t in quiet:
            print(f"   · {t['slug']}")
    print()


def _print_items(items, label, is_slack=False):
    if not items:
        return
    errs = [i for i in items if i.get("_error")]
    real = [i for i in items if not i.get("_error")]
    if errs:
        print(f"    {label}: ⚠️  {errs[0]['_error']}")
        return
    if not real:
        return
    suffix = ""
    if is_slack and real[0].get("_query"):
        suffix = f'   query: "{real[0]["_query"].split(" after:")[0]}"'
    print(f"    {label} ({len(real)}){suffix}")
    for i in real:
        chan = f"  #{i['channel']}" if is_slack and i.get("channel") else ""
        link = f"  {i['permalink']}" if is_slack and i.get("permalink") else ""
        print(f"      • {i['author']} · {ago(i['created'])}{chan} — \"{snip(i['text'])}\"{link}")


def snip(text, n=120):
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1] + "…"


def ago(dt):
    secs = (datetime.now(timezone.utc) - dt).total_seconds()
    if secs < 3600:
        return f"{int(secs // 60)}m ago"
    if secs < 86400:
        return f"{int(secs // 3600)}h ago"
    return f"{int(secs // 86400)}d ago"


def parse_iso(s):
    if not s:
        return None
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


# === Entry point ===

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Catch up on Notion + Slack activity across active tasks.")
    ap.add_argument("--hours", type=int, default=24, help="time window in hours (default 24)")
    ap.add_argument("--ship", default=None, help="limit to one ship slug")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()
    run(args.hours, args.ship, args.json)

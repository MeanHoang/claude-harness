---
name: test-environments
description: Map of test environments and hands-on test capabilities — which store belongs to which app (local vs staging), storefront password, how to set up app settings for a test (Firestore direct / admin UI / REST API), how to read logs and the DB to verify behavior, and how to log in as a customer on the storefront. Use when running browser tests, choosing which store to test against, setting up test data, "store nào để test", "storefront password", "đăng nhập customer", or verifying test results in DB/logs.
---

# Test Environments — stores, data setup, verification access

## 1. Store ↔ App map

The user works with: local + **staging 7** + **staging 22** (+ prod store for production checks). Other staging tomls (8/16/17) exist but he doesn't use them.

| Env | App handle | client_id | Store | Notes |
|---|---|---|---|---|
| **Local (active)** | `ag-hoangtm-local` | `04ef25d6…` | **`{{DEV_STORE}}`** | Default `shopify.app.toml` + `dev-local` + `ag-hoangtm-local` tomls all point here |
| **Staging 7** | `{{FIREBASE_STAGING}}-7` | `6e2b9001…` | **`{{STAGING_STORE}}`** | SA: `serviceAccount.staging7.json` (verified read 2026-06-11) |
| **Staging 22** | `{{FIREBASE_STAGING}}-22` | `dcc946b7…` | **`{{STAGING_STORE_ALT}}`** | SA: `serviceAccount.staging22.json` |
| **Prod** | — | — | **`{{DEV_STORE_ALT}}`** | Production checks ONLY — read/observe, no test writes |
| Local (alt, unused) | `mh-{{APP_HANDLE}}` / `{{APP_HANDLE}}4` | `7cb00e16…` / `7b5bbd12…` | — | |
| Staging 8/16/17 (unused) | `{{FIREBASE_STAGING}}-{8,16,17}` | — | — | tomls exist; user doesn't use them |

- Store domain for the ACTIVE local app: `.shopify/project.json` keyed by client_id (NOT in the toml — see `project_browser_test_env_corrections` memory).
- **Loyalty page (theme blocks: my-reward, WayToRedeem, Rewards Redemption…) on the local store lives at `https://{{DEV_STORE}}/pages/contact`** (user-provided 2026-06-12) — go straight there, don't hunt for the page.
- **Rule: local code changes → test on the LOCAL store (`{{DEV_STORE}}`); staging deploys → test on that staging's store.** Testing a staging store against local code (or vice versa) gives meaningless results. When the right store is unknown (❓ above), ask the user ONCE and update this table.
- **Local stack not running when a local test is needed → AUTO-START it via the `local-dev` skill (user 2026-06-12), don't stop to ask**: `bash .claude/skills/local-dev/scripts/check-local-dev.sh` → start `yarn emulators` + non-sudo `yarn dev` in background → wait for readiness → fix stale tunnel URLs → re-check. Only fall back to notifying the user when the non-sudo `yarn dev` fails with permission errors (see Automation scope below). Default mode = STANDALONE (local-dev Step 5) unless he says "embed"; on success report the tunnel URLs (base + `/auth/login`). **Auto-started for a test → auto-STOP it when that test work completes** (local-dev Stopping section); if HE asked to run it, it stays up until he orders the stop.

## ⚠️ Automation scope (decided 2026-06-11, updated 2026-07-02)

- **Storefront tests = FULLY automatable** by Claude (incl. customer OTP login via IMAP). This is the default automated target.
- **Admin / standalone tests via playwright-cli = NOT fully automatable**: reaching the embedded admin requires a Shopify merchant login that ends at **2FA via authenticator app** (6-digit TOTP on the user's phone) — no key/env/app-password can supply this. Claude gets through email + password (stored in `.env.agent`) but STOPS at the authenticator step.
- **⭐ 2FA workaround: Claude in Chrome (see §1c)** — drives the user's REAL Chrome profile where he is already logged into Shopify Admin, so no 2FA seed is needed. Prefer it for admin UI tests when the session has Chrome connected.
- **Playwright fallback**: admin/standalone tests via playwright-cli need a ONE-TIME manual session seed — the user enters the 2FA code once into Claude's persistent browser profile; the session then persists for future runs.
- **Rule:** whenever a test needs setup Claude can't do alone (seed admin login, `sudo yarn dev` after the `local-dev` non-sudo auto-start failed, provide a store/credential, apply the standalone local fixes), **tell the user in chat** with the exact step needed.

## 1b. Standalone admin (no Shopify-admin shell) — USER'S CHOSEN CONVENTION

Open **`https://<live-tunnel>/auth/login`** → enter shop domain → Install → then browse pages like `/programs`. NOT localhost:3000/5010 (redirect_uri follows `ctx.host`; only tunnel callbacks are auto-whitelisted). Get the current URL with:
```bash
bash scripts/standalone-url.sh   # prints https://<live-tunnel>/auth/login
```
(User decided 2026-06-11: tunnel URL + this script, NOT deploying config to whitelist localhost — deploy was blocked by 25 remaining extension duplicates, per deploy-extensions skill rule.)
Prereqs: your project's local stack up (backend + emulators/DB + the standalone admin), however your repo starts it. Local-only patches your machine needs to run standalone belong in your project's own dev docs, not here — this skill assumes the stack is already running.

## 1c. Browser engines — playwright-cli vs Claude in Chrome

Two ways Claude can drive a browser; pick per test:

| | **playwright-cli** (`--headed --persistent`) | **Claude in Chrome** (extension) |
|---|---|---|
| Profile | Isolated Claude profile — needs its own logins/seeds | User's REAL Chrome — Shopify Admin, Notion, GitLab sessions already live |
| 2FA admin login | Blocked until one-time manual seed (§ Automation scope) | **Not needed** — reuses existing merchant session |
| Stability | Stable, good for repeated/scripted runs | Beta; extension service worker can idle-drop (reconnect via `/chrome`) |
| Availability | Always (installed globally) | Only when the Claude Code session was started with `--chrome` / user enabled `/chrome`; extension v1.0.36+ must be installed and Chrome running |
| Best for | Storefront tests, OTP login flow, repeatable scripted checks | Admin UI tests, anything gated by the merchant 2FA login, quick visual checks |

**Decision rule:** storefront → playwright-cli (default, scripted, OTP recipe below). Admin/standalone UI → Claude in Chrome if connected; otherwise fall back to playwright + ask for the 2FA seed.

⚠️ Claude in Chrome operates the user's real logged-in accounts: read/click/verify only — never change config through it (config changes stay API-first per §3), never act on the prod store beyond observing, and stop + ask before anything destructive or outside the test shop.

## 2. Storefront password

**Every dev/staging store uses storefront password `{{STOREFRONT_PASSWORD}}`.** When the storefront shows the password page:

```bash
playwright-cli goto "https://{{DEV_STORE}}" && playwright-cli snapshot
# if password page → fill the password field with {{STOREFRONT_PASSWORD}} and submit, then continue
```

## 3. Changing/creating app config & settings — API FIRST, Firestore LAST (decided 2026-06-11)

**Never use the admin browser to change config** (blocked by 2FA). Order of preference:

| Priority | Route | Why / When |
|---|---|---|
| **1 ⭐ API** | **REST API v2 / the app's own endpoints** | Goes through the REAL save path — validation, business logic, side-effects (cache invalidation, publish events, related-doc updates). Use `test-internal-api` skill to temporarily expose an internal controller/service, or `packages/api-tests` for public endpoints. THIS IS THE DEFAULT for any config change. |
| **2 (fallback)** | **Direct Firestore write** | ONLY when no API path exists or for read-back/verification. ⚠️ Bypasses ALL business logic — a raw `status:false` may skip syncs/events the real save would fire, so the storefront/cache can end up inconsistent. Note this risk when you use it. SA per env (`serviceAccount.development.json` local, `.staging7.json`, `.staging22.json` — verified). Scope EVERY op by the test shop's `shopId` (shared project). |
| visual only | Admin UI via playwright | LIMITED — only to *see* the UI; needs one-time 2FA seed (§1b). Never to *change* config. |

Firestore reference (for reads & last-resort writes): find shop by `shopifyDomain` → `programs` where `shopId==` → program `type`: `spending`=redeem, `earning`, `tier_privileges`, `referral`…; status/enable field varies per doc — read first. Always **read back to verify** after any change.

(2026-06-11 demo toggled redeem "Free product" via raw Firestore as a proof — but the API route is preferred precisely because Firestore skips the program's save-side effects.)

## 4. Verifying results — logs & DB (access confirmed)

> **RULE (user, 2026-06-11): a browser/UI test alone is NEVER a complete test.** Every test run MUST be combined with reading the env's backend logs over the test window — mark the log position before acting, then after the actions diff the new lines: trace the triggered flow end-to-end (request → pubsub/background handlers → external API calls) and check it caused no side effects (errors, unexpected cascades, retries, cost-heavy calls). Classify every error found as caused-by-this-flow vs pre-existing-env-noise (e.g. local: Redis timeout, BigQuery SA perms) — and say which in the report.

- **Local backend logs**: `firebase-debug.log` (actively written; grep for errors after each browser action). Local stack = `yarn emulators` (hosting+functions+pubsub only — **no Firestore emulator**; data lives in the real `{{FIREBASE_STAGING}}` project).
- **DB read** (verified working):
  ```bash
  node -e "const a=require('firebase-admin');a.initializeApp({credential:a.credential.cert(require('./{{PKG_BACKEND}}/serviceAccount.development.json'))});a.firestore().collection('shops').where(...).get().then(...)"
  ```
  Staging 22 → `serviceAccount.staging22.json` (project `{{FIREBASE_STAGING}}-22`). Other stagings → check `.env.{{FIREBASE_STAGING}}-*` / ask.
- **Staging/prod logs**: your cloud provider log console. ⭐ **Staging-22 access verified 2026-06-11**: the gcloud account `{{WORK_EMAIL}}` (already credentialed on the machine — `gcloud config set account {{WORK_EMAIL}}`) CAN read `{{FIREBASE_STAGING}}-22` logs; the firebase-adminsdk SA canNOT (no Logs Viewer). v2 functions log as `resource.type="cloud_run_revision"` with lowercase `resource.labels.service_name` (e.g. `apihookv1popupv2`, `backgroundhandlingmediumv2`) — NOT `cloud_function`. Redeem-flow markers: `HANDLE_REDEEM`, `ATOMIC_DEDUCT`, `handle background type == meta_field_update`, `Update meta field`.
- Assertion pattern per test: browser action → grep `firebase-debug.log` for new errors → read the affected Firestore doc(s) → compare against expected.

## 5. Customer login on the storefront

Needed for loyalty features (points, rewards, tiers). Two account types — detect at runtime from the login page:

- **Classic accounts** (email + password form): log in directly via playwright (`fill` email/password, submit).
- **New customer accounts (email OTP) — FULLY AUTOMATED** (verified 2026-06-11): the test customer email is **`{{WORK_EMAIL}}`**; its Gmail App Password lives in `.env.agent` (`TEST_MAIL_USER` / `TEST_MAIL_APP_PASSWORD`). IMAP access verified working. Flow:
  1. On the storefront login page, submit `{{WORK_EMAIL}}` → Shopify sends the code.
  2. Poll IMAP (Python stdlib, no deps) every ~5s, up to ~90s, for a mail NEWER than the submit time:
     ```python
     import imaplib, email, re, os
     m = imaplib.IMAP4_SSL("imap.gmail.com", 993)
     m.login(os.environ["TEST_MAIL_USER"], os.environ["TEST_MAIL_APP_PASSWORD"])
     m.select("INBOX", readonly=True)
     _, ids = m.search(None, '(FROM "shopifyemail.com")')   # NOT just "shopify" — see below
     # fetch newest id, get subject, code = re.search(r"\b(\d{6})\b", subject).group(1)
     ```
     ⚠️ **Lesson 2026-06-11 (user-confirmed recipe):** each store sends its OTP from ONE fixed address — `store+<store_id>@t.shopifyemail.com` (sender display name = the store name; the store id is the number in that address, so once you have seen one code from a store you know its exact sender forever). So: filter `FROM "t.shopifyemail.com"` (or the exact per-store address once known), take the NEWEST match, code is the first 6 digits of the SUBJECT (`"123456 is your code"`). No fuzzy `FROM "shopify"`, no strict timestamp gymnastics — newest-from-that-address is enough (allow ~10s clock skew vs submit time as sanity check only).
  3. Fill the code in the browser → logged in.
  - ⚠️ This App Password reads the user's REAL work mailbox: ONLY ever search/peek Shopify OTP mails (`readonly=True`, `BODY.PEEK`), never read anything else, never mark mails seen, never delete. He can revoke the key in one click at myaccount.google.com/apppasswords.
- The `--persistent` profile keeps customer sessions too — after one successful login, subsequent runs are already logged in until the session expires.

## Rules

- Never run destructive writes (deletes, bulk changes) against shared staging Firestore — test-shop-scoped docs only.
- When a test needs a store/credential not in this file → ask the user, then UPDATE THIS SKILL so the next session doesn't ask again.

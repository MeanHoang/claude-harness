#!/usr/bin/env bash
# Replace every {{VAR}} in an installed harness with the values from a config file.
#
#   ./fill-vars.sh <target-project> [config-file]
#
# Reads KEY=value lines (harness.config by default), then rewrites {{KEY}} in place
# under <target-project>/.claude/. Idempotent: re-running with an updated config only
# touches placeholders that are still unfilled.
#
# Any {{VAR}} with no matching key is left alone and reported, so nothing is silently
# replaced by an empty string.

set -uo pipefail

TARGET="${1:-}"
CONFIG="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harness.config}"

[ -n "$TARGET" ] || { echo "usage: $0 <target-project> [config-file]" >&2; exit 1; }
[ -d "$TARGET/.claude" ] || { echo "no .claude in $TARGET — run install.sh first" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "no config file: $CONFIG (copy harness.config.example)" >&2; exit 1; }

python3 - "$TARGET/.claude" "$CONFIG" <<'PY'
import os, re, sys

root, cfg_path = sys.argv[1], sys.argv[2]

cfg = {}
for line in open(cfg_path, encoding='utf-8'):
    line = line.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    cfg[k.strip()] = v.split('#')[0].strip()

filled, files = 0, 0
leftover = {}

for dirpath, dirnames, filenames in os.walk(root):
    # Loại state task (.claude/ship) nhưng CHỈ ở tầng gốc — có một skill cũng tên 'ship'.
    skip = {'.impeccable', '__pycache__'}
    if os.path.abspath(dirpath) == os.path.abspath(root):
        skip.add('ship')
    dirnames[:] = [d for d in dirnames if d not in skip]
    for fn in filenames:
        if not fn.endswith(('.md', '.py', '.sh', '.html', '.json', '.txt')):
            continue
        p = os.path.join(dirpath, fn)
        try:
            s = open(p, encoding='utf-8').read()
        except Exception:
            continue
        original = s

        def swap(m):
            global filled
            key = m.group(1)
            if key in cfg:
                filled += 1
                return cfg[key]
            leftover[key] = leftover.get(key, 0) + 1
            return m.group(0)

        s = re.sub(r'\{\{([A-Z][A-Z0-9_]*)\}\}', swap, s)
        if s != original:
            open(p, 'w', encoding='utf-8').write(s)
            files += 1

print(f"filled {filled} placeholder(s) across {files} file(s)")
if leftover:
    print("\nstill unfilled (no key in the config):")
    for k, n in sorted(leftover.items(), key=lambda kv: -kv[1]):
        print(f"  {{{{{k}}}}}  x{n}")
    print("\nAdd them to the config and re-run, or leave them if they do not apply.")
PY

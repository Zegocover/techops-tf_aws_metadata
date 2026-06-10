#!/usr/bin/env bash
# PreToolUse hook — git safety
# Blocks dangerous git patterns before Bash tool execution.
# stdin: {"tool_name":"Bash","tool_input":{"command":"<cmd>"}}
# Exit 2 + stderr  → command blocked
# Exit 0           → command allowed (also on parse failure — fail open)

set -euo pipefail

# Read all stdin upfront; subshell $(cat) would compete with python3 for stdin
INPUT=$(cat)

CMD=$(python3 -c "
import json, sys
try:
    payload = json.loads(sys.argv[1])
    print(payload['tool_input']['command'])
except Exception:
    sys.exit(0)
" "$INPUT") || exit 0

# Exit 0 if CMD is empty (parse failure produced no output)
[ -z "${CMD:-}" ] && exit 0

block() {
    printf "BLOCKED: '%s' is forbidden by the Zego AI safety hook.\n" "$CMD" >&2
    printf "Stop and surface this block to the user. Do not attempt to rephrase or work around it.\n" >&2
    exit 2
}

python3 -c "
import re, sys

cmd = sys.argv[1]

# Force push variants (bare --force and -f are always blocked;
# --force-with-lease is only blocked on protected branches)
force_patterns = [
    r'git\s+push\b.*\s--force(?!-with-lease|-if-includes)\b',
    r'git\s+push\b.*\s-[a-zA-Z]*f',
]
for p in force_patterns:
    if re.search(p, cmd):
        sys.exit(1)

# Push to protected branch (any remote) — match branch name after space, + or :
# Covers: push origin main, push origin +main, push origin HEAD:main, push origin main:main
protected = r'git\s+push\b.*[\s+:](?:main|master|production|staging|release/\S+?)(?=\s|$|:)'
if re.search(protected, cmd):
    sys.exit(1)

# Hard reset
if re.search(r'git\s+reset\b.*--hard', cmd):
    sys.exit(1)

# git clean with -f flag
if re.search(r'git\s+clean\b.*-[a-zA-Z]*f[a-zA-Z]*', cmd):
    sys.exit(1)

# Discard all changes
if re.search(r'git\s+checkout\s+--\s+\.', cmd):
    sys.exit(1)
if re.search(r'git\s+restore\s+\.', cmd):
    sys.exit(1)

# Force branch delete
if re.search(r'git\s+branch\b.*\s-[a-zA-Z]*D', cmd):
    sys.exit(1)

# Stash discard
if re.search(r'git\s+stash\s+drop', cmd):
    sys.exit(1)
if re.search(r'git\s+stash\s+clear', cmd):
    sys.exit(1)

# gh pr merge
if re.search(r'gh\s+pr\s+merge', cmd):
    sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

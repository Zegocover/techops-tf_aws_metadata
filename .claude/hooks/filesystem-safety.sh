#!/usr/bin/env bash
# PreToolUse hook — filesystem safety
# Blocks dangerous filesystem patterns before Bash tool execution.
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

# Recursive delete: rm with both recursive and force flags (combined or separate)
python3 -c "
import re, sys

cmd = sys.argv[1]

if re.search(r'\brm\b', cmd):
    has_recursive = bool(re.search(r'\s-[a-zA-Z]*[rR][a-zA-Z]*|--recursive', cmd))
    has_force = bool(re.search(r'\s-[a-zA-Z]*[fF][a-zA-Z]*|--force', cmd))
    if has_recursive and has_force:
        sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

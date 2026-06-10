#!/usr/bin/env bash
# PreToolUse hook — database safety
# Blocks dangerous database patterns before Bash tool execution.
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

# DROP TABLE / DROP DATABASE / TRUNCATE TABLE (case-insensitive)
if re.search(r'(?i)drop\s+table', cmd):
    sys.exit(1)
if re.search(r'(?i)drop\s+database', cmd):
    sys.exit(1)
if re.search(r'(?i)\btruncate\s+(?:table\s+|only\s+)?[A-Za-z_]\w*', cmd):
    sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0
